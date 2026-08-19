-- ============================================================================
-- GRC Hub v2.0 — Schema PostgreSQL
-- Substitui completamente o schema v1.x (execute com banco limpo)
-- ============================================================================
SET client_min_messages = 'warning';
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- CONFIGURAÇÕES GLOBAIS
-- ============================================================================
CREATE TABLE IF NOT EXISTS configuracoes(
  chave TEXT PRIMARY KEY,
  valor TEXT NOT NULL DEFAULT '',
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO configuracoes (chave, valor) VALUES
  ('empresa_nome',      'Minha Empresa')
, ('empresa_subtitulo', 'GRC Hub · ISO 27001 · CIS · NIST')
, ('empresa_logo',      '')
, ('admins_extras',     '')
ON CONFLICT (chave) DO NOTHING;

-- ============================================================================
-- LOGS DE AUDITORIA
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs_auditoria(
  id          BIGSERIAL PRIMARY KEY,
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
  usuario     TEXT NOT NULL,
  acao        TEXT NOT NULL,
  modulo      TEXT NOT NULL,
  objeto_id   TEXT,
  objeto_nome TEXT,
  detalhes    TEXT
);
CREATE INDEX IF NOT EXISTS idx_logs_criado   ON logs_auditoria(criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_logs_usuario  ON logs_auditoria(usuario);
CREATE INDEX IF NOT EXISTS idx_logs_modulo   ON logs_auditoria(modulo);

-- ============================================================================
-- FRAMEWORK ENGINE
-- ============================================================================
CREATE TABLE IF NOT EXISTS frameworks(
  codigo           TEXT PRIMARY KEY,
  nome             TEXT NOT NULL,
  versao           TEXT,
  tipo             TEXT,  -- ISO / NIST / CIS / COBIT / GOV
  descricao        TEXT,
  cor              TEXT DEFAULT '#00d4ff',
  total_controles  INT  DEFAULT 0,
  ativo            BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS fw_controles(
  id                SERIAL PRIMARY KEY,
  framework_codigo  TEXT NOT NULL REFERENCES frameworks(codigo) ON DELETE CASCADE,
  codigo            TEXT NOT NULL,
  dominio           TEXT,
  subdominio        TEXT,
  titulo            TEXT NOT NULL,
  descricao         TEXT,
  nivel_ig          TEXT,      -- CIS: IG1/IG2/IG3
  funcao_csf        TEXT,      -- NIST CSF: GV/ID/PR/DE/RS/RC
  asset_type        TEXT,      -- CIS: Devices/Users/Data/Network/Applications
  ordem             INT  DEFAULT 0,
  UNIQUE(framework_codigo, codigo)
);
CREATE INDEX IF NOT EXISTS idx_fw_controles_fw     ON fw_controles(framework_codigo);
CREATE INDEX IF NOT EXISTS idx_fw_controles_dom    ON fw_controles(dominio);

-- Mapeamentos cruzados
CREATE TABLE IF NOT EXISTS fw_mapeamentos(
  id                  SERIAL PRIMARY KEY,
  controle_origem_id  INT NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  controle_destino_id INT NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  relacao             TEXT DEFAULT 'Parcial',  -- Equivalente / Parcial / Complementar
  notas               TEXT,
  UNIQUE(controle_origem_id, controle_destino_id)
);
CREATE INDEX IF NOT EXISTS idx_fw_map_origem ON fw_mapeamentos(controle_origem_id);
CREATE INDEX IF NOT EXISTS idx_fw_map_dest   ON fw_mapeamentos(controle_destino_id);

-- Tabela temporária para resolução de IDs de mapeamento durante o seed
CREATE TABLE IF NOT EXISTS fw_mapeamentos_seed(
  id              SERIAL PRIMARY KEY,
  origem_codigo   TEXT NOT NULL,
  origem_fw_guess TEXT,
  dest_fw         TEXT NOT NULL,
  dest_codigo     TEXT NOT NULL,
  relacao         TEXT DEFAULT 'Parcial',
  notas           TEXT
);

-- ============================================================================
-- AVALIAÇÕES DE MATURIDADE (0-5 CMMI por controle)
-- ============================================================================
CREATE TABLE IF NOT EXISTS avaliacoes(
  id                BIGSERIAL PRIMARY KEY,
  framework_codigo  TEXT NOT NULL REFERENCES frameworks(codigo),
  controle_id       INT  NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  usuario           TEXT NOT NULL,
  maturidade_atual  SMALLINT NOT NULL DEFAULT 0 CHECK (maturidade_atual BETWEEN 0 AND 5),
  maturidade_meta   SMALLINT NOT NULL DEFAULT 3 CHECK (maturidade_meta BETWEEN 0 AND 5),
  justificativa     TEXT,
  evidencia         TEXT,
  aplicavel         BOOLEAN NOT NULL DEFAULT TRUE,
  criado_em         TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- avaliação é organizacional: uma linha por controle; usuario = último avaliador
  UNIQUE(framework_codigo, controle_id)
);
CREATE INDEX IF NOT EXISTS idx_aval_fw      ON avaliacoes(framework_codigo);
CREATE INDEX IF NOT EXISTS idx_aval_ctrl    ON avaliacoes(controle_id);
CREATE INDEX IF NOT EXISTS idx_aval_usuario ON avaliacoes(usuario);

CREATE TABLE IF NOT EXISTS avaliacao_anexos(
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  avaliacao_id    BIGINT NOT NULL REFERENCES avaliacoes(id) ON DELETE CASCADE,
  nome_original   TEXT NOT NULL,
  arquivo         TEXT,          -- NULL quando o anexo é um link externo
  url             TEXT,          -- link externo (SharePoint, Google Workspace…)
  hash_sha256     TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_aval_anexos ON avaliacao_anexos(avaliacao_id);

-- Ciclos formais de avaliação (fechar ciclo = snapshot nomeado por controle)
CREATE TABLE IF NOT EXISTS ciclos(
  id                BIGSERIAL PRIMARY KEY,
  framework_codigo  TEXT NOT NULL REFERENCES frameworks(codigo) ON DELETE CASCADE,
  nome              TEXT NOT NULL,
  fechado_por       TEXT,
  fechado_em        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ciclos_fw ON ciclos(framework_codigo, fechado_em DESC);

CREATE TABLE IF NOT EXISTS ciclo_avaliacoes(
  id                BIGSERIAL PRIMARY KEY,
  ciclo_id          BIGINT NOT NULL REFERENCES ciclos(id) ON DELETE CASCADE,
  controle_id       INT NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  maturidade_atual  SMALLINT NOT NULL DEFAULT 0,
  maturidade_meta   SMALLINT NOT NULL DEFAULT 3,
  aplicavel         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE(ciclo_id, controle_id)
);

-- Snapshots diários de maturidade por framework (evolução temporal)
CREATE TABLE IF NOT EXISTS maturidade_snapshots(
  id                BIGSERIAL PRIMARY KEY,
  framework_codigo  TEXT NOT NULL REFERENCES frameworks(codigo) ON DELETE CASCADE,
  data              DATE NOT NULL DEFAULT CURRENT_DATE,
  media_atual       NUMERIC(3,1) NOT NULL DEFAULT 0,
  media_meta        NUMERIC(3,1) NOT NULL DEFAULT 0,
  avaliados         INT NOT NULL DEFAULT 0,
  gaps              INT NOT NULL DEFAULT 0,
  UNIQUE(framework_codigo, data)
);
CREATE INDEX IF NOT EXISTS idx_snapshots_fw ON maturidade_snapshots(framework_codigo, data);

-- ============================================================================
-- SGSI CORE — Ativos, Riscos, NCs, Planos, SOA, Políticas
-- ============================================================================
CREATE TABLE IF NOT EXISTS ativos(
  codigo            TEXT PRIMARY KEY,
  nome              TEXT NOT NULL,
  categoria         TEXT,
  tipo_subtipo      TEXT,
  dono              TEXT,
  usuario_principal TEXT,
  localizacao       TEXT,
  ambiente          TEXT,
  cid               TEXT[] DEFAULT '{}',
  criticidade       TEXT DEFAULT 'Média',
  classificacao     TEXT DEFAULT 'Interno',
  dependencias      TEXT,
  status            TEXT DEFAULT 'Ativo',
  data_aquisicao    DATE,
  data_expiracao    DATE,
  criado_em         TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ativos_status ON ativos(status);

CREATE TABLE IF NOT EXISTS riscos(
  codigo                  TEXT PRIMARY KEY,
  ativo_codigo            TEXT REFERENCES ativos(codigo) ON DELETE SET NULL,
  fator                   TEXT NOT NULL,
  descricao               TEXT,
  probabilidade           SMALLINT DEFAULT 2,
  impacto                 SMALLINT DEFAULT 2,
  score_inerente          SMALLINT GENERATED ALWAYS AS (probabilidade * impacto) STORED,
  nivel_inerente          TEXT DEFAULT 'Médio',
  impacto_financeiro      TEXT DEFAULT 'Não',
  racional_impacto        TEXT,
  tratamento_inerente     TEXT DEFAULT 'Mitigar',
  controle_codigo_iso     TEXT,
  controle_descricao      TEXT,
  controle_documentacao   TEXT,
  controle_natureza       TEXT DEFAULT 'Preventivo',
  controle_categoria      TEXT DEFAULT 'Manual',
  controle_frequencia     TEXT DEFAULT 'Mensal',
  controle_dono           TEXT,
  controle_avaliacao      TEXT DEFAULT 'Não Avaliado',
  cid                     TEXT[] DEFAULT '{}',
  prob_residual           SMALLINT DEFAULT 1,
  impacto_residual        SMALLINT DEFAULT 1,
  score_residual          SMALLINT GENERATED ALWAYS AS (prob_residual * impacto_residual) STORED,
  nivel_residual          TEXT DEFAULT 'Baixo',
  gap_referencia          TEXT,
  gap_descricao           TEXT,
  ultima_revisao          DATE,
  proxima_revisao         DATE,
  criado_em               TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_riscos_ativo  ON riscos(ativo_codigo);
CREATE INDEX IF NOT EXISTS idx_riscos_nivel  ON riscos(nivel_residual);

CREATE TABLE IF NOT EXISTS ncs(
  codigo                    TEXT PRIMARY KEY,
  risco_codigo              TEXT REFERENCES riscos(codigo) ON DELETE SET NULL,
  ativo_codigo              TEXT REFERENCES ativos(codigo) ON DELETE SET NULL,
  detalhe                   TEXT NOT NULL,
  descricao                 TEXT,
  processos                 TEXT[] DEFAULT '{}',
  origem                    TEXT,
  clausula                  TEXT,
  tipo                      TEXT DEFAULT 'Menor',
  dono_correcao             TEXT,
  identificado_por          TEXT,
  data_identificacao        DATE,
  data_encerramento         DATE,
  causa_raiz                TEXT,
  correcao_imediata         TEXT,
  acao_corretiva            TEXT,
  acao_preventiva           TEXT,
  data_proposta             DATE,
  dono_proposta             TEXT,
  descricao_acao_preventiva TEXT,
  justificativa             TEXT,
  status_correcao           TEXT DEFAULT 'Aberto',
  status_preventiva         TEXT DEFAULT 'Aberto',
  status_eficacia           TEXT DEFAULT 'Não Avaliado',
  link_evidencia            TEXT,
  observacoes               TEXT,
  criado_em                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ncs_risco ON ncs(risco_codigo);
CREATE INDEX IF NOT EXISTS idx_ncs_status ON ncs(status_correcao);

CREATE TABLE IF NOT EXISTS nc_anexos(
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nc_codigo       TEXT NOT NULL REFERENCES ncs(codigo) ON DELETE CASCADE,
  nome_original   TEXT NOT NULL,
  arquivo         TEXT,          -- NULL quando o anexo é um link externo
  url             TEXT,          -- link externo (SharePoint, Google Workspace…)
  hash_sha256     TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_nc_anexos ON nc_anexos(nc_codigo);

CREATE TABLE IF NOT EXISTS planos(
  codigo                    TEXT PRIMARY KEY,
  risco_codigo              TEXT REFERENCES riscos(codigo) ON DELETE SET NULL,
  nc_codigo                 TEXT REFERENCES ncs(codigo) ON DELETE SET NULL,
  secao_iso                 TEXT,
  nome                      TEXT NOT NULL,
  tipo                      TEXT DEFAULT 'Processo',
  origem                    TEXT DEFAULT 'Auditoria',
  descricao                 TEXT,
  responsavel               TEXT,
  status                    TEXT DEFAULT 'Aberto',
  data_inicio               DATE,
  data_fim                  DATE,
  link_evidencia            TEXT,
  arquivo_evidencia         TEXT,
  arquivo_evidencia_nome    TEXT,
  arquivo_evidencia_hash    TEXT,
  verificado_por            TEXT,
  notas                     TEXT,
  licoes_aprendidas         TEXT,
  progresso                 SMALLINT NOT NULL DEFAULT 0,
  controle_ref              TEXT,
  criado_em                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_planos_status ON planos(status);
CREATE INDEX IF NOT EXISTS idx_planos_controle_ref ON planos(controle_ref);

CREATE TABLE IF NOT EXISTS soa(
  codigo                    TEXT PRIMARY KEY,
  categoria                 TEXT NOT NULL DEFAULT 'controle',  -- 'requisito' (cláusulas 4–10 da ISO 27001) | 'controle' (Anexo A / ISO 27002)
  dominio                   TEXT NOT NULL,
  dominio_label             TEXT NOT NULL DEFAULT '',
  titulo                    TEXT NOT NULL,
  descricao                 TEXT,
  justificativa             TEXT,
  aplicavel                 BOOLEAN DEFAULT TRUE,
  status_implementacao      TEXT DEFAULT 'Planejado',
  conformidade              TEXT DEFAULT 'Não Avaliado',   -- ausência de auditoria não é conformidade
  evidencias                TEXT[] DEFAULT '{}',
  documentos_referencia     TEXT,
  origem_apontamento        TEXT,
  assessment_score          NUMERIC(3,1),
  maturidade_cmmi           TEXT,
  colaborador_responsavel   TEXT,
  area_responsavel          TEXT,
  responsaveis              TEXT[] DEFAULT '{}',
  criado_em                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_soa_dominio ON soa(dominio);
CREATE INDEX IF NOT EXISTS idx_soa_status  ON soa(status_implementacao);

CREATE TABLE IF NOT EXISTS soa_anexos(
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  soa_codigo      TEXT NOT NULL REFERENCES soa(codigo) ON DELETE CASCADE,
  nome_original   TEXT NOT NULL,
  arquivo         TEXT,          -- NULL quando o anexo é um link externo
  url             TEXT,          -- link externo (SharePoint, Google Workspace…)
  hash_sha256     TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_soa_anexos ON soa_anexos(soa_codigo);

-- Perfis RBAC do portal (autenticação continua no Keycloak)
CREATE TABLE IF NOT EXISTS usuarios_perfis(
  email          TEXT PRIMARY KEY,
  perfil         TEXT NOT NULL DEFAULT 'Leitor',  -- Administrador / Gestor de Risco / Avaliador / Auditor / Leitor
  atualizado_em  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS politicas(
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo              TEXT NOT NULL,
  tipo                TEXT DEFAULT 'Política',
  status              TEXT DEFAULT 'Vigente',
  arquivo             TEXT,
  arquivo_nome_original TEXT,
  url                 TEXT,      -- documento hospedado externamente (SharePoint, Google Docs…)
  hash_sha256         TEXT,
  criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Analista IA — cache de análises (semânticas e LLM)
CREATE TABLE IF NOT EXISTS ia_analises(
  id         BIGSERIAL PRIMARY KEY,
  tipo       TEXT NOT NULL,
  objeto_id  TEXT NOT NULL,
  motor      TEXT NOT NULL,
  resultado  JSONB NOT NULL,
  criado_em  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(tipo, objeto_id)
);

-- Vínculo políticas ⇄ controles do Mapa de Aplicabilidade (hub de correlação)
CREATE TABLE IF NOT EXISTS soa_politicas(
  soa_codigo   TEXT NOT NULL REFERENCES soa(codigo) ON DELETE CASCADE,
  politica_id  UUID NOT NULL REFERENCES politicas(id) ON DELETE CASCADE,
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(soa_codigo, politica_id)
);
CREATE INDEX IF NOT EXISTS idx_soa_politicas_pol ON soa_politicas(politica_id);

-- ============================================================================
-- AUDITORIAS — cronograma e consolidado (interna, externa, personalizadas)
-- (criadas ao final pois ncs/riscos/planos ganham FK para auditorias)
-- ============================================================================
CREATE TABLE IF NOT EXISTS auditorias(
  id               BIGSERIAL PRIMARY KEY,
  codigo           TEXT UNIQUE NOT NULL,
  nome             TEXT NOT NULL,
  tipo             TEXT NOT NULL DEFAULT 'Interna',
  norma            TEXT DEFAULT 'ISO/IEC 27001:2022',
  escopo           TEXT,
  auditor_lider    TEXT,
  organismo        TEXT,
  data_inicio      DATE,
  data_fim         DATE,
  status           TEXT NOT NULL DEFAULT 'Planejada',
  carta_comentario TEXT,
  carta_arquivo    TEXT,
  carta_arquivo_nome TEXT,
  carta_url        TEXT,
  conclusao        TEXT,
  criado_em        TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auditorias_inicio ON auditorias(data_inicio DESC);

CREATE TABLE IF NOT EXISTS auditoria_achados(
  id            BIGSERIAL PRIMARY KEY,
  auditoria_id  BIGINT NOT NULL REFERENCES auditorias(id) ON DELETE CASCADE,
  tipo          TEXT NOT NULL DEFAULT 'Observação',
  referencia    TEXT,
  descricao     TEXT NOT NULL,
  nc_codigo     TEXT REFERENCES ncs(codigo) ON DELETE SET NULL,
  plano_codigo  TEXT REFERENCES planos(codigo) ON DELETE SET NULL,
  status        TEXT NOT NULL DEFAULT 'Aberto',
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_achados_aud ON auditoria_achados(auditoria_id);

ALTER TABLE ncs    ADD COLUMN IF NOT EXISTS auditoria_id BIGINT REFERENCES auditorias(id) ON DELETE SET NULL;
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS auditoria_id BIGINT REFERENCES auditorias(id) ON DELETE SET NULL;
ALTER TABLE planos ADD COLUMN IF NOT EXISTS auditoria_id BIGINT REFERENCES auditorias(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_ncs_aud    ON ncs(auditoria_id);
CREATE INDEX IF NOT EXISTS idx_riscos_aud ON riscos(auditoria_id);
CREATE INDEX IF NOT EXISTS idx_planos_aud ON planos(auditoria_id);
