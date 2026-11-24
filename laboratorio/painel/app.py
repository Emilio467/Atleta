"""Painel portátil para preparar, iniciar e parar o laboratório EMQX/MySQL."""
from __future__ import annotations

import argparse
import ctypes
from datetime import datetime
import os
from pathlib import Path
import queue
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk
import webbrowser

from rede import detect_interfaces, diagnose, diagnose_local, find_folder, port_pairs, save_address, atomic_json, read_json
from servidor import LabController, LabError, network_enabled, initialized, prepare_files, operation_lock, DOCKER_DOWNLOAD
from live_readings import LiveReadings

VERSION = '1.11.2'
BG, WHITE, TEXT, MUTED = '#F2F6F3', '#FFFFFF', '#172C24', '#51665E'
ACCENT, GOOD, WARN, BAD = '#176453', '#166448', '#865500', '#A52D36'
BORDER, HERO, HERO_MUTED, MINT = '#D5E1DA', '#15352B', '#D0E4DA', '#C5F1D4'


class App:
    def __init__(self, root, folder):
        self.root, self.folder = root, Path(folder)
        self.events = queue.Queue()
        self.busy = False
        self.interfaces = []
        self.result = self.saved = self.last_error = None
        self.error_kind = None
        self.ip = tk.StringVar(value='Detectando…')
        self.adapter = tk.StringVar()
        self.status = tk.StringVar(value='Verificando o servidor')
        self.details = tk.StringVar(value='Consultando as conexões deste computador…')
        self.ports = tk.StringVar(value='MQTT —     Dashboard —')
        self.feedback = tk.StringVar()
        self.allow_network = tk.BooleanVar(value=network_enabled(self.folder))
        self.closed = self.health_busy = False
        self.health = {}
        self.health_at = 0
        self.live_readings = LiveReadings(self.folder)
        self.displayed_live = None
        self.heading = tk.StringVar(value='Verificando a conexão…')
        self.guidance = tk.StringVar(value='Consultando o servidor local e o relógio.')
        self.pc_summary = tk.StringVar(value='Verificando o computador…')
        self.m5_summary = tk.StringVar(value='Procurando o M5…')
        self.freshness = tk.StringVar(value='Consultando a última leitura…')
        root.title('Atleta IP')
        icon = Path(sys._MEIPASS) / 'painel.ico' if getattr(sys, 'frozen', False) else Path(__file__).parent / 'build/painel.ico'
        if icon.is_file():
            root.iconbitmap(str(icon))
        root.configure(bg=BG)
        root.resizable(True, True)
        root.geometry('900x720')
        style = ttk.Style(root)
        style.theme_use('clam')
        style.configure('TNotebook', background=BG, borderwidth=0)
        style.configure('TNotebook.Tab', padding=(16, 8), font=('Segoe UI', 10, 'bold'),
                        background='#E3EDE7', foreground=MUTED)
        style.map('TNotebook.Tab', background=[('selected', WHITE), ('active', '#DDEBE3')],
                  foreground=[('selected', ACCENT)])
        style.configure('TCombobox', font=('Segoe UI', 10), padding=6)
        style.configure('Primary.TButton', font=('Segoe UI', 11, 'bold'), padding=(16, 12),
                        background=ACCENT, foreground=WHITE, borderwidth=0, focusthickness=2, focuscolor=TEXT)
        style.map('Primary.TButton', background=[('disabled', '#D5DFDB'), ('pressed', '#104637'), ('active', '#124F41')],
                  foreground=[('disabled', '#485A53')])
        style.configure('Secondary.TButton', font=('Segoe UI', 10), padding=(9, 9),
                        background=WHITE, foreground=TEXT, borderwidth=1, bordercolor=BORDER, focuscolor=ACCENT)
        style.map('Secondary.TButton', background=[('active', '#E5EBE8')])
        style.configure('Hero.TButton', font=('Segoe UI', 10, 'bold'), padding=(13, 11),
                        background=MINT, foreground=HERO, borderwidth=0, focuscolor=HERO)
        style.map('Hero.TButton', background=[('pressed', '#A5DEB9'), ('active', '#DCF8E6')])
        style.configure('TCheckbutton', background=BG, foreground=TEXT, font=('Segoe UI', 10))
        style.map('TCheckbutton', background=[('active', BG)])
        frame = tk.Frame(root, bg=BG, padx=24, pady=15)
        frame.pack(fill='both', expand=True)
        tk.Label(frame, text='Atleta IP', font=('Segoe UI', 24, 'bold'), fg=TEXT, bg=BG,
                 anchor='w').pack(fill='x', pady=(0, 8))
        self.notebook = ttk.Notebook(frame)
        self.notebook.pack(fill='both', expand=True)
        home = tk.Frame(self.notebook, bg=BG, pady=12)
        outer = tk.Frame(self.notebook, bg=BG, padx=16, pady=14)
        self.log_tab = tk.Frame(self.notebook, bg=BG, pady=12)
        self.notebook.add(home, text='Início', underline=0)
        self.notebook.add(outer, text='Opções avançadas', underline=0)
        self.notebook.add(self.log_tab, text='Detalhes', underline=0)
        self.notebook.enable_traversal()
        self.build_home(home)
        self.build_log_tab()
        self.notebook.bind('<<NotebookTabChanged>>', self.on_tab_changed)

        card = tk.Frame(outer, bg=WHITE, highlightbackground=BORDER, highlightthickness=1, padx=20, pady=15)
        card.pack(fill='x')
        tk.Label(card, text='ENDEREÇO IP', font=('Segoe UI', 9, 'bold'), fg=MUTED, bg=WHITE, anchor='w').pack(fill='x')
        tk.Label(card, textvariable=self.ip, font=('Consolas', 21, 'bold'), fg=TEXT, bg=WHITE,
                 anchor='w').pack(fill='x', pady=(3, 10))
        self.combo = ttk.Combobox(card, textvariable=self.adapter, state='disabled', takefocus=True)
        self.combo.pack(fill='x')
        self.combo.bind('<<ComboboxSelected>>', lambda event: self.refresh(False, keep=True))
        self.status_label = tk.Label(card, textvariable=self.status, font=('Segoe UI', 12, 'bold'), fg=MUTED,
                                     bg=WHITE, anchor='w')
        self.status_label.pack(fill='x', pady=(15, 5))
        self.detail_label = tk.Label(card, textvariable=self.details, font=('Segoe UI', 10), fg=MUTED, bg=WHITE,
                                     anchor='nw', justify='left', wraplength=480, height=3)
        self.detail_label.pack(fill='x')
        tk.Label(card, textvariable=self.ports, font=('Consolas', 10), fg=TEXT, bg=WHITE,
                 anchor='w').pack(fill='x', pady=(5, 0))
        self.network_check = ttk.Checkbutton(outer, text='Permitir conexão do M5 pela rede', variable=self.allow_network)
        self.network_check.pack(anchor='w', pady=(12, 10))
        row = tk.Frame(outer, bg=BG)
        row.pack(fill='x')
        self.refresh_button = ttk.Button(row, text='Atualizar IP', style='Secondary.TButton',
                                         command=lambda: self.refresh(True, keep=True))
        self.refresh_button.pack(side='left', fill='x', expand=True, padx=(0, 5))
        self.stop_button = ttk.Button(row, text='Parar laboratório', style='Secondary.TButton', command=self.stop_lab)
        self.stop_button.pack(side='left', fill='x', expand=True, padx=(5, 0))
        row2 = tk.Frame(outer, bg=BG)
        row2.pack(fill='x', pady=(9, 0))
        self.copy_button = ttk.Button(row2, text='Copiar IP', style='Secondary.TButton', command=self.copy_ip)
        self.copy_button.pack(side='left', fill='x', expand=True, padx=(0, 5))
        self.dashboard_button = ttk.Button(row2, text='Abrir Dashboard', style='Secondary.TButton', command=self.open_dashboard)
        self.dashboard_button.pack(side='left', fill='x', expand=True, padx=5)
        self.password_button = ttk.Button(row2, text='Copiar senha admin', style='Secondary.TButton', command=self.copy_password)
        self.password_button.pack(side='left', fill='x', expand=True, padx=(5, 0))
        from nuvem import CloudWorker
        self.cloud_worker = CloudWorker(self.folder, lambda result: self.events.put(('cloud', result)))
        self.cloud_worker.start()
        root.bind('<Destroy>', self.on_destroy, add='+')
        footer = tk.Frame(frame, bg=BG)
        footer.pack(side='bottom', fill='x', pady=(8, 0), before=self.notebook)
        self.details_button = ttk.Button(footer, text='Ver detalhes', style='Secondary.TButton', command=self.open_details)
        self.details_button.pack(side='right')
        tk.Label(footer, text=f'v{VERSION}', font=('Segoe UI', 9), fg=MUTED, bg=BG).pack(side='left')
        self.feedback_label = tk.Label(footer, textvariable=self.feedback, font=('Segoe UI', 9), fg=MUTED,
                                       bg=BG, justify='left', anchor='w', wraplength=570)
        self.feedback_label.pack(side='left', fill='x', expand=True, padx=12)
        self.actions = (self.primary, self.refresh_button, self.stop_button, self.copy_button,
                        self.dashboard_button, self.password_button, self.network_check, self.m5_button)
        root.bind('<F5>', lambda event: self.refresh(False, keep=True))
        root.bind('<Control-m>', lambda event: self.open_wifi_config())
        root.bind('<Control-d>', lambda event: self.open_athlete_data())
        root.bind('<Configure>', self.resize)
        root.update_idletasks()
        vertical_margin = round(root.winfo_fpixels('0.4i'))
        root.minsize(760, max(625, frame.winfo_reqheight() + vertical_margin))
        root.after(80, self.poll)
        root.after(150, lambda: self.refresh(False))
        root.after(300, self.monitor)

    def build_home(self, home):
        hero = tk.Frame(home, bg=HERO, padx=20, pady=16)
        hero.pack(fill='x', pady=(0, 12))
        hero.columnconfigure(0, weight=1)
        self.heading_label = tk.Label(hero, textvariable=self.heading, font=('Segoe UI', 18, 'bold'),
                                      fg=WHITE, bg=HERO, anchor='w', justify='left')
        self.heading_label.grid(row=0, column=0, sticky='ew')
        self.guidance_label = tk.Label(hero, textvariable=self.guidance, font=('Segoe UI', 10),
                                       fg=HERO_MUTED, bg=HERO, anchor='w', justify='left', wraplength=510)
        self.guidance_label.grid(row=1, column=0, sticky='ew', pady=(4, 0))
        self.athlete_button = ttk.Button(hero, text='Ver dados do atleta', command=self.open_athlete_data,
                                         style='Hero.TButton')
        self.athlete_button.grid(row=0, column=1, rowspan=2, sticky='e', padx=(12, 0))

        metrics = tk.Frame(home, bg=BG)
        metrics.pack(fill='x')
        self.metric_text = {}
        for column, (key, title) in enumerate((('passos', 'Passos'), ('tempo', 'Tempo de atividade'), ('bateria', 'Bateria'))):
            metrics.columnconfigure(column, weight=1, uniform='metric')
            card = tk.Frame(metrics, bg=WHITE, padx=14, pady=10, highlightthickness=1, highlightbackground=BORDER)
            card.grid(row=0, column=column, sticky='nsew', padx=(0, 10 if column < 2 else 0))
            tk.Label(card, text=title, bg=WHITE, fg=MUTED, font=('Segoe UI', 10)).pack(anchor='w')
            self.metric_text[key] = tk.StringVar(value='—')
            tk.Label(card, textvariable=self.metric_text[key], bg=WHITE, fg=TEXT,
                     font=('Segoe UI', 22, 'bold')).pack(anchor='w')
        self.freshness_label = tk.Label(home, textvariable=self.freshness, bg=BG, fg=MUTED,
                                        font=('Segoe UI', 9), anchor='w')
        self.freshness_label.pack(fill='x', pady=(5, 13))

        tk.Label(home, text='Conexão e manutenção', bg=BG, fg=TEXT,
                 font=('Segoe UI', 13, 'bold'), anchor='w').pack(fill='x', pady=(0, 7))
        connections = tk.Frame(home, bg=BG)
        connections.pack(fill='x')
        connections.columnconfigure(0, weight=2, uniform='connection')
        connections.columnconfigure(1, weight=3, uniform='connection')

        def connection_card(column, title, summary):
            card = tk.Frame(connections, bg=WHITE, padx=14, pady=11,
                            highlightthickness=1, highlightbackground=BORDER)
            card.grid(row=0, column=column, sticky='nsew', padx=(0, 10 if column == 0 else 0))
            tk.Label(card, text=title, bg=WHITE, fg=TEXT, font=('Segoe UI', 11, 'bold')).pack(anchor='w')
            label = tk.Label(card, textvariable=summary, bg=WHITE, fg=MUTED, font=('Segoe UI', 10),
                             anchor='w', justify='left', wraplength=245)
            label.pack(fill='x', pady=(2, 7))
            actions = tk.Frame(card, bg=WHITE)
            actions.pack(side='bottom', fill='x')
            return label, actions

        self.pc_label, server_actions = connection_card(0, 'Servidor local', self.pc_summary)
        self.primary = ttk.Button(server_actions, text='Preparar computador', command=self.start_lab,
                                  style='Secondary.TButton')
        self.primary.pack(side='left')
        self.m5_label, watch_actions = connection_card(1, 'Relógio M5', self.m5_summary)
        self.m5_button = ttk.Button(watch_actions, text='Configurar Wi-Fi', command=self.open_wifi_config,
                                    style='Secondary.TButton')
        self.m5_button.pack(side='left')
        self.update_button = ttk.Button(watch_actions, text='Atualizar por Wi-Fi', command=self.open_m5_update,
                                        style='Secondary.TButton')
        self.update_button.pack(side='left', padx=(8, 0))

        self.cloud_status = tk.StringVar(value='Nuvem • verificando conexão…')
        self.cloud_label = tk.Label(home, textvariable=self.cloud_status, font=('Segoe UI', 10), fg=MUTED,
                                    bg=BG, anchor='w', justify='left', wraplength=750)
        self.cloud_label.pack(fill='x', pady=(12, 0))

    def build_log_tab(self):
        header = tk.Frame(self.log_tab, bg=BG)
        header.pack(fill='x', pady=(0, 8))
        tk.Label(header, text='Registro do servidor local', bg=BG, fg=TEXT,
                 font=('Segoe UI', 15, 'bold')).pack(side='left')
        ttk.Button(header, text='Atualizar registro', style='Secondary.TButton',
                   command=self.refresh_details).pack(side='right')
        self.install_docker_button = ttk.Button(header, text='Instalar Docker', style='Secondary.TButton',
                                                 command=lambda: webbrowser.open(DOCKER_DOWNLOAD))
        self.log_status = tk.StringVar()
        self.log_status_label = tk.Label(self.log_tab, textvariable=self.log_status, bg=BG, fg=MUTED,
                                         anchor='w', justify='left', font=('Segoe UI', 9))
        self.log_status_label.pack(fill='x', pady=(0, 6))

        card = tk.Frame(self.log_tab, bg=WHITE, highlightbackground=BORDER, highlightthickness=1)
        card.pack(fill='both', expand=True)
        scrollbar = ttk.Scrollbar(card, orient='vertical')
        scrollbar.pack(side='right', fill='y')
        self.log_text = tk.Text(card, bg=WHITE, fg=TEXT, font=('Consolas', 10), relief='flat',
                                borderwidth=0, padx=12, pady=10, wrap='word', width=1, height=1,
                                yscrollcommand=scrollbar.set, state='disabled')
        self.log_text.pack(side='left', fill='both', expand=True)
        scrollbar.configure(command=self.log_text.yview)

    def resize(self, event):
        if event.widget == self.root:
            self.detail_label.configure(wraplength=max(400, event.width - 170))
            self.log_status_label.configure(wraplength=event.width - 64)
            self.feedback_label.configure(wraplength=max(400, event.width - 240))
            self.heading_label.configure(wraplength=event.width - 310)
            self.guidance_label.configure(wraplength=event.width - 310)
            self.cloud_label.configure(wraplength=event.width - 64)
            self.pc_label.configure(wraplength=int((event.width - 70) * .4) - 32)
            self.m5_label.configure(wraplength=int((event.width - 70) * .6) - 32)

    def on_destroy(self, event):
        if event.widget is self.root:
            self.closed = True
            self.cloud_worker.stop()
            self.live_readings.stop()

    def monitor(self):
        if self.closed:
            return
        self.live_readings.refresh()
        if not self.health_busy and not self.busy:
            self.health_busy = True
            address = self.result.get('ip') if self.result else None
            def worker():
                from inicio import read_overview
                try:
                    self.events.put(('health', read_overview(self.folder, address)))
                except Exception:
                    self.events.put(('health', {'ports': [], 'database_error': True, 'row': None, 'server_ready': False}))
            threading.Thread(target=worker, daemon=True).start()
        self.render_home()
        self.root.after(3000, self.monitor)

    def render_home(self):
        from dados_atleta import RECENT_SECONDS, metric_values
        stored = self.health.get('row')
        direct = self.live_readings.current(stored)
        self.displayed_live = direct
        row = direct.as_row() if direct else stored
        age = direct.age_seconds if direct else (stored['age_seconds'] + max(0, time.monotonic() - self.health_at) if stored else None)
        live = bool(direct or (stored and not self.health.get('database_error') and age <= RECENT_SECONDS))
        ready = bool(direct) or self.health.get('server_ready', bool(self.result and self.result['state'] in ('online', 'mqtt_only')))
        checked = bool(direct or self.health or self.result)
        ports = self.health.get('ports', [])
        if checked:
            self.pc_summary.set('Pronto para receber dados' if ready else 'Indisponível para receber dados')
        self.pc_label.configure(fg=GOOD if ready else MUTED)
        self.primary.configure(style='Secondary.TButton' if ready or not checked else 'Primary.TButton')
        if live:
            self.m5_summary.set('Wi-Fi ativo • recebendo ao vivo' if direct else 'Wi-Fi ativo • recebendo dados')
            self.freshness.set('Leitura recebida agora' if age < 2 else f'Leitura recebida há {int(age)} s')
        elif checked:
            self.m5_summary.set(f'USB detectado ({", ".join(ports)})' if ports else 'Sem dados recentes do M5')
            self.freshness.set('Última leitura salva em ' + row['received_at'].astimezone().strftime('%d/%m às %H:%M')
                               if row else 'Nenhuma leitura do M5 disponível')
        self.m5_label.configure(fg=GOOD if live else MUTED)
        self.freshness_label.configure(fg=GOOD if live else MUTED)
        values = metric_values(row['payload'] if row else {})
        for key, field in self.metric_text.items():
            field.set('—' if values[key] == 'Indisponível' else values[key])
        if self.busy:
            self.heading.set(self.status.get())
            self.guidance.set('Acompanhe o andamento no rodapé.')
        elif self.last_error:
            self.heading.set(self.status.get())
            self.guidance.set(self.last_error)
        elif live:
            self.heading.set('M5 conectado por Wi-Fi')
            self.guidance.set('Abra os dados do atleta para ver o histórico.')
        elif not checked:
            self.heading.set('Verificando a conexão…')
            self.guidance.set('Consultando o servidor local e o relógio.')
        elif not ready:
            self.heading.set('Servidor local indisponível')
            self.guidance.set('Prepare o computador para receber as leituras do M5.')
        else:
            self.heading.set('Aguardando dados do M5')
            self.guidance.set('Ligue o relógio na mesma rede ou configure o Wi-Fi do M5 por Bluetooth.')
        self.heading_label.configure(fg=MINT if live and not self.busy and not self.last_error else WHITE)

    def selected_ip(self):
        index = self.combo.current()
        return self.interfaces[index].ip if 0 <= index < len(self.interfaces) else None

    def snapshot(self, save, selected):
        interfaces = detect_interfaces()
        if selected is None:
            selected = read_json(self.folder / 'config.local.json', {}).get('mqtt_host')
        chosen = next((item for item in interfaces if item.ip == selected), interfaces[0] if interfaces else None)
        pairs = port_pairs(self.folder)
        result = diagnose(chosen.ip, pairs) if chosen else diagnose_local(pairs)
        path = save_address(self.folder, result) if save and chosen else None
        return interfaces, chosen, result, path

    def dispatch(self, title, worker):
        if self.busy:
            return
        self.busy, self.last_error, self.error_kind = True, None, None
        for button in self.actions:
            button.configure(state='disabled')
        self.combo.configure(state='disabled')
        self.primary.configure(text='Aguarde…')
        self.status.set(title)
        self.status_label.configure(fg=MUTED)
        self.details.set('A janela continuará respondendo durante a operação.')
        self.feedback.set('Aguarde a conclusão antes de iniciar outra operação.')
        self.render_home()
        def run():
            try:
                self.events.put(('result', worker()))
            except Exception as error:
                LabController(self.folder).record_error(error, f'{title} (Painel {VERSION})')
                if isinstance(error, LabError):
                    message, kind = str(error), error.kind
                elif isinstance(error, PermissionError):
                    message, kind = 'Sem permissão para gravar. Mova o aplicativo para uma pasta sua.', 'permission'
                elif isinstance(error, ValueError):
                    message, kind = 'Configuração inválida. Confira os arquivos JSON antes de tentar novamente.', 'configuration'
                else:
                    message, kind = f'Não foi possível concluir ({type(error).__name__}). Consulte os detalhes.', 'operation'
                self.events.put(('error', (message, kind)))
        threading.Thread(target=run, daemon=True).start()

    def refresh(self, save, keep=False):
        selected = self.selected_ip() if keep else None
        self.dispatch('Verificando o servidor', lambda: (*self.snapshot(save, selected), None))

    def start_lab(self):
        selected, allow = self.selected_ip(), self.allow_network.get()
        def worker():
            controller = LabController(self.folder, lambda text: self.events.put(('progress', text)))
            result = controller.start(allow)
            return (*self.snapshot(True, selected), {'type': 'start', **result})
        self.dispatch('Iniciando o laboratório', worker)

    def stop_lab(self):
        selected = self.selected_ip()
        def worker():
            controller = LabController(self.folder, lambda text: self.events.put(('progress', text)))
            result = controller.stop()
            return (*self.snapshot(False, selected), {'type': 'stop', **result})
        self.dispatch('Parando o laboratório', worker)

    def poll(self):
        if self.closed:
            return
        if self.live_readings.current(self.health.get('row')) is not self.displayed_live:
            self.render_home()
        try:
            kind, value = self.events.get_nowait()
        except queue.Empty:
            self.root.after(80, self.poll)
            return
        if kind == 'cloud':
            message = value['message']
            if 'DNS' in message:
                message = 'Nuvem Aiven indisponível (DNS). As leituras continuam neste computador.'
            elif value.get('state') == 'online' and not value.get('pending'):
                message = 'Nuvem conectada • histórico sincronizado.'
            self.cloud_status.set(message)
            self.cloud_label.configure(fg=GOOD if value.get('state') == 'online' else WARN)
            self.root.after(80, self.poll)
            return
        if kind == 'health':
            self.health_busy = False
            if not self.busy:
                observed_at = time.monotonic()
                if value['database_error'] and (previous := self.health.get('row')):
                    elapsed = max(0, observed_at - self.health_at)
                    value['row'] = {**previous, 'age_seconds': previous['age_seconds'] + elapsed}
                self.health, self.health_at = value, observed_at
                self.render_home()
            self.root.after(80, self.poll)
            return
        if kind == 'progress':
            self.details.set(value)
            self.feedback.set(value)
            self.root.after(80, self.poll)
            return
        self.busy = False
        for button in self.actions:
            button.configure(state='normal')
        self.primary.configure(text='Preparar computador')
        self.stop_button.configure(state='normal' if initialized(self.folder) else 'disabled')
        self.password_button.configure(state='normal' if (self.folder / 'runtime/secrets.json').is_file() else 'disabled')
        self.copy_button.configure(state='disabled')
        self.dashboard_button.configure(state='disabled')
        if kind == 'result':
            self.interfaces, chosen, self.result, path, action = value
            self.ip.set(chosen.ip if chosen else 'Sem IP de rede')
            self.combo.configure(values=[f'{item.name} — {item.ip}' for item in self.interfaces],
                                 state='readonly' if chosen else 'disabled')
            if chosen:
                self.combo.current(self.interfaces.index(chosen))
                self.copy_button.configure(state='normal')
            else:
                self.adapter.set('Conecte este PC ao Wi-Fi ou Ethernet')
            state = self.result['state']
            if state == 'online':
                title, detail, color = 'Online — EMQX respondendo', 'MQTT e Dashboard responderam neste IP. O teste de conexão a partir do M5 ainda depende da placa.', GOOD
            elif state == 'mqtt_only':
                title, detail, color = 'MQTT online • Dashboard indisponível', 'Um broker MQTT respondeu, mas o Dashboard não foi identificado nas portas verificadas.', WARN
            elif state == 'local_only':
                title, detail, color = 'Pronto para usar neste PC', 'O Dashboard está disponível localmente. Para conectar o M5, marque a opção de rede e clique em iniciar.', WARN
                if self.allow_network.get():
                    detail = 'O MQTT respondeu apenas pelo acesso local. Confira a publicação das portas e o firewall para conectar o M5.'
                if not self.result['loopback']['dashboard_online']:
                    title, detail = 'MQTT disponível apenas neste PC', 'O MQTT respondeu por localhost, mas o Dashboard não foi identificado nas portas verificadas.'
            else:
                title, detail, color = 'Offline — servidor sem resposta', 'Clique em iniciar. O programa prepara os arquivos, inicia o Docker e aguarda o EMQX e o MySQL.', BAD
            if not chosen and state == 'offline':
                title, detail = 'Sem IP de rede', 'Conecte este PC à rede. Se as imagens já estiverem instaladas, o laboratório também pode iniciar localmente.'
            self.status.set(title)
            self.status_label.configure(fg=color)
            self.details.set(detail)
            self.ports.set(f"MQTT {self.result['mqtt_port']}     Dashboard {self.result['dashboard_port']}")
            self.dashboard_button.configure(state='normal' if self.result['dashboard_url'] else 'disabled')
            self.saved = path or self.saved
            if action and action['type'] == 'start':
                self.feedback.set('Computador preparado. Ligue o M5 para receber dados.')
            elif action and action['type'] == 'stop':
                self.feedback.set('Laboratório parado. Dados e configurações foram preservados.')
            elif path:
                self.feedback.set('IP atualizado na configuração. Wi-Fi e senhas existentes foram preservados.')
            else:
                self.feedback.set(f'Conexão verificada às {datetime.now():%H:%M:%S}.')
        else:
            self.last_error, self.error_kind = value
            self.status.set({'docker_missing': 'Docker não encontrado',
                             'docker_not_ready': 'Docker ainda não está pronto',
                             'docker_network': 'Falha de rede no Docker',
                             'port_busy': 'Porta do laboratório ocupada',
                             'permission': 'Sem permissão para gravar'}.get(self.error_kind, 'Não foi possível concluir'))
            self.status_label.configure(fg=BAD)
            self.details.set(self.last_error)
            self.feedback.set('Abra Ver detalhes para encontrar o instalador do Docker.' if self.error_kind == 'docker_missing'
                              else 'Clique em Ver detalhes para consultar o registro da operação.')
        self.on_tab_changed()
        self.render_home()
        self.root.after(80, self.poll)

    def copy_ip(self):
        if self.result and self.result['ip']:
            self.root.clipboard_clear()
            self.root.clipboard_append(self.result['ip'])
            self.feedback.set('IP copiado para a área de transferência.')

    def copy_password(self):
        try:
            password = read_json(self.folder / 'runtime/secrets.json')['dashboard']
            self.root.clipboard_clear()
            self.root.clipboard_append(password)
            self.feedback.set('Senha copiada. No Dashboard, use o usuário admin e cole a senha.')
        except (OSError, ValueError, KeyError):
            self.feedback.set('A senha desta instalação ainda não está disponível.')

    def open_dashboard(self):
        if self.result and self.result['dashboard_url']:
            webbrowser.open(self.result['dashboard_url'])

    def open_wifi_config(self):
        if self.busy:
            return
        for name in ('wifi_window', 'm5_window'):
            window = getattr(self, name, None)
            if window is not None and window.winfo_exists():
                window.lift()
                return
        from wifi_ble import WifiBluetoothWindow
        window = tk.Toplevel(self.root)
        try:
            WifiBluetoothWindow(window, self.folder, self.selected_ip(), self.open_m5_config)
        except (OSError, ValueError):
            window.destroy()
            self.feedback.set('Não foi possível ler a configuração do M5 nesta pasta.')
            return
        self.wifi_window = window

    def open_m5_config(self):
        if self.busy:
            return
        from configurar_m5 import ConfigWindow
        window = getattr(self, 'm5_window', None)
        if window is not None and window.winfo_exists():
            window.lift()
            return
        self.m5_window = tk.Toplevel(self.root)
        ConfigWindow(self.m5_window, self.folder, on_data=self.open_athlete_data)

    def open_athlete_data(self):
        from dados_atleta import AthleteWindow
        window = getattr(self, 'athlete_window', None)
        if window is not None and window.winfo_exists():
            window.lift()
            return
        self.athlete_window = tk.Toplevel(self.root)
        AthleteWindow(self.athlete_window, self.folder, self.live_readings)

    def open_m5_update(self):
        from ota_m5 import UpdateWindow
        window = getattr(self, 'm5_update_window', None)
        if window is not None and window.winfo_exists():
            window.lift()
            return
        self.m5_update_window = tk.Toplevel(self.root)
        UpdateWindow(self.m5_update_window, self.folder)

    def open_details(self):
        if self.notebook.select() == str(self.log_tab):
            self.refresh_details()
        else:
            self.notebook.select(self.log_tab)

    def on_tab_changed(self, event=None):
        if self.notebook.select() == str(self.log_tab):
            self.refresh_details()

    def refresh_details(self):
        if self.error_kind == 'docker_missing':
            self.install_docker_button.pack(side='right', padx=(0, 8))
        else:
            self.install_docker_button.pack_forget()
        log = self.folder / 'runtime/painel-acao.log'
        try:
            content = log.read_text(encoding='utf-8-sig', errors='replace')
        except FileNotFoundError:
            content = ''
            status = 'Ainda não há operações registradas. O histórico aparecerá aqui após iniciar ou parar o servidor.'
        except OSError:
            content = ''
            status = 'Não foi possível ler o registro. Clique em Atualizar registro para tentar novamente.'
        else:
            status = f'Registro carregado às {datetime.now():%H:%M:%S}.' if content.strip() else 'O registro ainda está vazio.'
        self.log_status.set(status)
        self.log_text.configure(state='normal')
        self.log_text.delete('1.0', tk.END)
        self.log_text.insert('1.0', content)
        self.log_text.configure(state='disabled')
        self.log_text.see(tk.END)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pasta', type=Path, help='Pasta da configuração do laboratório')
    parser.add_argument('--diagnostico', type=Path, help='Salva diagnóstico sem abrir a janela ou alterar a configuração')
    parser.add_argument('--preparar', action='store_true', help='Prepara os arquivos sem iniciar serviços; exige --pasta')
    parser.add_argument('--dados-atleta', action='store_true', help='Abre diretamente a tela de leituras do M5')
    args = parser.parse_args()
    executable = sys.executable if getattr(sys, 'frozen', False) else __file__
    folder = args.pasta or find_folder(executable)
    if not args.pasta and getattr(sys, 'frozen', False) and not (folder / 'compose.yaml').exists():
        folder = folder / 'laboratorio'
    if args.preparar:
        if not args.pasta:
            parser.error('--preparar exige uma pasta explícita em --pasta')
        with operation_lock(folder):
            prepare_files(folder, network_enabled(folder))
        return
    if args.diagnostico:
        interfaces = detect_interfaces()
        result = diagnose(interfaces[0].ip, port_pairs(folder)) if interfaces else diagnose_local(port_pairs(folder))
        atomic_json(args.diagnostico, result)
        return
    if os.name == 'nt':
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError, OSError):
            pass
    root = tk.Tk()
    if args.dados_atleta:
        from dados_atleta import AthleteWindow
        ttk.Style(root).theme_use('clam')
        AthleteWindow(root, folder)
    else:
        App(root, folder)
    root.mainloop()


if __name__ == '__main__':
    main()
