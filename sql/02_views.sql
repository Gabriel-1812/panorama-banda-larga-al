-- =========================================================
-- 02_views.sql: camada analítica do projeto
-- Executado pelo pipeline (src/load.py) depois da carga das tabelas.
-- Ordem: uma view que depende de outra vem depois dela.
--   vw_operadora_destaque  depende de  vw_market_share
--   vw_municipio_resumo    depende de  vw_mes_referencia
--   vw_starlink_municipio  depende de  vw_mes_referencia
-- Regras gerais:
--   R1. Análises de mercado usam só tipo_produto = 'INTERNET' (exceto vw_linha_dedicada).
--   R2. Nunca somar acessos entre meses diferentes (acessos é um estoque mensal).
--   R3. Nenhuma data fixa no código.
--   R4. Percentuais de 0 a 100, com 2 casas decimais.
--   R5. Nomes em português, snake_case, com a pergunta de cada view no cabeçalho.
-- Atenção: o pipeline separa os comandos por ponto e vírgula. Não use esse
-- caractere dentro de comentários.
-- =========================================================


-- =========================================================
-- BLOCO A: séries mensais do mercado
-- =========================================================

-- ---------------------------------------------------------
-- 1. vw_evolucao_mensal
-- Pergunta: o mercado de banda larga (INTERNET) de Alagoas está crescendo?
-- Grão: uma linha por mês.
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_evolucao_mensal AS
WITH acessos_mensais AS (
    SELECT ano_mes,
           SUM(acessos) AS total_acessos
    FROM fato_acessos
    WHERE tipo_produto = 'INTERNET'
    GROUP BY ano_mes
),
comparacoes AS (
    SELECT ano_mes,
           total_acessos,
           LAG(total_acessos, 1)  OVER (ORDER BY ano_mes) AS acessos_mes_anterior,
           LAG(total_acessos, 12) OVER (ORDER BY ano_mes) AS acessos_12m_atras
    FROM acessos_mensais
)
SELECT ano_mes,
       total_acessos,
       total_acessos - acessos_mes_anterior                                    AS var_abs_mensal,
       ROUND((total_acessos - acessos_mes_anterior) / acessos_mes_anterior * 100, 2) AS var_pct_mensal,
       ROUND((total_acessos - acessos_12m_atras) / acessos_12m_atras * 100, 2)       AS var_pct_12m
FROM comparacoes;


