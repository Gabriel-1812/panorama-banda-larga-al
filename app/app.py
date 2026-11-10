"""Dashboard: Panorama da Banda Larga Fixa em Alagoas."""
import math
import sys
from decimal import Decimal
from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st

# O Streamlit roda a partir de app/: avisamos onde fica a raiz do projeto.
# Esta linha PRECISA vir antes do "from src.db import ..."
sys.path.append(str(Path(__file__).resolve().parent.parent))
from src.db import get_engine  # noqa: E402

st.set_page_config(page_title="Banda Larga em Alagoas", page_icon=":signal_strength:", layout="wide")

COR_DESTAQUE = "#E4572E"
COR_NEUTRA = "#B0B7C3"


# =========================================================
# Funções auxiliares
# =========================================================
@st.cache_resource
def conexao():
    """Cria a conexão com o banco uma única vez."""
    return get_engine()


@st.cache_data(ttl=3600)
def consultar(sql: str) -> pd.DataFrame:
    """Executa uma consulta, ajusta os tipos e guarda o resultado por 1 hora."""
    df = pd.read_sql(sql, conexao())
    # Só as colunas DECIMAL viram float. CNPJ e código IBGE continuam texto.
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
ref = consultar("SELECT mes_referencia FROM vw_mes_referencia")
ultimo_mes = pd.Timestamp(ref["mes_referencia"].iloc[0])

# Participação da fibra em cada mês (usada nas duas abas)
fibra = (tecnologia[tecnologia["meio_acesso"] == "Fibra"]
         .set_index("ano_mes")["participacao_pct"])


# =========================================================
# Barra lateral: filtros (valem para a aba "Evolução do mercado")
# =========================================================
st.sidebar.header("Filtros")
st.sidebar.caption("Valem para a aba **Evolução do mercado**. "
                   "A aba de municípios mostra sempre o último mês.")

inicio, fim = st.sidebar.select_slider(
    "Período", options=meses, value=(meses[0], ultimo_mes), format_func=mes)

# Operadoras do último mês do período, da maior para a menor
no_fim = mercado[mercado["ano_mes"] == fim].sort_values("ranking").copy()

# Nomes repetidos (ex.: os dois CNPJs da Claro) ganham o CNPJ no rótulo
repetidos = no_fim["empresa"].duplicated(keep=False)
no_fim["rotulo"] = no_fim["empresa"].where(
    ~repetidos, no_fim["empresa"] + " (" + no_fim["cnpj"].map(fmt_cnpj) + ")")
rotulos = dict(zip(no_fim["cnpj"], no_fim["rotulo"]))

cnpj_destaque = st.sidebar.selectbox(
    "Operadora em destaque",
    options=list(rotulos),
    format_func=rotulos.get,
    help="Operadoras com acessos de internet no último mês do período. "
         "Se uma operadora não aparece, ela não reportou nesse mês.",
)
nome_destaque = rotulos[cnpj_destaque]


def no_periodo(df: pd.DataFrame) -> pd.DataFrame:
    """Mantém só as linhas dentro do período escolhido."""
    return df[df["ano_mes"].between(inicio, fim)]


# =========================================================
# Cabeçalho e abas
# =========================================================
st.title(":signal_strength: Panorama da Banda Larga Fixa em Alagoas")
st.caption("Fonte: dados abertos da Anatel · banda larga fixa (SCM), produto INTERNET")

aba_mercado, aba_municipios = st.tabs([
    "📈 Evolução do mercado",
    f"🗺️ Retrato dos municípios ({mes(ultimo_mes)})",
])


