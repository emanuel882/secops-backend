from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel
from database import conexao
import mysql.connector

app = FastAPI(
    title="SecOps Control API",
    description="API de Gestão de Incidentes integrada ao MySQL com controle transacional e restrições de acesso.",
    version="1.0.0"
)


# Modelos Pydantic para validação de entrada
class IncidenteCreate(BaseModel):
    id_ativo: str
    titulo: str
    descricao: str
    severidade: str  # BAIXA, MEDIA, ALTA, CRITICA


@app.get("/")
def read_root():
    return {"status": "online", "message": "API SecOps Control operando com usuário restrito."}



@app.get("/incidentes", tags=["Incidentes"])
def listar_incidentes():
    """Consulta dados utilizando a View vw_resumo_incidentes."""
    conn = conexao()
    if not conn:
        raise HTTPException(status_code=500, detail="Erro de conexão com o banco de dados.")

    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM vw_resumo_incidentes ORDER BY criado_em DESC;")
        resultado = cursor.fetchall()
        return {"total": len(resultado), "incidentes": resultado}
    except mysql.connector.Error as err:
        raise HTTPException(status_code=500, detail=f"Erro ao consultar view: {err}")
    finally:
        cursor.close()
        conn.close()



@app.post("/incidentes", status_code=status.HTTP_201_CREATED, tags=["Incidentes"])
def criar_incidente(incidente: IncidenteCreate):
    """
    Cadastra um incidente chamando a Stored Procedure sp_cadastrar_incidente
    e aplicando controle de transação (COMMIT / ROLLBACK).
    """
    conn = conexao()
    if not conn:
        raise HTTPException(status_code=500, detail="Erro de conexão com o banco de dados.")

    cursor = conn.cursor()
    try:
        # Inicia explicitamente a transação (TCL)
        conn.start_transaction()

        # Parâmetros para a Stored Procedure (IN: id_ativo, titulo, descricao, severidade | OUT: p_id_gerado)
        args = (incidente.id_ativo, incidente.titulo, incidente.descricao, incidente.severidade, '')

        # Chamada da Stored Procedure
        result_cursor = cursor.callproc('sp_cadastrar_incidente', args)

        # Recupera o parâmetro OUT gerado pela procedure (o ID customizado)
        id_gerado = result_cursor[4]

        # Confirma a transação (Commit)
        conn.commit()

        return {
            "mensagem": "Incidente cadastrado com sucesso via Stored Procedure!",
            "id_incidente": id_gerado,
            "dados": incidente
        }

    except mysql.connector.Error as err:
        # Em caso de erro, desfaz a transação (Rollback) conforme exigido pela regra acadêmica
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Erro na transação (Rollback executado): {err}")
    finally:
        cursor.close()
        conn.close()