-- =========================================================
-- 03_validacoes.sql: testes de qualidade do banco e das views
-- Não faz parte do pipeline: rodar manualmente depois de cada carga.
-- Cada teste traz o resultado ESPERADO em comentário.
--
-- Valores de referência desta versão:
--   base de jan/2021 a set/2026 (69 meses)
--   mês de referência = 2026-08-01 (set/2026 está incompleto, ver bloco 10)
-- Quando a base for atualizada, os valores mudam: rode tudo e atualize os comentários.
--
-- Convenções:
--   "nenhuma linha" = o teste lista só os problemas, então vazio é sucesso.
--   Testes de "retrato atual" usam o mês de referência, não o último mês da base.
-- =========================================================
USE banda_larga_al;


-- =========================================================
-- 0. TABELAS BASE
-- =========================================================

-- 0.1 Tamanho das tabelas
-- Esperado: dim_municipio = 102 | dim_operadora = 555 | fato_acessos = 418.489
SELECT 'dim_municipio' AS tabela, COUNT(*) AS linhas FROM dim_municipio
UNION ALL SELECT 'dim_operadora', COUNT(*) FROM dim_operadora
UNION ALL SELECT 'fato_acessos',  COUNT(*) FROM fato_acessos;

-- 0.2 Período coberto
-- Esperado: 2021-01-01 | 2026-09-01 | 69 meses
SELECT MIN(ano_mes)            AS primeiro_mes,
       MAX(ano_mes)            AS ultimo_mes,
       COUNT(DISTINCT ano_mes) AS meses
FROM fato_acessos;

-- 0.3 Reconciliação com a exploração (notebook): todos os produtos, último mês da base
-- Esperado: 387.165
SELECT SUM(acessos) AS total_ultimo_mes
FROM fato_acessos
WHERE ano_mes = (SELECT MAX(ano_mes) FROM fato_acessos);

-- 0.4 Integridade referencial: linhas da fato sem operadora ou sem município
-- Esperado: 0 | 0 (garantido pelas chaves estrangeiras)
SELECT
    (SELECT COUNT(*) FROM fato_acessos f
     LEFT JOIN dim_operadora o ON o.cnpj = f.cnpj
     WHERE o.cnpj IS NULL)       AS sem_operadora,
    (SELECT COUNT(*) FROM fato_acessos f
     LEFT JOIN dim_municipio m ON m.cod_ibge = f.cod_ibge
     WHERE m.cod_ibge IS NULL)   AS sem_municipio;

-- 0.5 Acessos negativos ou vazios (o transform descarta, então não pode haver)
-- Esperado: 0
SELECT COUNT(*) AS linhas_invalidas
FROM fato_acessos
WHERE acessos IS NULL OR acessos < 0;


-- =========================================================
-- 1. vw_evolucao_mensal
-- =========================================================

-- 1.1 Uma linha por mês
-- Esperado: 69
SELECT COUNT(*) AS meses FROM vw_evolucao_mensal;

-- 1.2 Comparações sem mês anterior são nulas, nunca zero
-- Esperado: 1 nulo na variação mensal | 12 nulos na variação de 12 meses
SELECT SUM(var_pct_mensal IS NULL) AS nulos_mensal,
       SUM(var_pct_12m IS NULL)    AS nulos_12m
FROM vw_evolucao_mensal;

-- 1.3 Total de INTERNET no mês de referência
-- Esperado: 2026-08-01 | 430.365 | 20,46
SELECT ev.ano_mes, ev.total_acessos, ev.var_pct_12m
FROM vw_evolucao_mensal ev
JOIN vw_mes_referencia r ON r.mes_referencia = ev.ano_mes;


-- =========================================================
-- 2. vw_market_share
-- =========================================================

-- 2.1 Prova dos 100%: soma das participações em cada mês
-- Esperado: 69 meses, valores muito próximos de 100 (arredondamento de centenas de operadoras)
SELECT MIN(soma) AS menor_soma,
       MAX(soma) AS maior_soma,
       COUNT(*)  AS meses
