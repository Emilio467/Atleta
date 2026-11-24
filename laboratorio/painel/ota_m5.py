"""Descoberta e envio do firmware do M5 na rede local."""
from contextlib import ExitStack
import hashlib
import hmac
from ipaddress import IPv4Address, IPv4Network
import json
import os
from pathlib import Path
import queue
import re
import secrets
import select
import socket
import subprocess
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk

from m5_serial import device_ports, open_serial
from rede import atomic_json, detect_interfaces, port, read_json, valid_ip

if not getattr(sys, 'frozen', False):
    tools = str(Path(__file__).resolve().parents[1] / 'tools')
    if tools not in sys.path:
        sys.path.insert(0, tools)

from ota import release_app


PORT = 3232
DISCOVERY = 'ATLETA-OTA-DISCOVERY/1'
UPLOAD = 'ATLETA-OTA/1'
DISCOVERY_SECONDS = 25


def sign(key, message):
    return hmac.new(key.encode('ascii'), message.encode('ascii'), 'sha256').hexdigest()


def pairing_file(folder):
    return Path(folder) / 'runtime/ota-m5.json'


def pair_usb(folder):
    ports = device_ports()
    if len(ports) != 1:
        raise ValueError('Conecte somente um M5 por USB para vincular.')
    target = pairing_file(folder)
    pairing = read_json(target)
    key = pairing.get('key')
    if not isinstance(key, str) or not re.fullmatch(r'[0-9a-f]{64}', key):
        key = secrets.token_hex(32)
        pairing = {'key': key}
        atomic_json(target, pairing)
    with open_serial(ports[0]) as connection:
        time.sleep(2)
        connection.reset_input_buffer()
        connection.write(f'OTA_PAIR {key}\n'.encode('ascii'))
        connection.flush()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            answer = connection.readline().strip()
            if answer == b'OTA_PAIR_OK':
                break
            if answer == b'OTA_PAIR_ERROR':
                raise ValueError('O M5 recusou a gravação do vínculo. Tente novamente com a USB conectada.')
        else:
            raise ValueError('O M5 não confirmou o vínculo. Instale o firmware 2.2.0 ou posterior por USB.')

        connection.write(b'INVENTORY\n')
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            answer = connection.readline()
            if answer.startswith(b'INVENTORY '):
                ip = json.loads(answer[len(b'INVENTORY '):]).get('wifi_ip')
                if valid_ip(ip):
                    pairing['ip'] = ip
                break
    pairing['confirmed'] = True
    atomic_json(target, pairing)


def advertisement(data, key):
    try:
        marker, nonce, version, signature = data.decode('ascii').split(' ')
    except (UnicodeError, ValueError):
        return None
    if (marker != DISCOVERY or not re.fullmatch(r'[0-9a-f]{32}', nonce)
            or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,4}', version)
            or not hmac.compare_digest(signature, sign(key, f'{marker} {nonce} {version}'))):
        return None
    return nonce, version


