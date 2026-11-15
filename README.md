# secops-backend
Uma api desenvolvida em interfaces de backend/front end e bancos de dados do MYSQL que é voltada ao sistema de triagem envolvendo conceitos da segurança da informação.

Sobre o projeto: 
O SecOps propõe uma solução ideal para o gerenciamento, triagem e auditoria para incidentes relacionados à segurança de rede. Feito por ferramentas backend como python e suas bibliotecas, o projeto visa o uso de views, Triggers e funções customizadas que geram ids. Dispensando o uso total do usuário root.

Como executar o projeto:
Faça o uso do MySQL workbench para fazer a criação do banco de dados secops_db, todas as tabelas e dados do banco estão em um arquivo redirecionado no repositório.

Abra os arquivos database.py e main.py para configurar o serviço de backend do projeto

Instale as dependências necessárias 

Execute o comando: pip install fastapi unicorn mysql-connector-python pydantic 

E por último executar a aplicação com uvicorn 

Uvicorn main:app --reload
