-- =====================================================================
-- 1. CONFIGURAÇÃO INICIAL E CRIAÇÃO DO BANCO DE DADOS
-- =====================================================================
DROP DATABASE IF EXISTS secops_db;
CREATE DATABASE secops_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE secops_db;

-- =====================================================================
-- 2. FUNÇÃO CUSTOMIZADA PARA GERAÇÃO DE IDs (Substituindo AUTO_INCREMENT)
-- Justificativa: Garante rastreabilidade semântica, evita vazamento de volume 
-- de dados (IDs sequenciais previsíveis) e atende à regra de negócio de dados críticos.
-- =====================================================================
DELIMITER $$
CREATE FUNCTION fn_gerar_id(p_prefixo VARCHAR(5)) 
RETURNS VARCHAR(36)
DETERMINISTIC
BEGIN
    DECLARE v_seq INT;
    DECLARE v_novo_id VARCHAR(36);
    
    -- Tabela temporária ou controle de sequência baseada em timestamp + hash/uuid curto
    -- Para robustez acadêmica, utilizamos um UUID v4 truncado combinado com o prefixo.
    SET v_novo_id = CONCAT(p_prefixo, '-', UPPER(SUBSTRING(UUID(), 1, 8)));
    
    RETURN v_novo_id;
END$$
DELIMITER ;

-- =====================================================================
-- 3. CRIAÇÃO DAS TABELAS OBRIGATÓRIAS E RELACIONADAS
-- =====================================================================

-- Tabela 1: grupos_usuarios (Obrigatória)
CREATE TABLE grupos_usuarios (
    id_grupo VARCHAR(36) NOT NULL,
    nome_grupo VARCHAR(50) NOT NULL UNIQUE,
    descricao VARCHAR(255),
    nivel_permissao INT NOT NULL, -- 1: Viewer, 5: Analyst, 10: Admin
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_grupo)
) ENGINE=InnoDB;

-- Tabela 2: usuarios (Obrigatória)
CREATE TABLE usuarios (
    id_usuario VARCHAR(36) NOT NULL,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    senha_hash VARCHAR(255) NOT NULL,
    id_grupo VARCHAR(36) NOT NULL,
    ativo BOOLEAN DEFAULT TRUE,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_usuario),
    CONSTRAINT fk_usuario_grupo FOREIGN KEY (id_grupo) 
        REFERENCES grupos_usuarios(id_grupo) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Tabela 3: ativos_rede
CREATE TABLE ativos_rede (
    id_ativo VARCHAR(36) NOT NULL,
    hostname VARCHAR(100) NOT NULL,
    endereco_ip VARCHAR(45) NOT NULL UNIQUE,
    sistema_operacional VARCHAR(100),
    criticidade ENUM('BAIXA', 'MEDIA', 'ALTA', 'CRITICA') DEFAULT 'MEDIA',
    PRIMARY KEY (id_ativo)
) ENGINE=InnoDB;

-- Tabela 4: incidentes
CREATE TABLE incidentes (
    id_incidente VARCHAR(36) NOT NULL,
    id_ativo VARCHAR(36) NOT NULL,
    id_responsavel VARCHAR(36) NULL,
    titulo VARCHAR(150) NOT NULL,
    descricao TEXT,
    severidade ENUM('BAIXA', 'MEDIA', 'ALTA', 'CRITICA') NOT NULL,
    status VARCHAR(30) DEFAULT 'ABERTO', -- ABERTO, EM_ANALISE, RESOLVIDO
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id_incidente),
    CONSTRAINT fk_incidente_ativo FOREIGN KEY (id_ativo) 
        REFERENCES ativos_rede(id_ativo) ON DELETE CASCADE,
    CONSTRAINT fk_incidente_usuario FOREIGN KEY (id_responsavel) 
        REFERENCES usuarios(id_usuario) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Tabela 5: logs_auditoria (Para suporte a Triggers)
CREATE TABLE logs_auditoria (
    id_log VARCHAR(36) NOT NULL,
    tabela_afetada VARCHAR(50) NOT NULL,
    operacao VARCHAR(20) NOT NULL,
    detalhes TEXT,
    usuario_banco VARCHAR(100),
    data_hora TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_log)
) ENGINE=InnoDB;

-- =====================================================================
-- 4. CRIAÇÃO DE ÍNDICES (INDEX) COM JUSTIFICATIVA
-- =====================================================================
-- Justificativa 1: Otimizar buscas frequentes por status e severidade de incidentes em painéis SOC (Dashboard).
CREATE INDEX idx_incidentes_status_severidade ON incidentes(status, severidade);

-- Justificativa 2: Acelerar a busca de ativos de rede pelo endereço IP durante triagens de incidentes.
CREATE INDEX idx_ativos_ip ON ativos_rede(endereco_ip);

-- =====================================================================
-- 5. CRIAÇÃO DE VIEWS (Mínimo de 2)
-- =====================================================================

-- View 1: Resumo Executivo de Incidentes Ativos (Simplifica JOINs complexos para o Frontend)
CREATE OR REPLACE VIEW vw_resumo_incidentes AS
SELECT 
    i.id_incidente,
    i.titulo,
    i.severidade,
    i.status,
    a.hostname AS ativo_afetado,
    a.endereco_ip,
    COALESCE(u.nome, 'Não Atribuído') AS responsavel,
    i.criado_em
