-- =========================================================
-- Esquema do banco banda_larga_al (esquema estrela)
-- Recria as tabelas do zero: o pipeline recarrega tudo a cada execução.
-- Executar conectado ao banco definido em DB_NAME (.env). O pipeline já conecta
-- nele. No Navicat, selecione o banco antes de rodar o script.
-- =========================================================

-- A fato sai primeiro, porque depende das dimensões (chaves estrangeiras)
DROP TABLE IF EXISTS fato_acessos;
DROP TABLE IF EXISTS dim_operadora;
DROP TABLE IF EXISTS dim_municipio;

CREATE TABLE dim_municipio (
    cod_ibge   CHAR(7)       NOT NULL,
    municipio  VARCHAR(100)  NOT NULL,
    uf         CHAR(2)       NOT NULL,
    PRIMARY KEY (cod_ibge)
);

CREATE TABLE dim_operadora (
    cnpj             CHAR(14)      NOT NULL,
    empresa          VARCHAR(200)  NOT NULL,
    grupo_economico  VARCHAR(200)  NOT NULL,
    porte            VARCHAR(20)   NOT NULL,
    PRIMARY KEY (cnpj)
);

CREATE TABLE fato_acessos (
    id                BIGINT         NOT NULL AUTO_INCREMENT,
    ano_mes           DATE           NOT NULL,   -- sempre o dia 1 do mês
    cod_ibge          CHAR(7)        NOT NULL,
    cnpj              CHAR(14)       NOT NULL,
    faixa_velocidade  VARCHAR(30),
    velocidade_mbps   DECIMAL(12,3),
    tecnologia        VARCHAR(50),
    meio_acesso       VARCHAR(50),
    tipo_pessoa       VARCHAR(30),
    tipo_produto      VARCHAR(30),
    acessos           INT            NOT NULL,
    PRIMARY KEY (id),
    KEY idx_mes            (ano_mes),
    KEY idx_operadora_mes  (cnpj, ano_mes),
    KEY idx_municipio_mes  (cod_ibge, ano_mes),
    CONSTRAINT fk_fato_municipio FOREIGN KEY (cod_ibge) REFERENCES dim_municipio (cod_ibge),
    CONSTRAINT fk_fato_operadora FOREIGN KEY (cnpj)     REFERENCES dim_operadora (cnpj)
);