# =========================================================
# ABA 1: Evolução do mercado (usa os filtros)
# =========================================================
with aba_mercado:
    # ---------- KPIs ----------
    st.caption(f"Período analisado: {mes(inicio)} a {mes(fim)}")

    linha_fim = evolucao[evolucao["ano_mes"] == fim].iloc[0]
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

    # ---------- 1. Evolução do mercado ----------
    st.subheader("1. Evolução do mercado")

    fig = px.line(
        no_periodo(evolucao), x="ano_mes", y="total_acessos", markers=True,
        labels={"ano_mes": "", "total_acessos": "Acessos"},
    )
    fig.update_traces(line_color=COR_DESTAQUE, hovertemplate="%{y:,.0f} acessos")
    st.plotly_chart(estilo(fig), width="stretch")

    # ---------- 2. A virada da fibra ----------
    st.subheader("2. A virada da fibra")

    fig = px.line(
        no_periodo(tecnologia), x="ano_mes", y="participacao_pct", color="meio_acesso",
        category_orders={"meio_acesso": ["Fibra"]},   # fibra sempre primeiro na legenda
        labels={"ano_mes": "", "participacao_pct": "% dos acessos", "meio_acesso": ""},
    )
    fig.update_traces(hovertemplate="%{y:.1f}%")
    fig.update_yaxes(range=[0, 100], ticksuffix="%")
    st.plotly_chart(estilo(fig), width="stretch")

    st.caption(
        f"Em {mes(inicio)}, a fibra respondia por {br(fibra[inicio], 2)}% dos acessos; "
        f"em {mes(fim)}, por {br(fibra[fim], 2)}%."
    )

    # ---------- 3. Quem lidera o mercado ----------
    st.subheader(f"3. Quem lidera o mercado ({mes(fim)})")

    top = no_fim.head(10).copy()
    top["grupo"] = top["cnpj"].eq(cnpj_destaque).map({True: "Em destaque", False: "Demais"})

    fig = px.bar(
        top, x="participacao_pct", y="rotulo", orientation="h", color="grupo",
        color_discrete_map={"Em destaque": COR_DESTAQUE, "Demais": COR_NEUTRA},
        text="participacao_pct",
        labels={"participacao_pct": "% do mercado", "rotulo": ""},
    )
    fig.update_traces(texttemplate="%{text:.1f}%", textposition="outside",
                      hovertemplate="%{x:.2f}%")
    fig = estilo(fig, altura=420)
    fig.update_layout(hovermode="closest", showlegend=False,
                      yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, width="stretch")

    # Se a operadora escolhida não está no top 10, avisamos onde ela está
    if cnpj_destaque not in set(top["cnpj"]):
        posicao = no_fim[no_fim["cnpj"] == cnpj_destaque].iloc[0]
        st.info(
            f"**{nome_destaque}** está fora do top 10: {int(posicao['ranking'])}º lugar, "
            f"com {br(posicao['participacao_pct'], 2)}% do mercado."
        )

    # ---------- 4. Operadora em destaque ----------
    st.subheader(f"4. Em destaque: {nome_destaque}")

    op = no_periodo(destaque[destaque["cnpj"] == cnpj_destaque]).sort_values("ano_mes")

    # Grade com TODOS os meses do período: meses sem reporte viram buracos no gráfico
    meses_periodo = pd.DataFrame({"ano_mes": [m for m in meses if inicio <= m <= fim]})
    serie = meses_periodo.merge(op, on="ano_mes", how="left")

    atual = op[op["ano_mes"] == fim].iloc[0]
    primeiro = op.iloc[0]

    c1, c2, c3 = st.columns(3)
    c1.metric(
        "Acessos",
        br(atual["acessos_totais"]),
        f"{br(atual['acessos_totais'] - primeiro['acessos_totais'])} desde {mes(primeiro['ano_mes'])}",
    )
    c2.metric(
        "Participação",
        f"{br(atual['participacao_pct'], 2)}%",
        f"{br(atual['participacao_pct'] - primeiro['participacao_pct'], 2)} p.p.",
    )
    c3.metric(
        "Ranking",
        f"{int(atual['ranking'])}º",
        f"{int(primeiro['ranking'] - atual['ranking'])} posições desde {mes(primeiro['ano_mes'])}",
    )

    g1, g2 = st.columns(2)

    fig = px.line(serie, x="ano_mes", y="acessos_totais", markers=True,
                  labels={"ano_mes": "", "acessos_totais": "Acessos"})
    fig.update_traces(line_color=COR_DESTAQUE, hovertemplate="%{y:,.0f} acessos")
    g1.plotly_chart(estilo(fig, altura=300), width="stretch")

    fig = px.line(serie, x="ano_mes", y="participacao_pct", markers=True,
                  labels={"ano_mes": "", "participacao_pct": "% do mercado"})
    fig.update_traces(line_color=COR_DESTAQUE, hovertemplate="%{y:.2f}%")
    g2.plotly_chart(estilo(fig, altura=300), width="stretch")

    # A pegadinha do Card 4, agora visível para quem usa o dashboard
    meses_sem_reporte = int((op["meses_ultima_aparicao"] - 1).clip(lower=0).sum())
    if meses_sem_reporte:
        st.warning(
            f"{nome_destaque} ficou **{meses_sem_reporte} mês(es) sem reportar** acessos "
            "no período. Esses intervalos aparecem como falhas na linha."
        )


