"""Sincronização opcional por terminal; também é iniciada pelo painel."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / 'laboratorio/painel'))
from nuvem import main

if __name__ == '__main__':
    raise SystemExit(main())
