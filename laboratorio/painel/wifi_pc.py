"""Consulta a rede ativa e, na configuração do M5, a chave liberada pelo Windows."""
import ctypes
from ctypes import wintypes
from ipaddress import IPv4Address
import json
import os
from pathlib import Path
import subprocess
from uuid import UUID
from xml.etree import ElementTree


def validate_wifi(ssid, password):
    if not ssid or '\0' in ssid or len(ssid.encode('utf-8')) > 32:
        raise ValueError('Informe o nome da rede Wi-Fi, com até 32 bytes.')
    if '\0' in password or (password and not (8 <= len(password.encode('utf-8')) <= 63 or
            len(password) == 64 and all(c in '0123456789abcdefABCDEF' for c in password))):
        raise ValueError('A senha Wi-Fi deve ter 8 a 63 bytes, ou 64 dígitos hexadecimais. Rede aberta pode ficar sem senha.')


def select_wifi(records):
    if isinstance(records, dict):
        records = [records]
    names = sorted({r['ssid'] for r in records or [] if isinstance(r, dict)
                    and r.get('connected') is True and isinstance(r.get('ssid'), str)
                    and 0 < len(r['ssid'].encode('utf-8')) <= 32})
    if len(names) == 1:
        return {'state': 'connected', 'ssid': names[0],
                'message': 'Wi-Fi do computador detectado. O M5 precisa de acesso a essa rede em 2,4 GHz.'}
    if len(names) > 1:
        return {'state': 'multiple', 'ssid': None,
                'message': 'Há mais de uma conexão Wi-Fi ativa. Informe abaixo a rede que o M5 deve usar.'}
    return {'state': 'no_wifi', 'ssid': None,
            'message': 'Nenhuma conexão Wi-Fi ativa foi detectada neste PC. Se ele usa cabo, informe abaixo a rede Wi-Fi do M5.'}


def profile_password(xml, ssid):
    profile = ElementTree.fromstring(xml)
    target = ssid.encode('utf-8').hex()
    for network in profile.findall('./{*}SSIDConfig/{*}SSID'):
        raw_name = network.findtext('{*}hex')
        matches = raw_name.lower() == target if raw_name else network.findtext('{*}name') == ssid
        if matches:
            break
    else:
        return None
    security = profile.find('./{*}MSM/{*}security')
    if security is None:
        return None
    auth = security.findtext('./{*}authEncryption/{*}authentication', '').upper()
    encryption = security.findtext('./{*}authEncryption/{*}encryption', '').upper()
    if security.findtext('./{*}authEncryption/{*}useOneX', '').lower() in ('true', '1'):
        return None
    if auth == 'OPEN' and encryption == 'NONE':
        return ''
    if auth not in ('WPAPSK', 'WPA2PSK', 'WPA3SAE'):
        return None
    if security.findtext('./{*}sharedKey/{*}protected', '').lower() not in ('false', '0'):
        return None
    password = security.findtext('./{*}sharedKey/{*}keyMaterial')
    if not password:
        return None
    validate_wifi(ssid, password)
    return password


def windows_profile_password(adapter, profile, ssid):
    wlan = ctypes.WinDLL('wlanapi.dll')
    handle, api_version = wintypes.HANDLE(), wintypes.DWORD()
    pointer = ctypes.c_void_p()
    guid = (ctypes.c_ubyte * 16).from_buffer_copy(UUID(adapter).bytes_le)
    pointer_type = ctypes.POINTER(ctypes.c_void_p)
    dword_pointer = ctypes.POINTER(wintypes.DWORD)
    wlan.WlanOpenHandle.argtypes = (wintypes.DWORD, ctypes.c_void_p, dword_pointer, ctypes.POINTER(wintypes.HANDLE))
    wlan.WlanOpenHandle.restype = wintypes.DWORD
    wlan.WlanCloseHandle.argtypes = (wintypes.HANDLE, ctypes.c_void_p)
    wlan.WlanCloseHandle.restype = wintypes.DWORD
    wlan.WlanFreeMemory.argtypes = (ctypes.c_void_p,)
    wlan.WlanFreeMemory.restype = None
    wlan.WlanGetProfile.argtypes = (wintypes.HANDLE, ctypes.c_void_p, wintypes.LPCWSTR,
                                   ctypes.c_void_p, pointer_type, dword_pointer, dword_pointer)
    wlan.WlanGetProfile.restype = wintypes.DWORD
    if wlan.WlanOpenHandle(2, None, ctypes.byref(api_version), ctypes.byref(handle)):
        return None
    try:
        flags = wintypes.DWORD(4)  # WLAN_PROFILE_GET_PLAINTEXT_KEY
        error = wlan.WlanGetProfile(handle, ctypes.byref(guid), profile, None, ctypes.byref(pointer),
                                    ctypes.byref(flags), None)
        return profile_password(ctypes.wstring_at(pointer), ssid) if not error and pointer.value else None
    finally:
        if pointer.value:
            wlan.WlanFreeMemory(pointer)
        wlan.WlanCloseHandle(handle, None)


def windows_network_json(command):
    executable = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    result = subprocess.run([str(executable), '-NoProfile', '-NonInteractive', '-Command', command],
                            capture_output=True, encoding='utf-8', errors='strict', timeout=10,
                            creationflags=subprocess.CREATE_NO_WINDOW, check=True)
    return json.loads(result.stdout.strip() or 'null')


