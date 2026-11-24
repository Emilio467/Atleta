"""Configuração local de Wi-Fi e perfil opcional do M5, sem imprimir credenciais."""
import argparse
from pathlib import Path
import tkinter as tk
from tkinter import ttk
import queue
import threading

from rede import atomic_json, read_json, port
from m5_serial import device_ports
from conexao_m5 import connect_easy
from wifi_pc import detect_wifi, validate_wifi, wifi_form_values
from servidor import LabError


def save_device_settings(folder, ssid, password, weight='', step_length='', met='', athlete_id=''):
    folder = Path(folder)
    validate_wifi(ssid, password)
    config = read_json(folder / 'config.local.json', {})
    if not isinstance(config, dict):
        raise ValueError('O arquivo de configuração precisa ser um objeto JSON.')
    profile = {}
    for key, raw, minimum, maximum in (
            ('weight_kg', weight, 10, 400), ('step_length_m', step_length, 0.1, 2.5),
            ('activity_met', met, 1, 25), ('athlete_id', athlete_id, 1, 2147483647)):
        if not raw.strip():
            profile[key] = None
            continue
        try:
            number = float(raw.replace(',', '.'))
        except ValueError:
            raise ValueError('Confira os números do perfil opcional.') from None
        if not minimum <= number <= maximum or key == 'athlete_id' and number != int(number):
            raise ValueError('Um número do perfil está fora do intervalo permitido.')
        profile[key] = int(number) if key == 'athlete_id' else number
    config.update(wifi_ssid=ssid, wifi_password=password, device_id='m5-atleta-01', **profile)
    config.setdefault('mqtt_host', '')
    config.setdefault('mqtt_port', 1883)
    if port(config['mqtt_port'], None) is None:
        raise ValueError('A porta MQTT na configuração é inválida.')
    atomic_json(folder / 'config.local.json', config)
    return config


