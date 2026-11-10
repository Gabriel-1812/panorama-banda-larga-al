-- =========================================================
-- 03_validacoes.sql — testes de qualidade do banco e das views
-- Não faz parte do pipeline: rodar manualmente após cada carga.
-- Cada bloco traz o resultado ESPERADO em comentário.
-- Valores de referência: carga com dados de jan/2021 a set/2026.
-- =========================================================
USE banda_larga_al;

-- =========================================================
-- 0. TABELAS BASE
-- =========================================================

-- 0.1 Tamanho das tabelas
-- Esperado: dim_municipio = 102 | dim_operadora = 555 e fato_acessos = 418489 com linhas
SELECT 'dim_municipio' AS tabela, COUNT(*) AS linhas FROM dim_municipio
UNION ALL SELECT 'dim_operadora', COUNT(*) FROM dim_operadora
UNION ALL SELECT 'fato_acessos', COUNT(*) FROM fato_acessos;

-- 0.2 Período coberto
-- Esperado: 2021-01-01 | 2026-09-01 | 69 meses
SELECT MIN(ano_mes)            AS primeiro_mes,
       MAX(ano_mes)            AS ultimo_mes,
       COUNT(DISTINCT ano_mes) AS meses
FROM fato_acessos;

-- 0.3 Reconciliação com a exploração (todos os produtos, último mês 2026-09-01)
-- Esperado: 387.165
SELECT SUM(acessos) AS total_ultimo_mes
FROM fato_acessos
WHERE ano_mes = (SELECT MAX(ano_mes) FROM fato_acessos);

-- 0.4 Integridade referencial: linhas da fato sem operadora ou município
-- Esperado: 0 e 0 (garantido pelas chaves estrangeiras)
SELECT
    (SELECT COUNT(*) FROM fato_acessos f
     LEFT JOIN dim_operadora o ON o.cnpj = f.cnpj
     WHERE o.cnpj IS NULL)                         AS sem_operadora,
    (SELECT COUNT(*) FROM fato_acessos f
     LEFT JOIN dim_municipio m ON m.cod_ibge = f.cod_ibge
     WHERE m.cod_ibge IS NULL)                     AS sem_municipio;


-- =========================================================
-- 1. vw_evolucao_mensal
-- =========================================================

-- 1.1 Uma linha por mês
-- Esperado: 69
SELECT COUNT(*) AS meses FROM vw_evolucao_mensal;

-- 1.2 Comparações sem mês anterior devem ser nulas, nunca zero
-- Esperado: 1 nulo na variação mensal e 12 nulos na variação de 12 meses
SELECT SUM(var_pct_mensal IS NULL) AS nulos_mensal,
       SUM(var_pct_12m IS NULL)    AS nulos_12m
FROM vw_evolucao_mensal;

-- 1.3 Total de INTERNET no último mês
-- Esperado: 382.217 acessos e 1,19% na variação de 12 meses
SELECT ano_mes, total_acessos, var_pct_12m
FROM vw_evolucao_mensal
WHERE ano_mes = (SELECT MAX(ano_mes) FROM vw_evolucao_mensal);


-- =========================================================
-- 2. vw_market_share
-- =========================================================

-- 2.1 Prova dos 100%: soma das participações em cada mês
-- Esperado: 69 meses, valores muito próximos de 100 (arredondamento)
SELECT MIN(soma) AS menor_soma,
       MAX(soma) AS maior_soma,
       COUNT(*)  AS meses
FROM (
    SELECT ano_mes, SUM(participacao_pct) AS soma
    FROM vw_market_share
    GROUP BY ano_mes
) AS somas_mensais;

-- 2.2 Reconciliação com o total do estado
-- Esperado: nenhuma linha (as duas views contam a mesma história)
SELECT ms.ano_mes,
       SUM(ms.acessos_totais) AS soma_operadoras,
       ev.total_acessos
FROM vw_market_share ms
JOIN vw_evolucao_mensal ev ON ev.ano_mes = ms.ano_mes
GROUP BY ms.ano_mes, ev.total_acessos
HAVING soma_operadoras <> ev.total_acessos;

-- 2.3 Top 3 do último mês
-- Esperado: BRISANET 29,53% | CLARO 22,07% | VIVO 5,63%
SELECT ranking, empresa, acessos_totais, participacao_pct
FROM vw_market_share
WHERE ano_mes = (SELECT MAX(ano_mes) FROM vw_market_share)
  AND ranking <= 3
ORDER BY ranking;


-- =========================================================
-- 3. vw_tecnologia
-- =========================================================

-- 3.1 Categorias de meio de acesso
-- Esperado: 6 categorias (5 meios físicos + Indeterminado), nenhuma nula
SELECT DISTINCT meio_acesso
FROM vw_tecnologia
ORDER BY meio_acesso;

-- 3.2 Prova dos 100%
-- Esperado: 69 meses, entre 99,99 e 100,02
SELECT MIN(soma) AS menor_soma,
       MAX(soma) AS maior_soma,
       COUNT(*)  AS meses
FROM (
    SELECT ano_mes, SUM(participacao_pct) AS soma
    FROM vw_tecnologia
    GROUP BY ano_mes
) AS somas_mensais;

