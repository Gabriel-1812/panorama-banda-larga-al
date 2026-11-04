"""Pipeline completo: extract -> transform -> load.

Uso (na raiz do projeto):  python -m src.pipeline
"""
"""Pipeline completo: extract -> transform -> load.

Uso (na raiz do projeto):
    python -m src.pipeline             # reaproveita o transform salvo, se existir
    python -m src.pipeline --refazer   # reprocessa os CSVs do zero
"""
import logging
import sys
import time
from pathlib import Path
import pandas as pd
from src import extract, load, transform

log = logging.getLogger("pipeline")

PROCESSADOS = Path(__file__).resolve().parent.parent / "data" / "processed"
TABELAS = ["dim_municipio", "dim_operadora", "fato_acessos"]


def salvar_checkpoint(tabelas: dict[str, pd.DataFrame]) -> None:
    PROCESSADOS.mkdir(parents=True, exist_ok=True)
    for nome, df in tabelas.items():
        df.to_pickle(PROCESSADOS / f"{nome}.pkl")
    log.info("Checkpoint salvo em %s", PROCESSADOS)


def ler_checkpoint() -> dict[str, pd.DataFrame] | None:
    arquivos = [PROCESSADOS / f"{nome}.pkl" for nome in TABELAS]
    if not all(a.exists() for a in arquivos):
        return None
    log.info("Usando checkpoint de %s", PROCESSADOS)
    return {nome: pd.read_pickle(a) for nome, a in zip(TABELAS, arquivos)}


def main(refazer: bool = False) -> None:
    inicio = time.perf_counter()

    log.info("1/3 Extração")
    extract.baixar()
    extract.descompactar()

    log.info("2/3 Transformação")
    tabelas = None if refazer else ler_checkpoint()
    if tabelas is None:
        tabelas = transform.transformar()
        salvar_checkpoint(tabelas)

    log.info("3/3 Carga")
    load.carregar(tabelas)

    log.info("Pipeline concluído em %.1f min", (time.perf_counter() - inicio) / 60)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s")
    main(refazer="--refazer" in sys.argv)