"""Prepara a nuvem e cria uma conta restrita; segredos ficam somente em arquivos locais."""
from contextlib import closing
from pathlib import Path
import argparse
import json
import re
import secrets
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'painel'))
from nuvem import load_config, prepare_cloud, connect_cloud, validate_schema, safe_error, CloudError
from rede import read_json, atomic_json


def provision(folder):
    folder = Path(folder)
    admin_file = folder / 'runtime/cloud-admin.local.json'
    admin = read_json(admin_file) if admin_file.exists() else load_config(folder)
    if not re.fullmatch(r'[A-Za-z0-9_]+', admin['database']):
        raise CloudError('Nome de banco inválido para preparação automática.')
    prepare_cloud(folder, admin)
    pending = folder / 'runtime/provision-sync.local.json'
    if pending.exists():
        client = read_json(pending)
        if any(client.get(k) != admin.get(k) for k in ('host', 'port', 'database')):
            raise CloudError('Preparação anterior pertence a outro destino; preserve os arquivos privados.')
    else:
        client = dict(admin, user='atleta_sync_' + secrets.token_hex(4), password=secrets.token_urlsafe(32))
        atomic_json(pending, client)
    with closing(connect_cloud(folder, admin)) as db, db.cursor() as cur:
        cur.execute("CREATE USER IF NOT EXISTS %s@'%%' IDENTIFIED BY %s REQUIRE SSL", (client['user'], client['password']))
        database = admin['database']
        cur.execute(f"GRANT SELECT, INSERT ON `{database}`.telemetry TO %s@'%%'", (client['user'],))
        cur.execute(f"GRANT SELECT, INSERT, UPDATE ON `{database}`.atleta_sync_checkpoints TO %s@'%%'", (client['user'],))
    with closing(connect_cloud(folder, client)) as db:
        validate_schema(db)
    if not admin_file.exists():
        atomic_json(admin_file, admin)
    atomic_json(folder / 'cloud.local.json', client)
    return {'prepared': True, 'tls_verified': True, 'restricted_account': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pasta', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        print(json.dumps(provision(args.pasta)))
    except Exception as error:
        print(safe_error(error))
        raise SystemExit(1)