FROM (
    SELECT ano_mes, SUM(participacao_pct) AS soma
    FROM vw_market_share
    GROUP BY ano_mes
) AS somas_mensais;

-- 2.2 Reconciliação com o total do estado
-- Esperado: nenhuma linha
SELECT ms.ano_mes,
       SUM(ms.acessos_totais) AS soma_operadoras,
       ev.total_acessos
FROM vw_market_share ms
JOIN vw_evolucao_mensal ev ON ev.ano_mes = ms.ano_mes
GROUP BY ms.ano_mes, ev.total_acessos
HAVING soma_operadoras <> ev.total_acessos;

-- 2.3 Top 3 no mês de referência (por CNPJ)
-- Esperado: BRISANET(26,25%) em 1º, CLARO em 2º (19,49%)
-- Obs.: no Power BI o top 10 agrupa por nome, então Brisanet e Claro aparecem com
--       os CNPJs somados (27,17% e 19,76%). Aqui cada CNPJ é uma linha.
SELECT ms.ranking, ms.empresa, ms.cnpj, ms.acessos_totais, ms.participacao_pct
FROM vw_market_share ms
JOIN vw_mes_referencia r ON r.mes_referencia = ms.ano_mes
WHERE ms.ranking <= 3
ORDER BY ms.ranking;

-- 2.4 Empresas com mais de um CNPJ no mês de referência
-- Esperado: lista com BRISANET e CLARO, entre outras
SELECT ms.empresa, COUNT(*) AS cnpjs, SUM(ms.participacao_pct) AS participacao_somada
FROM vw_market_share ms
JOIN vw_mes_referencia r ON r.mes_referencia = ms.ano_mes
GROUP BY ms.empresa
HAVING COUNT(*) > 1
ORDER BY participacao_somada DESC;


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
       SUM(t.acessos) AS soma_meios,
       ev.total_acessos
FROM vw_tecnologia t
JOIN vw_evolucao_mensal ev ON ev.ano_mes = t.ano_mes
GROUP BY t.ano_mes, ev.total_acessos
HAVING soma_meios <> ev.total_acessos;

-- 3.4 KPI da fibra: primeiro mês da série e mês de referência
-- Esperado: 2021-01-01 | 24,68 e 2026-08-01 | 83,90
SELECT t.ano_mes, t.participacao_pct AS fibra_pct
FROM vw_tecnologia t
WHERE t.meio_acesso = 'Fibra'
  AND t.ano_mes IN ((SELECT MIN(ano_mes) FROM vw_tecnologia),
                    (SELECT mes_referencia FROM vw_mes_referencia))
ORDER BY t.ano_mes;


-- =========================================================
-- 4. vw_operadora_destaque
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
-- Esperado: lista não vazia, com um intervalo de 40 e poucos meses entre os primeiros
SELECT empresa,
       cnpj,
       ano_mes,
       meses_ultima_aparicao
FROM vw_operadora_destaque
WHERE meses_ultima_aparicao > 1
ORDER BY meses_ultima_aparicao DESC
LIMIT 10;

-- 4.4 O primeiro registro de cada operadora não tem anterior
-- Esperado: nenhuma linha (distância e variação nulas no primeiro mês de cada CNPJ)
SELECT od.cnpj, od.ano_mes, od.meses_ultima_aparicao, od.var_pct_anterior
FROM vw_operadora_destaque od
JOIN (SELECT cnpj, MIN(ano_mes) AS primeiro FROM vw_market_share GROUP BY cnpj) p
     ON p.cnpj = od.cnpj AND p.primeiro = od.ano_mes
WHERE od.meses_ultima_aparicao IS NOT NULL OR od.var_pct_anterior IS NOT NULL;


-- =========================================================
-- 5. vw_municipio_resumo (mês de referência)
-- =========================================================

-- 5.1 Todos os municípios e reconciliação com o total do estado
-- Esperado: 102 municípios | 430.365 acessos
SELECT COUNT(*)               AS municipios,
       SUM(acessos_municipio) AS total_estado
FROM vw_municipio_resumo;

