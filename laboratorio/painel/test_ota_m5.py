from concurrent.futures import ThreadPoolExecutor
import hashlib
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import MagicMock, patch

import ota_m5
from rede import Interface, atomic_json, read_json


class OtaTests(unittest.TestCase):
    key = 'a' * 64
    nonce = 'b' * 32

    def test_discovery_requires_the_paired_key(self):
        body = f'{ota_m5.DISCOVERY} {self.nonce} 2.2.0'
        packet = f'{body} {ota_m5.sign(self.key, body)}'.encode('ascii')
        self.assertEqual(ota_m5.advertisement(packet, self.key), (self.nonce, '2.2.0'))
        self.assertIsNone(ota_m5.advertisement(packet, '0' * 64))
        self.assertIsNone(ota_m5.advertisement(packet.replace(b'2.2.0', b'2.2.1'), self.key))

    def test_usb_pairing_records_the_ip_after_ack(self):
        with tempfile.TemporaryDirectory() as folder:
            connection = MagicMock()
            connection.__enter__.return_value = connection
            connection.readline.side_effect = [b'OTA_PAIR_OK\n', b'INVENTORY {"wifi_ip":"192.168.0.118"}\n']
            with patch('ota_m5.device_ports', return_value=['COM3']), patch('ota_m5.open_serial', return_value=connection), patch('ota_m5.time.sleep'):
                ota_m5.pair_usb(folder)
            pairing = read_json(ota_m5.pairing_file(folder))
            self.assertTrue(pairing['confirmed'])
            self.assertEqual(pairing['ip'], '192.168.0.118')
            connection.write.assert_any_call(f"OTA_PAIR {pairing['key']}\n".encode('ascii'))

    def test_pc_discovers_and_sends_image_over_outbound_tcp(self):
        ip = '127.0.0.1'
        image = b'\xe9' + bytes(range(256)) * 420
        with tempfile.TemporaryDirectory() as folder, socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as discovery:
            install = Path(folder)
            data = install / 'entrega/firmware'
            data.mkdir(parents=True)
            (data / 'firmware.bin').write_bytes(image)
            digest = hashlib.sha256(image).hexdigest()
            atomic_json(data / 'manifest.json', {
                'version': '2.2.0',
                'segments': [{'offset': '0x10000', 'file': 'firmware.bin', 'sha256': digest}],
            })
            atomic_json(ota_m5.pairing_file(install), {'key': self.key, 'confirmed': True, 'ip': '192.168.0.118'})
            server.bind((ip, 0))
            port = server.getsockname()[1]
            server.listen(1)
            server.settimeout(5)
            discovery.bind((ip, port))
            discovery.settimeout(5)

            def receive():
                query, peer = discovery.recvfrom(256)
                self.assertEqual(query, ota_m5.DISCOVERY.encode('ascii'))
                body = f'{ota_m5.DISCOVERY} {self.nonce} 2.2.0'
                discovery.sendto(f'{body} {ota_m5.sign(self.key, body)}'.encode('ascii'), peer)
                with server.accept()[0] as client, client.makefile('rb') as incoming:
                    client.settimeout(5)
                    request = f'{ota_m5.UPLOAD} {self.nonce} {len(image)} {digest}'
                    self.assertEqual(incoming.readline(), f'{request} {ota_m5.sign(self.key, request)}\n'.encode('ascii'))
                    client.sendall(b'READY\n')
                    self.assertEqual(incoming.read(len(image)), image)
                    client.sendall(b'OK\n')

            events = []
            with ThreadPoolExecutor(1) as worker:
                watch = worker.submit(receive)
                with patch('ota_m5.PORT', port), \
                        patch('ota_m5.detect_interfaces', return_value=[Interface('127.0.0.2', 'Teste', prefix=24)]), \
                        patch('ota_m5.mqtt_peers', return_value=(ip,)), \
                        patch('ota_m5.valid_ip', return_value=True):
                    self.assertEqual(ota_m5.update_m5(install, lambda label, value: events.append(value)), '2.2.0')
                watch.result()
            self.assertEqual(events[-1], 100)


if __name__ == '__main__':
    unittest.main()
