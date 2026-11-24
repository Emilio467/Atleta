"""Envia ao M5, pela rede local, o aplicativo verificado da entrega."""

import argparse
import getpass
import hashlib
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import tempfile


FIRMWARE = Path(__file__).resolve().parents[1] / "entrega/firmware"
OTA_PORT = 3232


def release_app(directory):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    app = next(
        (part for part in manifest["segments"]
         if int(part["offset"], 0) == 0x10000 and part["file"] == "firmware.bin"),
        None,
    )
    if not app:
        raise ValueError("A entrega não contém o segmento de aplicativo do ESP32.")
    image = directory / app["file"]
    data = image.read_bytes()
    if not data.startswith(b"\xe9") or hashlib.sha256(data).hexdigest() != app["sha256"]:
        raise ValueError("firmware.bin inválido ou diferente do manifesto. Gere a entrega novamente.")
    return manifest["version"], data


def espressif_uploader():
    core = Path(os.environ.get("PLATFORMIO_CORE_DIR", Path.home() / ".platformio"))
    path = core / "packages/framework-arduinoespressif32/tools/espota.py"
    if not path.is_file():
        raise ValueError("Execute primeiro laboratorio/tools/release.py --firmware-only para instalar o framework.")
    spec = importlib.util.spec_from_file_location("espota", path)
    uploader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(uploader)
    return uploader


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ip", required=True, type=ipaddress.IPv4Address,
                        help="Endereço IPv4 mostrado na tela OTA do relógio")
    args = parser.parse_args()
    try:
        version, data = release_app(FIRMWARE)
        uploader = espressif_uploader()
        address = str(args.ip)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
            route.connect((address, OTA_PORT))
            local_address = route.getsockname()[0]
        code = getpass.getpass(f"Senha OTA mostrada no M5 ({address}): ").strip().lower()
        if not re.fullmatch(r"[0-9a-f]{16}", code):
            raise ValueError("Digite os 16 caracteres da senha mostrada no relógio.")
        print(f"Enviando firmware {version} para {address}...")
        with tempfile.TemporaryDirectory(prefix="atleta-ota-") as directory:
            image = Path(directory) / "firmware.bin"
            image.write_bytes(data)
            result = uploader.main([
                "--ip", address, "--host_ip", local_address, "--port", str(OTA_PORT),
                "--file", str(image), "--auth", code, "--progress", "--timeout", "2",
            ])
        if result:
            parser.exit(result, "Falha no envio. Confira a tela OTA e a conexão local.\n")
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(f"Envio concluído. Aguarde o reinício e confira a versão {version} na tela.")


if __name__ == "__main__":
    main()
