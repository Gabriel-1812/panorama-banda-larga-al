"""Dashboard: Panorama da Banda Larga Fixa em Alagoas."""
import sys
from pathlib import Path
import pandas as pd
import streamlit as st

# O Streamlit roda o script em app/
# Mostra a raíz do projeto para importar src/
sys.path.append(str(Path(__file__).resolve().parent.parent))
from src.db import get_engine  # noqa: E402

st.set_page_config(page_title="Banda Larga em Alagoas", page_icon="📶", layout="wide")


@st.cache_resource
def conexao():
    """Cria a conexão com o banco uma única vez."""
    return get_engine()


@st.cache_data(ttl=3600)
def consultar(sql: str) -> pd.DataFrame:
    """Executa uma consulta e guarda o resultado por 1 hora."""
    return pd.read_sql(sql, conexao())


def br(numero, casas: int = 0) -> str:
    """Formata um número no padrão brasileiro: 1.234,5"""
    texto = f"{numero:,.{casas}f}"
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


st.title("📶 Panorama da Banda Larga Fixa em Alagoas")
st.caption("Fonte: dados abertos da Anatel · banda larga fixa (SCM), produto INTERNET")

evolucao = consultar("SELECT * FROM vw_evolucao_mensal ORDER BY ano_mes")

# ---------- Dados ----------
mercado = consultar("""
    SELECT * FROM vw_market_share
    WHERE ano_mes = (SELECT MAX(ano_mes) FROM vw_market_share)
""")
tecnologia = consultar("SELECT * FROM vw_tecnologia ORDER BY ano_mes")

ultimo = evolucao.iloc[-1]                                   # último mês da série
fibra = tecnologia[tecnologia["meio_acesso"] == "Fibra"]
fibra_atual = fibra.iloc[-1]["participacao_pct"]
fibra_inicio = fibra.iloc[0]["participacao_pct"]
lider = mercado.sort_values("ranking").iloc[0]

# ---------- KPIs ----------
st.subheader(f"Retrato de {pd.to_datetime(ultimo['ano_mes']):%m/%Y}")

col1, col2, col3, col4 = st.columns(4)
col1.metric("Acessos de banda larga",
            br(ultimo["total_acessos"]),
            f"{br(ultimo['var_pct_12m'], 1)}% em 12 meses")
col2.metric("Operadoras ativas", br(len(mercado)))
col3.metric("Participação da Fibra",
            f"{br(fibra_atual, 2)}%",
            f"{br(fibra_atual - fibra_inicio, 2)} p.p. desde jan/2021")
col4.metric("Líder do mercado",
            lider["empresa"],
            f"{br(lider['participacao_pct'], 1)}% do mercado",
            delta_color="off")