-- 5.2 HHI máximo (10.000) só onde há uma única operadora
-- Esperado: nenhuma linha (nenhum município com operadora única em ago/2026)
--           Se aparecer alguma, ela precisa ter operadoras = 1 e hhi = 10000 ao mesmo tempo.
SELECT municipio, operadoras, hhi
FROM vw_municipio_resumo
WHERE hhi = 10000 OR operadoras = 1;

-- 5.3 Os 10 mercados mais competitivos (menor HHI)
-- Esperado: Arapiraca em primeiro
SELECT municipio, operadoras, hhi, empresa_lider, participacao_lider_pct
FROM vw_municipio_resumo
ORDER BY hhi
LIMIT 10;

-- 5.4 Maceió: muitas operadoras, mercado concentrado
-- Esperado: 221.538 acessos | 137 operadoras | BRISANET | 35,62 | 74,71 | HHI 2622
SELECT municipio, acessos_municipio, operadoras, empresa_lider,
       participacao_lider_pct, fibra_pct, hhi,
       ROUND(10000 / hhi, 2) AS concorrentes_equivalentes
FROM vw_municipio_resumo
WHERE municipio = 'Maceió';


-- =========================================================
-- 6. vw_starlink_municipio (mês de referência)
-- =========================================================

-- 6.1 Municípios com Starlink
-- Esperado: 98 (de 102)
SELECT COUNT(*) AS municipios_com_starlink
FROM vw_starlink_municipio;

-- 6.2 Municípios SEM Starlink
-- Esperado: 4 municípios
SELECT m.municipio
FROM dim_municipio m
LEFT JOIN vw_starlink_municipio s ON s.cod_ibge = m.cod_ibge
WHERE s.cod_ibge IS NULL
ORDER BY m.municipio;

