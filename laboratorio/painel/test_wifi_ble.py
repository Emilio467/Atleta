import asyncio
import hmac
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

import wifi_ble as wifi
from rede import Interface, atomic_json, read_json


class BluetoothWifiTests(unittest.TestCase):
    def test_setup_code_or_confirmed_ota_link(self):
        with TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError, 'código'):
                wifi.setup_secret(temp, '')
            self.assertEqual(wifi.setup_secret(temp, '1234567890ABCDEF'), '1234567890abcdef')
            atomic_json(wifi.pairing_file(temp), {'key': 'a' * 64, 'confirmed': True})
            self.assertEqual(wifi.setup_secret(temp, ''), 'a' * 64)

    def test_local_target_is_used_only_on_the_matching_network(self):
        with TemporaryDirectory() as temp:
            folder = Path(temp)
            atomic_json(folder / 'runtime/settings.json', {'mqtt_port': 1883, 'bind': '0.0.0.0'})
            atomic_json(folder / 'runtime/secrets.json', {'m5-atleta-01': 'fixture-key'})
            with patch.object(wifi, 'detect_hotspot', return_value={}), \
                    patch.object(wifi, 'detect_wifi', return_value={'ssid': 'Rede nova'}), \
                    patch.object(wifi, 'detect_interfaces', return_value=[Interface('192.168.10.20', 'Wi-Fi')]):
                self.assertIsNone(wifi.local_server(folder, 'Outra rede'))
                self.assertEqual(wifi.local_server(folder, 'Rede nova'), {
                    'host': '192.168.10.20', 'port': 1883, 'password': 'fixture-key',
                })

    def test_hotspot_uses_its_own_address_instead_of_the_uplink(self):
        with TemporaryDirectory() as temp:
            folder = Path(temp)
            atomic_json(folder / 'runtime/settings.json', {'mqtt_port': 1883, 'bind': '0.0.0.0'})
            atomic_json(folder / 'runtime/secrets.json', {'m5-atleta-01': 'fixture-key'})
            with patch.object(wifi, 'detect_hotspot', return_value={'ssid': 'Hotspot', 'host': '192.168.137.1'}), \
                    patch.object(wifi, 'detect_wifi', return_value={'ssid': 'Faculdade'}) as uplink:
                self.assertEqual(wifi.local_server(folder, 'Hotspot', '10.0.0.20'), {
                    'host': '192.168.137.1', 'port': 1883, 'password': 'fixture-key',
                })
                uplink.assert_not_called()
            with patch.object(wifi, 'detect_hotspot', return_value={'ssid': 'Hotspot', 'message': 'Ative o hotspot'}), \
                    patch.object(wifi, 'detect_wifi', return_value={'ssid': 'Faculdade'}):
                with self.assertRaisesRegex(ValueError, 'Ative o hotspot'):
                    wifi.local_server(folder, 'Hotspot')

    def test_bluetooth_uses_authenticated_chunks_and_waits_for_the_saved_status(self):
        settings = {'ssid': 'Rede nova ç', 'password': 'teste de rede'}
        challenge = b'c' * 16
        secret = '7' * 64
        client = MagicMock()
        client.read_gatt_char = AsyncMock(side_effect=[bytes([wifi.CLOSED]) + bytes(16),
                                                       bytes([wifi.READY]) + challenge,
                                                       bytes([wifi.TESTING]) + challenge,
                                                       bytes([wifi.SAVED]) + bytes(16)])
        client.write_gatt_char = AsyncMock()
        device = SimpleNamespace(address='M5')
        transport = MagicMock()
        transport.__aenter__ = AsyncMock(return_value=client)
        transport.__aexit__ = AsyncMock(return_value=False)
        with patch.object(wifi.BleakScanner, 'discover', new_callable=AsyncMock) as discover, \
                patch.object(wifi, 'BleakClient', return_value=transport) as connect:
            discover.side_effect = [{}, {'device': (device, SimpleNamespace(service_uuids=[wifi.SERVICE]))}]
            progress = []
            asyncio.run(wifi.transfer_settings(settings, secret, progress.append))
            self.assertTrue(connect.call_args.kwargs['pair'])
            self.assertEqual(discover.await_count, 2)
            self.assertIn('Aguardando a liberação no relógio', ' '.join(progress))
        records = [call.args[1] for call in client.write_gatt_char.await_args_list]
        self.assertTrue(all(len(record) <= 20 for record in records))
        self.assertTrue(all(call.kwargs['response'] for call in client.write_gatt_char.await_args_list))
        self.assertEqual((records[0], records[-1]), (b'\x01', b'\x03'))
        payload = b''.join(record[1:] for record in records[1:-1])
        key = hmac.digest(secret.encode('ascii'), b'ATLETA-WIFI/1', 'sha256')
        self.assertEqual(json.loads(AESGCM(key).decrypt(payload[:12], payload[12:], challenge)), settings)
        self.assertNotIn(settings['password'], ' '.join(progress))

    def test_cancelling_while_window_is_closed_prevents_writes(self):
        attempt = wifi.SetupAttempt()
        client = MagicMock()
        client.read_gatt_char = AsyncMock(return_value=bytes(17))
        client.write_gatt_char = AsyncMock()
        transport = MagicMock()
        transport.__aenter__ = AsyncMock(return_value=client)
        transport.__aexit__ = AsyncMock(return_value=False)
        watch = SimpleNamespace(address='M5')

        def progress(message):
            if 'Aguardando a liberação no relógio' in message:
                self.assertTrue(attempt.cancel())

        with patch.object(wifi.BleakScanner, 'discover', new_callable=AsyncMock) as discover, \
                patch.object(wifi, 'BleakClient', return_value=transport):
            discover.return_value = {'watch': (watch, SimpleNamespace(service_uuids=[wifi.SERVICE]))}
            with self.assertRaises(wifi.SearchCancelled):
                asyncio.run(wifi.transfer_settings({}, '7' * 64, progress, attempt))
        client.write_gatt_char.assert_not_awaited()

    def test_rejected_wifi_preserves_local_config_and_success_leaves_profile_intact(self):
        with TemporaryDirectory() as temp:
            folder = Path(temp)
            config_path = folder / 'config.local.json'
            original = {'wifi_ssid': 'antiga', 'wifi_password': 'senha antiga', 'weight_kg': 65}
            atomic_json(config_path, original)
            with patch.object(wifi, 'transfer_settings', new_callable=AsyncMock) as send, \
                    patch.object(wifi, 'local_server', return_value=None):
                send.side_effect = ValueError(wifi.MESSAGES[wifi.NETWORK_ERROR])
                with self.assertRaisesRegex(ValueError, 'rede anterior'):
                    wifi.apply_network(folder, 'nova', 'senha nova', '0' * 16, None, lambda _: None)
                self.assertEqual(read_json(config_path), original)
                send.side_effect = None
                self.assertIn('vai reiniciar', wifi.apply_network(folder, 'nova', 'senha nova', '0' * 16, None, lambda _: None))
                self.assertEqual(read_json(config_path), {
                    'wifi_ssid': 'nova', 'wifi_password': 'senha nova', 'weight_kg': 65,
                    'device_id': 'm5-atleta-01',
                })


if __name__ == '__main__':
    unittest.main()
