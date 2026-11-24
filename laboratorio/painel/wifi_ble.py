"""Configura o Wi-Fi do M5 via Bluetooth após autorização na tela do relógio."""
import asyncio
import hmac
import json
from pathlib import Path
import queue
import re
import secrets
import threading
import tkinter as tk
from tkinter import ttk

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakBluetoothNotAvailableError, BleakError
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from ota_m5 import pairing_file
from rede import atomic_json, detect_interfaces, port, read_json, valid_ip
from wifi_pc import detect_hotspot, detect_wifi, validate_wifi, wifi_form_values


SERVICE = '747e1000-7e91-4e27-a560-697562673001'
CONTROL = '747e1004-7e91-4e27-a560-697562673001'
STATUS = '747e1005-7e91-4e27-a560-697562673001'
DOMAIN = b'ATLETA-WIFI/1'
CLOSED, READY, TESTING, SAVED, AUTH_ERROR, INVALID, NETWORK_ERROR, STORAGE_ERROR, BUSY = range(9)
SEARCH_SECONDS = 60
INSTRUCTIONS = ('No M5, toque em B até Wi-Fi por Bluetooth. Segure B até aparecer '
                '“No painel: Configurar Wi-Fi”.')
WAITING_FOR_M5 = 'Aguardando o M5. Desconecte-o do app no celular, caso esteja em uso. ' + INSTRUCTIONS
MESSAGES = {
    CLOSED: 'O M5 respondeu por Bluetooth, mas a janela de configuração ficou fechada. ' + INSTRUCTIONS,
    AUTH_ERROR: 'O M5 não reconheceu o vínculo. Digite o código que aparece no relógio e tente de novo.',
    INVALID: 'O M5 recusou a configuração recebida. Confira os dados e tente novamente.',
    NETWORK_ERROR: 'Envio por Bluetooth concluído. O M5 não conseguiu entrar no Wi-Fi de 2,4 GHz. Confira o nome e a senha da rede. A rede anterior foi preservada.',
    STORAGE_ERROR: 'O M5 entrou na rede, mas não conseguiu salvar. A configuração anterior foi preservada.',
    BUSY: 'Finalize o treino no app do celular e libere a configuração no M5.',
}


class SearchCancelled(ValueError):
    def __init__(self):
        super().__init__('Busca cancelada. Você pode iniciar outro envio quando quiser.')


class SetupAttempt:
    def __init__(self):
        self._lock = threading.Lock()
        self.cancelled = False
        self.sending = False

    def cancel(self):
        with self._lock:
            if self.sending:
                return False
            self.cancelled = True
            return True

    def check_cancelled(self):
        if self.cancelled:
            raise SearchCancelled()

    def begin_transfer(self):
        with self._lock:
            self.check_cancelled()
            self.sending = True


def setup_secret(folder, code):
    code = code.strip().lower()
    if code:
        if not re.fullmatch(r'[0-9a-f]{16}', code):
            raise ValueError('Digite os 16 caracteres do código mostrado no M5.')
        return code
    pairing = read_json(pairing_file(folder), {})
    key = pairing.get('key')
    if pairing.get('confirmed') and isinstance(key, str) and re.fullmatch(r'[0-9a-f]{64}', key):
        return key
    raise ValueError('Informe o código mostrado no M5 para configurar a rede neste computador.')