-- ---------------------------------------------------------
-- 2. vw_market_share
-- Pergunta: quem lidera o mercado (INTERNET) e como o ranking muda mês a mês?
-- Grão: uma linha por mês e operadora (CNPJ).
-- Obs.: ranking por CNPJ. Um grupo com mais de um CNPJ (ex.: Claro) aparece dividido.
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_market_share AS
WITH acessos_mes AS (
    SELECT ano_mes,
           cnpj,
           SUM(acessos) AS acessos_totais
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
       RANK() OVER (PARTITION BY am.ano_mes ORDER BY am.acessos_totais DESC)                     AS ranking
FROM acessos_mes am
JOIN dim_operadora op ON op.cnpj = am.cnpj;


-- ---------------------------------------------------------
-- 3. vw_tecnologia
-- Pergunta: quanto do mercado (INTERNET) é fibra e como cada meio de acesso evolui?
-- Grão: uma linha por mês e meio de acesso.
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_tecnologia AS
WITH acessos_mes AS (
    SELECT ano_mes,
           meio_acesso,
           SUM(acessos) AS acessos
    FROM fato_acessos
    WHERE tipo_produto = 'INTERNET'
    GROUP BY ano_mes, meio_acesso
)
SELECT ano_mes,
       meio_acesso,
       acessos,
       ROUND(acessos / SUM(acessos) OVER (PARTITION BY ano_mes) * 100, 2) AS participacao_pct,
       RANK() OVER (PARTITION BY ano_mes ORDER BY acessos DESC)           AS ranking
FROM acessos_mes;


-- ---------------------------------------------------------
-- 4. vw_operadora_destaque
-- Pergunta: como cada operadora evoluiu em relação ao seu registro anterior?
-- Grão: uma linha por mês e operadora (mesmo grão da vw_market_share).
-- View genérica: o filtro da operadora é feito no dashboard (Streamlit).
-- Obs.: o LAG pega a linha anterior que EXISTE, não o mês anterior do calendário.
--       Por isso meses_ultima_aparicao mostra a distância em meses: valores maiores
--       que 1 indicam meses sem reporte, e var_pct_anterior cobre esse intervalo todo.
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_operadora_destaque AS
WITH comparacoes AS (
    SELECT ano_mes,
           cnpj,
           empresa,
           grupo_economico,
           acessos_totais,
           participacao_pct,
           ranking,
           LAG(ano_mes)        OVER (PARTITION BY cnpj ORDER BY ano_mes) AS ultima_aparicao,
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
       TIMESTAMPDIFF(MONTH, ultima_aparicao, ano_mes)                AS meses_ultima_aparicao,
       ROUND((acessos_totais - valor_anterior) / valor_anterior * 100, 2) AS var_pct_anterior
FROM comparacoes;


-- ---------------------------------------------------------
-- 5. vw_porte_mensal
-- Pergunta: quanto do mercado (INTERNET) está com prestadoras de pequeno e grande porte?
-- Grão: uma linha por mês e porte.
-- Obs.: "Pequeno porte" é a classificação da Anatel (PPP: menos de 5% de participação
--       nacional) e inclui a Brisanet, líder do estado.
--       O porte vem da dim_operadora (SCD Tipo 1 = classificação mais recente), então
--       meses antigos usam a classificação atual de cada operadora.
--       Operadoras contadas por CNPJ.
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_porte_mensal AS
WITH acessos_mes AS (
    SELECT f.ano_mes,
           op.porte,
           SUM(f.acessos)         AS acessos,
           COUNT(DISTINCT f.cnpj) AS operadoras
    FROM fato_acessos f
    JOIN dim_operadora op ON op.cnpj = f.cnpj
    WHERE f.tipo_produto = 'INTERNET'
    GROUP BY f.ano_mes, op.porte
)
SELECT ano_mes,
       porte,
       acessos,
       operadoras,
       ROUND(acessos / SUM(acessos) OVER (PARTITION BY ano_mes) * 100, 2) AS participacao_pct
FROM acessos_mes;


-- ---------------------------------------------------------
-- 6. vw_linha_dedicada
-- Pergunta: quem lidera o mercado corporativo (linha dedicada), mês a mês?
-- Grão: uma linha por mês e operadora (CNPJ), só LINHA_DEDICADA (exceção à R1).
-- Mesma lógica da vw_market_share, com outro tipo de produto. Mantida separada de
-- propósito: se um terceiro produto for analisado, criar uma view base com o produto
-- como coluna ("regra de três").
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_linha_dedicada AS
WITH acessos_mes AS (
    SELECT ano_mes,
           cnpj,
           SUM(acessos) AS acessos_totais
    FROM fato_acessos
    WHERE tipo_produto = 'LINHA_DEDICADA'
    GROUP BY ano_mes, cnpj
)
SELECT am.ano_mes,
       am.cnpj,
       op.empresa,
       op.grupo_economico,
       am.acessos_totais,
       ROUND(am.acessos_totais / SUM(am.acessos_totais) OVER (PARTITION BY am.ano_mes) * 100, 2) AS participacao_pct,
       RANK() OVER (PARTITION BY am.ano_mes ORDER BY am.acessos_totais DESC)                     AS ranking
FROM acessos_mes am
JOIN dim_operadora op ON op.cnpj = am.cnpj;


-- =========================================================
-- BLOCO B: mês de referência e retrato atual
-- =========================================================

-- ---------------------------------------------------------
-- 7. vw_mes_referencia
-- Pergunta: qual é o último mês com dados completos?
-- Regra: o mês mais recente em que o número de operadoras com INTERNET é de pelo
--        menos 95% da média dos 3 meses anteriores. O mês mais recente da base
--        costuma vir incompleto porque parte das operadoras reporta com atraso.
-- Justificativa do limite: a validação 10.3 lista os meses barrados pela regra.
--        Com a base atual, só set/2026 é barrado (cerca de 91,6% da média).
-- Limitações: dois meses seguidos incompletos rebaixam a média de comparação, e
--        os primeiros meses da série têm menos de 3 meses anteriores na média.
-- Grão: uma única linha.
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_mes_referencia AS
WITH analise AS (
    SELECT ano_mes,
           COUNT(DISTINCT cnpj) AS operadoras
    FROM fato_acessos
    WHERE tipo_produto = 'INTERNET'
    GROUP BY ano_mes
),
calc_media AS (
    SELECT ano_mes,
           operadoras,
           AVG(operadoras) OVER (ORDER BY ano_mes
                                 ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS media_3_meses
    FROM analise
)
SELECT ano_mes                                    AS mes_referencia,
       operadoras,
       ROUND(media_3_meses, 2)                    AS media_3_meses,
       ROUND(operadoras / media_3_meses * 100, 2) AS percentual
FROM calc_media
WHERE media_3_meses IS NOT NULL
  AND operadoras >= media_3_meses * 0.95
ORDER BY ano_mes DESC
LIMIT 1;


-- ---------------------------------------------------------
-- 8. vw_municipio_resumo
-- Pergunta: como está o mercado (INTERNET) de cada município no mês de referência?
-- Grão: uma linha por município.
-- Entrega: acessos, número de operadoras, líder e sua participação, % de fibra e HHI
--          (soma dos quadrados das participações, de 0 a 10.000).
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_municipio_resumo AS
WITH mes_ref AS (
    SELECT mes_referencia AS ano_mes
    FROM vw_mes_referencia
),
operadoras_mun AS (
    SELECT f.cod_ibge,
           f.cnpj,
           SUM(f.acessos)                                                   AS acessos_operadora,
           SUM(CASE WHEN f.meio_acesso = 'Fibra' THEN f.acessos ELSE 0 END) AS acessos_fibra
    FROM fato_acessos f
    JOIN mes_ref r ON r.ano_mes = f.ano_mes
    WHERE f.tipo_produto = 'INTERNET'
    GROUP BY f.cod_ibge, f.cnpj
),
calculo AS (
    SELECT cod_ibge,
           cnpj,
           acessos_operadora,
           SUM(acessos_operadora) OVER (PARTITION BY cod_ibge) AS acessos_municipio,
           SUM(acessos_fibra)     OVER (PARTITION BY cod_ibge) AS fibra_municipio,
           COUNT(*)               OVER (PARTITION BY cod_ibge) AS operadoras,
           -- participação SEM arredondar: o HHI usa o valor exato
           acessos_operadora / SUM(acessos_operadora) OVER (PARTITION BY cod_ibge) * 100 AS participacao,
           -- desempate pelo CNPJ: o líder é sempre o mesmo em todas as execuções
           ROW_NUMBER() OVER (PARTITION BY cod_ibge
                              ORDER BY acessos_operadora DESC, cnpj) AS posicao
    FROM operadoras_mun
),
concentracao AS (
    SELECT cod_ibge,
           SUM(POWER(participacao, 2)) AS hhi
    FROM calculo
    GROUP BY cod_ibge
)
SELECT c.cod_ibge,
       m.municipio,
       c.acessos_municipio,
       c.operadoras,
       c.cnpj                                                  AS cnpj_lider,
       o.empresa                                               AS empresa_lider,
       ROUND(c.participacao, 2)                                AS participacao_lider_pct,
       ROUND(c.fibra_municipio / c.acessos_municipio * 100, 2) AS fibra_pct,
       ROUND(h.hhi, 0)                                         AS hhi
FROM calculo c
JOIN concentracao  h ON h.cod_ibge = c.cod_ibge
JOIN dim_municipio m ON m.cod_ibge = c.cod_ibge
JOIN dim_operadora o ON o.cnpj     = c.cnpj
WHERE c.posicao = 1;


-- ---------------------------------------------------------
-- 9. vw_starlink_municipio
-- Pergunta: onde a Starlink (satélite) tem mais participação, há menos fibra?
-- Grão: uma linha por município onde a Starlink tem acessos de INTERNET no mês de referência.
-- Obs.: a Starlink é identificada pelo CNPJ 40154884000153
--       (STARLINK BRAZIL SERVICOS DE INTERNET LTDA.), nunca pelo nome.
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW vw_starlink_municipio AS
WITH mes_ref AS (
    SELECT mes_referencia AS ano_mes
    FROM vw_mes_referencia
),
operadoras_mun AS (
    SELECT f.cod_ibge,
           f.cnpj,
           SUM(f.acessos)                                                   AS acessos_operadora,
           SUM(CASE WHEN f.meio_acesso = 'Fibra' THEN f.acessos ELSE 0 END) AS acessos_fibra
    FROM fato_acessos f
    JOIN mes_ref r ON r.ano_mes = f.ano_mes
    WHERE f.tipo_produto = 'INTERNET'
    GROUP BY f.cod_ibge, f.cnpj
),
totais AS (
    SELECT cod_ibge,
           cnpj,
           acessos_operadora,
           SUM(acessos_operadora) OVER (PARTITION BY cod_ibge) AS acessos_municipio,
           SUM(acessos_fibra)     OVER (PARTITION BY cod_ibge) AS fibra_municipio
    FROM operadoras_mun
)
SELECT t.cod_ibge,
       m.municipio,
       t.acessos_operadora                                     AS acessos_starlink,
       ROUND(t.acessos_operadora / t.acessos_municipio * 100, 2) AS participacao_starlink_pct,
       ROUND(t.fibra_municipio / t.acessos_municipio * 100, 2)   AS fibra_pct
FROM totais t
JOIN dim_municipio m ON m.cod_ibge = t.cod_ibge
WHERE t.cnpj = '40154884000153';
