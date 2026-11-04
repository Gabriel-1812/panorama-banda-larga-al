-- =========================================================
-- Views do projeto - Camada analítica
-- =========================================================

-- 1. vw_evolucao_mensal
-- Análise da evolução quantitativa do mercado de Banda Larga em Alagoas
CREATE OR REPLACE VIEW vw_evolucao_mensal AS
WITH acessos_mensais AS (
SELECT ano_mes, SUM(acessos) AS total_acessos
FROM fato_acessos
WHERE tipo_produto = 'INTERNET'
GROUP BY ano_mes
),
comparacoes AS (
SELECT ano_mes, total_acessos, 
LAG(total_acessos, 1)  OVER (ORDER BY ano_mes) AS acessos_mes_anterior,
LAG(total_acessos, 12) OVER (ORDER BY ano_mes) AS acessos_12m_atras
FROM acessos_mensais
)
SELECT ano_mes, 
total_acessos, 
total_acessos - acessos_mes_anterior AS var_abs_mensal,
ROUND((total_acessos - acessos_mes_anterior) / acessos_mes_anterior * 100, 2) AS var_pct_mensal,
ROUND((total_acessos - acessos_12m_atras)  / acessos_12m_atras  * 100, 2) AS var_pct_12m
FROM comparacoes;

-- 2. vw_market_share
-- Ranking das empresas pelos acessos, por mês
-- Grão: uma linha por mês e operadora, só INTERNET
CREATE OR REPLACE VIEW vw_market_share AS
WITH acessos_mes AS (
SELECT ano_mes, cnpj, SUM(acessos) AS acessos_totais
FROM fato_acessos
WHERE tipo_produto = 'INTERNET'
GROUP BY ano_mes, cnpj
)
SELECT am.ano_mes, 
am.cnpj, 
op.empresa,
op.grupo_economico,
am.acessos_totais,
ROUND(am.acessos_totais / SUM(am.acessos_totais) OVER (PARTITION BY am.ano_mes) * 100, 2) AS participacao_pct,
RANK() OVER (PARTITION BY am.ano_mes ORDER BY am.acessos_totais DESC) AS ranking
FROM acessos_mes am
JOIN dim_operadora op ON am.cnpj = op.cnpj;

-- 3. vw_tecnologia
-- Paticipação dos meios de acesso de banda larga, crescimento da Fibra
-- Grão: Uma linha por Mês e meio de acesso
CREATE OR REPLACE VIEW vw_tecnologia AS
WITH acessos_mes AS (
SELECT ano_mes, meio_acesso, SUM(acessos) AS acessos
FROM fato_acessos
WHERE tipo_produto = 'INTERNET'
GROUP BY ano_mes, meio_acesso
)
SELECT ano_mes,
meio_acesso,
acessos,
ROUND(acessos / SUM(acessos) OVER (PARTITION BY ano_mes) * 100, 2) AS participacao_pct, 
RANK() OVER (PARTITION BY ano_mes ORDER BY acessos DESC) AS ranking
FROM acessos_mes;

-- 4. vw_operadora_destaque
-- Comparação de acessos de uma empresa e sua variação com a última aparição da mesma
-- View genérica, filtro é feito no dashboard
-- Grão: uma linha por mês e operadora
CREATE OR REPLACE VIEW vw_operadora_destaque AS
WITH comparacoes AS(
SELECT ano_mes, cnpj, empresa, grupo_economico, acessos_totais, participacao_pct, ranking,
LAG(ano_mes) OVER (PARTITION BY cnpj ORDER BY ano_mes) AS ultima_aparicao,
LAG(acessos_totais) OVER (PARTITION BY cnpj ORDER BY ano_mes) AS valor_anterior
FROM vw_market_share
)
SELECT ano_mes, 
cnpj, 
empresa, 
grupo_economico, 
acessos_totais, 
participacao_pct,
ranking,
TIMESTAMPDIFF(MONTH,ultima_aparicao,ano_mes) AS meses_ultima_aparicao,
ROUND((acessos_totais - valor_anterior) / valor_anterior * 100, 2) AS var_pct_anterior
FROM comparacoes;

