"""Testes reais em dois bancos MySQL temporários locais; não acessa a Aiven.

Executar com --run. As bases teste_nuvem_<aleatorio> são criadas e removidas.
"""
from contextlib import closing
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import secrets
import ssl
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB / 'painel'))
import pymysql
import nuvem
import servidor


class CloudIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        credentials = json.loads((LAB / 'runtime/secrets.json').read_text())
        settings = json.loads((LAB / 'runtime/settings.json').read_text())
        cls.options = dict(host='127.0.0.1', port=settings['mysql_port'], user='root',
                           password=credentials['mysql_root'], connect_timeout=5,
                           read_timeout=10, write_timeout=10, charset='utf8mb4',
                           init_command="SET time_zone = '+00:00'",
                           cursorclass=pymysql.cursors.DictCursor)
        cls.prefix = 'teste_nuvem_' + secrets.token_hex(6)
        cls.names = [cls.prefix + '_local', cls.prefix + '_cloud']
        with closing(pymysql.connect(**cls.options, autocommit=True)) as admin, admin.cursor() as cur:
            for name in cls.names:
                cur.execute(f'CREATE DATABASE `{name}`')
        cls.local = pymysql.connect(**cls.options, database=cls.names[0], autocommit=True)
        cls.cloud = pymysql.connect(**cls.options, database=cls.names[1], autocommit=False)
        for db in (cls.local, cls.cloud):
            with db.cursor() as cur:
                cur.execute(nuvem.TELEMETRY_DDL)
                cur.execute(nuvem.CHECKPOINT_DDL)
            db.commit()

    @classmethod
    def tearDownClass(cls):
        cls.local.close(); cls.cloud.close()
        with closing(pymysql.connect(**cls.options, autocommit=True)) as admin, admin.cursor() as cur:
            for name in cls.names:
                if not name.startswith(cls.prefix + '_'):
                    raise AssertionError('Banco de teste fora do prefixo autorizado')
                cur.execute(f'DROP DATABASE `{name}`')

    def setUp(self):
        for db in (self.local, self.cloud):
            db.rollback()
            with db.cursor() as cur:
                cur.execute('TRUNCATE telemetry')
                cur.execute('TRUNCATE atleta_sync_checkpoints')
            db.commit()

    def seed(self, count, boot='boot-test'):
        with self.local.cursor() as cur:
            cur.executemany(f'INSERT INTO telemetry ({nuvem.COLUMNS}) VALUES ({",".join(["%s"]*11)})',
                [(datetime(2026, 1, 1), 'teste', 'teste', 'test/topic', boot, i, 'test',
                  .125, .25, 1., json.dumps({'sample_seq': i, 'test': True})) for i in range(count)])

    def count(self, db, table='telemetry'):
        with db.cursor() as cur:
            cur.execute(f'SELECT COUNT(*) AS n FROM {table}')
            return cur.fetchone()['n']

    def drain(self, batch=17):
        for _ in range(100):
            result = nuvem.sync_batch(self.local, self.cloud, batch)
            if not result['pending']:
                return result
        self.fail('O histórico não foi concluído')

    def test_recovers_all_103_rows_in_small_batches(self):
        self.seed(103); self.drain()
        self.assertEqual(self.count(self.cloud), 103)
        with self.local.cursor() as a, self.cloud.cursor() as b:
            a.execute(f'SELECT {nuvem.COLUMNS} FROM telemetry ORDER BY sample_seq')
            b.execute(f'SELECT {nuvem.COLUMNS} FROM telemetry ORDER BY sample_seq')
            self.assertEqual([nuvem.fingerprint(r) for r in a.fetchall()],
                             [nuvem.fingerprint(r) for r in b.fetchall()])

    def test_resume_and_repeated_calls_do_not_duplicate(self):
        self.seed(63)
        nuvem.sync_batch(self.local, self.cloud, 10)
        self.drain()
        self.assertEqual(nuvem.sync_batch(self.local, self.cloud, 10)['inserted'], 0)
        self.assertEqual(self.count(self.cloud), 63)

    def test_failure_before_checkpoint_rolls_back_rows(self):
        self.seed(30)
        original = pymysql.cursors.DictCursor.execute
        def fail(cursor, sql, args=None):
            statement = sql.decode() if isinstance(sql, (bytes, bytearray)) else sql
            if statement.startswith('UPDATE atleta_sync_checkpoints'):
                raise OSError('falha simulada')
            return original(cursor, sql, args)
        with patch.object(pymysql.cursors.DictCursor, 'execute', fail):
            with self.assertRaises(OSError):nuvem.sync_batch(self.local, self.cloud, 30)
        self.assertEqual(self.count(self.cloud), 0)
        self.assertEqual(self.count(self.cloud, 'atleta_sync_checkpoints'), 0)
        self.drain(); self.assertEqual(self.count(self.cloud), 30)

    def test_lost_commit_acknowledgment_is_retryable(self):
        self.seed(31)
        real_commit = self.cloud.commit
        def uncertain_commit():
            real_commit(); raise OSError('resposta perdida após commit')
        with patch.object(self.cloud, 'commit', uncertain_commit):
            with self.assertRaises(OSError):nuvem.sync_batch(self.local, self.cloud, 15)
        self.drain(); self.assertEqual(self.count(self.cloud), 31)

    def test_conflicting_sample_never_overwrites_cloud(self):
        self.seed(3); self.drain()
        with self.local.cursor() as cur:cur.execute('UPDATE telemetry SET accel_x_g=99 WHERE sample_seq=2')
        with self.assertRaises(nuvem.CloudError):self.drain()
        with self.cloud.cursor() as cur:
            cur.execute('SELECT accel_x_g FROM telemetry WHERE sample_seq=2')
            self.assertEqual(cur.fetchone()['accel_x_g'], .125)

    def test_local_database_reset_restarts_cursor(self):
        self.seed(30); self.drain()
        with self.local.cursor() as cur:cur.execute('TRUNCATE telemetry')
        self.seed(4, 'different-boot'); self.drain()
        self.assertEqual(self.count(self.cloud), 34)

    def test_cloud_restore_without_checkpoint_deduplicates(self):
        self.seed(22); self.drain()
        with self.cloud.cursor() as cur:cur.execute('TRUNCATE atleta_sync_checkpoints')
        self.drain(); self.assertEqual(self.count(self.cloud), 22)

    def test_two_workers_share_transactional_checkpoint(self):
        self.seed(70)
        def worker():
            with closing(pymysql.connect(**self.options, database=self.names[0], autocommit=True)) as a, \
                 closing(pymysql.connect(**self.options, database=self.names[1], autocommit=False)) as b:
                return nuvem.sync_batch(a, b, 40)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: worker(), range(2)))
        self.assertEqual(sum(r['inserted'] for r in results), 70)
        self.assertEqual(self.count(self.cloud), 70)

    def test_schema_requires_unique_identity(self):
        nuvem.validate_schema(self.cloud)
        with self.cloud.cursor() as cur:cur.execute('ALTER TABLE telemetry DROP INDEX sample_identity')
        try:
            with self.assertRaises(nuvem.CloudError):nuvem.validate_schema(self.cloud)
        finally:
            with self.cloud.cursor() as cur:cur.execute('ALTER TABLE telemetry ADD UNIQUE KEY sample_identity (mqtt_username,boot_id,sample_seq)')

    def test_out_of_order_source_commits_cannot_skip_lower_id(self):
        with closing(pymysql.connect(**self.options, database=self.names[0], autocommit=False)) as writer:
            with writer.cursor() as cur:
                cur.execute(f'INSERT INTO telemetry ({nuvem.COLUMNS}) VALUES ({",".join(["%s"]*11)})',
                    (datetime(2026,1,1),'teste','teste','test/topic','late-commit',999,'test',.125,.25,1.,'{}'))
            self.seed(1)
            with ThreadPoolExecutor(max_workers=1) as pool:
                task = pool.submit(nuvem.sync_batch,self.local,self.cloud,20)
                time.sleep(.2)
                writer.commit()
                task.result(timeout=10)
            self.drain()
            self.assertEqual(self.count(self.cloud),2)


