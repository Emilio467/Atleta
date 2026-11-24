"""Read-only subscription for the current physical M5 readings."""
from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
import time

import paho.mqtt.client as mqtt

from rede import port, read_json
from servidor import LabError, operation_lock


DEVICE = 'm5-atleta-01'
TOPIC = f'atletas/{DEVICE}/telemetria'
RECENT_SECONDS = 10


@dataclass(frozen=True)
class LiveReading:
    payload: dict
    received_at: datetime
    received_monotonic: float

    @property
    def age_seconds(self):
        return time.monotonic() - self.received_monotonic

    def as_row(self):
        return {'payload': self.payload, 'received_at': self.received_at, 'age_seconds': self.age_seconds}


class LiveReadings:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.client = None
        self.connection = None
        self.latest = None
        self.lock = None

    def refresh(self):
        """Use the existing lab observer and reconnect if its local settings change."""
        try:
            settings = read_json(self.folder / 'runtime/settings.json', {})
            secrets = read_json(self.folder / 'runtime/secrets.json', {})
            mqtt_port = port(settings.get('mqtt_port'), None)
            password = secrets.get('lab-observer')
        except (OSError, ValueError, AttributeError):
            return
        if mqtt_port is None or not isinstance(password, str) or not password:
            return
        connection = (mqtt_port, password)
        if connection == self.connection:
            return
        self.stop()
        lock = operation_lock(self.folder, 'telemetria-ao-vivo.lock')
        try:
            lock.__enter__()
        except (LabError, OSError):
            return
        self.lock = lock
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='lab-observer')
        client.username_pw_set('lab-observer', password)
        client.on_connect = self.on_connect
        client.on_message = self.on_message
        client.reconnect_delay_set(min_delay=1, max_delay=10)
        self.client, self.connection = client, connection
        client.connect_async('127.0.0.1', mqtt_port, keepalive=15)
        client.loop_start()

    def on_connect(self, client, userdata, flags, reason, properties):
        if client is self.client and not reason.is_failure:
            client.subscribe(TOPIC, qos=0)

    def on_message(self, client, userdata, message):
        if client is not self.client or message.topic != TOPIC or message.retain or len(message.payload) > 2048:
            return
        try:
            payload = json.loads(message.payload)
        except ValueError:
            return
        if (not isinstance(payload, dict) or payload.get('source') != 'device' or payload.get('device_id') != DEVICE
                or not isinstance(payload.get('boot_id'), str) or not payload['boot_id']
                or type(payload.get('sample_seq')) is not int or payload['sample_seq'] < 0):
            return
        previous = self.latest
        if (previous and previous.payload['boot_id'] == payload['boot_id']
                and previous.payload['sample_seq'] >= payload['sample_seq']):
            return
        self.latest = LiveReading(payload, datetime.now(timezone.utc), time.monotonic())

    def current(self, stored=None):
        reading = self.latest
        if not reading or reading.age_seconds > RECENT_SECONDS:
            return None
        if stored:
            payload = stored['payload']
            if (payload.get('boot_id') == reading.payload['boot_id'] and type(payload.get('sample_seq')) is int
                    and payload['sample_seq'] > reading.payload['sample_seq']):
                return None
        return reading

    def stop(self):
        client = self.client
        self.client = self.connection = None
        if client is not None:
            client.disconnect()
            client.loop_stop()
        if self.lock is not None:
            self.lock.__exit__(None, None, None)
            self.lock = None
        self.latest = None