def detect_hotspot(include_password=False):
    unavailable = {'state': 'unavailable', 'ssid': None,
                   'message': 'Ative o Hotspot móvel de 2,4 GHz nas configurações do Windows e tente novamente.'}
    if os.name != 'nt':
        return unavailable
    command = """[Console]::OutputEncoding=[Text.UTF8Encoding]::new();
$ErrorActionPreference='Stop';
$net=[Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime];
$type=[Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime];
$profile=$net::GetInternetConnectionProfile();
if ($null -eq $profile) { exit };
$manager=$type::CreateFromConnectionProfile($profile);
$config=$manager.GetCurrentAccessPointConfiguration();
$result=@{ssid=$config.Ssid};
if ($manager.TetheringOperationalState.ToString() -ne 'On' -or
    $config.Band.ToString() -ne 'TwoPointFourGigahertz') {
  $result | ConvertTo-Json -Compress; exit };
$adapters=@(Get-NetAdapter -IncludeHidden | Where-Object {
  $_.Status -eq 'Up' -and $_.InterfaceDescription -like 'Microsoft Wi-Fi Direct Virtual Adapter*' });
if ($adapters.Count -ne 1) { exit };
$ips=@(Get-NetIPAddress -InterfaceIndex $adapters[0].ifIndex -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '169.254.*' });
if ($ips.Count -ne 1) { exit };
$result.host=$ips[0].IPAddress;
"""
    if include_password:
        command += '$result.password=$config.Passphrase;\n'
    command += '$result | ConvertTo-Json -Compress'
    try:
        result = windows_network_json(command)
        if not isinstance(result, dict):
            return unavailable
        ssid = result.get('ssid')
        if not isinstance(ssid, str):
            return unavailable
        validate_wifi(ssid, '')
        host = result.get('host')
        if not host:
            return {**unavailable, 'ssid': ssid}
        if not IPv4Address(host).is_private:
            return unavailable
        password = result.get('password', '')
        if not isinstance(password, str) or include_password and not password:
            return unavailable
        validate_wifi(ssid, password)
    except (OSError, ValueError, TypeError, subprocess.SubprocessError):
        return unavailable
    return {**result, 'state': 'connected', 'message': 'Hotspot de 2,4 GHz do notebook detectado.'}


def detect_wifi(include_password=False):
    if os.name != 'nt':
        return {'state': 'unavailable', 'ssid': None, 'message': 'Informe a rede Wi-Fi do M5 abaixo.'}
    command = """[Console]::OutputEncoding=[Text.UTF8Encoding]::new();
$ErrorActionPreference='Stop';
$wifiProfiles=[Windows.Networking.Connectivity.NetworkInformation,Windows,ContentType=WindowsRuntime]::GetConnectionProfiles();
@($wifiProfiles | Where-Object { $_.IsWlanConnectionProfile -and $_.GetNetworkConnectivityLevel().ToString() -ne 'None' } |
ForEach-Object { [PSCustomObject]@{ssid=$_.WlanConnectionProfileDetails.GetConnectedSsid();connected=$true;
profile=$_.ProfileName;adapter=[string]$_.NetworkAdapter.NetworkAdapterId} }) | ConvertTo-Json -Compress
"""
    try:
        records = windows_network_json(command)
        records = [records] if isinstance(records, dict) else records
        connection = select_wifi(records)
    except (OSError, ValueError, TypeError, subprocess.SubprocessError):
        return {'state': 'unavailable', 'ssid': None,
                'message': 'O Windows não permitiu consultar o Wi-Fi. Você pode preencher a rede manualmente; confira também as permissões de localização do Windows.'}
    if not include_password or not connection['ssid']:
        return connection
    profiles = {(row['adapter'], row['profile']) for row in records if isinstance(row, dict)
                and row.get('connected') is True and row.get('ssid') == connection['ssid']
                and isinstance(row.get('adapter'), str) and isinstance(row.get('profile'), str)}
    if len(profiles) == 1:
        adapter, profile = profiles.pop()
        try:
            password = windows_profile_password(adapter, profile, connection['ssid'])
        except (OSError, ValueError, ElementTree.ParseError):
            password = None
        if password is not None:
            connection['password'] = password
    return connection


def autofill(saved_ssid, saved_password, detected_ssid):
    """Uma senha do projeto só é reutilizada para exatamente o mesmo SSID."""
    if not detected_ssid:
        return saved_ssid, saved_password
    return detected_ssid, saved_password if detected_ssid == saved_ssid else ''


def wifi_form_values(saved_ssid, saved_password, connection):
    if connection.get('state') == 'unavailable':
        return saved_ssid, saved_password, connection['message']
    detected = connection.get('ssid')
    ssid, password = autofill(saved_ssid, saved_password, detected)
    windows_password = connection.get('password')
    if detected and windows_password is not None:
        if windows_password:
            if connection.get('host'):
                return detected, windows_password, 'Hotspot de 2,4 GHz selecionado. O M5 usará o servidor pelo endereço do hotspot.'
            return detected, windows_password, 'Rede e senha preenchidas com os dados do Windows. O M5 usa Wi-Fi de 2,4 GHz.'
        return detected, '', 'A rede ativa do notebook é aberta. Nenhuma senha é necessária.'
    if detected and password:
        return ssid, password, 'Rede do notebook detectada. Usando a senha já salva no Atleta para essa rede.'
    if detected:
        return ssid, '', 'Rede do notebook preenchida. Se ela for protegida, informe a senha para o M5.'
    return ssid, password, connection['message']