class CloudSafety(unittest.TestCase):
    def test_missing_ca_blocks_before_network(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch('nuvem.pymysql.connect') as connect:
                with self.assertRaises(nuvem.CloudError):
                    nuvem.connect_cloud(tmp, dict(host='example.test', port=3306, user='test',
                        password='never-send-this', database='test', ca_file='missing.pem'))
                connect.assert_not_called()

    def test_tls_checks_hostname_and_certificate(self):
        ctx = nuvem.tls_context(LAB, {'ca_file': 'runtime/aiven-ca.pem'})
        self.assertTrue(ctx.check_hostname)
        self.assertEqual(ctx.verify_mode, ssl.CERT_REQUIRED)

    def test_driver_errors_do_not_expose_secrets(self):
        self.assertNotIn('SECRET_TEST', nuvem.safe_error(pymysql.OperationalError(1045, 'SECRET_TEST')))

    def test_empty_generated_placeholders_are_regenerated(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);(folder/'runtime').mkdir()
            for name in ('01-init.sql','base.hocon'):(folder/'runtime'/name).touch()
            servidor.prepare_files(folder, True)
            self.assertTrue(servidor.initialized(folder))
            self.assertIn('CREATE USER', (folder/'runtime/01-init.sql').read_text())

    def test_public_selection_excludes_all_private_config(self):
        path=LAB.parent/'tools/empacotar.py'
        spec=importlib.util.spec_from_file_location('pack_test',path)
        pack=importlib.util.module_from_spec(spec);spec.loader.exec_module(pack)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);lab=root/'laboratorio';lab.mkdir()
            for name in ('.env','.env.prod','config.json','cloud.local.json','ca.pem','cloud.example.json'):
                (lab/name).write_text('{}')
            with patch.object(pack,'ROOT',root),patch.object(pack,'LAB',lab):
                self.assertEqual([p.name for p in pack.lab_files()],['cloud.example.json'])
                for name in ('.env','config.json','cloud.local.json','ca.pem'):
                    with self.assertRaises(ValueError):pack.assert_public([lab/name])


if __name__ == '__main__':
    if '--run' not in sys.argv:
        raise SystemExit('Use --run para criar bases de teste temporárias no MySQL local.')
    sys.argv.remove('--run')
    unittest.main()