-- 6.3 Teste da hipótese: Starlink x fibra por quartil
-- Esperado (quartil | municípios | Starlink média | fibra média):
--   1 | 25 | 14,62 | 68,56
--   2 | 25 |  1,58 | 92,73
--   3 | 24 |  0,57 | 91,42
--   4 | 24 |  0,30 | 90,53
-- Obs.: com set/2026 (incompleto) o quartil 1 dava 19,83 | 54,87: o mês incompleto exagerava o efeito.
WITH ranqueado AS (
    SELECT participacao_starlink_pct,
           fibra_pct,
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
-- 7. QUALIDADE DO REPORTE
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


-- =========================================================
-- 8. vw_porte_mensal
-- =========================================================

-- 8.1 Uma linha por mês e porte
-- Esperado: 138 linhas | 69 meses | 2 portes
SELECT COUNT(*)                AS linhas,
       COUNT(DISTINCT ano_mes) AS meses,
       COUNT(DISTINCT porte)   AS portes
FROM vw_porte_mensal;

-- 8.2 Prova dos 100%
-- Esperado: 69 meses, valores muito próximos de 100
SELECT MIN(soma) AS menor_soma, MAX(soma) AS maior_soma, COUNT(*) AS meses
FROM (
    SELECT ano_mes, SUM(participacao_pct) AS soma
    FROM vw_porte_mensal
    GROUP BY ano_mes
) AS somas_mensais;

-- 8.3 Reconciliação com o total do estado
-- Esperado: nenhuma linha
SELECT p.ano_mes, SUM(p.acessos) AS soma_portes, ev.total_acessos
FROM vw_porte_mensal p
JOIN vw_evolucao_mensal ev ON ev.ano_mes = p.ano_mes
GROUP BY p.ano_mes, ev.total_acessos
HAVING soma_portes <> ev.total_acessos;

-- 8.4 Porte da Brisanet (PPP, mesmo liderando o estado)
-- Esperado: todos os CNPJs do grupo BRISANET como "Pequeno Porte"
SELECT cnpj, empresa, grupo_economico, porte
FROM dim_operadora
WHERE grupo_economico = 'BRISANET';


-- =========================================================
-- 9. vw_linha_dedicada
-- =========================================================

-- 9.1 Prova dos 100%
-- Esperado: valores muito próximos de 100 em todos os meses
SELECT MIN(soma) AS menor_soma, MAX(soma) AS maior_soma, COUNT(*) AS meses
FROM (
    SELECT ano_mes, SUM(participacao_pct) AS soma
    FROM vw_linha_dedicada
    GROUP BY ano_mes
) AS somas_mensais;

-- 9.2 Reconciliação com a fato (só LINHA_DEDICADA)
-- Esperado: nenhuma linha
SELECT ld.ano_mes, SUM(ld.acessos_totais) AS soma_view, f.total_fato
FROM vw_linha_dedicada ld
JOIN (
    SELECT ano_mes, SUM(acessos) AS total_fato
    FROM fato_acessos
    WHERE tipo_produto = 'LINHA_DEDICADA'
    GROUP BY ano_mes
) f ON f.ano_mes = ld.ano_mes
GROUP BY ld.ano_mes, f.total_fato
HAVING soma_view <> f.total_fato;

-- 9.3 Top 3 e número de operadoras no mês de referência
-- Esperado: 1º Claro (46,36%), 2º OI (38,71%), 3º Cirion Technologies (7,48%)
SELECT ld.ranking, ld.empresa, ld.acessos_totais, ld.participacao_pct,
       COUNT(*) OVER () AS operadoras_no_mes
FROM vw_linha_dedicada ld
JOIN vw_mes_referencia r ON r.mes_referencia = ld.ano_mes
ORDER BY ld.ranking
LIMIT 3;


-- =========================================================
-- 10. vw_mes_referencia
-- =========================================================

-- 10.1 Uma única linha
-- Esperado: 1
SELECT COUNT(*) AS linhas FROM vw_mes_referencia;

-- 10.2 O mês escolhido
-- Esperado: 2026-08-01 | 320 operadoras (enquanto a base terminar em set/2026)
SELECT mes_referencia, operadoras, media_3_meses, percentual
FROM vw_mes_referencia;

-- 10.3 Meses barrados pela regra dos 95%
-- Esperado: só 2026-09-01, com cerca de 91,6% e 2022-05-01 com 67,2%

WITH analise AS (
    SELECT ano_mes, COUNT(DISTINCT cnpj) AS operadoras
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
SELECT ano_mes,
       operadoras,
       ROUND(media_3_meses, 2)                    AS media_3_meses,
       ROUND(operadoras / media_3_meses * 100, 2) AS percentual
FROM calc_media
WHERE media_3_meses IS NOT NULL
  AND operadoras < media_3_meses * 0.95;

-- 10.4 Os 5 meses de menor cobertura (justifica o limite de 95%)
-- Esperado: mai/2025 em primeiro e set/2026 em segundo, os demais acima de 95%
WITH analise AS (
    SELECT ano_mes, COUNT(DISTINCT cnpj) AS operadoras
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
SELECT ano_mes,
       operadoras,
       ROUND(operadoras / media_3_meses * 100, 2) AS percentual
FROM calc_media
WHERE media_3_meses IS NOT NULL
ORDER BY percentual
LIMIT 5;

-- 10.5 As views de município usam o mês de referência
-- Esperado: 2026-08-01 | 430.365 | 430.365
SELECT r.mes_referencia,
       ev.total_acessos,
       (SELECT SUM(acessos_municipio) FROM vw_municipio_resumo) AS soma_municipios
FROM vw_mes_referencia r
JOIN vw_evolucao_mensal ev ON ev.ano_mes = r.mes_referencia;

-- 10.6 O mês incompleto, documentado
-- Esperado: 2026-09-01 | 382.217 acessos | 295 operadoras
SELECT ms.ano_mes,
       SUM(ms.acessos_totais) AS acessos,
       COUNT(*)               AS operadoras
FROM vw_market_share ms
WHERE ms.ano_mes = (SELECT MAX(ano_mes) FROM vw_market_share)
GROUP BY ms.ano_mes;
m_dados,
       TIMESTAMPDIFF(MONTH, MIN(ano_mes), MAX(ano_mes)) + 1 AS meses_no_intervalo
FROM vw_market_share
GROUP BY cnpj, empresa
HAVING meses_com_dados < meses_no_intervalo
ORDER BY meses_no_intervalo - meses_com_dados DESC
LIMIT 10;