class ConfigWindow:
    def __init__(self, root, folder, ssid='', on_data=None):
        self.root, self.folder = root, Path(folder)
        self.saved = False
        self.busy = False
        self.detecting = False
        self.closed = False
        self.events = queue.Queue()
        self.on_data = on_data
        config = read_json(self.folder / 'config.local.json', {})
        root.title('Atleta — conectar M5')
        root.configure(bg='#F3F5F7')
        style = ttk.Style(root)
        style.configure('TFrame', background='#F3F5F7')
        style.configure('TLabel', background='#F3F5F7', foreground='#17212B')
        root.geometry('660x800')
        root.minsize(620, 790)
        outer = ttk.Frame(root, padding=22)
        outer.pack(fill='both', expand=True)
        ttk.Label(outer, text='Conectar M5', font=('Segoe UI', 19, 'bold')).pack(anchor='w')
        ttk.Label(outer, text='1. Conecte o cabo USB.  2. Confira o Wi-Fi.  3. Clique em Conectar.',
                  font=('Segoe UI', 10), wraplength=590).pack(anchor='w', pady=(6, 12))
        self.tabs = ttk.Notebook(outer)
        self.tabs.pack(fill='x')
        network = ttk.Frame(self.tabs, padding=14)
        panel = ttk.Frame(self.tabs, padding=14)
        self.tabs.add(network, text='  Conexão  ', underline=2)
        self.tabs.add(panel, text='  Perfil do atleta (opcional)  ', underline=2)
        self.tabs.enable_traversal()
        ports = device_ports()
        self.usb_port = tk.StringVar(value=ports[0] if len(ports) == 1 else '')
        self.usb_hint = tk.StringVar()
        ttk.Label(network, text='M5 por USB', font=('Segoe UI', 10, 'bold')).pack(anchor='w')
        usb_row = ttk.Frame(network)
        usb_row.pack(fill='x', pady=(4, 10))
        self.port_combo = ttk.Combobox(usb_row, textvariable=self.usb_port, values=ports, width=12)
        self.port_combo.pack(side='left')
        ttk.Label(usb_row, textvariable=self.usb_hint, wraplength=390).pack(side='left', padx=12)
        self.ssid = tk.StringVar(value=ssid or config.get('wifi_ssid', ''))
        self.password = tk.StringVar(value=config.get('wifi_password', '') if self.ssid.get() == config.get('wifi_ssid') else '')
        self.ssid_trace = self.ssid.trace_add('write', lambda *_: self.password.set(''))
        self.entries = [self.port_combo]
        for label, variable, mask in (('Nome da rede', self.ssid, ''), ('Senha da rede', self.password, '*')):
            ttk.Label(network, text=label, font=('Segoe UI', 10)).pack(anchor='w', pady=(8, 4))
            entry = ttk.Entry(network, textvariable=variable, show=mask, font=('Segoe UI', 12))
            entry.pack(fill='x', ipady=5)
            self.entries.append(entry)
            if mask:
                self.password_entry = entry
        self.show_password = tk.BooleanVar(value=False)
        ttk.Checkbutton(network, text='Mostrar senha', variable=self.show_password,
                        command=lambda: self.password_entry.configure(show='' if self.show_password.get() else '*')).pack(anchor='w', pady=8)
        self.detect_button = ttk.Button(network, text='Usar o Wi-Fi deste computador', command=self.detect_network)
        self.detect_button.pack(anchor='w', pady=(0, 4))
        self.wifi_hint = tk.StringVar(value='Consultando a conexão Wi-Fi do computador…')
        ttk.Label(network, textvariable=self.wifi_hint, wraplength=530, font=('Segoe UI', 9)).pack(fill='x')
        self.profile = {}
        ttk.Label(panel, text='Opcional. Você pode conectar o M5 sem preencher estes campos.',
                  wraplength=530).grid(row=0, column=0, columnspan=2, sticky='w', pady=(0, 16))
        for row, (key, label) in enumerate((('weight_kg', 'Peso (kg)'), ('step_length_m', 'Comprimento de um passo (m)'),
                                            ('activity_met', 'Intensidade da atividade (MET)'), ('athlete_id', 'ID do atleta no projeto'))):
            value = config.get(key)
            variable = tk.StringVar(value='' if value is None else str(value))
            self.profile[key] = variable
            ttk.Label(panel, text=label).grid(row=row + 1, column=0, sticky='w', padx=(0, 12), pady=6)
            entry = ttk.Entry(panel, textvariable=variable, width=13)
            entry.grid(row=row + 1, column=1, sticky='ew', pady=6)
            self.entries.append(entry)
        panel.columnconfigure(1, weight=1)
        ttk.Label(panel, text='Sem comprimento de passo, a distância fica indisponível.\nSem peso e MET, as calorias ficam indisponíveis.',
                  font=('Segoe UI', 9), wraplength=530).grid(row=5, column=0, columnspan=2, sticky='w', pady=12)
        self.save_button = ttk.Button(panel, text='Salvar no computador sem enviar ao M5', command=self.save)
        self.save_button.grid(row=6, column=0, columnspan=2, sticky='ew')
        ttk.Label(outer, text='Use uma rede de 2,4 GHz com acesso a este computador.\nAo aplicar a configuração, o M5 reinicia e começa uma nova sessão.',
                  font=('Segoe UI', 9), wraplength=590).pack(fill='x', pady=(12, 0))
        self.feedback = tk.StringVar(value='A rede e a senha salvas no projeto já aparecem acima. Confira antes de conectar.')
        ttk.Label(outer, textvariable=self.feedback, wraplength=590, font=('Segoe UI', 10)).pack(fill='x', pady=12)
        self.progress = ttk.Progressbar(outer, mode='indeterminate')
        self.send_button = ttk.Button(outer, text='Conectar M5', command=self.send, style='Primary.TButton')
        self.send_button.pack(fill='x', ipady=8)
        self.view_button = ttk.Button(outer, text='Ver dados do atleta', command=self.open_data)
        root.bind('<Return>', lambda event: self.send())
        self.poll_id = root.after(100, self.poll)
        self.detect_id = root.after(150, self.detect_network)
        self.refresh_ports()
        root.bind('<Destroy>', self.on_destroy, add='+')
        self.password_entry.focus_set()

    def on_destroy(self, event):
        if event.widget is self.root:
            self.closed = True
            self.ssid.trace_remove('write', self.ssid_trace)
            for callback in (self.poll_id, self.ports_id, self.detect_id):
                self.root.after_cancel(callback)

    def refresh_ports(self):
        if self.closed:
            return
        if not self.busy:
            try:
                ports = device_ports()
            except OSError:
                ports = []
            self.port_combo.configure(values=ports)
            if len(ports) == 1 and (not self.usb_port.get() or self.usb_port.get() not in ports):
                self.usb_port.set(ports[0])
            elif not ports:
                self.usb_port.set('')
            self.usb_hint.set('Cabo detectado. Pronto para configurar.' if ports else 'Conecte o M5 com um cabo de dados.')
        self.ports_id = self.root.after(2000, self.refresh_ports)

    def open_data(self):
        if self.on_data:
            self.on_data()
        else:
            from dados_atleta import AthleteWindow
            window = getattr(self, 'data_window', None)
            if window is not None and window.winfo_exists():
                window.lift()
            else:
                self.data_window = tk.Toplevel(self.root)
                AthleteWindow(self.data_window, self.folder)

    def detect_network(self):
        if self.closed or self.busy or self.detecting:
            return
        self.detecting = True
        self.detect_button.configure(state='disabled')
        self.send_button.configure(state='disabled')
        baseline = self.ssid.get(), self.password.get()
        def worker():
            self.events.put(('wifi', (baseline, detect_wifi(include_password=True))))
        threading.Thread(target=worker, daemon=True).start()

    def apply_network(self, baseline, result):
        self.wifi_hint.set(result['message'])
        if (self.ssid.get(), self.password.get()) == baseline:
            ssid, password, message = wifi_form_values(*baseline, result)
            self.ssid.set(ssid)
            self.password.set(password)
            self.wifi_hint.set(message)

    def save(self):
        try:
            save_device_settings(self.folder, self.ssid.get(), self.password.get(),
                                 self.profile['weight_kg'].get(), self.profile['step_length_m'].get(),
                                 self.profile['activity_met'].get(), self.profile['athlete_id'].get())
        except (ValueError, OSError) as error:
            self.feedback.set(str(error) if isinstance(error, ValueError) else 'Não foi possível salvar nesta pasta.')
            return
        self.saved = True
        self.feedback.set('Configuração salva no computador. Clique em Conectar M5 para aplicá-la na placa.')

    def send(self):
        if self.busy or self.detecting:
            return
        if not self.usb_port.get():
            self.feedback.set('Conecte o M5 com um cabo USB de dados. A porta será detectada automaticamente.')
            return
        self.saved = False
        self.save()
        if not self.saved:
            return
        self.busy = True
        self.save_button.configure(state='disabled')
        self.send_button.configure(state='disabled')
        self.detect_button.configure(state='disabled')
        for entry in self.entries:
            entry.configure(state='disabled')
        self.view_button.pack_forget()
        self.send_button.configure(text='Conectando…')
        self.progress.pack(fill='x', before=self.send_button, pady=(0, 10))
        self.progress.start(12)
        self.feedback.set('Conferindo o computador e a conexão com o M5…')
        port_name = self.usb_port.get()
        def worker():
            try:
                result = connect_easy(self.folder, port_name,
                            progress=lambda message: self.events.put(('progress', message)))
                self.events.put(('done', result))
            except ValueError as error:
                self.events.put(('done', str(error)))
            except LabError as error:
                self.events.put(('done', str(error)))
            except Exception:
                self.events.put(('done', 'Não foi possível concluir a configuração USB. Confira o cabo e feche outros monitores seriais.'))
        threading.Thread(target=worker, daemon=True).start()

    def poll(self):
        if self.closed:
            return
        try:
            kind, message = self.events.get_nowait()
        except queue.Empty:
            pass
        else:
            if kind == 'wifi':
                self.apply_network(*message)
                self.detecting = False
                self.detect_button.configure(state='normal')
                self.send_button.configure(state='normal')
            elif kind == 'progress':
                self.feedback.set(message)
            else:
                self.busy = False
                self.save_button.configure(state='normal')
                self.send_button.configure(state='normal')
                self.send_button.configure(text='Conectar M5')
                self.detect_button.configure(state='normal')
                for entry in self.entries:
                    entry.configure(state='normal')
                self.progress.stop()
                self.progress.pack_forget()
                self.feedback.set(message)
                if message.startswith('Conexão confirmada:'):
                    self.view_button.pack(fill='x', pady=(8, 0), ipady=5)
        self.poll_id = self.root.after(100, self.poll)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pasta', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--ssid', default='')
    args = parser.parse_args()
    root = tk.Tk()
    ConfigWindow(root, args.pasta, args.ssid)
    root.mainloop()


if __name__ == '__main__':
    main()
