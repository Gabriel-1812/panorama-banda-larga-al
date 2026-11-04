#Dashboard: Panorama da Banda Larga Fixa em Alagoas.

import math
import sys
from pathlib import Path
import pandas as pd
import plotly.express as px
import streamlit as st
from decimal import Decimal

# O Streamlit roda a partir de app/:
sys.path.append(str(Path(__file__).resolve().parent.parent))
from src.db import get_engine  # noqa: E402

st.set_page_config(page_title="Banda Larga em Alagoas", page_icon="📶", layout="wide")

COR_DESTAQUE = "#E4572E"
COR_NEUTRA = "#B0B7C3"

# =========================================================
# Funções auxiliares
# =========================================================
@st.cache_resource
def conexao():
    #Conexão com o banco.
    return get_engine()


@st.cache_data(ttl=3600)
def consultar(sql: str) -> pd.DataFrame:
    #Executa consulta, ajusta os tipos e guarda o resultado por 1 hora.
    df = pd.read_sql(sql, conexao())
    # colunas decimais viram float
    for coluna in df.columns:
        valores = df[coluna].dropna()
        if not valores.empty and isinstance(valores.iloc[0], Decimal):
            df[coluna] = df[coluna].astype(float)
    if "ano_mes" in df.columns:
        df["ano_mes"] = pd.to_datetime(df["ano_mes"])
    return df


def br(numero, casas: int = 0) -> str:
    """Formata um número no padrão brasileiro: 1.234,5"""
    if pd.isna(numero):
        return "—"
    texto = f"{numero:,.{casas}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


def fmt_cnpj(cnpj: str) -> str:
    """02558157000162 -> 02.558.157/0001-62"""
    return f"{cnpj[:2]}.{cnpj[2:5]}.{cnpj[5:8]}/{cnpj[8:12]}-{cnpj[12:]}"


def mes(data) -> str:
    """Data -> 'mm/aaaa'"""
    return pd.Timestamp(data).strftime("%m/%Y")


def estilo(fig, altura: int = 350):
    """Aplica o mesmo visual a todos os gráficos."""
    fig.update_layout(
        height=altura,
        margin=dict(l=0, r=0, t=10, b=0),
        separators=",.",               # decimal com vírgula, milhar com ponto
        hovermode="x unified",
        legend=dict(orientation="h", y=-0.15, title=None),
    )
    return fig


# =========================================================
# Dados: cada view é lida uma vez e fica em cache
# =========================================================
evolucao   = consultar("SELECT * FROM vw_evolucao_mensal")
mercado    = consultar("SELECT * FROM vw_market_share")
tecnologia = consultar("SELECT * FROM vw_tecnologia")
destaque   = consultar("SELECT * FROM vw_operadora_destaque")
municipios = consultar("SELECT * FROM vw_municipio_resumo")
starlink   = consultar("SELECT * FROM vw_starlink_municipio")

meses = list(evolucao["ano_mes"].sort_values())


# =========================================================
# Barra lateral: filtros
# =========================================================
st.sidebar.header("Filtros")

inicio, fim = st.sidebar.select_slider(
    "Período",
    options=meses,
    value=(meses[0], meses[-1]),
    format_func=mes,
)

# Operadoras do último mês do período, da maior para a menor
no_fim = mercado[mercado["ano_mes"] == fim].sort_values("ranking").copy()

# Nomes repetidos (ex.: os dois CNPJs da Claro) ganham o CNPJ no rótulo
repetidos = no_fim["empresa"].duplicated(keep=False)
no_fim["rotulo"] = no_fim["empresa"].where(
    ~repetidos, no_fim["empresa"] + " (" + no_fim["cnpj"].map(fmt_cnpj) + ")"
)
rotulos = dict(zip(no_fim["cnpj"], no_fim["rotulo"]))

cnpj_destaque = st.sidebar.selectbox(
    "Operadora em destaque",
    options=list(rotulos),
    format_func=rotulos.get,
    help="Ordenadas por número de acessos no último mês do período",
)
nome_destaque = rotulos[cnpj_destaque]

st.sidebar.caption("Fonte: dados abertos da Anatel · banda larga fixa (SCM), produto INTERNET")


def no_periodo(df: pd.DataFrame) -> pd.DataFrame:
    """Mantém só as linhas dentro do período escolhido."""
    return df[df["ano_mes"].between(inicio, fim)]


# =========================================================
# Cabeçalho e KPIs
# =========================================================
st.title("📶 Panorama da Banda Larga Fixa em Alagoas")
st.caption(f"Período analisado: {mes(inicio)} a {mes(fim)}")

linha_fim = evolucao[evolucao["ano_mes"] == fim].iloc[0]
fibra = (tecnologia[tecnologia["meio_acesso"] == "Fibra"]
         .set_index("ano_mes")["participacao_pct"])
lider = no_fim.iloc[0]

col1, col2, col3, col4 = st.columns(4)
col1.metric(
    f"Acessos em {mes(fim)}",
    br(linha_fim["total_acessos"]),
    None if pd.isna(linha_fim["var_pct_12m"])
    else f"{br(linha_fim['var_pct_12m'], 1)}% em 12 meses",
)
col2.metric("Operadoras ativas", br(len(no_fim)))
col3.metric(
    "Participação da fibra",
    f"{br(fibra[fim], 2)}%",
    f"{br(fibra[fim] - fibra[inicio], 2)} p.p. desde {mes(inicio)}",
)
col4.metric(
    "Líder do mercado",
    lider["rotulo"],
    f"{br(lider['participacao_pct'], 1)}% do mercado",
    delta_color="off",
)

st.divider()

# ========================================
# 1. Evolução do Mercado
# ========================================
st.subheader("1. Evolução do mercado")

fig = px.line(
    no_periodo(evolucao),
    x="ano_mes",
    y="total_acessos",
    markers=True,
    labels={"ano_mes": "", "total_acessos": "Acessos"},
)
fig.update_traces(line_color=COR_DESTAQUE, hovertemplate="%{y:,.0f} acessos")
st.plotly_chart(estilo(fig), width="stretch")

# =========================================================
# 2. A virada da fibra
# =========================================================
st.subheader("2.A virada da fibra")

fig = px.line(
    no_periodo(tecnologia),
    x="ano_mes",
    y="participacao_pct",
    color="meio_acesso",
    category_orders={"meio_acesso":["Fibra"]}, #Fibra primeiro
    labels={"ano_mes": "", "participacao_pct": "% dos acessos", "meio_acesso": ""},
)
fig.update_traces(hovertemplate="%{y:.1f}%")
fig.update_yaxes(range=[0, 100], ticksuffix="%")
st.plotly_chart(estilo(fig), width="stretch")

st.caption(
    f"Em {mes(inicio)}, a fibra respondida por {br(fibra[inicio], 2)}% dos acessos; "
    f"Em {mes(fim)}, por {br(fibra[fim], 2)}%"
)