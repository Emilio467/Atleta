"""Sincronização MySQL com TLS verificado, deduplicação e retomada transacional."""
from __future__ import annotations
import argparse
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import threading
import pymysql
from rede import atomic_json, read_json

FIELDS = ('received_at', 'mqtt_username', 'client_id', 'topic', 'boot_id', 'sample_seq',
          'source', 'accel_x_g', 'accel_y_g', 'accel_z_g', 'payload')
IDENTITY = ('mqtt_username', 'boot_id', 'sample_seq')
COLUMNS = ', '.join(FIELDS)
TELEMETRY_DDL = """CREATE TABLE IF NOT EXISTS telemetry (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, received_at TIMESTAMP(3) NOT NULL,
 mqtt_username VARCHAR(64) NOT NULL, client_id VARCHAR(64) NOT NULL,
 topic VARCHAR(255) NOT NULL, boot_id VARCHAR(32) NOT NULL,
 sample_seq BIGINT UNSIGNED NOT NULL, source ENUM('device','test') NOT NULL,
 accel_x_g DOUBLE NOT NULL, accel_y_g DOUBLE NOT NULL, accel_z_g DOUBLE NOT NULL,
 payload JSON NOT NULL, UNIQUE KEY sample_identity (mqtt_username, boot_id, sample_seq),
 KEY recent_device (mqtt_username, received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin"""
CHECKPOINT_DDL = """CREATE TABLE IF NOT EXISTS atleta_sync_checkpoints (
 source_id CHAR(64) PRIMARY KEY, last_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
 anchor_hash CHAR(64) NOT NULL DEFAULT '',
 updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
 ON UPDATE CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB"""


class CloudError(Exception):
    """Mensagem pública sem senhas ou SQL bruto."""


def load_config(folder):
    try:
        cfg = read_json(Path(folder) / 'cloud.local.json')
    except (OSError, ValueError):
        raise CloudError('Nuvem não configurada: preencha cloud.local.json.') from None
    if not isinstance(cfg, dict) or cfg.get('enabled') is not True:
        raise CloudError('Sincronização com a nuvem desativada.')
    for key in ('host', 'user', 'database', 'ca_file'):
        if not isinstance(cfg.get(key), str) or not cfg[key].strip():
            raise CloudError(f'Configuração da nuvem incompleta: {key}.')
    cfg['password'] = os.environ.get('ATLETA_CLOUD_PASSWORD') or cfg.get('password')
    if not isinstance(cfg['password'], str) or not cfg['password']:
        raise CloudError('Informe a senha privada da nuvem.')
    for key, default, low, high in [('port', 3306, 1, 65535),
                                  ('batch_size', 250, 1, 1000),
                                  ('interval_seconds', 5, 1, 300)]:
        value = cfg.get(key, default)
        if type(value) is not int or not low <= value <= high:
            raise CloudError(f'Valor inválido em {key}.')
        cfg[key] = value
    return cfg


def tls_context(folder, cfg):
    ca = Path(cfg['ca_file'])
    if not ca.is_absolute():
        ca = Path(folder) / ca
    if not ca.is_file():
        raise CloudError('Falta o certificado CA da Aiven em runtime/aiven-ca.pem.')
    try:
        context = ssl.create_default_context(cafile=str(ca))
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        return context
    except (OSError, ssl.SSLError):
        raise CloudError('Certificado CA inválido. Baixe o certificado do serviço na Aiven.') from None


def connect_cloud(folder, cfg):
    return pymysql.connect(host=cfg['host'], port=cfg['port'], user=cfg['user'],
                           password=cfg['password'], database=cfg['database'],
                           ssl=tls_context(folder, cfg), charset='utf8mb4',
                           connect_timeout=8, read_timeout=12, write_timeout=12,
                           init_command="SET time_zone = '+00:00'",
                           cursorclass=pymysql.cursors.DictCursor, autocommit=False)


def connect_local(folder):
    try:
        settings = read_json(Path(folder) / 'runtime/settings.json')
        secrets = read_json(Path(folder) / 'runtime/secrets.json')
        port, password = settings['mysql_port'], secrets['mysql_reader']
        if type(port) is not int or not 1 <= port <= 65535 or not password:
            raise ValueError()
    except (OSError, ValueError, KeyError, TypeError):
        raise CloudError('Inicie o laboratório para preparar o acesso de leitura ao MySQL local.') from None
    return pymysql.connect(host='127.0.0.1', port=port, user='lab_reader',
                           password=password, database='athlete_lab', charset='utf8mb4',
                           connect_timeout=5, read_timeout=12, write_timeout=12,
                           init_command="SET time_zone = '+00:00'",
                           cursorclass=pymysql.cursors.DictCursor, autocommit=True)