-- 5. vw_municipio_resumo
-- Mercado de Banda Larga em cada município no último mês
-- Grão: Uma linha por município (Apenas último mês disponível)
CREATE OR REPLACE VIEW vw_municipio_resumo AS
WITH ultimo_mes AS (
SELECT MAX(ano_mes) AS ano_mes
FROM fato_acessos
),
operadoras_mun AS (
SELECT f.cod_ibge, 
f.cnpj, 
SUM(f.acessos) AS acessos_operadora,
SUM(CASE WHEN f.meio_acesso = 'Fibra' THEN f.acessos ELSE 0 END) AS acessos_fibra
FROM fato_acessos f
JOIN ultimo_mes u ON f.ano_mes = u.ano_mes
WHERE tipo_produto = 'INTERNET'
GROUP BY cod_ibge, cnpj
),
calculo AS (
SELECT cod_ibge, cnpj, acessos_operadora, acessos_fibra,
SUM(acessos_operadora) OVER (PARTITION BY cod_ibge) AS acessos_municipio,
SUM(acessos_fibra) OVER (PARTITION BY cod_ibge) AS fibra_municipio,
COUNT(*) OVER (PARTITION BY cod_ibge) AS operadoras,
acessos_operadora / SUM(acessos_operadora) OVER (PARTITION BY cod_ibge) * 100 AS participacao,
ROW_NUMBER() OVER (PARTITION BY cod_ibge ORDER BY acessos_operadora DESC, cnpj) AS posicao
FROM operadoras_mun
),
concentracao AS (
SELECT cod_ibge, 
SUM(POWER(participacao, 2)) AS hhi
FROM calculo
GROUP BY cod_ibge
)
SELECT 
c.cod_ibge,
m.municipio,
c.acessos_municipio,
c.operadoras,
c.cnpj AS cnpj_lider,
o.empresa AS empresa_lider,
ROUND(c.participacao, 2) AS participacao_lider_pct,
ROUND(c.fibra_municipio / c.acessos_municipio * 100, 2) AS fibra_pct,
ROUND(h.hhi, 0) AS hhi
FROM calculo c
JOIN concentracao  h ON h.cod_ibge = c.cod_ibge
JOIN dim_municipio m ON m.cod_ibge = c.cod_ibge
JOIN dim_operadora o ON o.cnpj     = c.cnpj
WHERE c.posicao = 1;

-- 6. vw_starlink_municipio
-- Cada município que contem starlink, quantidade de acesso no mês mais atual e comparação com presença da fibra no municìpio
-- Grão: Cada linha um município que possui starlink
CREATE OR REPLACE VIEW vw_starlink_municipio AS
WITH ultimo_mes AS (
SELECT MAX(ano_mes) AS ano_mes
FROM fato_acessos
),
operadoras_mun AS (
SELECT f.cod_ibge, 
f.cnpj, 
SUM(f.acessos) AS acessos_operadora,
SUM(CASE WHEN f.meio_acesso = 'Fibra' THEN f.acessos ELSE 0 END) AS acessos_fibra
FROM fato_acessos f
JOIN ultimo_mes u ON f.ano_mes = u.ano_mes
WHERE f.tipo_produto = 'INTERNET'
GROUP BY f.cod_ibge, f.cnpj
),
totais AS (
SELECT *,
SUM(acessos_operadora) OVER (PARTITION BY cod_ibge) AS acessos_municipio,
SUM(acessos_fibra) OVER (PARTITION BY cod_ibge) AS fibra_municipio
FROM operadoras_mun
)
SELECT 
t.cod_ibge,
m.municipio AS municipio,
t.acessos_operadora AS acessos_starlink,
ROUND (t.acessos_operadora / t.acessos_municipio * 100, 2) AS participacao_starlink_pct,
ROUND (t.fibra_municipio / t.acessos_municipio * 100, 2) AS fibra_pct
FROM totais t
JOIN dim_municipio m ON t.cod_ibge = m.cod_ibge
WHERE t.cnpj = '40154884000153' -- CNPJ da empresa Starlink
;