# Baixa e descompacta a base de banda larga fixa da Anatel

import logging
import zipfile
from pathlib import Path
import requests

URL = ("https://www.anatel.gov.br/dadosabertos/paineis_de_dados/"
       "acessos/acessos_banda_larga_fixa.zip")

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
ZIP_PATH = RAW_DIR / "acessos-banda_larga_fixa.zip"
EXTRACT_DIR = RAW_DIR / "acessos_banda_larga_fixa"

log = logging.getLogger(__name__)

def baixar(forcar:bool = False) -> Path:
    # Baixa o .zip da Anatel se ainda não existir
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    if ZIP_PATH. exists() and not forcar:
        log.info("Zip já existe, pulando download: %s", ZIP_PATH.name)
        return ZIP_PATH
    
    temporario = ZIP_PATH.with_suffix(".part")
    log.info("Baixando %s", URL)
    with requests.get(URL, stream=True, timeout=60) as resposta:
        resposta.raise_for_status()
        total = int(resposta.headers.get("content-length", 0))
        baixado = 0
        with open(temporario, "wb") as arquivo:
            for pedaco in resposta.iter_content(chunk_size=1024 * 1024):
                arquivo.write(pedaco)
                baixado += len(pedaco)
                if total:
                    print(f"\r  {baixado / total:.0%} de {total / 1e6:.0f} MB",
                          end="", flush=True)
    print()
    temporario.rename(ZIP_PATH)   # só vira .zip quando o download termina inteiro
    return ZIP_PATH


def descompactar() -> list[Path]:
    """Extrai os CSVs do .zip e lista o que veio dentro."""
    with zipfile.ZipFile(ZIP_PATH) as z:
        for info in z.infolist():
            log.info("  %-55s %8.1f MB", info.filename, info.file_size / 1e6)
        z.extractall(EXTRACT_DIR)
    return sorted(EXTRACT_DIR.rglob("*.csv"))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    baixar()
    csvs = descompactar()
    log.info("%d arquivos CSV extraídos em %s", len(csvs), EXTRACT_DIR)