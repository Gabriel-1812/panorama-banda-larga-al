"""Roda todas as validações do 03_validacoes.sql e salva um relatório.

Uso (na raiz do projeto, depois do pipeline):
    python -m src.validar

Para cada teste, o relatório mostra o número, o resultado esperado (escrito no
comentário do .sql) e o resultado obtido no banco do .env. A comparação é feita
por quem lê: os esperados são texto livre, não valores automáticos.
O relatório é salvo em data/validacoes_<banco>_<data>.txt.
"""
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import pandas as pd

from src.db import get_engine

ROOT = Path(__file__).resolve().parent.parent
VALIDACOES = ROOT / "sql" / "03_validacoes.sql"
SAIDA = ROOT / "data"
MAX_LINHAS = 15        # linhas mostradas por teste
LIMITE_SEGUNDOS = 120  # um teste mais lento que isso é interrompido e vira ERRO

ROTULO = re.compile(r"^--\s*(\d+\.\d+)\s+(.*)")


def ler_testes(caminho: Path) -> list[dict]:
    """Separa o arquivo em testes: rótulo, comentários (com o esperado) e a consulta.

    Um teste começa numa linha "-- N.N título" e termina na linha cuja parte de
    código acaba em ";". Comentários depois da consulta (como o cabeçalho da
    próxima seção) não entram no teste. Comandos USE são ignorados: o banco
    vem do .env.
    """
    testes, atual, codigo = [], None, []
    for linha in caminho.read_text(encoding="utf-8").splitlines():
        limpa = linha.strip()
        rotulo = ROTULO.match(limpa)
        if rotulo:
            atual = {"id": rotulo.group(1), "titulo": rotulo.group(2), "notas": []}
            codigo = []
            continue
        if limpa.startswith("--"):
            if atual is not None and not codigo:
                atual["notas"].append(limpa.lstrip("- ").rstrip())
            continue
        if not limpa or limpa.upper().startswith("USE "):
            continue
        codigo.append(linha)
        if limpa.split("--")[0].rstrip().endswith(";") and atual is not None:
            testes.append({**atual, "sql": "\n".join(codigo).rstrip().rstrip(";")})
            atual, codigo = None, []
    return testes


def rodar(testes: list[dict]) -> tuple[str, str]:
    """Executa cada teste e devolve o nome do banco e o texto do relatório."""
    engine = get_engine()
    conexao = engine.raw_connection()   # cursor direto: o % do LIKE não vira parâmetro
    partes = []
    try:
        cursor = conexao.cursor()
        cursor.execute("SELECT DATABASE()")
        banco = cursor.fetchone()[0]
        cursor.execute(f"SET SESSION max_execution_time = {LIMITE_SEGUNDOS * 1000}")
        for i, t in enumerate(testes, start=1):
            print(f"[{i:2}/{len(testes)}] {t['id']:5} {t['titulo'][:50]:50}", end=" ", flush=True)
            inicio = time.perf_counter()
            partes.append(f"\n{'=' * 70}\n{t['id']} {t['titulo']}")
            partes.extend(f"   {n}" for n in t["notas"] if n)
            partes.append("-" * 70)
            try:
                cursor.execute(t["sql"])
                colunas = [c[0] for c in cursor.description]
                df = pd.DataFrame(cursor.fetchall(), columns=colunas)
                if df.empty:
                    partes.append("(nenhuma linha)")
                else:
                    partes.append(df.head(MAX_LINHAS).to_string(index=False))
                    if len(df) > MAX_LINHAS:
                        partes.append(f"... mais {len(df) - MAX_LINHAS} linhas ({len(df)} no total)")
            except Exception as erro:   # um teste quebrado não interrompe os outros
                partes.append(f"ERRO: {erro}")
                print("ERRO", end=" ")
            print(f"{time.perf_counter() - inicio:5.1f}s")
    finally:
        conexao.close()
    cabecalho = (f"Validações do banco {banco} em {datetime.now():%d/%m/%Y %H:%M}\n"
                 f"{len(testes)} testes lidos de {VALIDACOES.name}")
    return banco, cabecalho + "\n" + "\n".join(partes) + "\n"


def main() -> None:
    testes = ler_testes(VALIDACOES)
    banco, relatorio = rodar(testes)
    SAIDA.mkdir(exist_ok=True)
    arquivo = SAIDA / f"validacoes_{banco}_{datetime.now():%Y%m%d}.txt"
    arquivo.write_text(relatorio, encoding="utf-8")
    erros = relatorio.count("\nERRO: ")
    print(f"{len(testes)} testes rodados no banco {banco}, {erros} com erro.")
    print(f"Relatório: {arquivo.relative_to(ROOT)}")
    sys.exit(1 if erros else 0)


if __name__ == "__main__":
    main()
