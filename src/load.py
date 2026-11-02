#Etapa 3 do pipeline: recria o esquema e carrega as tabelas no MySQL.
import logging
from pathlib import Path
import pandas as pd
from sqlalchemy import text
from src.db import get_engine

log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "sql" / "01_schema.sql"

# Ordem importa: dimensões antes da fato, por causa das chaves estrangeiras
ORDEM_CARGA = ["dim_municipio", "dim_operadora", "fato_acessos"]


def recriar_esquema(conn) -> None:
    #Executa o 01_schema.sql
    linhas = [linha for linha in SCHEMA.read_text(encoding="utf-8").splitlines()
              if not linha.strip().startswith("--")]
    for comando in "\n".join(linhas).split(";"):
        if comando.strip():
            conn.execute(text(comando))
    log.info("Esquema recriado a partir de %s", SCHEMA.name)


def carregar(tabelas: dict[str, pd.DataFrame]) -> None:
    engine = get_engine()
    with engine.begin() as conn:
        recriar_esquema(conn)
        for nome in ORDEM_CARGA:
            df = tabelas[nome]
            df.to_sql(nome, conn, if_exists="append", index=False,
                      chunksize=5_000, method="multi")
            log.info("%s: %s linhas carregadas", nome, f"{len(df):,}")