def safe_error(error):
    if isinstance(error, CloudError):
        return str(error)
    if isinstance(error, socket.gaierror) or isinstance(getattr(error, 'original_exception', None), socket.gaierror):
        return 'Falha de DNS da nuvem. Confira o serviço e o endereço do banco na Aiven. Leituras preservadas no banco local.'
    if isinstance(error, (ssl.SSLError, ssl.CertificateError)) or 'CERTIFICATE_VERIFY_FAILED' in str(error):
        return 'Certificado da nuvem não validado. Confira o CA, o endereço e a validade.'
    code = error.args[0] if error.args else None
    if code in (1044, 1045, 1142):
        return 'Acesso ao banco recusado. Confira as credenciais e permissões privadas.'
    if code in (1049, 1146):
        return 'Banco ou tabelas ausentes. Execute enviar_nuvem.py --preparar com o administrador.'
    if code in (1452, 1062):
        return 'Identidade de amostra ou cadastro de dispositivo incompatível na nuvem. Execute --preparar com o administrador.'
    return 'Não foi possível sincronizar. As leituras ficam no banco local para nova tentativa.'


def validate_schema(connection):
    with connection.cursor() as cur:
        cur.execute("SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='telemetry'")
        if not set(FIELDS).issubset({row['COLUMN_NAME'] for row in cur.fetchall()}):
            raise CloudError('A tabela telemetry da nuvem não possui as colunas necessárias.')
        cur.execute("SELECT INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='telemetry' AND NON_UNIQUE=0 ORDER BY INDEX_NAME, SEQ_IN_INDEX")
        indexes = {}
        for row in cur.fetchall():
            indexes.setdefault(row['INDEX_NAME'], []).append(row['COLUMN_NAME'])
        if list(IDENTITY) not in indexes.values():
            raise CloudError('Falta o índice único (mqtt_username, boot_id, sample_seq) na nuvem.')
        cur.execute("SELECT TABLE_NAME, ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ('telemetry','atleta_sync_checkpoints')")
        engines = {row['TABLE_NAME']: row['ENGINE'] for row in cur.fetchall()}
        if engines != {'telemetry': 'InnoDB', 'atleta_sync_checkpoints': 'InnoDB'}:
            raise CloudError('Prepare as tabelas InnoDB da nuvem com --preparar.')


def prepare_cloud(folder, cfg=None):
    cfg = cfg or load_config(folder)
    with closing(connect_cloud(folder, cfg)) as connection:
        with connection.cursor() as cur:
            cur.execute(TELEMETRY_DDL)
            cur.execute(CHECKPOINT_DDL)
            cur.execute("SELECT DISTINCT REFERENCED_TABLE_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='telemetry' AND REFERENCED_TABLE_NAME IS NOT NULL")
            parents = {row['REFERENCED_TABLE_NAME'] for row in cur.fetchall()}
            if parents and parents != {'mqtt_users'}:
                raise CloudError('A nuvem possui relacionamentos não suportados; preserve o esquema existente.')
            if parents:
                with closing(connect_local(folder)) as local, local.cursor() as reader:
                    reader.execute('SELECT DISTINCT mqtt_username, client_id FROM telemetry')
                    devices = reader.fetchall()
                devices += [{'mqtt_username': name, 'client_id': name} for name in ('m5-atleta-01', 'lab-teste-01')]
                for device in devices:
                    cur.execute('SELECT username FROM mqtt_users WHERE username=%s', (device['mqtt_username'],))
                    if cur.fetchone() is None:
                        # Somente metadados do arquivo; não replica senhas nem habilita login MQTT.
                        cur.execute('INSERT INTO mqtt_users (username,client_id,password_hash,is_superuser,enabled) VALUES (%s,%s,%s,FALSE,FALSE)',
                                    (device['mqtt_username'], device['client_id'], '!CLOUD_ARCHIVE_DISABLED!'))
        validate_schema(connection)
        connection.commit()
    return {'state': 'prepared', 'message': 'Tabelas da nuvem preparadas com TLS verificado.'}


def identity(row):
    return tuple(row[key] for key in IDENTITY)


def fingerprint(row):
    if row is None:
        return ''
    values = {key: row[key] for key in FIELDS}
    if isinstance(values['payload'], (str, bytes)):
        values['payload'] = json.loads(values['payload'])
    encoded = json.dumps(values, sort_keys=True, separators=(',', ':'), default=str, ensure_ascii=False)
    return hashlib.sha256(encoded.encode('utf-8')).hexdigest()


