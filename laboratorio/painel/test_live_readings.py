import json
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from live_readings import DEVICE, RECENT_SECONDS, TOPIC, LiveReadings


class LiveReadingsTest(unittest.TestCase):
    def setUp(self):
        self.feed = LiveReadings('.')
        self.feed.client = object()
        self.payload = dict(source='device', device_id=DEVICE, boot_id='boot', sample_seq=2)

    def receive(self, payload, topic=TOPIC, retain=False):
        message = SimpleNamespace(topic=topic, retain=retain, payload=json.dumps(payload).encode())
        self.feed.on_message(self.feed.client, None, message)

    def test_ignores_retained_test_and_other_device_messages(self):
        self.receive(self.payload, retain=True)
        self.receive(self.payload, topic='atletas/lab-teste/telemetria')
        self.receive({**self.payload, 'source': 'test'})
        self.receive({**self.payload, 'device_id': 'outro'})
        self.receive({**self.payload, 'sample_seq': True})
        self.assertIsNone(self.feed.current())

    def test_drops_duplicates_and_expired_samples_and_prefers_newer_history(self):
        with patch('live_readings.time.monotonic', return_value=100):
            self.receive(self.payload)
            latest = self.feed.current()
            self.assertIsNotNone(latest)
            self.receive({**self.payload, 'sample_seq': 1})
            self.assertIs(self.feed.current(), latest)
            self.assertIsNone(self.feed.current({'payload': {**self.payload, 'sample_seq': 3}}))
        with patch('live_readings.time.monotonic', return_value=101 + RECENT_SECONDS):
            self.assertIsNone(self.feed.current())
