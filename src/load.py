"""Etapa 3 do pipeline: recria o esquema, carrega as tabelas e cria as views no MySQL."""
import logging
from pathlib import Path
import pandas as pd
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from src.db import get_engine

log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "sql" / "01_schema.sql"
VIEWS = ROOT / "sql" / "02_views.sql"

# Ordem importa: dimensões antes da fato, por causa das chaves estrangeiras
ORDEM_CARGA = ["dim_municipio", "dim_operadora", "fato_acessos"]


def executar_arquivo_sql(conn, caminho: Path) -> None:
    """Executa um arquivo .sql, um comando por vez.

    Remove as linhas de comentário (que começam com --) e separa os comandos
    pelo ponto e vírgula. Por isso esse caractere não pode aparecer em comentários.
    """
    linhas = [linha for linha in caminho.read_text(encoding="utf-8").splitlines()
              if not linha.strip().startswith("--")]
    for comando in "\n".join(linhas).split(";"):
        if comando.strip():
            conn.execute(text(comando))
    log.info("Executado: %s", caminho.name)


def carregar(tabelas: dict[str, pd.DataFrame]) -> None:
    """Recria o esquema, carrega dimensões e fato (nessa ordem) e cria as views."""
    engine = get_engine()
    with engine.begin() as conn:
        executar_arquivo_sql(conn, SCHEMA)
        for nome in ORDEM_CARGA:
            df = tabelas[nome]
            log.info("%s: colunas %s", nome, list(df.columns))
            try:
                df.to_sql(nome, conn, if_exists="append", index=False,
                          chunksize=5_000, method="multi")
            except SQLAlchemyError as erro:
                # Mostra só a mensagem do MySQL
                log.error("Falha ao carregar %s: %s", nome, getattr(erro, "orig", erro))
                raise SystemExit(1)
            log.info("%s: %s linhas carregadas", nome, f"{len(df):,}")
        executar_arquivo_sql(conn, VIEWS)