def sync_batch(local, cloud, batch_size):
    """Lote e cursor confirmados juntos; instâncias concorrentes serializam pelo cursor."""
    with local.cursor() as reader:
        reader.execute('SELECT @@server_uuid AS server_uuid, DATABASE() AS db')
        origin = reader.fetchone()
    source_id = hashlib.sha256((origin['server_uuid'] + '/' + origin['db']).encode()).hexdigest()
    cloud.begin()
    try:
        local.begin()
        with cloud.cursor() as writer, local.cursor() as reader:
            writer.execute("INSERT INTO atleta_sync_checkpoints (source_id) VALUES (%s) ON DUPLICATE KEY UPDATE source_id=VALUES(source_id)", (source_id,))
            writer.execute('SELECT last_id, anchor_hash FROM atleta_sync_checkpoints WHERE source_id=%s FOR UPDATE', (source_id,))
            checkpoint = writer.fetchone()
            last_id = checkpoint['last_id']
            if last_id:
                reader.execute(f'SELECT id, {COLUMNS} FROM telemetry WHERE id=%s', (last_id,))
                anchor = reader.fetchone()
                if fingerprint(anchor) != checkpoint['anchor_hash']:
                    last_id = 0
                elif anchor:
                    writer.execute(f'SELECT {COLUMNS} FROM telemetry WHERE mqtt_username=%s AND boot_id=%s AND sample_seq=%s', identity(anchor))
                    if fingerprint(writer.fetchone()) != checkpoint['anchor_hash']:
                        last_id = 0
            # Espera inserções ainda não confirmadas com ID menor que o próximo lote.
            # Sem essa leitura, commits fora de ordem poderiam deixar uma lacuna permanente.
            reader.execute(f'SELECT id, {COLUMNS} FROM telemetry WHERE id>%s ORDER BY id ASC LIMIT %s FOR SHARE', (last_id, batch_size))
            rows = reader.fetchall()
            upper_id = rows[-1]['id'] if rows else last_id
            reader.execute('SELECT COUNT(*) AS pending FROM telemetry WHERE id>%s', (upper_id,))
            pending = reader.fetchone()['pending']
            local.commit()  # Libera a origem antes de enviar o lote pela internet.
            inserted = 0
            if rows:
                keys = [identity(row) for row in rows]
                placeholders = ','.join(['(%s,%s,%s)'] * len(keys))
                writer.execute(f'SELECT {COLUMNS} FROM telemetry WHERE (mqtt_username,boot_id,sample_seq) IN ({placeholders})', tuple(value for key in keys for value in key))
                existing = {identity(row): row for row in writer.fetchall()}
                additions = []
                for row in rows:
                    old = existing.get(identity(row))
                    if old is not None and fingerprint(old) != fingerprint(row):
                        raise CloudError('A nuvem contém uma amostra com a mesma identidade e conteúdo diferente. Sincronização interrompida para preservar os dados.')
                    if old is None:
                        additions.append(tuple(row[key] for key in FIELDS))
                if additions:
                    writer.executemany(f'INSERT INTO telemetry ({COLUMNS}) VALUES ({",".join(["%s"] * len(FIELDS))})', additions)
                    inserted = len(additions)
                last_id = rows[-1]['id']
                writer.execute('UPDATE atleta_sync_checkpoints SET last_id=%s, anchor_hash=%s WHERE source_id=%s', (last_id, fingerprint(rows[-1]), source_id))
        cloud.commit()
        return {'state': 'online', 'inserted': inserted, 'verified': len(rows),
                'pending': pending, 'last_local_id': last_id, 'tls_verified': True,
                'message': f'Nuvem conectada • {pending} leituras pendentes'}
    except Exception:
        try:
            local.rollback()
        except Exception:
            pass
        try:
            cloud.rollback()
        except Exception:
            pass
        raise


def sync_once(folder):
    cfg = load_config(folder)
    with closing(connect_local(folder)) as local, closing(connect_cloud(folder, cfg)) as cloud:
        validate_schema(cloud)
        return sync_batch(local, cloud, cfg['batch_size'])


def save_status(folder, result):
    result = dict(result, checked_at_utc=datetime.now(timezone.utc).isoformat())
    atomic_json(Path(folder) / 'runtime/cloud-status.json', result)
    return result


class CloudWorker:
    def __init__(self, folder, callback=None):
        self.folder, self.callback = Path(folder), callback or (lambda result: None)
        self.stop_event = threading.Event()
        self.thread = None

    def start(self):
        if self.thread and self.thread.is_alive():
            return
        self.thread = threading.Thread(target=self.run, daemon=True, name='AtletaCloud')
        self.thread.start()

    def stop(self):
        self.stop_event.set()

    def run(self):
        delay = 5
        while not self.stop_event.is_set():
            try:
                result = sync_once(self.folder)
                delay = .2 if result['pending'] else load_config(self.folder)['interval_seconds']
            except Exception as error:
                result = {'state': 'pending', 'message': safe_error(error)}
                delay = min(max(5, delay * 2), 60)
            try:
                result = save_status(self.folder, result)
            except OSError:
                pass
            if not self.stop_event.is_set():
                self.callback(result)
            self.stop_event.wait(delay)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pasta', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--uma-vez', action='store_true', help='Sincroniza um lote e encerra')
    parser.add_argument('--preparar', action='store_true', help='Cria tabelas ausentes; exige administrador')
    args = parser.parse_args(argv)
    if args.preparar or args.uma_vez:
        try:
            result = prepare_cloud(args.pasta) if args.preparar else sync_once(args.pasta)
            print(json.dumps(save_status(args.pasta, result), ensure_ascii=False))
            return 0
        except Exception as error:
            print(json.dumps(save_status(args.pasta, {'state': 'pending', 'message': safe_error(error)}), ensure_ascii=False))
            return 1
    worker = CloudWorker(args.pasta, lambda result: print(json.dumps(result, ensure_ascii=False), flush=True))
    try:
        worker.run()
    except KeyboardInterrupt:
        worker.stop()
    return 0
