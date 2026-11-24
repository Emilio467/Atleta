"""Estado da tela inicial: consultas de leitura, sem abrir ou reiniciar a porta USB."""
from pathlib import Path

from dados_atleta import DataError, fetch_readings
from m5_serial import device_ports
from rede import inspect_pair, read_json


def read_overview(folder, address=None):
    folder = Path(folder)
    try:
        ports = device_ports()
    except OSError:
        ports = []
    try:
        rows = fetch_readings(folder, 1)
        row, database_error = rows[0] if rows else None, False
    except (DataError, OSError, ValueError):
        row, database_error = None, True
    try:
        settings = read_json(folder / 'runtime/settings.json')
        result = inspect_pair(address or '127.0.0.1', (settings['mqtt_port'], settings['dashboard_port']))
        ready = bool(result['mqtt_online']) and not database_error
    except (OSError, ValueError, KeyError, TypeError):
        ready = False
    return {'ports': ports, 'row': row, 'database_error': database_error, 'server_ready': ready}
