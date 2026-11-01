# Conexão com o MySQL, credenciais do .env

import os

from dotenv import load_dotenv 
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()

def get_engine():
    # Retorna um engine do SQLAlchemy conectado ao banco

    url = URL.create(
        drivername = "mysql+pymysql",
        username = os.getenv("DB_USER"),
        password = os.getenv("DB_PASSWORD"),
        host = os.getenv("DB_HOST"),
        port = int(os.getenv("DB_PORT", 3306)),
        database = os.getenv("DB_NAME"),
        query ={ "charset": "utf8mb4"}
    )
    return create_engine(url)

if __name__ == "__main__":
    with get_engine().connect() as conn:
        versao = conn.execute(text("SELECT VERSION()")).scalar()
        print(f"Conectado ao MySQL {versao}")