-- 3.3 Reconciliação com o total do estado
-- Esperado: nenhuma linha
SELECT t.ano_mes,
       SUM(t.acessos)   AS soma_meios,
       ev.total_acessos
FROM vw_tecnologia t
JOIN vw_evolucao_mensal ev ON ev.ano_mes = t.ano_mes
GROUP BY t.ano_mes, ev.total_acessos
HAVING soma_meios <> ev.total_acessos;

-- 3.4 KPI da fibra: primeiro e último mês
-- Esperado: 24,68% em 2021-01 | 82,35% em 2026-09
SELECT ano_mes, participacao_pct AS fibra_pct
FROM vw_tecnologia
WHERE meio_acesso = 'Fibra'
  AND ano_mes IN ((SELECT MIN(ano_mes) FROM vw_tecnologia),
                  (SELECT MAX(ano_mes) FROM vw_tecnologia))
ORDER BY ano_mes;


-- =========================================================
-- 4. vw_operadora_destaque
-- Obs.: se você renomeou a coluna de distância (ex.: meses_desde_anterior),
--       ajuste o nome nas consultas abaixo.
-- =========================================================

-- 4.1 Mesmo grão da vw_market_share
-- Esperado: 1 (verdadeiro)
SELECT (SELECT COUNT(*) FROM vw_operadora_destaque)
     = (SELECT COUNT(*) FROM vw_market_share) AS mesma_quantidade_de_linhas;

-- 4.2 Operadora estável: os dois CNPJs da Claro
-- Esperado: 2 CNPJs, com 69 e 63 meses, maior distância = 1 (sem buracos)
SELECT cnpj,
       empresa,
       COUNT(*)                   AS meses,
       MAX(meses_ultima_aparicao) AS maior_distancia
FROM vw_operadora_destaque
WHERE empresa LIKE 'CLARO%'
GROUP BY cnpj, empresa;

-- 4.3 Buracos de reporte: os maiores intervalos entre dois registros
-- Esperado: lista não vazia, com o caso de 40 e poucos meses entre os primeiros
SELECT empresa,
       cnpj,
       ano_mes,
       meses_ultima_aparicao
FROM vw_operadora_destaque
WHERE meses_ultima_aparicao > 1
ORDER BY meses_ultima_aparicao DESC
LIMIT 10;


-- =========================================================
-- 5. vw_municipio_resumo
-- =========================================================

-- 5.1 Todos os municípios e reconciliação com o total do estado
-- Esperado: 102 municípios | 430.365 acessos
SELECT COUNT(*)               AS municipios,
       SUM(acessos_municipio) AS total_estado
FROM vw_municipio_resumo;

-- 5.2 HHI máximo (10.000) só onde há uma única operadora
-- Esperado: vazio (nenhum município com operadora única em ago/2026),
-- ou linhas com operadoras = 1 e hhi = 10000 ao mesmo tempo
SELECT municipio, operadoras, hhi
FROM vw_municipio_resumo
WHERE hhi = 10000 OR operadoras = 1;

-- 5.3 Os 10 mercados mais competitivos (menor HHI)
-- Esperado: Arapiraca em primeiro
SELECT municipio, operadoras, hhi, empresa_lider, participacao_lider_pct
FROM vw_municipio_resumo
ORDER BY hhi
LIMIT 10;


-- =========================================================
-- 6. vw_starlink_municipio
-- =========================================================

-- 6.1 Municípios com Starlink no último mês
-- Esperado: 98 (de 102)
SELECT COUNT(*) AS municipios_com_starlink
FROM vw_starlink_municipio;

-- 6.2 Municípios SEM Starlink
-- Esperado: 4
SELECT m.municipio
FROM dim_municipio m
LEFT JOIN vw_starlink_municipio s ON s.cod_ibge = m.cod_ibge
WHERE s.cod_ibge IS NULL
ORDER BY m.municipio;

-- 6.3 Teste da hipótese: Starlink x fibra por quartil
-- Esperado: quartil 1 com Starlink ~14,62% e fibra ~68,56%
--           quartis 2 a 4 com Starlink abaixo de 1% e fibra acima de 90%
WITH ranqueado AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY participacao_starlink_pct DESC) AS quartil
    FROM vw_starlink_municipio
)
SELECT quartil,
       COUNT(*)                                 AS municipios,
       ROUND(AVG(participacao_starlink_pct), 2) AS starlink_media_pct,
       ROUND(AVG(fibra_pct), 2)                 AS fibra_media_pct
FROM ranqueado
GROUP BY quartil
ORDER BY quartil;


-- =========================================================
-- 7. QUALIDADE DO REPORTE (prévia do Card 9)
-- =========================================================

-- 7.1 Operadoras com meses faltando entre o primeiro e o último registro
-- Esperado: lista não vazia (reporte intermitente / subnotificação)
SELECT empresa,
       MIN(ano_mes) AS primeiro_mes,
       MAX(ano_mes) AS ultimo_mes,
       COUNT(*)     AS meses_com_dados,
       TIMESTAMPDIFF(MONTH, MIN(ano_mes), MAX(ano_mes)) + 1 AS meses_no_intervalo
FROM vw_market_share
GROUP BY cnpj, empresa
HAVING meses_com_dados < meses_no_intervalo
ORDER BY meses_no_intervalo - meses_com_dados DESC
LIMIT 10;