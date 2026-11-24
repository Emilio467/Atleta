"""Monta os pacotes públicos e verifica integridade, hashes e links locais."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit
from datetime import datetime, timezone, timedelta
import argparse
import ast
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / "laboratorio"
SITE = ROOT / "site"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lab_files():
    return sorted(p for p in LAB.rglob('*') if p.is_file()
                  and not any(part in p.relative_to(LAB).parts for part in
                              ('runtime', 'migracao', '.pio', '__pycache__', 'build', 'dist'))
                  and not private_path(p)
                  and p.suffix not in ('.pyc', '.tmp', '.lock'))


def private_path(path):
    return (path.name in ('config.json', 'config.local.json', 'endereco-servidor.json')
            or path.name.endswith('.local.json') or path.name.startswith('.env')
            or path.suffix.lower() in ('.pem', '.key', '.crt', '.cer')
            or any(part in ('runtime', 'migracao', '.git', '.pio', '__pycache__', 'validacao-local')
                   for part in path.relative_to(ROOT).parts))


def assert_public(paths):
    # A cópia de migração é privada. Confira credenciais conhecidas sem exibi-las.
    original = LAB
    credentials = []
    for candidate in [original / "runtime/secrets.json", original / "config.local.json",
                      original / "config.json", original / "cloud.local.json",
                      original / "runtime/cloud-admin.local.json", original / "runtime/device-config.json"]:
        if candidate.exists():
            data = json.loads(candidate.read_text(encoding="utf-8-sig"))
            entries = data.values() if candidate.name == "secrets.json" else [v for k, v in data.items() if any(s in k.lower() for s in ('password', 'secret', 'token'))]
            credentials.extend(v.encode("utf-8") for v in entries if isinstance(v, str) and v)
    for file in paths:
        if not file.is_file():
            raise ValueError(f"Arquivo necessário ausente: {file.relative_to(ROOT)}")
        parts = file.relative_to(ROOT).parts
        if private_path(file):
            raise ValueError("Arquivo privado na seleção pública.")
        content = file.read_bytes()
        if any(secret in content for secret in credentials):
            raise ValueError(f"Credencial conhecida detectada em {file.relative_to(ROOT)}")


def archive(target, paths):
    assert_public(paths)
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for file in sorted(paths):
            z.write(file, file.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(target) as z:
        if z.testzip() is not None:
            raise ValueError("Falha de integridade do ZIP.")
    return {"file": target.name, "bytes": target.stat().st_size, "sha256": sha(target), "files": len(paths)}


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if "id" in values:
            self.ids.add(values["id"])
        for attribute in ("href", "src"):
            if attribute in values:
                self.links.append(values[attribute])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='Caminho do ZIP completo, fora da pasta do projeto')
    args = parser.parse_args()
    stamp = datetime.now(timezone(timedelta(hours=-3))).strftime('%Y-%m-%d_%H%M%S')
    output = (args.output or ROOT.parent / 'Backups' / ROOT.name / f'ATLETA-PROJETO-{stamp}.zip').resolve()
    if output.is_relative_to(ROOT):
        raise ValueError('Salve o backup fora da pasta do projeto.')
    if output.exists():
        raise FileExistsError('Este backup já existe. Escolha outro nome para preservar a cópia anterior.')
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((LAB / "entrega/firmware/manifest.json").read_text(encoding="utf-8"))
    sources = {"firmware/src/main.cpp": "source_sha256", "firmware/src/activity.h": "activity_header_sha256", "firmware/platformio.ini": "platformio_ini_sha256"}
    for file, key in sources.items():
        if sha(LAB / file) != manifest[key]:
            raise ValueError(f"Fonte diferente do manifesto: {file}")
    for row in [*manifest["segments"], manifest["merged"]]:
        if sha(LAB / "entrega/firmware" / row["file"]) != row["sha256"]:
            raise ValueError("Firmware com checksum divergente.")
    panel = json.loads((LAB / "entrega/manifest-painel.json").read_text(encoding="utf-8"))
    if sha(LAB / "entrega/PainelIP.exe") != panel["files"]["PainelIP.exe"]["sha256"]:
        raise ValueError("Painel com checksum divergente.")
    python_files = [p for p in LAB.rglob("*.py") if not private_path(p)] + list((ROOT / "tools").glob("*.py")) + [ROOT / 'enviar_nuvem.py']
    for file in python_files:
        ast.parse(file.read_text(encoding="utf-8-sig"), filename=str(file))
    documentation = [ROOT / "README.md", ROOT / "LEIA PRIMEIRO.txt", *sorted((ROOT / "docs").glob("*.md")),
                     *sorted((SITE / "assets").glob("*v1.svg")), *sorted((SITE / "assets").glob("*v1.png"))]
    downloads = SITE / "downloads"
    downloads.mkdir(exist_ok=True)
    firmware_zip = archive(downloads / "firmware-plataforma-v1.zip", lab_files())
    docs_zip = archive(downloads / "documentacao-v1.zip", documentation)
    parser = Links()
    parser.feed((SITE / "index.html").read_text(encoding="utf-8"))
    count = 0
    for link in parser.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        if url.path:
            target = (SITE / unquote(url.path)).resolve()
            if not target.is_relative_to(SITE) or not target.is_file():
                raise ValueError(f"Link local inválido: {link}")
        elif url.fragment and url.fragment not in parser.ids:
            raise ValueError(f"Âncora ausente: {link}")
        count += 1
    report = {"created_at_utc": datetime.now(timezone.utc).isoformat(), "passed": True,
              "firmware_version": manifest["version"], "firmware_sources_and_images_match_manifest": True,
              "firmware_physical_device_tested_per_original_manifest": manifest["physical_device_tested"],
              "panel_image_matches_manifest": True, "python_files_syntax_checked": len(python_files),
              "local_links_checked": count, "known_credentials_absent": True,
              "hardware_or_live_server_tested_this_run": False,
              "downloads": [firmware_zip, docs_zip]}
    (downloads / "verificacao-pacote.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    (downloads / "SHA256SUMS.txt").write_text("\n".join(f"{r['sha256']}  {r['file']}" for r in (firmware_zip, docs_zip))+"\n", encoding="utf-8")
    public_site = [SITE / "index.html", SITE / "favicon.ico", *[p for p in (SITE / "assets").iterdir() if p.suffix in (".css", ".js", ".svg", ".png")],
                   downloads / "firmware-plataforma-v1.zip", downloads / "documentacao-v1.zip",
                   downloads / "verificacao-pacote.json", downloads / "SHA256SUMS.txt"]
    if (downloads / "verificacao-navegador.json").is_file():
        public_site.append(downloads / "verificacao-navegador.json")
    complete = sorted(set(lab_files() + documentation + public_site + [ROOT / ".gitignore", ROOT / ".github/workflows/pages.yml", *sorted((ROOT / "tools").glob("*.py"))]))
    complete += [ROOT / 'ABRIR PAINEL.exe', ROOT / 'ABRIR PAINEL PYTHON.cmd', ROOT / 'enviar_nuvem.py', *sorted((ROOT / 'codigo-original').glob('*'))]
    full = archive(output, complete)
    output.with_suffix('.sha256.txt').write_text(f"{full['sha256']}  {full['file']}\n", encoding="utf-8")
    backup_manifest = {'created_at_utc': datetime.now(timezone.utc).isoformat(), 'archive': full,
                       'local_configuration_included': False, 'telemetry_history_included': False,
                       'files': [{'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p)} for p in sorted(complete)]}
    output.with_suffix('.manifesto.json').write_text(json.dumps(backup_manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({"passed": True, "full_delivery": full, "local_links_checked": count,
                      "firmware_sources_and_images_match_manifest": True, "known_credentials_absent": True,
                      "backup_path": str(output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
