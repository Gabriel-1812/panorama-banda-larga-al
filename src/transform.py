#Etapa 2 do pipeline: lê os CSVs da Anatel, filtra Alagoas e monta as tabelas.

import logging
from pathlib import Path
import pandas as pd
from src.extract import EXTRACT_DIR

log = logging.getLogger(__name__)

UF = "AL"
ANO_INICIAL = 2021
TAMANHO_CHUNK = 500000

RENOMEAR = {
    "Ano": "ano",
    "Mês": "mes",
    "Grupo Econômico": "grupo_economico",
    "Empresa": "empresa",
    "CNPJ": "cnpj",
    "Porte da Prestadora": "porte",
    "UF": "uf",
    "Município": "municipio",
    "Código IBGE Município": "cod_ibge",
    "Faixa de Velocidade": "faixa_velocidade",
    "Velocidade": "velocidade_mbps",
    "Tecnologia": "tecnologia",
    "Meio de Acesso": "meio_acesso",
    "Tipo de Pessoa": "tipo_pessoa",
    "Tipo de Produto": "tipo_produto",
    "Acessos": "acessos",
}

COLUNAS_TEXTO = [
    "grupo_economico", "empresa", "cnpj", "porte", "uf", "municipio", "cod_ibge",
    "faixa_velocidade", "tecnologia", "meio_acesso", "tipo_pessoa", "tipo_produto",
]

# Colunas que identificam uma linha da tabela fato
DIMENSOES_FATO = [
    "ano_mes", "cod_ibge", "cnpj", "faixa_velocidade", "velocidade_mbps",
    "tecnologia", "meio_acesso", "tipo_pessoa", "tipo_produto",
]


def listar_arquivos() -> list[Path]:
    #Seleciona só os arquivos anuais a partir de ANO_INICIAL.
    
    arquivos = []
    for caminho in sorted(EXTRACT_DIR.glob("Acessos_Banda_Larga_Fixa_*.csv")):
        sufixo = caminho.stem.removeprefix("Acessos_Banda_Larga_Fixa_")

        if sufixo.isdigit() and int(sufixo) >= ANO_INICIAL:
            arquivos.append(caminho)
    return arquivos


def ler_alagoas(caminho: Path) -> pd.DataFrame:
    """Lê um CSV em pedaços e guarda só as linhas da UF escolhida."""
    pedacos, total = [], 0
    for chunk in pd.read_csv(caminho, sep=";", dtype=str, encoding="utf-8-sig",
                             chunksize=TAMANHO_CHUNK):
        total += len(chunk)
        pedacos.append(chunk[chunk["UF"] == UF])
    df = pd.concat(pedacos, ignore_index=True)
    log.info("%s: %s linhas lidas, %s de %s", caminho.name, f"{total:,}", f"{len(df):,}", UF)
    return df


def padronizar(df: pd.DataFrame) -> pd.DataFrame:

    #Renomeia colunas, limpa textos e converte os tipos.
    df = df.rename(columns=RENOMEAR)

    for coluna in COLUNAS_TEXTO:
        df[coluna] = df[coluna].str.strip()

    # Só dígitos; o CNPJ sempre com 14 posições (zeros à esquerda)
    df["cnpj"] = df["cnpj"].str.replace(r"\D", "", regex=True).str.zfill(14)
    df["cod_ibge"] = df["cod_ibge"].str.replace(r"\D", "", regex=True)

    # Ano + Mês viram uma data: sempre o dia 1 do mês
    df["ano_mes"] = pd.to_datetime(pd.DataFrame({
        "year": df["ano"].astype(int),
        "month": df["mes"].astype(int),
        "day": 1,
    }))

    # Vírgula decimal brasileira -> ponto
    df["velocidade_mbps"] = pd.to_numeric(
        df["velocidade_mbps"].str.replace(",", ".", regex=False), errors="coerce")
    df["acessos"] = pd.to_numeric(df["acessos"], errors="coerce")

    return df.drop(columns=["ano", "mes"])


def validar(df: pd.DataFrame) -> pd.DataFrame:

    #Checagens de qualidade: registra problemas no log e remove linhas inválidas.
    obrigatorias = ["ano_mes", "cnpj", "cod_ibge", "acessos"]
    vazias = df[obrigatorias].isna().any(axis=1)
    if vazias.any():
        log.warning("%d linhas sem campos obrigatórios foram descartadas", vazias.sum())
        df = df[~vazias]

    negativas = df["acessos"] < 0
    if negativas.any():
        log.warning("%d linhas com acessos negativos foram descartadas", negativas.sum())
        df = df[~negativas]

    log.info("Período: %s a %s (%d meses) | Municípios: %d | Empresas: %d",
             df["ano_mes"].min().date(), df["ano_mes"].max().date(),
             df["ano_mes"].nunique(), df["cod_ibge"].nunique(), df["cnpj"].nunique())
    return df


def montar_tabelas(df: pd.DataFrame) -> dict[str, pd.DataFrame]:
    #Separa os dados em duas dimensões e uma fato (esquema estrela).
    # Ordena do mais recente para o mais antigo: se um nome mudou ao longo do tempo, a dimensão fica com a versão mais atual
    recente = df.sort_values("ano_mes", ascending=False)

    dim_municipio = (recente[["cod_ibge", "municipio", "uf"]]
                     .drop_duplicates("cod_ibge"))
    dim_operadora = (recente[["cnpj", "empresa", "grupo_economico", "porte"]]
                     .drop_duplicates("cnpj"))

    # Linhas repetidas com a mesma combinação são somadas numa só
    fato = (df.groupby(DIMENSOES_FATO, dropna=False, as_index=False)["acessos"].sum())
    fato["acessos"] = fato["acessos"].astype(int)
    if len(fato) < len(df):
        log.info("%d linhas duplicadas foram consolidadas na fato", len(df) - len(fato))

    log.info("Tabelas: dim_municipio=%d, dim_operadora=%d, fato_acessos=%s",
             len(dim_municipio), len(dim_operadora), f"{len(fato):,}")
    return {"dim_municipio": dim_municipio,
            "dim_operadora": dim_operadora,
            "fato_acessos": fato}


def transformar() -> dict[str, pd.DataFrame]:
    arquivos = listar_arquivos()
    if not arquivos:
        raise FileNotFoundError("Nenhum CSV encontrado. Rode a extração antes.")
    log.info("%d arquivos selecionados: %s", len(arquivos), [a.name for a in arquivos])

    brutos = pd.concat([ler_alagoas(a) for a in arquivos], ignore_index=True)
    return montar_tabelas(validar(padronizar(brutos)))