# =========================================================
# ABA 2: Retrato dos municípios (último mês, sem filtros)
# =========================================================
with aba_municipios:
    st.caption(f"Retrato de {mes(ultimo_mes)}, o último mês disponível. Esta aba não depende de filtros.")

    # ---------- 1. Os municípios ----------
    st.subheader("1. Concorrência e fibra em cada município")
    st.caption(
        "HHI vai de 0 a 10.000; acima de 2.500, o mercado é considerado altamente concentrado. "
        "Concorrentes equivalentes = 10.000 ÷ HHI: quantas operadoras de tamanho igual "
        "produziriam a mesma concentração."
    )

    tabela = (municipios
              .assign(concorrentes_equivalentes=10_000 / municipios["hhi"])
              .sort_values("acessos_municipio", ascending=False))

    busca = st.text_input("Buscar município", placeholder="Ex.: Arapiraca")
    if busca:
        tabela = tabela[tabela["municipio"].str.contains(busca, case=False, na=False)]

    st.dataframe(
        tabela[["municipio", "acessos_municipio", "operadoras", "empresa_lider",
                "participacao_lider_pct", "fibra_pct", "hhi", "concorrentes_equivalentes"]],
        hide_index=True,
        width="stretch",
        height=400,
        column_config={
            "municipio": "Município",
            "acessos_municipio": st.column_config.NumberColumn("Acessos", format="localized"),
            "operadoras": "Operadoras",
            "empresa_lider": "Líder",
            "participacao_lider_pct": st.column_config.NumberColumn("Part. do líder", format="%.1f%%"),
            "fibra_pct": st.column_config.ProgressColumn(
                "Fibra", format="%.1f%%", min_value=0, max_value=100),
            "hhi": st.column_config.NumberColumn("HHI", format="localized"),
            "concorrentes_equivalentes": st.column_config.NumberColumn(
                "Concorrentes equiv.", format="%.1f"),
        },
    )

    st.divider()

    # ---------- 2. Lacunas de fibra ----------
    st.subheader("2. Lacunas de fibra: onde a Starlink é mais forte")

    ordenado = starlink.sort_values("participacao_starlink_pct", ascending=False)
    n_quartil = math.ceil(len(ordenado) / 4)      # 98 municípios -> 25
    topo, resto = ordenado.head(n_quartil), ordenado.iloc[n_quartil:]

    c1, c2, c3 = st.columns(3)
    c1.metric("Municípios com Starlink", f"{len(starlink)} de {len(municipios)}")
    c2.metric(
        "Fibra onde a Starlink é mais forte",
        f"{br(topo['fibra_pct'].mean(), 1)}%",
        help=f"Média simples da fibra nos {n_quartil} municípios (1º quartil) "
             "com maior participação da Starlink.",
    )
    c3.metric(
        "Fibra nos demais municípios",
        f"{br(resto['fibra_pct'].mean(), 1)}%",
        help=f"Média simples da fibra nos outros {len(resto)} municípios com Starlink.",
    )

    # Dispersão: a relação completa, sem recortes arbitrários
    fig = px.scatter(
        starlink,
        x="fibra_pct",
        y="participacao_starlink_pct",
        hover_name="municipio",
        custom_data=["acessos_starlink"],
        labels={"fibra_pct": "% de fibra no município",
                "participacao_starlink_pct": "% de participação da Starlink"},
    )
    fig.update_traces(
        marker=dict(color=COR_DESTAQUE, size=10, opacity=0.7),
        hovertemplate="Fibra: %{x:.1f}%<br>Starlink: %{y:.1f}%"
                      "<br>%{customdata[0]:,.0f} acessos Starlink<extra></extra>",
    )
    fig = estilo(fig, altura=380)
    fig.update_layout(hovermode="closest")
    fig.add_vline(
        x=fibra[ultimo_mes], line_dash="dot", line_color=COR_NEUTRA,
        annotation_text=f"Média do estado: {br(fibra[ultimo_mes], 1)}% de fibra",
        annotation_position="top left",
    )
    st.plotly_chart(fig, width="stretch")

    st.caption(
        "Cada ponto é um município. A Starlink só ganha participação relevante onde há pouca "
        "fibra: o padrão se mantém dividindo os municípios em 4, 5 ou 6 grupos."
    )

    st.markdown(f"**Os {n_quartil} municípios onde a Starlink é mais forte**")
    st.dataframe(
        topo[["municipio", "acessos_starlink", "participacao_starlink_pct", "fibra_pct"]],
        hide_index=True,
        width="stretch",
        column_config={
            "municipio": "Município",
            "acessos_starlink": st.column_config.NumberColumn("Acessos Starlink", format="localized"),
            "participacao_starlink_pct": st.column_config.NumberColumn(
                "Part. da Starlink", format="%.1f%%"),
            "fibra_pct": st.column_config.ProgressColumn(
                "Fibra", format="%.1f%%", min_value=0, max_value=100),
        },
    )


# =========================================================
# Rodapé: limitações (vale para as duas abas)
# =========================================================
st.divider()
st.caption(
    "**Limitações.** Os dados são os acessos reportados pelas operadoras à Anatel: "
    "algumas reportam de forma intermitente, e há subnotificação, principalmente entre "
    "pequenos provedores. As análises consideram apenas o produto INTERNET e o período "
    "de jan/2021 em diante, após a mudança de metodologia da Anatel."
)