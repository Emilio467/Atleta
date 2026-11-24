from contextlib import closing
from datetime import timedelta, timezone
import json
import sys
import time
from pathlib import Path

folder = Path(__file__).resolve().parents[1] / 'laboratorio'
sys.path.insert(0, str(folder / 'painel'))
import nuvem

fortaleza = timezone(timedelta(hours=-3))
once = '--uma-vez' in sys.argv
device = 'm5-atleta-01'
last_id = 0
idle = None

print('ATLETA IP  |  AIVEN / defaultdb  |  M5 AO VIVO')
print('Consulta direta ao banco. Horário de Fortaleza. Ctrl+C para encerrar.\n')
print(f'{"Recebido":<12} {"Amostra":>9} {"Passos":>8} {"Tempo ativo":>14}')

try:
    while True:
        try:
            cfg = nuvem.load_config(folder)
            with closing(nuvem.connect_cloud(folder, cfg)) as db, db.cursor() as cursor:
                db.autocommit(True)
                print(f'Aiven conectada ({db._sock.version()}).')
                while True:
                    cursor.execute(
                        "SELECT id, received_at, sample_seq, payload, "
                        "TIMESTAMPDIFF(SECOND, received_at, UTC_TIMESTAMP()) AS age_s "
                        "FROM telemetry WHERE source='device' AND mqtt_username=%s "
                        "ORDER BY id DESC LIMIT 1",
                        (device,),
                    )
                    newest = cursor.fetchone()
                    stale = newest is None or newest['age_s'] > 12
                    if idle != stale and stale:
                        print('Aguardando uma leitura recente do M5 na Aiven.')
                    elif idle is True and not stale:
                        print('Leituras recentes voltaram a chegar.')
                    idle = stale
                    if last_id == 0:
                        cursor.execute(
                            "SELECT id, received_at, sample_seq, payload FROM telemetry "
                            "WHERE source='device' AND mqtt_username=%s ORDER BY id DESC LIMIT 5",
                            (device,),
                        )
                        rows = reversed(cursor.fetchall())
                    else:
                        cursor.execute(
                            "SELECT id, received_at, sample_seq, payload FROM telemetry "
                            "WHERE id>%s AND source='device' AND mqtt_username=%s ORDER BY id LIMIT 100",
                            (last_id, device),
                        )
                        rows = cursor.fetchall()
                    for row in rows:
                        data = json.loads(row['payload'])
                        total = int(data['duracao_s'])
                        hours, rem = divmod(total, 3600)
                        minutes, seconds = divmod(rem, 60)
                        elapsed = f'{hours:02d}:{minutes:02d}:{seconds:02d}'
                        timestamp = row['received_at'].replace(tzinfo=timezone.utc).astimezone(fortaleza).strftime('%H:%M:%S.%f')[:-3]
                        print(f"{timestamp:<12} {row['sample_seq']:>9} {data['passos']:>8} {elapsed:>14}")
                        last_id = row['id']
                    if once:
                        sys.exit(0 if last_id else 1)
                    time.sleep(2)
        except (OSError, ValueError, KeyError, nuvem.CloudError, nuvem.pymysql.MySQLError) as error:
            print(nuvem.safe_error(error))
            if once:
                sys.exit(1)
            print('Reconectando à Aiven em 5 s.')
            time.sleep(5)
except KeyboardInterrupt:
    print('\nLeitura encerrada.')
