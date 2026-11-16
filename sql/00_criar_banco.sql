-- =========================================================
-- Criação do banco banda_larga_al
-- Rodar uma única vez, antes do primeiro pipeline, com um usuário que possa
-- criar bancos (ex.: root). Depois disso, quem cria as tabelas e as views é
-- o próprio pipeline (python -m src.pipeline).
--
-- Se trocar o nome do banco aqui, troque também o DB_NAME no .env.
-- =========================================================

-- utf8mb4 guarda qualquer caractere (acentos, cedilha e emojis).
-- A collation utf8mb4_0900_ai_ci compara sem diferenciar maiúsculas e acentos,
-- então 'MACEIÓ' e 'maceio' são considerados iguais num WHERE.
CREATE DATABASE IF NOT EXISTS banda_larga_al
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