def mqtt_peers(folder):
    """Suggest local TCP peers as hints. The signed OTA reply still identifies the M5."""
    if os.name != 'nt':
        return ()
    try:
        settings = read_json(Path(folder) / 'runtime/settings.json')
        mqtt_port = port(settings.get('mqtt_port'), None)
        if mqtt_port is None:
            return ()
        command = (f"@(Get-NetTCPConnection -LocalPort {mqtt_port} -State Established "
                   "-ErrorAction SilentlyContinue | Select-Object -ExpandProperty RemoteAddress -Unique) "
                   "| ConvertTo-Json -Compress")
        result = subprocess.run(['powershell.exe', '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', command],
                                capture_output=True, encoding='ascii', errors='replace', timeout=5,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode:
            return ()
        addresses = json.loads(result.stdout.strip() or '[]')
        if isinstance(addresses, str):
            addresses = [addresses]
        return tuple(value for value in addresses if valid_ip(value)) if isinstance(addresses, list) else ()
    except (OSError, ValueError, subprocess.SubprocessError):
        return ()


def find_m5(key, previous_ip=None, peer_ips=()):
    interfaces = [item for item in detect_interfaces() if not item.virtual]
    candidates = tuple(dict.fromkeys(ip for ip in (*peer_ips, previous_ip) if valid_ip(ip)))
    with ExitStack() as stack:
        contacts = []
        for item in interfaces:
            sock = stack.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
            try:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
                sock.bind((item.ip, 0))
            except OSError:
                continue
            network = IPv4Network(f'{item.ip}/{item.prefix}', strict=False) if item.prefix else None
            targets = [ip for ip in candidates if ip != item.ip and
                       (not network or (IPv4Address(ip) in network and IPv4Address(ip) != network.broadcast_address))]
            targets.append(str(network.broadcast_address) if network else '255.255.255.255')
            contacts.append((sock, targets))
        if not contacts:
            raise ValueError('Conecte o PC à mesma rede local do M5.')

        end = time.monotonic() + DISCOVERY_SECONDS
        while time.monotonic() < end:
            for sock, targets in contacts:
                for host in targets:
                    try:
                        sock.sendto(DISCOVERY.encode('ascii'), (host, PORT))
                    except OSError:
                        continue
            deadline = min(end, time.monotonic() + 1.2)
            while (remaining := deadline - time.monotonic()) > 0:
                ready, _, _ = select.select([sock for sock, _ in contacts], [], [], remaining)
                for sock in ready:
                    try:
                        data, (ip, port) = sock.recvfrom(256)
                    except ConnectionResetError:
                        # Windows reports ICMP port unreachable on the UDP socket.
                        continue
                    if port == PORT and (result := advertisement(data, key)):
                        return ip, *result
    raise ValueError('O OTA não respondeu. No M5, abra a tela OTA e segure B até aparecer o IP. Confira se o notebook consegue alcançar o relógio pela rede local.')


def update_m5(folder, progress):
    pairing = read_json(pairing_file(folder))
    key = pairing.get('key')
    if not pairing.get('confirmed') or not isinstance(key, str) or not re.fullmatch(r'[0-9a-f]{64}', key):
        raise ValueError('Use Vincular por USB para preparar o M5 neste computador.')
    version, image = release_app(Path(folder) / 'entrega/firmware')
    progress('Aguardando o M5 na rede local. Na tela OTA do relógio, segure B até aparecer o IP.', 0)
    ip, nonce, current = find_m5(key, pairing.get('ip'), mqtt_peers(folder))
    message = f'{UPLOAD} {nonce} {len(image)} {hashlib.sha256(image).hexdigest()}'
    header = f'{message} {sign(key, message)}\n'.encode('ascii')
    progress(f'M5 encontrado. Enviando {version} a partir de {current}…', 0)
    with socket.create_connection((ip, PORT), timeout=8) as connection:
        with connection.makefile('rb') as replies:
            connection.sendall(header)
            if replies.readline(16) != b'READY\n':
                raise ValueError('O M5 recusou o envio. Libere a tela OTA novamente e confira o vínculo.')
            for start in range(0, len(image), 32768):
                chunk = image[start:start + 32768]
                connection.sendall(chunk)
                progress('Enviando firmware…', (start + len(chunk)) * 100 / len(image))
            progress('Aguardando a confirmação do relógio…', 100)
            if replies.readline(16) != b'OK\n':
                raise ValueError('O M5 não confirmou a gravação. Confira a mensagem na tela antes de repetir.')
    pairing['ip'] = ip
    try:
        atomic_json(pairing_file(folder), pairing)
    except OSError:
        pass
    return version


class UpdateWindow:
    def __init__(self, root, folder):
        self.root, self.folder = root, folder
        self.events = queue.Queue()
        self.busy = False
        root.title('Atualizar M5 por Wi-Fi')
        root.geometry('520x290')
        root.minsize(490, 275)
        body = ttk.Frame(root, padding=20)
        body.pack(fill='both', expand=True)
        ttk.Label(body, text='Atualizar M5 por Wi-Fi',
                  font=('Segoe UI', 16, 'bold')).pack(anchor='w')
        ttk.Label(body, text='No relógio, toque em B até a tela OTA e segure B. '
                  'Depois clique em Atualizar M5.', wraplength=445).pack(anchor='w', pady=(8, 12))
        try:
            linked = read_json(pairing_file(folder)).get('confirmed')
        except (OSError, ValueError):
            linked = False
        self.status = tk.StringVar(value='M5 vinculado a este painel.' if linked
                                   else 'Na primeira vez, vincule o M5 por USB.')
        ttk.Label(body, textvariable=self.status, wraplength=445).pack(anchor='w', pady=(0, 8))
        self.progress = ttk.Progressbar(body, maximum=100)
        self.progress.pack(fill='x', pady=(0, 14))
        buttons = ttk.Frame(body)
        buttons.pack(fill='x', side='bottom')
        self.pair_button = ttk.Button(buttons, text='Vincular por USB', style='Secondary.TButton',
                                      command=lambda: self.run(True))
        self.pair_button.pack(side='left')
        self.update_button = ttk.Button(buttons, text='Atualizar M5', style='Primary.TButton',
                                        command=lambda: self.run(False))
        self.update_button.pack(side='right')
        root.protocol('WM_DELETE_WINDOW', self.close)
        root.after(80, self.poll)

    def close(self):
        if not self.busy:
            self.root.destroy()

    def run(self, pair):
        self.busy = True
        self.pair_button.state(['disabled'])
        self.update_button.state(['disabled'])
        self.progress['value'] = 0
        self.status.set('Vinculando pela USB…' if pair else 'Procurando o M5…')

        def worker():
            try:
                if pair:
                    pair_usb(self.folder)
                    message = 'M5 vinculado. Retire a USB, libere a tela OTA e clique em Atualizar M5.'
                else:
                    version = update_m5(self.folder, lambda text, value: self.events.put(('progress', text, value)))
                    message = f'Firmware {version} confirmado pelo M5. Aguarde o reinício.'
                self.events.put(('done', message, 100 if not pair else 0))
            except (OSError, ValueError, KeyError) as error:
                self.events.put(('done', f'Falha na operação. {error}', 0))

        threading.Thread(target=worker, daemon=True).start()

    def poll(self):
        while True:
            try:
                action, message, value = self.events.get_nowait()
            except queue.Empty:
                break
            self.status.set(message)
            self.progress['value'] = value
            if action == 'done':
                self.busy = False
                self.pair_button.state(['!disabled'])
                self.update_button.state(['!disabled'])
        self.root.after(80, self.poll)