def settings_frames(settings, secret, challenge):
    key = hmac.digest(secret.encode('ascii'), DOMAIN, 'sha256')
    nonce = secrets.token_bytes(12)
    plain = json.dumps(settings, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    payload = nonce + AESGCM(key).encrypt(nonce, plain, challenge)
    if len(payload) > 768:
        raise ValueError('A configuração excede o limite do M5.')
    return [b'\x01', *(b'\x02' + payload[i:i + 19] for i in range(0, len(payload), 19)), b'\x03']


def local_server(folder, ssid, preferred_ip=None):
    """Sugere o endereço que o M5 consegue usar na rede Wi-Fi escolhida."""
    hotspot = detect_hotspot()
    hotspot_ip = hotspot.get('host')
    on_hotspot = hotspot.get('ssid') == ssid and valid_ip(hotspot_ip)
    if not on_hotspot and detect_wifi().get('ssid') != ssid:
        if hotspot.get('ssid') == ssid:
            raise ValueError(hotspot['message'])
        return None
    runtime = read_json(folder / 'runtime/settings.json', {})
    mqtt_port = port(runtime.get('mqtt_port'), None)
    if not mqtt_port or runtime.get('bind') == '127.0.0.1':
        return None
    config = read_json(folder / 'config.local.json', {})
    password = config.get('mqtt_password') or read_json(folder / 'runtime/secrets.json', {}).get('m5-atleta-01')
    if not isinstance(password, str) or not 0 < len(password.encode('utf-8')) <= 128 or '\0' in password:
        return None
    if on_hotspot:
        return {'host': hotspot_ip, 'port': mqtt_port, 'password': password}
    addresses = [item.ip for item in detect_interfaces() if not item.virtual and valid_ip(item.ip) and item.ip != hotspot_ip]
    target = next((ip for ip in (preferred_ip, config.get('mqtt_host')) if ip in addresses), None)
    if target is None and len(addresses) == 1:
        target = addresses[0]
    return {'host': target, 'port': mqtt_port, 'password': password} if target else None


async def read_setup_status(client):
    value = await client.read_gatt_char(STATUS, use_cached=False)
    if len(value) != 17 or value[0] > BUSY:
        raise ValueError('Resposta de configuração Bluetooth incompatível. Atualize o firmware do M5.')
    return value[0], bytes(value[1:])


async def wait_for_setup(client, deadline, attempt, progress):
    clock = asyncio.get_running_loop().time
    waiting = False
    while clock() < deadline:
        attempt.check_cancelled()
        async with asyncio.timeout(min(5, max(0, deadline - clock()))):
            state, challenge = await read_setup_status(client)
        if state == BUSY:
            raise ValueError(MESSAGES[BUSY])
        if state in (TESTING, SAVED):
            raise ValueError('O M5 já está aplicando uma rede. Aguarde a configuração terminar.')
        if state != CLOSED:
            return challenge
        if not waiting:
            progress('M5 conectado por Bluetooth. Aguardando a liberação no relógio. ' + INSTRUCTIONS)
            waiting = True
        await asyncio.sleep(0.5)
    attempt.check_cancelled()
    raise ValueError(MESSAGES[CLOSED])


async def transfer_settings(settings, secret, progress, attempt=None):
    attempt = SetupAttempt() if attempt is None else attempt
    clock = asyncio.get_running_loop().time
    deadline = clock() + SEARCH_SECONDS
    target = None
    retries = 0
    progress(WAITING_FOR_M5)
    while clock() < deadline:
        attempt.check_cancelled()
        discovered = await BleakScanner.discover(timeout=min(4, deadline - clock()), service_uuids=[SERVICE], return_adv=True)
        attempt.check_cancelled()
        watches = [device for device, adv in discovered.values() if SERVICE in adv.service_uuids]
        if len(watches) > 1:
            raise ValueError('Há mais de um Atleta-M5 por perto. Deixe anunciando apenas o relógio que você quer configurar.')
        if not watches or target is not None and watches[0].address != target:
            continue
        watch = watches[0]
        target = watch.address
        confirmed = False
        progress('Conectando ao M5. Se o Windows pedir, confirme o pareamento.')
        try:
            remaining = deadline - clock()
            if remaining <= 0:
                break
            async with BleakClient(watch, services=[SERVICE], pair=True, timeout=min(30, remaining),
                                   winrt={'use_cached_services': False}) as client:
                if not client.services.get_characteristic(CONTROL) or not client.services.get_characteristic(STATUS):
                    raise ValueError('O Windows não encontrou o serviço de configuração. Confirme o firmware 2.2.2 ou posterior e o pareamento do M5.')
                challenge = await wait_for_setup(client, deadline, attempt, progress)
                frames = settings_frames(settings, secret, challenge)
                attempt.begin_transfer()
                progress('Enviando a configuração por Bluetooth…')
                async with asyncio.timeout(15):
                    for frame in frames:
                        await client.write_gatt_char(CONTROL, frame, response=True)
                progress('Configuração enviada. Aguardando o M5 testar e salvar a rede…')
                async with asyncio.timeout(30):
                    while True:
                        state, _ = await read_setup_status(client)
                        if state == SAVED:
                            confirmed = True
                            return
                        if state in MESSAGES:
                            raise ValueError(MESSAGES[state])
                        await asyncio.sleep(0.25)
        except BleakBluetoothNotAvailableError:
            raise
        except (BleakError, OSError, TimeoutError) as error:
            if confirmed:
                return
            attempt.check_cancelled()
            if attempt.sending:
                raise
            if retries or 'pair' in str(error).lower():
                raise ValueError('O M5 apareceu, mas o Windows não abriu a conexão Bluetooth. Desconecte-o do celular e confira se ele está pareado no Windows.') from error
            retries += 1
            progress('A conexão Bluetooth oscilou. Procurando o mesmo M5 novamente…')
    attempt.check_cancelled()
    raise ValueError('O M5 não apareceu durante a busca. ' + WAITING_FOR_M5)


def apply_network(folder, ssid, password, code, preferred_ip, progress, attempt=None):
    folder = Path(folder)
    validate_wifi(ssid, password)
    secret = setup_secret(folder, code)
    settings = {'ssid': ssid, 'password': password}
    server = local_server(folder, ssid, preferred_ip)
    if server:
        settings['server'] = server
    asyncio.run(transfer_settings(settings, secret, progress, attempt))

    try:
        config_path = folder / 'config.local.json'
        config = read_json(config_path, {})
        config.update(wifi_ssid=ssid, wifi_password=password)
        config.setdefault('device_id', 'm5-atleta-01')
        if server:
            config.update(mqtt_host=server['host'], mqtt_port=server['port'])
        atomic_json(config_path, config)
    except (OSError, ValueError, AttributeError):
        return 'Rede salva no M5. Não foi possível salvar uma cópia da configuração neste PC.'
    message = 'Rede testada e salva. O M5 vai reiniciar.'
    return message if server else message + ' Para receber leituras, mantenha o M5 e o servidor na mesma rede.'


class WifiBluetoothWindow:
    def __init__(self, root, folder, preferred_ip, open_usb):
        self.root, self.folder = root, Path(folder)
        self.preferred_ip, self.open_usb = preferred_ip, open_usb
        self.events = queue.Queue()
        self.busy = False
        self.closed = False
        self.attempt = None
        self.close_after_cancel = False
        self.controls = []

        config = read_json(self.folder / 'config.local.json', {})
        self.ssid = tk.StringVar(value=config.get('wifi_ssid', ''))
        self.password = tk.StringVar(value=config.get('wifi_password', ''))
        self.ssid_trace = self.ssid.trace_add('write', lambda *_: self.password.set(''))
        self.code = tk.StringVar()
        self.feedback = tk.StringVar(value='Detectando o Wi-Fi do notebook…')
        root.title('Atleta IP — configurar Wi-Fi por Bluetooth')
        root.geometry('650x580')
        shell = ttk.Frame(root, padding=22)
        shell.pack(fill='both', expand=True)
        ttk.Label(shell, text='Configurar Wi-Fi', font=('Segoe UI', 18, 'bold')).pack(anchor='w')
        ttk.Label(shell, text=INSTRUCTIONS, wraplength=560, justify='left').pack(anchor='w', pady=(6, 10))

        for title, value, mask in (('Rede Wi-Fi de 2,4 GHz', self.ssid, ''), ('Senha da rede', self.password, '*'),
                                   ('Código do M5 (se o PC ainda não estiver vinculado)', self.code, '')):
            ttk.Label(shell, text=title).pack(anchor='w', pady=(7, 3))
            entry = ttk.Entry(shell, textvariable=value, show=mask, font=('Segoe UI', 11))
            entry.pack(fill='x', ipady=3)
            self.controls.append(entry)
        sources = ttk.Frame(shell)
        sources.pack(anchor='w', pady=(10, 6))
        self.detect_button = ttk.Button(sources, text='Usar o Wi-Fi deste computador', command=self.use_pc_wifi,
                                        style='Secondary.TButton')
        self.detect_button.pack(side='left')
        self.hotspot_button = ttk.Button(sources, text='Usar hotspot do notebook', command=self.use_hotspot,
                                         style='Secondary.TButton')
        self.hotspot_button.pack(side='left', padx=(8, 0))
        ttk.Label(shell, textvariable=self.feedback, wraplength=560, justify='left').pack(fill='x', pady=(3, 10))
        self.progress = ttk.Progressbar(shell, mode='indeterminate')
        actions = ttk.Frame(shell)
        actions.pack(side='bottom', fill='x')
        self.usb_button = ttk.Button(actions, text='Configurar por USB', command=self.switch_to_usb,
                                      style='Secondary.TButton')
        self.usb_button.pack(side='left')
        self.send_button = ttk.Button(actions, text='Enviar por Bluetooth', command=self.send, style='Primary.TButton')
        self.send_button.pack(side='right')
        self.cancel_button = ttk.Button(actions, text='Cancelar busca', command=self.cancel_wait,
                                        style='Secondary.TButton')
        self.controls += [self.detect_button, self.hotspot_button, self.usb_button, self.send_button]
        root.update_idletasks()
        root.minsize(620, max(560, shell.winfo_reqheight() + round(root.winfo_fpixels('0.9i'))))
        root.protocol('WM_DELETE_WINDOW', self.close)
        root.bind('<Destroy>', self.on_destroy, add='+')
        root.bind('<Return>', lambda event: self.send())
        self.poll_id = root.after(90, self.poll)
        self.detect_id = root.after(120, lambda: self.detect_network(prefer_saved_hotspot=True))

    def close(self):
        if not self.busy:
            self.root.destroy()
        elif self.cancel_wait():
            self.close_after_cancel = True

    def cancel_wait(self):
        if self.attempt is not None and self.attempt.cancel():
            self.cancel_button.state(['disabled'])
            self.feedback.set('Cancelando a busca pelo M5…')
            return True
        return False

    def on_destroy(self, event):
        if event.widget is self.root:
            self.closed = True
            if self.attempt is not None:
                self.attempt.cancel()
            self.ssid.trace_remove('write', self.ssid_trace)
            self.root.after_cancel(self.poll_id)
            self.root.after_cancel(self.detect_id)

    def switch_to_usb(self):
        self.close()
        if self.closed:
            self.open_usb()

    def set_busy(self, busy):
        self.busy = busy
        for widget in self.controls:
            widget.state(['disabled'] if busy else ['!disabled'])
        if busy:
            self.progress.pack(fill='x', pady=(0, 8))
            self.progress.start(14)
        else:
            self.progress.stop()
            self.progress.pack_forget()
            self.cancel_button.pack_forget()
            self.attempt = None

    def use_pc_wifi(self):
        self.detect_network()

    def use_hotspot(self):
        self.detect_network(hotspot_only=True)

    def detect_network(self, hotspot_only=False, prefer_saved_hotspot=False):
        if self.busy or self.closed:
            return
        saved_ssid = self.ssid.get()
        self.set_busy(True)
        self.feedback.set('Consultando o Wi-Fi do computador…')

        def worker():
            network = detect_hotspot(include_password=True) if hotspot_only or prefer_saved_hotspot else None
            if not hotspot_only and (not network or network.get('ssid') != saved_ssid):
                network = detect_wifi(include_password=True)
            self.events.put(('detected', network))

        threading.Thread(target=worker, daemon=True).start()

    def send(self):
        if self.busy:
            return
        ssid, password, code = self.ssid.get(), self.password.get(), self.code.get()
        attempt = self.attempt = SetupAttempt()
        self.set_busy(True)
        self.cancel_button.state(['!disabled'])
        self.cancel_button.pack(side='right', padx=(0, 10))

        def worker():
            try:
                result = apply_network(self.folder, ssid, password, code, self.preferred_ip,
                                       lambda message: self.events.put(('progress', message)), attempt)
                event = ('saved', result)
            except ValueError as error:
                event = ('done', str(error))
            except BleakBluetoothNotAvailableError:
                event = ('done', 'Ative o Bluetooth deste computador e tente novamente.')
            except (BleakError, OSError, TimeoutError):
                event = ('done', 'Não foi possível confirmar a configuração. Confira a mensagem no relógio e, se necessário, libere novamente.')
            self.events.put(event)

        threading.Thread(target=worker, daemon=True).start()

    def poll(self):
        if self.closed:
            return
        while True:
            try:
                event, payload = self.events.get_nowait()
            except queue.Empty:
                break
            if event == 'detected':
                ssid, password, message = wifi_form_values(self.ssid.get(), self.password.get(), payload)
                self.ssid.set(ssid)
                self.password.set(password)
                self.feedback.set(message)
            elif event != 'progress' or self.attempt is None or not self.attempt.cancelled:
                self.feedback.set(payload)
                if event == 'saved':
                    self.code.set('')
            if event != 'progress':
                self.set_busy(False)
                if self.close_after_cancel:
                    self.root.destroy()
                    return
        if self.attempt is not None and self.attempt.sending:
            self.cancel_button.state(['disabled'])
        self.poll_id = self.root.after(90, self.poll)
