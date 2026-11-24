import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch, MagicMock

from wifi_pc import select_wifi, detect_wifi, detect_hotspot, autofill, profile_password, wifi_form_values
import conexao_m5
from rede import atomic_json, read_json, Interface


class WifiAutoTests(unittest.TestCase):
    def test_easy_connection_reuses_ready_server(self):
        with patch('conexao_m5.prepare_target', return_value={'host': '10.0.0.20', 'port': 1883}), \
             patch('servidor.LabController') as controller, \
             patch('conexao_m5.configure_and_check', return_value='Conferido') as configure:
            self.assertEqual(conexao_m5.connect_easy('LAB', 'COM_TESTE'), 'Conferido')
        controller.assert_not_called()
        self.assertEqual(configure.call_args.args[:2], ('LAB', 'COM_TESTE'))

    def test_easy_connection_prepares_server_before_usb(self):
        calls = []
        with patch('conexao_m5.prepare_target', side_effect=ValueError('Servidor parado')), \
             patch('servidor.LabController') as controller, \
             patch('conexao_m5.configure_and_check', side_effect=lambda *args: calls.append('usb')):
            controller.return_value.start.side_effect = lambda allow: calls.append(('server', allow))
            conexao_m5.connect_easy('LAB', 'COM_TESTE')
        self.assertEqual(calls, [('server', True), 'usb'])

    def test_server_start_failure_never_writes_usb(self):
        from servidor import LabError
        with patch('conexao_m5.prepare_target', side_effect=ValueError('Servidor parado')), \
             patch('servidor.LabController') as controller, \
             patch('conexao_m5.configure_and_check') as configure:
            controller.return_value.start.side_effect = LabError('Docker indisponível')
            with self.assertRaises(LabError):
                conexao_m5.connect_easy('LAB', 'COM_TESTE')
        configure.assert_not_called()

    def test_new_network_never_reuses_saved_password(self):
        self.assertEqual(autofill('CASA', 'SENHA_DA_CASA', 'LAB'), ('LAB', ''))
        self.assertEqual(autofill('Claro11', 'SENHA', 'CLARO11'), ('CLARO11', ''))

    def test_same_network_reuses_only_project_password(self):
        self.assertEqual(autofill('LAB', 'SENHA_SALVA_NO_PROJETO', 'LAB'), ('LAB', 'SENHA_SALVA_NO_PROJETO'))

    def test_windows_key_takes_priority_over_the_old_project_key(self):
        connection = {'ssid': 'LAB', 'password': 'senha-atual'}
        self.assertEqual(wifi_form_values('LAB', 'senha-antiga', connection)[:2], ('LAB', 'senha-atual'))
        self.assertEqual(wifi_form_values('CASA', 'senha-de-casa', connection)[:2], ('LAB', 'senha-atual'))

    def test_inactive_hotspot_keeps_existing_wifi_form_and_its_identity(self):
        with patch('wifi_pc.os.name', 'nt'), patch('wifi_pc.windows_network_json', return_value={'ssid': 'Hotspot'}):
            status = detect_hotspot(include_password=True)
        self.assertEqual(status['ssid'], 'Hotspot')
        self.assertNotIn('password', status)
        self.assertEqual(wifi_form_values('Casa', 'chave-salva', status)[:2], ('Casa', 'chave-salva'))

    def test_open_network_clears_an_old_key_and_other_protected_network_cannot_reuse_it(self):
        self.assertEqual(wifi_form_values('LAB', 'chave-antiga', {'ssid': 'LAB', 'password': ''})[:2], ('LAB', ''))
        self.assertEqual(wifi_form_values('LAB', 'chave-antiga', {'ssid': 'OUTRA'})[:2], ('OUTRA', ''))
        self.assertEqual(wifi_form_values('LAB', 'chave-antiga', {'ssid': 'LAB'})[:2], ('LAB', 'chave-antiga'))

    def test_only_the_matching_personal_profile_can_supply_a_plaintext_key(self):
        xml = '''<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
          <SSIDConfig><SSID><hex>4C4142</hex><name>LAB</name></SSID></SSIDConfig>
          <MSM><security><authEncryption><authentication>WPA2PSK</authentication>
            <encryption>AES</encryption></authEncryption>
            <sharedKey><protected>false</protected><keyMaterial>chave-fixture</keyMaterial></sharedKey>
          </security></MSM></WLANProfile>'''
        self.assertEqual(profile_password(xml, 'LAB'), 'chave-fixture')
        self.assertIsNone(profile_password(xml, 'lab'))
        self.assertIsNone(profile_password(xml.replace('4C4142', '5043'), 'LAB'))
        self.assertIsNone(profile_password(xml.replace('false', 'true'), 'LAB'))
        self.assertIsNone(profile_password(xml.replace('WPA2PSK', 'WPA2'), 'LAB'))
        self.assertEqual(profile_password(xml.replace('WPA2PSK', 'open').replace('AES', 'none'), 'LAB'), '')

    def test_wired_or_disconnected_pc_does_not_invent_ssid(self):
        self.assertEqual(select_wifi([])['state'], 'no_wifi')
        self.assertIsNone(select_wifi([{'ssid': 'ANTIGA', 'connected': False}])['ssid'])
        self.assertEqual(autofill('REDE_M5', 'SENHA', None), ('REDE_M5', 'SENHA'))

    def test_active_network_supports_unicode_and_ignores_old_profile(self):
        self.assertEqual(select_wifi([{'ssid': 'Laboratório', 'connected': True},
                                      {'ssid': 'ANTIGA', 'connected': False}])['ssid'], 'Laboratório')
        self.assertEqual(select_wifi({'ssid': 'Casa', 'connected': True})['ssid'], 'Casa')

    def test_multiple_active_networks_are_not_chosen_arbitrarily(self):
        result = select_wifi([{'ssid': 'A', 'connected': True}, {'ssid': 'B', 'connected': True}])
        self.assertEqual(result['state'], 'multiple')
        self.assertIsNone(result['ssid'])

    def test_windows_failure_keeps_manual_entry_available(self):
        with patch('wifi_pc.subprocess.run', side_effect=subprocess.TimeoutExpired('powershell', 10)):
            result = detect_wifi()
        self.assertEqual(result['state'], 'unavailable')
        self.assertIsNone(result['ssid'])

    def test_target_uses_current_pc_and_exact_lab_ports_preserving_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            atomic_json(Path(tmp) / 'runtime/settings.json', {'bind': '0.0.0.0', 'mqtt_port': 1883, 'dashboard_port': 18083})
            atomic_json(Path(tmp) / 'config.local.json', {'mqtt_host': '192.168.0.67', 'weight_kg': 90, 'wifi_password': 'PRIVADA'})
            status = {'mqtt_online': True, 'dashboard_online': True, 'mqtt_port': 1883, 'dashboard_port': 18083}
            with patch('conexao_m5.detect_interfaces', return_value=[Interface('10.0.0.20', 'Wi-Fi', True)]), \
                 patch('conexao_m5.inspect_pair', return_value=status) as probe:
                target = conexao_m5.prepare_target(tmp)
            self.assertEqual(target, {'host': '10.0.0.20', 'port': 1883})
            probe.assert_called_once_with('10.0.0.20', (1883, 18083))
            config = read_json(Path(tmp) / 'config.local.json')
            self.assertEqual(config['weight_kg'], 90)
            self.assertEqual(config['wifi_password'], 'PRIVADA')
            self.assertEqual(config['mqtt_host'], '10.0.0.20')

    def test_network_disabled_stops_before_usb_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            atomic_json(Path(tmp) / 'runtime/settings.json', {'bind': '127.0.0.1', 'mqtt_port': 1883, 'dashboard_port': 18083})
            with patch('conexao_m5.send_configuration') as send:
                with self.assertRaisesRegex(ValueError, 'Permitir conexão'):
                    conexao_m5.configure_and_check(tmp, 'COM_TESTE')
                send.assert_not_called()

    def test_old_or_other_device_sample_is_not_live_success(self):
        sample = {'payload': {'source': 'device', 'boot_id': 'novo', 'sample_seq': 2}, 'age_seconds': 100, 'id': 45}
        self.assertIsNone(conexao_m5.persisted_match([sample], {('novo', 2)}))
        sample['age_seconds'] = 1
        self.assertIsNone(conexao_m5.persisted_match([sample], {('outro', 2)}))
        self.assertEqual(conexao_m5.persisted_match([sample], {('novo', 2)}), 45)

    def test_saved_configuration_alone_is_not_connection_success(self):
        state = {'samples': set()}
        conexao_m5.observe('CONFIG_OK', state)
        self.assertNotIn('confirmada', conexao_m5.conclusion(state, {'host': '10.0.0.20', 'port': 1883}))

    def test_diagnostic_distinguishes_wifi_auth_server_and_database(self):
        target = {'host': '10.0.0.20', 'port': 1883}
        self.assertIn('não entrou no Wi-Fi', conexao_m5.conclusion({'usb_response': True, 'wifi': False}, target))
        self.assertIn('recusou o login', conexao_m5.conclusion({'usb_response': True, 'wifi': True, 'mqtt': False, 'mqtt_error': 5}, target))
        self.assertIn('10.0.0.20:1883', conexao_m5.conclusion({'usb_response': True, 'wifi': True, 'mqtt': False}, target))
        self.assertIn('nenhuma leitura nova', conexao_m5.conclusion({'usb_response': True, 'wifi': True, 'mqtt': True}, target))

    def test_usb_telemetry_and_database_confirmation_report_no_passwords(self):
        with tempfile.TemporaryDirectory() as tmp:
            connection = MagicMock()
            connection.__enter__.return_value = connection
            payload = {'source': 'device', 'boot_id': 'nova-sessao', 'sample_seq': 3, 'mqtt_connected': True}
            connection.readline.side_effect = [b'STATUS wifi=1 mqtt=1 imu=1\n', ('TELEMETRY ' + json.dumps(payload) + '\n').encode()]
            row = {'id': 42, 'payload': payload, 'age_seconds': 0.1}
            with patch('conexao_m5.open_serial', return_value=connection), patch('conexao_m5.time.sleep'), \
                 patch('conexao_m5.fetch_readings', return_value=[row]):
                result = conexao_m5.verify_connection(tmp, 'COM_TESTE', {'host': '10.0.0.20', 'port': 1883})
            self.assertIn('leitura nova gravada', result)
            report = read_json(Path(tmp) / 'runtime/diagnostico-conexao-m5.json')
            self.assertTrue(report['live_data_confirmed'])
            self.assertEqual(report['mysql_row_id'], 42)
            self.assertNotIn('samples', report)


if __name__ == '__main__':
    unittest.main(verbosity=2)