FROM incidentes i
JOIN ativos_rede a ON i.id_ativo = a.id_ativo
LEFT JOIN usuarios u ON i.id_responsavel = u.id_usuario;

-- View 2: Carga de Trabalho por Analista (Métricas para gestores)
CREATE OR REPLACE VIEW vw_carga_analistas AS
SELECT 
    u.id_usuario,
    u.nome AS analista,
    g.nome_grupo AS grupo,
    COUNT(i.id_incidente) AS total_incidentes_atribuidos,
    SUM(CASE WHEN i.status = 'ABERTO' THEN 1 ELSE 0 END) AS incidentes_abertos
FROM usuarios u
JOIN grupos_usuarios g ON u.id_grupo = g.id_grupo
LEFT JOIN incidentes i ON u.id_usuario = i.id_responsavel
GROUP BY u.id_usuario, u.nome, g.nome_grupo;

-- =====================================================================
-- 6. STORED PROCEDURES E FUNCTIONS (Mínimo de 2)
-- =====================================================================

DELIMITER $$

-- Procedure 1: Cadastrar Novo Incidente com uso da função de ID customizado
CREATE PROCEDURE sp_cadastrar_incidente(
    IN p_id_ativo VARCHAR(36),
    IN p_titulo VARCHAR(150),
    IN p_descricao TEXT,
    IN p_severidade VARCHAR(20),
    OUT p_id_gerado VARCHAR(36)
)
BEGIN
    SET p_id_gerado = fn_gerar_id('INC');
    
    INSERT INTO incidentes (id_incidente, id_ativo, titulo, descricao, severidade, status)
    VALUES (p_id_gerado, p_id_ativo, p_titulo, p_descricao, p_severidade, 'ABERTO');
END$$

-- Procedure 2: Atribuir Incidente a um Analista com controle transacional implícito
CREATE PROCEDURE sp_atribuir_incidente(
    IN p_id_incidente VARCHAR(36),
    IN p_id_analista VARCHAR(36)
)
BEGIN
    UPDATE incidentes 
    SET id_responsavel = p_id_analista, 
        status = 'EM_ANALISE',
        atualizado_em = CURRENT_TIMESTAMP
    WHERE id_incidente = p_id_incidente;
END$$

DELIMITER ;

-- =====================================================================
-- 7. TRIGGERS (Mínimo de 2)
-- =====================================================================

DELIMITER $$

-- Trigger 1: Auditoria de exclusão de usuários críticos (Gera log antes de deletar)
CREATE TRIGGER trg_auditoria_usuario_delete
BEFORE DELETE ON usuarios
FOR EACH ROW
BEGIN
    INSERT INTO logs_auditoria (id_log, tabela_afetada, operacao, detalhes, usuario_banco)
    VALUES (
        fn_gerar_id('LOG'),
        'usuarios',
        'DELETE',
        CONCAT('Remoção do usuário ID: ', OLD.id_usuario, ' - Email: ', OLD.email),
        USER()
    );
END$$

-- Trigger 2: Registro automático de alteração de severidade em incidentes críticos
CREATE TRIGGER trg_alerta_incidente_critico
AFTER UPDATE ON incidentes
FOR EACH ROW
BEGIN
    IF NEW.severidade = 'CRITICA' AND OLD.severidade <> 'CRITICA' THEN
        INSERT INTO logs_auditoria (id_log, tabela_afetada, operacao, detalhes, usuario_banco)
        VALUES (
            fn_gerar_id('LOG'),
            'incidentes',
            'UPDATE_CRITICO',
            CONCAT('Incidente ', NEW.id_incidente, ' elevado para severidade CRITICA.'),
            USER()
        );
    END IF;
END$$

DELIMITER ;

-- =====================================================================
-- 8. CONTROLE DE ACESSO E SEGURANÇA (DCL)
-- Restrição: Proibido uso do root pela aplicação.
-- =====================================================================

-- Criar usuário específico da aplicação para conexões via backend
CREATE USER IF NOT EXISTS 'secops_app'@'localhost' IDENTIFIED BY 'SecOps@2026_SecurePass';

-- Conceder privilégios estritamente necessários nas tabelas e views do sistema
GRANT SELECT, INSERT, UPDATE ON secops_db.incidentes TO 'secops_app'@'localhost';
GRANT SELECT, INSERT ON secops_db.ativos_rede TO 'secops_app'@'localhost';
GRANT SELECT ON secops_db.usuarios TO 'secops_app'@'localhost';
GRANT SELECT ON secops_db.grupos_usuarios TO 'secops_app'@'localhost';
GRANT SELECT ON secops_db.vw_resumo_incidentes TO 'secops_app'@'localhost';
GRANT SELECT ON secops_db.vw_carga_analistas TO 'secops_app'@'localhost';
GRANT EXECUTE ON PROCEDURE secops_db.sp_cadastrar_incidente TO 'secops_app'@'localhost';
GRANT EXECUTE ON PROCEDURE secops_db.sp_atribuir_incidente TO 'secops_app'@'localhost';

FLUSH PRIVILEGES;