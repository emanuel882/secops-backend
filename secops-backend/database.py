import mysql.connector
from mysql.connector import Error

DB_CONFIG = {
    'host': 'localhost',
    'database': 'secops_db',
    'user': 'secops_app',
    'password': '35986585613!alf',
    'auth_plugin': 'mysql_native_password'
}

def conexao():
    try:
        connection = mysql.connector.connect(**DB_CONFIG)
        return connection
    except Error as e:
        print(f"[Erro de Conexão MySQL]: {e}")
        raise e