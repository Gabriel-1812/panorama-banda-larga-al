# Dicionário de dados — Acessos Banda Larga Fixa (Anatel)

**Fonte:** https://www.anatel.gov.br/dadosabertos/paineis_de_dados/acessos/acessos_banda_larga_fixa.zip
**Formato:** CSV, separador `;`, encoding UTF-8 (com BOM), decimal com vírgula
**Arquivos:** um por ano a partir de 2021 (`Acessos_Banda_Larga_Fixa_AAAA.csv`); antes de 2021, agrupados em biênios
**Recorte do projeto:** UF = AL, de jan/2021 a set/2026

| Coluna | Tipo | Descrição | Exemplo |
| --- | --- | --- | --- |
| Ano | inteiro | Ano de referência | 2026 |
| Mês | inteiro | Mês de referência | 9 |
| Grupo Econômico | texto | Grupo controlador; "OUTROS" para pequenos provedores | TELEFONICA |
| Empresa | texto | Nome da prestadora | VIVO |
| CNPJ | texto (14) | CNPJ da prestadora, ler como texto (zeros à esquerda) | 02558157000162 |
| Porte da Prestadora | texto | Pequeno Porte ou Grande Porte | Pequeno Porte |
| UF | texto (2) | Estado | AL |
| Município | texto | Nome do município | Maceió |
| Código IBGE Município | texto (7) | Código IBGE, ler como texto | 2704302 |
| Faixa de Velocidade | texto | Faixa da velocidade contratada | > 34Mbps |
| Velocidade | decimal | Velocidade contratada em Mbps (vírgula decimal) | 600,000000 |
| Tecnologia | texto | Tecnologia de acesso | FTTH |
| Meio de Acesso | texto | Meio físico | Fibra |
| Tipo de Pessoa | texto | Pessoa Física ou Jurídica | Pessoa Física |
| Tipo de Produto | texto | INTERNET, LINHA_DEDICADA, M2M, OUTROS | INTERNET |
| Acessos | inteiro | Acessos em serviço no mês | 18 |

## Regras e cuidados
- **`Acessos` é um estoque mensal: nunca somar entre meses diferentes.**
- Antes de 2021 a base tem 13 colunas e outra metodologia; o projeto começa em 2021.
- Algumas prestadoras reportam de forma intermitente (aparecem em alguns meses e somem em outros).
- O zip também traz `Densidade_Banda_Larga_Fixa.csv` (acessos por 100 habitantes, por município).