-- ============================================================================
-- GRC Hub v2.1 — Upgrade incremental (fusão GRC Platform premium)
-- Idempotente: pode ser executado em base nova (initdb) ou existente (psql).
-- ============================================================================
SET client_min_messages = 'warning';

-- ============================================================================
-- ANEXOS DE EVIDÊNCIA POR AVALIAÇÃO DE CONTROLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS avaliacao_anexos(
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  avaliacao_id    BIGINT NOT NULL REFERENCES avaliacoes(id) ON DELETE CASCADE,
  nome_original   TEXT NOT NULL,
  arquivo         TEXT NOT NULL,
  hash_sha256     TEXT,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_aval_anexos ON avaliacao_anexos(avaliacao_id);

-- ============================================================================
-- PLANOS — progresso (%) e rastreio do vínculo GAP→Plano
-- ============================================================================
ALTER TABLE planos ADD COLUMN IF NOT EXISTS progresso SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE planos ADD COLUMN IF NOT EXISTS controle_ref TEXT;
CREATE INDEX IF NOT EXISTS idx_planos_controle_ref ON planos(controle_ref);

-- Planos já implementados contam como 100%
UPDATE planos SET progresso = 100 WHERE status = 'Implementado' AND progresso = 0;

-- ============================================================================
-- PERFIS RBAC (Keycloak segue apenas como autenticação)
-- ============================================================================
CREATE TABLE IF NOT EXISTS usuarios_perfis(
  email          TEXT PRIMARY KEY,
  perfil         TEXT NOT NULL DEFAULT 'Leitor',  -- Administrador / Gestor de Risco / Avaliador / Auditor / Leitor
  atualizado_em  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- SNAPSHOTS DE MATURIDADE (evolução temporal, máx. 1/dia por framework)
-- ============================================================================
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
-- ANALISTA IA — cache de análises (semânticas e LLM)
-- ============================================================================
CREATE TABLE IF NOT EXISTS ia_analises(
  id         BIGSERIAL PRIMARY KEY,
  tipo       TEXT NOT NULL,       -- politica / risco / nc / plano
  objeto_id  TEXT NOT NULL,       -- id/codigo do objeto analisado
  motor      TEXT NOT NULL,       -- semantico / llm:<modelo>
  resultado  JSONB NOT NULL,
  criado_em  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(tipo, objeto_id)
);

-- ============================================================================
-- SOA COMO HUB — vínculo políticas ⇄ controles do Mapa de Aplicabilidade
-- ============================================================================
CREATE TABLE IF NOT EXISTS soa_politicas(
  soa_codigo   TEXT NOT NULL REFERENCES soa(codigo) ON DELETE CASCADE,
  politica_id  UUID NOT NULL REFERENCES politicas(id) ON DELETE CASCADE,
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(soa_codigo, politica_id)
);
CREATE INDEX IF NOT EXISTS idx_soa_politicas_pol ON soa_politicas(politica_id);

-- ============================================================================
-- CICLOS FORMAIS DE AVALIAÇÃO (fechar ciclo = snapshot nomeado por controle)
-- ============================================================================
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

-- ============================================================================
-- AVALIAÇÃO ORGANIZACIONAL — uma linha por controle (usuario = último avaliador)
-- Dedup mantém a avaliação mais recente e troca a unicidade.
-- ============================================================================
DELETE FROM avaliacoes a USING avaliacoes b
 WHERE a.framework_codigo = b.framework_codigo
   AND a.controle_id = b.controle_id
   AND (a.atualizado_em, a.id) < (b.atualizado_em, b.id);
ALTER TABLE avaliacoes DROP CONSTRAINT IF EXISTS avaliacoes_framework_codigo_controle_id_usuario_key;
ALTER TABLE avaliacoes DROP CONSTRAINT IF EXISTS avaliacoes_framework_codigo_controle_id_key;
ALTER TABLE avaliacoes ADD CONSTRAINT avaliacoes_framework_codigo_controle_id_key
  UNIQUE (framework_codigo, controle_id);

-- ============================================================================
-- MIGRAÇÃO MATRIZ DE RISCO 3×3 → 5×5
-- Escala antiga 1/2/3 → 1/3/5. Executa uma única vez (flag em configuracoes).
-- Níveis 5×5: Baixo ≤4 · Médio 5–9 · Alto 10–15 · Crítico ≥16.
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM configuracoes WHERE chave = 'escala_risco' AND valor = '5x5') THEN
    -- 1→1 · 2→3 · 3→5; valores fora da escala antiga são grampeados em 1–5
    UPDATE riscos SET
      probabilidade    = CASE WHEN probabilidade    = 2 THEN 3 WHEN probabilidade    = 3 THEN 5 WHEN probabilidade    > 5 THEN 5 WHEN probabilidade    < 1 THEN 1 ELSE probabilidade    END,
      impacto          = CASE WHEN impacto          = 2 THEN 3 WHEN impacto          = 3 THEN 5 WHEN impacto          > 5 THEN 5 WHEN impacto          < 1 THEN 1 ELSE impacto          END,
      prob_residual    = CASE WHEN prob_residual    = 2 THEN 3 WHEN prob_residual    = 3 THEN 5 WHEN prob_residual    > 5 THEN 5 WHEN prob_residual    < 1 THEN 1 ELSE prob_residual    END,
      impacto_residual = CASE WHEN impacto_residual = 2 THEN 3 WHEN impacto_residual = 3 THEN 5 WHEN impacto_residual > 5 THEN 5 WHEN impacto_residual < 1 THEN 1 ELSE impacto_residual END;

    UPDATE riscos SET
      nivel_inerente = CASE
        WHEN probabilidade * impacto >= 16 THEN 'Crítico'
        WHEN probabilidade * impacto >= 10 THEN 'Alto'
        WHEN probabilidade * impacto >= 5  THEN 'Médio'
        ELSE 'Baixo' END,
      nivel_residual = CASE
        WHEN prob_residual * impacto_residual >= 16 THEN 'Crítico'
        WHEN prob_residual * impacto_residual >= 10 THEN 'Alto'
        WHEN prob_residual * impacto_residual >= 5  THEN 'Médio'
        ELSE 'Baixo' END;

    INSERT INTO configuracoes(chave, valor) VALUES('escala_risco', '5x5')
      ON CONFLICT(chave) DO UPDATE SET valor = '5x5', atualizado_em = now();
  END IF;
END $$;

-- ============================================================================
-- v2.2 — SOA: requisitos ISO 27001 (cláusulas 4–10) separados dos controles
--        do Anexo A (ISO 27002) + anexos por LINK externo (SharePoint etc.)
-- ============================================================================
ALTER TABLE soa ADD COLUMN IF NOT EXISTS categoria TEXT NOT NULL DEFAULT 'controle';  -- 'requisito' | 'controle'
ALTER TABLE soa_anexos ADD COLUMN IF NOT EXISTS url TEXT;
ALTER TABLE soa_anexos ALTER COLUMN arquivo DROP NOT NULL;
ALTER TABLE avaliacao_anexos ADD COLUMN IF NOT EXISTS url TEXT;
ALTER TABLE avaliacao_anexos ALTER COLUMN arquivo DROP NOT NULL;
ALTER TABLE politicas ADD COLUMN IF NOT EXISTS url TEXT;

-- Requisitos mandatórios da ISO/IEC 27001:2022 (cláusulas 4–10).
-- Diferente do Anexo A, não admitem exclusão de aplicabilidade.
INSERT INTO soa (codigo,categoria,dominio,dominio_label,titulo,descricao,aplicavel,status_implementacao,conformidade) VALUES
 ('4.1','requisito','4','Contexto da Organização','Entendimento da organização e de seu contexto','Determinar questões internas e externas relevantes para o propósito e que afetam o resultado pretendido do SGSI (incl. clima, emenda 2024).',TRUE,'Planejado','OK'),
 ('4.2','requisito','4','Contexto da Organização','Necessidades e expectativas das partes interessadas','Determinar partes interessadas relevantes ao SGSI e seus requisitos, e quais serão atendidos pelo SGSI.',TRUE,'Planejado','OK'),
 ('4.3','requisito','4','Contexto da Organização','Determinação do escopo do SGSI','Definir limites e aplicabilidade do SGSI considerando contexto, partes interessadas e interfaces; escopo disponível como informação documentada.',TRUE,'Planejado','OK'),
 ('4.4','requisito','4','Contexto da Organização','Sistema de gestão de segurança da informação','Estabelecer, implementar, manter e melhorar continuamente o SGSI, incluindo processos necessários e suas interações.',TRUE,'Planejado','OK'),
 ('5.1','requisito','5','Liderança','Liderança e comprometimento','Alta direção demonstra liderança: política e objetivos compatíveis com a estratégia, recursos disponíveis, integração do SGSI aos processos.',TRUE,'Planejado','OK'),
 ('5.2','requisito','5','Liderança','Política de segurança da informação','Política apropriada ao propósito, com objetivos (ou moldura), compromisso com requisitos e melhoria contínua; comunicada e disponível.',TRUE,'Planejado','OK'),
 ('5.3','requisito','5','Liderança','Papéis, responsabilidades e autoridades','Atribuir e comunicar responsabilidades e autoridades para conformidade do SGSI e reporte de desempenho à alta direção.',TRUE,'Planejado','OK'),
 ('6.1','requisito','6','Planejamento','Ações para abordar riscos e oportunidades','Definir e aplicar processo de avaliação (critérios, identificação, análise, avaliação) e de tratamento de riscos de SI; produzir a Declaração de Aplicabilidade.',TRUE,'Planejado','OK'),
 ('6.2','requisito','6','Planejamento','Objetivos de SI e planejamento para alcançá-los','Objetivos mensuráveis, comunicados, atualizados e documentados; planejar o quê, recursos, responsáveis, prazos e avaliação de resultados.',TRUE,'Planejado','OK'),
 ('6.3','requisito','6','Planejamento','Planejamento de mudanças','Mudanças no SGSI realizadas de forma planejada.',TRUE,'Planejado','OK'),
 ('7.1','requisito','7','Apoio','Recursos','Determinar e prover recursos necessários para estabelecer, implementar, manter e melhorar continuamente o SGSI.',TRUE,'Planejado','OK'),
 ('7.2','requisito','7','Apoio','Competência','Determinar competências, assegurar por formação/experiência, tomar ações e reter informação documentada como evidência.',TRUE,'Planejado','OK'),
 ('7.3','requisito','7','Apoio','Conscientização','Pessoas cientes da política, de sua contribuição à eficácia do SGSI e das implicações de não conformidade.',TRUE,'Planejado','OK'),
 ('7.4','requisito','7','Apoio','Comunicação','Determinar comunicações internas e externas relevantes: o quê, quando, com quem e como comunicar.',TRUE,'Planejado','OK'),
 ('7.5','requisito','7','Apoio','Informação documentada','Criar, atualizar e controlar a informação documentada requerida pela norma e a necessária à eficácia do SGSI.',TRUE,'Planejado','OK'),
 ('8.1','requisito','8','Operação','Planejamento e controle operacionais','Planejar, implementar e controlar processos para atender requisitos; controlar mudanças e processos terceirizados.',TRUE,'Planejado','OK'),
 ('8.2','requisito','8','Operação','Avaliação de riscos de segurança da informação','Realizar avaliações de risco a intervalos planejados ou diante de mudanças significativas, retendo os resultados documentados.',TRUE,'Planejado','OK'),
 ('8.3','requisito','8','Operação','Tratamento de riscos de segurança da informação','Implementar o plano de tratamento de riscos e reter os resultados como informação documentada.',TRUE,'Planejado','OK'),
 ('9.1','requisito','9','Avaliação de Desempenho','Monitoramento, medição, análise e avaliação','Determinar o que monitorar/medir, métodos, quando e quem; avaliar desempenho de SI e eficácia do SGSI.',TRUE,'Planejado','OK'),
 ('9.2','requisito','9','Avaliação de Desempenho','Auditoria interna','Programa de auditoria a intervalos planejados: critérios, escopo, auditores imparciais, resultados reportados e documentados.',TRUE,'Planejado','OK'),
 ('9.3','requisito','9','Avaliação de Desempenho','Análise crítica pela direção','Alta direção analisa o SGSI a intervalos planejados: entradas (desempenho, feedback, riscos) e saídas (decisões de melhoria) documentadas.',TRUE,'Planejado','OK'),
 ('10.1','requisito','10','Melhoria','Melhoria contínua','Melhorar continuamente a adequação, suficiência e eficácia do SGSI.',TRUE,'Planejado','OK'),
 ('10.2','requisito','10','Melhoria','Não conformidade e ação corretiva','Reagir a NCs, avaliar causas, implementar ações corretivas proporcionais e reter evidências documentadas.',TRUE,'Planejado','OK')
ON CONFLICT (codigo) DO NOTHING;

-- ============================================================================
-- v2.3 — CRONOGRAMA E CONSOLIDADO DE AUDITORIAS (interna, externa e
--        personalizadas): achados, carta comentário e relatório final
-- ============================================================================
CREATE TABLE IF NOT EXISTS auditorias(
  id               BIGSERIAL PRIMARY KEY,
  codigo           TEXT UNIQUE NOT NULL,                 -- AUD-0001
  nome             TEXT NOT NULL,                        -- ex.: Auditoria Interna ISO 27001 — 2026
  tipo             TEXT NOT NULL DEFAULT 'Interna',      -- Interna / Externa (Certificação) / Externa (Manutenção) / Personalizada
  norma            TEXT DEFAULT 'ISO/IEC 27001:2022',
  escopo           TEXT,
  auditor_lider    TEXT,
  organismo        TEXT,                                 -- organismo certificador / empresa auditora
  data_inicio      DATE,
  data_fim         DATE,
  status           TEXT NOT NULL DEFAULT 'Planejada',    -- Planejada / Em Andamento / Aguardando Carta / Concluída / Cancelada
  carta_comentario TEXT,                                 -- resumo/transcrição da carta comentário
  carta_arquivo    TEXT,
  carta_arquivo_nome TEXT,
  carta_url        TEXT,                                 -- carta hospedada externamente
  conclusao        TEXT,                                 -- parecer final / recomendação do auditor
  criado_em        TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_auditorias_inicio ON auditorias(data_inicio DESC);

-- Achados da auditoria (NC Maior/Menor, Observação, Oportunidade de Melhoria, Ponto Forte)
CREATE TABLE IF NOT EXISTS auditoria_achados(
  id            BIGSERIAL PRIMARY KEY,
  auditoria_id  BIGINT NOT NULL REFERENCES auditorias(id) ON DELETE CASCADE,
  tipo          TEXT NOT NULL DEFAULT 'Observação',
  referencia    TEXT,                                    -- cláusula/controle (ex.: 7.5 ou A.5.15)
  descricao     TEXT NOT NULL,
  nc_codigo     TEXT REFERENCES ncs(codigo) ON DELETE SET NULL,
  plano_codigo  TEXT REFERENCES planos(codigo) ON DELETE SET NULL,
  status        TEXT NOT NULL DEFAULT 'Aberto',          -- Aberto / Em Tratamento / Encerrado
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_achados_aud ON auditoria_achados(auditoria_id);

-- Vínculo dos registros do SGSI com a auditoria de origem
ALTER TABLE ncs    ADD COLUMN IF NOT EXISTS auditoria_id BIGINT REFERENCES auditorias(id) ON DELETE SET NULL;
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS auditoria_id BIGINT REFERENCES auditorias(id) ON DELETE SET NULL;
ALTER TABLE planos ADD COLUMN IF NOT EXISTS auditoria_id BIGINT REFERENCES auditorias(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_ncs_aud    ON ncs(auditoria_id);
CREATE INDEX IF NOT EXISTS idx_riscos_aud ON riscos(auditoria_id);
CREATE INDEX IF NOT EXISTS idx_planos_aud ON planos(auditoria_id);

-- ============================================================================
-- v2.4 — NCs com anexos de documentos (arquivos e links, múltiplos por NC)
-- ============================================================================
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

-- ════════════════════════════════════════════════════════════════════════════
-- BIBLIOTECA DE EVIDÊNCIAS (OCR + frescor) — evidência operacional do SGSI
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS evidencias(
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo                 TEXT NOT NULL,
  tipo                   TEXT DEFAULT 'Documento',   -- Print/Screenshot, Log, Relatório, Ticket, Ata, Certificado, Configuração…
  descricao              TEXT,
  arquivo                TEXT,        -- NULL quando é link externo
  arquivo_nome_original  TEXT,
  url                    TEXT,        -- evidência hospedada fora (Jira, SharePoint, Git…)
  hash_sha256            TEXT,
  texto_ocr              TEXT,        -- texto extraído (OCR de imagem / extração de PDF/DOCX)
  fonte                  TEXT,        -- sistema/origem da evidência
  coletado_em            DATE NOT NULL DEFAULT CURRENT_DATE,
  validade_dias          INT NOT NULL DEFAULT 90,     -- janela de frescor
  criado_por             TEXT,
  criado_em              TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_evid_coletado ON evidencias(coletado_em DESC);

-- vínculo evidência ↔ controle/requisito do SOA (a evidência que legitima 'Implementado')
CREATE TABLE IF NOT EXISTS evidencia_soa(
  evidencia_id  UUID NOT NULL REFERENCES evidencias(id) ON DELETE CASCADE,
  soa_codigo    TEXT NOT NULL REFERENCES soa(codigo) ON DELETE CASCADE,
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(evidencia_id, soa_codigo)
);
CREATE INDEX IF NOT EXISTS idx_evid_soa_soa ON evidencia_soa(soa_codigo);


ALTER TABLE evidencias ADD COLUMN IF NOT EXISTS periodicidade TEXT DEFAULT 'Trimestral';
ALTER TABLE evidencias ALTER COLUMN validade_dias DROP NOT NULL;   -- NULL = não expira (permanente)


UPDATE ncs SET status_correcao = CASE status_correcao
  WHEN 'Aberto' THEN 'Registrada'
  WHEN 'Em Andamento' THEN 'Em tratamento'
  WHEN 'Implementada' THEN 'Encerrada'
  ELSE status_correcao END
WHERE status_correcao IN ('Aberto','Em Andamento','Implementada');


UPDATE ncs SET status_correcao = CASE lower(status_correcao)
  WHEN 'aberto' THEN 'Registrada'
  WHEN 'em andamento' THEN 'Em tratamento'
  WHEN 'implementada' THEN 'Encerrada'
  ELSE status_correcao END
WHERE lower(status_correcao) IN ('aberto','em andamento','implementada');


-- ════════════════════════════════════════════════════════════════════════════
-- FASE 1 (hub + lentes): vínculos generalizados e crosswalk automático
-- Política/evidência podem vincular a QUALQUER controle de QUALQUER framework;
-- o crosswalk (fw_mapeamentos) propaga os vínculos entre frameworks mapeados.
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS politica_controles(
  politica_id  UUID NOT NULL REFERENCES politicas(id) ON DELETE CASCADE,
  controle_id  INT  NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(politica_id, controle_id)
);
CREATE INDEX IF NOT EXISTS idx_polctrl_ctrl ON politica_controles(controle_id);

CREATE TABLE IF NOT EXISTS evidencia_controles(
  evidencia_id UUID NOT NULL REFERENCES evidencias(id) ON DELETE CASCADE,
  controle_id  INT  NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(evidencia_id, controle_id)
);
CREATE INDEX IF NOT EXISTS idx_evidctrl_ctrl ON evidencia_controles(controle_id);

-- Crosswalk sugerido pela IA (aguardando aprovação humana)
CREATE TABLE IF NOT EXISTS fw_map_sugestoes(
  id                  SERIAL PRIMARY KEY,
  controle_origem_id  INT NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  controle_destino_id INT NOT NULL REFERENCES fw_controles(id) ON DELETE CASCADE,
  relacao             TEXT NOT NULL DEFAULT 'Parcial',
  score               NUMERIC(4,3),
  status              TEXT NOT NULL DEFAULT 'Pendente',  -- Pendente/Aprovado/Rejeitado
  criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(controle_origem_id, controle_destino_id)
);


-- ════════════════════════════════════════════════════════════════════════════
-- MOTOR DE RECOMENDAÇÕES — fecha o ciclo de inteligência do GRC Hub
-- Política/evidência analisada → recomendações tipadas (maturidade, risco,
-- NC, plano) com ação pré-programada. Human-in-the-loop: Pendente → Aplicada/Descartada.
-- ════════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS recomendacoes(
  id             BIGSERIAL PRIMARY KEY,
  tipo           TEXT NOT NULL,              -- maturidade | risco | nc | plano
  objeto_id      TEXT NOT NULL,              -- código do risco/NC/plano · controle_id p/ maturidade
  titulo         TEXT NOT NULL,
  detalhe        TEXT,
  texto_sugerido TEXT,                       -- redação proposta (resolução/comentário)
  acao           JSONB,                      -- ação pré-programada (aplicar em 1 clique)
  origem_tipo    TEXT,                       -- politica | evidencia
  origem_id      TEXT,
  origem_titulo  TEXT,
  controles      TEXT[] DEFAULT '{}',        -- códigos que embasam a recomendação
  status         TEXT NOT NULL DEFAULT 'Pendente',  -- Pendente / Aplicada / Descartada
  criado_em      TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(tipo, objeto_id)
);
CREATE INDEX IF NOT EXISTS idx_recom_status ON recomendacoes(status, tipo);


-- Fase A — Confiança: verificação de escopo + explicabilidade nas recomendações
ALTER TABLE recomendacoes ADD COLUMN IF NOT EXISTS escopo_selo   TEXT DEFAULT 'nao_verificavel'; -- confere | divergente | nao_verificavel
ALTER TABLE recomendacoes ADD COLUMN IF NOT EXISTS escopo_motivo TEXT;
ALTER TABLE recomendacoes ADD COLUMN IF NOT EXISTS confianca     NUMERIC(4,3);
ALTER TABLE recomendacoes ADD COLUMN IF NOT EXISTS explicacao    JSONB;  -- cadeia de raciocínio (drawer)


-- Fase B — Embeddings: cache dos vetores dos critérios (evita re-embeddar a cada análise)
CREATE TABLE IF NOT EXISTS controle_embeddings(
  chave      TEXT PRIMARY KEY,
  modelo     TEXT NOT NULL,
  txt_hash   TEXT NOT NULL,
  vetor      DOUBLE PRECISION[] NOT NULL,
  criado_em  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ── Fase 3: metas de KRI extraídas das políticas por IA ─────────────────────
-- A IA lê a política e extrai compromissos quantitativos (treinamento 100%,
-- investimento ≥15%, MTTR ≤30d…), rastreáveis à cláusula de origem. Human-in-
-- the-loop: nascem 'pendente' e o usuário aprova. Aprovada, alimenta o KRI.
CREATE TABLE IF NOT EXISTS kri_metas (
  id          SERIAL PRIMARY KEY,
  politica_id UUID REFERENCES politicas(id) ON DELETE CASCADE,
  kri_id      TEXT NOT NULL,
  nome        TEXT NOT NULL,
  valor       NUMERIC NOT NULL,
  comparador  TEXT NOT NULL DEFAULT 'gte',   -- 'gte' | 'lte'
  unidade     TEXT NOT NULL DEFAULT '%',
  categoria   TEXT NOT NULL DEFAULT 'Governança',
  trecho      TEXT,
  realizado   NUMERIC,                        -- valor realizado (entrada manual)
  status      TEXT NOT NULL DEFAULT 'pendente', -- pendente|aprovada|rejeitada
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kri_metas_status ON kri_metas(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_kri_metas_uniq ON kri_metas(politica_id, kri_id);

-- ── Fase 4: histórico de KRIs por período (tendência trimestral) ────────────
-- Snapshot do estado dos KRIs por trimestre. Captura oportunista no load do
-- dashboard (upsert do período atual); períodos passados congelam ao virar o
-- trimestre. Sem depender de cron — o appliance pode não ter scheduler.
CREATE TABLE IF NOT EXISTS kri_snapshots (
  id           SERIAL PRIMARY KEY,
  periodo      TEXT NOT NULL,                 -- '2026-Q3'
  data         DATE NOT NULL DEFAULT CURRENT_DATE,
  atingimento  INTEGER NOT NULL DEFAULT 0,
  verde        INTEGER NOT NULL DEFAULT 0,
  amarelo      INTEGER NOT NULL DEFAULT 0,
  vermelho     INTEGER NOT NULL DEFAULT 0,
  cinza        INTEGER NOT NULL DEFAULT 0,
  detalhe      JSONB,                          -- {kri_id: atingimento}
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_kri_snap_periodo ON kri_snapshots(periodo);

-- ── Roteiro de auditoria (lado do AUDITOR — ISO 19011 / cláusula 9.2) ───────
-- O checklist é GERADO a partir do SOA: cada requisito (4–10) e controle
-- aplicável do Anexo A vira um item a testar, já com o que a organização
-- DECLARA (status, política, evidência). O auditor registra o resultado, a
-- evidência objetiva examinada e a AMOSTRA — sem amostra o achado não é
-- defensável perante a certificadora.
CREATE TABLE IF NOT EXISTS auditoria_roteiro (
  id            SERIAL PRIMARY KEY,
  auditoria_id  INTEGER NOT NULL REFERENCES auditorias(id) ON DELETE CASCADE,
  soa_codigo    TEXT NOT NULL,
  categoria     TEXT NOT NULL,              -- 'requisito' | 'controle'
  ordem         INTEGER NOT NULL DEFAULT 0,
  resultado     TEXT,                        -- NULL = ainda não auditado
  metodo        TEXT,                        -- Entrevista|Observação|Exame documental|Teste
  auditado      TEXT,                        -- quem foi entrevistado
  amostra       TEXT,                        -- "5 de 47 acessos privilegiados"
  evidencia_examinada TEXT,
  anotacoes     TEXT,
  nc_codigo     TEXT,                        -- achado convertido em NC
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_roteiro_uniq ON auditoria_roteiro(auditoria_id, soa_codigo);
CREATE INDEX IF NOT EXISTS idx_roteiro_aud ON auditoria_roteiro(auditoria_id);

-- ── Bloco A: RCA estruturada + ciclo de eficácia (ISO 27001 cl. 10.2) ───────
-- Análise de causa raiz com MÉTODO (5 Porquês / Ishikawa), não só texto livre.
-- Cada NC pode ter uma análise; o conteúdo estruturado fica em JSONB:
--   5 Porquês → {"porques":["...","..."], "causa":"..."}
--   Ishikawa  → {"espinhas":{"Pessoas":["..."],"Processo":["..."],...},"causa":"..."}
ALTER TABLE ncs ADD COLUMN IF NOT EXISTS rca_metodo TEXT;        -- '5porques'|'ishikawa'|'outro'
ALTER TABLE ncs ADD COLUMN IF NOT EXISTS rca_dados JSONB;         -- estrutura da técnica
ALTER TABLE ncs ADD COLUMN IF NOT EXISTS rca_o_que_aconteceu TEXT; -- detalhamento factual

-- Ciclo de eficácia do PLANO de ação (10.2): execução real, validação e eficácia.
ALTER TABLE planos ADD COLUMN IF NOT EXISTS data_execucao DATE;   -- conclusão REAL (≠ data_fim/meta)
ALTER TABLE planos ADD COLUMN IF NOT EXISTS validado_por TEXT;    -- quem confirma que executou
ALTER TABLE planos ADD COLUMN IF NOT EXISTS data_validacao DATE;
ALTER TABLE planos ADD COLUMN IF NOT EXISTS verificar_eficacia BOOLEAN DEFAULT TRUE;
ALTER TABLE planos ADD COLUMN IF NOT EXISTS eficacia_status TEXT; -- Eficaz|Parcialmente Eficaz|Ineficaz|Não Avaliado
ALTER TABLE planos ADD COLUMN IF NOT EXISTS eficacia_verificado_por TEXT; -- auditoria interna/designado
ALTER TABLE planos ADD COLUMN IF NOT EXISTS eficacia_data DATE;
ALTER TABLE planos ADD COLUMN IF NOT EXISTS eficacia_comentario TEXT;

-- ── Refactor Ativos → Ativos de Informação (ISO/IEC 27005) ──────────────────
-- Natureza: ativo PRIMÁRIO (processo/serviço/informação — valor de negócio) vs
-- de SUPORTE (TI/pessoas/instalações que sustentam os primários).
ALTER TABLE ativos ADD COLUMN IF NOT EXISTS natureza TEXT DEFAULT 'Suporte'; -- 'Primário'|'Suporte'

-- Dependências ESTRUTURADAS: um ativo primário depende de ativos de suporte.
-- (o campo texto 'dependencias' antigo continua, como nota livre.) A cadeia
-- permite ver que serviço de negócio para quando um ativo de suporte cai.
CREATE TABLE IF NOT EXISTS ativo_dependencias (
  ativo_codigo    TEXT NOT NULL REFERENCES ativos(codigo) ON DELETE CASCADE,
  depende_de      TEXT NOT NULL REFERENCES ativos(codigo) ON DELETE CASCADE,
  PRIMARY KEY (ativo_codigo, depende_de),
  CHECK (ativo_codigo <> depende_de)
);
CREATE INDEX IF NOT EXISTS idx_ativodep_dependede ON ativo_dependencias(depende_de);

-- ── Bloco B: Contexto & Riscos (ISO 27001 cl. 4 / 6.1 / 6.2 / 6.1.3) ────────
-- Risco deixa de ser só "ameaça de TI": ganha natureza (Ameaça/Oportunidade),
-- contexto (Interno/Externo) e categoria de contexto — o risco de NEGÓCIO.
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS tipo_risco TEXT DEFAULT 'Ameaça';   -- 'Ameaça'|'Oportunidade'
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS contexto TEXT;                       -- 'Interno'|'Externo'
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS categoria_contexto TEXT;             -- Tecnológico, Econômico...
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS objetivo_id INTEGER;                 -- FK objetivos_si (6.2)
-- Aceitação formal do risco (6.1.3): risco aceito sem plano PRECISA de registro.
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS aceito_por TEXT;
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS aceito_data DATE;
ALTER TABLE riscos ADD COLUMN IF NOT EXISTS aceito_justificativa TEXT;

-- Objetivos de Segurança da Informação (6.2) — o risco se alinha a um objetivo.
CREATE TABLE IF NOT EXISTS objetivos_si (
  id           SERIAL PRIMARY KEY,
  codigo       TEXT,
  descricao    TEXT NOT NULL,
  meta         TEXT,                 -- indicador/meta mensurável
  prazo        DATE,
  responsavel  TEXT,
  status       TEXT DEFAULT 'Em andamento',
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Partes Interessadas (4.2) — contexto interno/externo, necessidades e expectativas.
CREATE TABLE IF NOT EXISTS partes_interessadas (
  id           SERIAL PRIMARY KEY,
  nome         TEXT NOT NULL,
  contexto     TEXT DEFAULT 'Externo',   -- 'Interno'|'Externo'
  categoria    TEXT,                       -- Cliente, Regulador, Fornecedor, Colaborador...
  necessidades TEXT,                       -- necessidades e expectativas relevantes ao SGSI
  relevancia   TEXT DEFAULT 'Média',       -- Alta|Média|Baixa
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Bloco C: Gestão de Incidentes (A.5.24–A.5.26 / ISO 27035) ───────────────
-- Distinção EVENTO × INCIDENTE (27035): evento é uma ocorrência observada;
-- incidente é o evento (ou série) que compromete a SI ou ameaça comprometer.
-- SLA de resposta/resolução por criticidade — cobrado automaticamente.
CREATE TABLE IF NOT EXISTS incidentes (
  id            SERIAL PRIMARY KEY,
  codigo        TEXT UNIQUE,
  tipo          TEXT NOT NULL DEFAULT 'Evento',   -- 'Evento' | 'Incidente'
  titulo        TEXT NOT NULL,
  descricao     TEXT,
  categoria     TEXT,                              -- Malware, Acesso indevido, Phishing...
  criticidade   TEXT DEFAULT 'Média',              -- Alta|Média|Baixa (define o SLA)
  ativo_codigo  TEXT REFERENCES ativos(codigo) ON DELETE SET NULL,
  cid_afetado   TEXT[],                            -- C/I/D comprometidos
  detectado_em  TIMESTAMPTZ DEFAULT now(),
  respondido_em TIMESTAMPTZ,                        -- 1º atendimento (SLA de resposta)
  resolvido_em  TIMESTAMPTZ,                        -- encerramento (SLA de resolução)
  status        TEXT DEFAULT 'Aberto',             -- Aberto|Em resposta|Contido|Resolvido|Fechado
  acao          TEXT,                              -- contenção/erradicação/recuperação
  licoes        TEXT,
  nc_codigo     TEXT,                              -- incidente que gerou NC
  reportado_por TEXT,
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_incidentes_tipo ON incidentes(tipo,status);

-- ── Bloco C: Cenários de interrupção + Matriz de Impacto (A.5.29–30 / BIA) ──
CREATE TABLE IF NOT EXISTS cenarios (
  id           SERIAL PRIMARY KEY,
  codigo       TEXT,
  nome         TEXT NOT NULL,
  tipo         TEXT,                 -- Ciberataque, Indisponibilidade, Desastre físico...
  descricao    TEXT,
  probabilidade TEXT DEFAULT 'Média', -- Alta|Média|Baixa
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Impacto de um cenário sobre um ativo (a célula da matriz).
CREATE TABLE IF NOT EXISTS cenario_impactos (
  cenario_id   INTEGER NOT NULL REFERENCES cenarios(id) ON DELETE CASCADE,
  ativo_codigo TEXT NOT NULL REFERENCES ativos(codigo) ON DELETE CASCADE,
  severidade   TEXT DEFAULT 'Médio',  -- Crítico|Alto|Médio|Baixo|Nenhum
  rto          TEXT,                   -- tempo objetivo de recuperação
  rpo          TEXT,                   -- ponto objetivo de recuperação
  efeito       TEXT,                   -- efeito na SI (indisponibilidade, vazamento...)
  PRIMARY KEY (cenario_id, ativo_codigo)
);

-- ── Plano de auditoria (ISO 19011 §6.3) — colunas em auditorias ─────────────
ALTER TABLE auditorias ADD COLUMN IF NOT EXISTS plano_objetivos TEXT;
ALTER TABLE auditorias ADD COLUMN IF NOT EXISTS plano_criterios TEXT;
ALTER TABLE auditorias ADD COLUMN IF NOT EXISTS plano_equipe TEXT;
ALTER TABLE auditorias ADD COLUMN IF NOT EXISTS plano_agenda TEXT;

-- ── Programa de auditoria (cláusula 9.2.2) — o guarda-chuva anual/plurianual ─
CREATE TABLE IF NOT EXISTS auditoria_programa (
  id          SERIAL PRIMARY KEY,
  ano         INTEGER,
  ciclo       TEXT,                 -- 'Anual', 'Semestral'...
  objetivo    TEXT,
  criterios   TEXT,                 -- normas/critérios do programa
  cobertura   TEXT,                 -- o que será auditado no período
  metodos     TEXT,
  recursos    TEXT,
  notas       TEXT,                 -- considera importância dos processos e auditorias anteriores
  criado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Análise Crítica da Direção (cláusula 9.3) — o management review ──────────
-- Entradas (9.3.2) em parte auto-capturadas do sistema; saídas (9.3.3) = decisões.
CREATE TABLE IF NOT EXISTS analises_criticas (
  id            SERIAL PRIMARY KEY,
  codigo        TEXT,
  data          DATE NOT NULL DEFAULT CURRENT_DATE,
  periodo       TEXT,
  participantes TEXT,
  entradas      JSONB,              -- snapshot dos indicadores do SGSI
  acoes_anteriores TEXT,            -- status das ações da análise anterior (9.3.2a)
  mudancas_contexto TEXT,           -- mudanças internas/externas e partes interessadas (9.3.2b/c)
  feedback_partes  TEXT,
  entradas_notas TEXT,              -- comentários sobre o desempenho de SI (9.3.2d)
  decisoes      TEXT,               -- 9.3.3: oportunidades de melhoria contínua
  mudancas_sgsi TEXT,               -- 9.3.3: necessidades de mudança no SGSI
  proxima       DATE,
  status        TEXT DEFAULT 'Realizada',
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS risco_codigo TEXT;  -- backlink incidente→risco gerado

-- v2.6 — Ponte Contexto↔Ativos (fio dourado 4.2): a exigência da parte
-- interessada justifica a criticidade do ativo. N:N parte × ativo.
CREATE TABLE IF NOT EXISTS parte_ativos(
  id           BIGSERIAL PRIMARY KEY,
  parte_id     BIGINT NOT NULL REFERENCES partes_interessadas(id) ON DELETE CASCADE,
  ativo_codigo TEXT   NOT NULL REFERENCES ativos(codigo) ON DELETE CASCADE,
  pilar        TEXT,                       -- pilar CID que a parte exige (opcional)
  criado_em    TIMESTAMPTZ DEFAULT now(),
  UNIQUE(parte_id, ativo_codigo)
);
CREATE INDEX IF NOT EXISTS idx_parte_ativos_ativo ON parte_ativos(ativo_codigo);
BEGIN;
-- v2.7 LGPD: catálogo saneado (ótica do Encarregado)
-- 1) Remove o que NÃO é obrigação da organização (poderes/competências da ANPD)
DELETE FROM avaliacoes WHERE controle_id IN (SELECT id FROM fw_controles WHERE framework_codigo='lgpd' AND codigo IN ('Art.52','Art.53','Art.55'));
DELETE FROM fw_controles WHERE framework_codigo='lgpd' AND codigo IN ('Art.52','Art.53','Art.55');

-- 2) Inclui as obrigações que faltavam
INSERT INTO fw_controles (framework_codigo,codigo,dominio,subdominio,titulo,descricao,ordem) VALUES
('lgpd','Art.6','Princípios','Princípios','Princípios do tratamento de dados pessoais','Finalidade, adequação, necessidade, livre acesso, qualidade, transparência, segurança, prevenção, não discriminação e responsabilização (accountability). É a régua que a ANPD usa para julgar todo tratamento.',0),
('lgpd','Art.15','Ciclo de Vida','Término','Término do tratamento de dados','O tratamento se encerra quando a finalidade é alcançada, os dados deixam de ser necessários, o consentimento é revogado ou por determinação da autoridade. Exige gatilho e registro.',20),
('lgpd','Art.16','Ciclo de Vida','Eliminação','Eliminação dos dados após o término','Os dados devem ser eliminados após o término do tratamento, salvo hipóteses de guarda legal, estudo por órgão de pesquisa, transferência a terceiro ou uso exclusivo anonimizado. Exige prazo de retenção definido por atividade.',21),
('lgpd','Art.19','Direitos','Prazos','Prazos e forma de resposta ao titular','Confirmação de existência e acesso: formato simplificado imediato ou declaração completa em até 15 dias da requisição. O prazo é contado e auditável.',22),
('lgpd','Art.46.2','Segurança','Privacy by Design','Privacidade desde a concepção e por padrão','As medidas de segurança devem ser observadas DESDE A FASE DE CONCEPÇÃO do produto ou serviço até a sua execução (Art. 46, §2º). É obrigação legal, não recomendação: exige avaliação de privacidade antes de novos projetos, sistemas e mudanças.',23),
('lgpd','Art.50','Governança','Governança','Programa de governança em privacidade e boas práticas','Regras de boas práticas e governança: políticas, salvaguardas, planos de resposta, treinamento, supervisão interna e mitigação de riscos — a base da demonstração de accountability.',24)
ON CONFLICT (framework_codigo,codigo) DO NOTHING;

-- 3) Descrições dos artigos que já existiam (estavam TODOS vazios)
UPDATE fw_controles SET descricao='Hipóteses que autorizam o tratamento: consentimento, obrigação legal, políticas públicas, estudos, execução de contrato, exercício de direitos, proteção da vida, tutela da saúde, legítimo interesse e proteção do crédito. Toda atividade do RoPA precisa de uma base legal declarada.' WHERE framework_codigo='lgpd' AND codigo='Art.7';
UPDATE fw_controles SET descricao='Dados sensíveis (origem racial, convicção religiosa, opinião política, saúde, vida sexual, genético, biométrico) só podem ser tratados nas hipóteses específicas do Art. 11, com consentimento específico e destacado quando aplicável.' WHERE framework_codigo='lgpd' AND codigo='Art.11';
UPDATE fw_controles SET descricao='Direitos do titular: confirmação, acesso, correção, anonimização/bloqueio/eliminação, portabilidade, eliminação de dados consentidos, informação sobre compartilhamento, informação sobre negar consentimento e revogação. Exige canal de atendimento e registro.' WHERE framework_codigo='lgpd' AND codigo='Art.18';
UPDATE fw_controles SET descricao='O titular pode solicitar revisão de decisões tomadas unicamente com base em tratamento automatizado que afetem seus interesses, e o controlador deve informar os critérios e procedimentos utilizados.' WHERE framework_codigo='lgpd' AND codigo='Art.20';
UPDATE fw_controles SET descricao='O consentimento deve ser por escrito ou meio que demonstre a manifestação, destacado das demais cláusulas, para finalidades determinadas, e o ônus da prova é do controlador. Consentimento genérico é nulo.' WHERE framework_codigo='lgpd' AND codigo='Art.8';
UPDATE fw_controles SET descricao='Dados de crianças e adolescentes: tratamento no melhor interesse, com consentimento específico e destacado por ao menos um dos pais ou responsável legal, e informação em linguagem acessível.' WHERE framework_codigo='lgpd' AND codigo='Art.9';
UPDATE fw_controles SET descricao='Controlador e operador devem manter registro das operações de tratamento (RoPA), especialmente quando baseadas em legítimo interesse. É o inventário do qual dependem direitos, retenção, RIPD e resposta a incidentes.' WHERE framework_codigo='lgpd' AND codigo='Art.37';
UPDATE fw_controles SET descricao='A ANPD pode determinar ao controlador a elaboração de Relatório de Impacto à Proteção de Dados (RIPD), incluindo dados sensíveis, com descrição dos tratamentos, salvaguardas e mecanismos de mitigação de risco.' WHERE framework_codigo='lgpd' AND codigo='Art.38';
UPDATE fw_controles SET descricao='O operador deve realizar o tratamento segundo as instruções do controlador, que verificará a observância. Exige contrato/DPA e controle sobre suboperadores.' WHERE framework_codigo='lgpd' AND codigo='Art.39';
UPDATE fw_controles SET descricao='A ANPD pode dispor sobre padrões de interoperabilidade para portabilidade, livre acesso e segurança, considerando o porte dos agentes e o volume de dados.' WHERE framework_codigo='lgpd' AND codigo='Art.40';
UPDATE fw_controles SET descricao='Medidas de segurança técnicas e administrativas aptas a proteger os dados de acessos não autorizados e de destruição, perda, alteração ou tratamento ilícito.' WHERE framework_codigo='lgpd' AND codigo='Art.46';
UPDATE fw_controles SET descricao='Controlador e operador devem garantir a segurança da informação mesmo após o término do tratamento.' WHERE framework_codigo='lgpd' AND codigo='Art.47';
UPDATE fw_controles SET descricao='Comunicação de incidente que possa acarretar risco ou dano relevante: à ANPD e ao titular em até 3 DIAS ÚTEIS do conhecimento (Res. CD/ANPD 15/2024), com complementação em até 20 dias úteis. O registro do incidente deve ser guardado por 5 anos, mesmo quando não comunicado.' WHERE framework_codigo='lgpd' AND codigo='Art.48';
UPDATE fw_controles SET descricao='Designação formal do encarregado (DPO), com identidade e informações de contato DIVULGADAS PUBLICAMENTE. Atribuições: aceitar reclamações de titulares, receber comunicações da ANPD e orientar colaboradores e contratados.' WHERE framework_codigo='lgpd' AND codigo='Art.41';
UPDATE fw_controles SET descricao='O agente que causar dano patrimonial, moral, individual ou coletivo em violação à LGPD é obrigado a repará-lo, com responsabilidade solidária entre controlador e operador nas hipóteses da lei.' WHERE framework_codigo='lgpd' AND codigo='Art.42';
UPDATE fw_controles SET descricao='Transferência internacional só é permitida nas hipóteses do Art. 33 (país com nível adequado, cláusulas-padrão contratuais, normas corporativas globais, selos, consentimento específico, entre outras).' WHERE framework_codigo='lgpd' AND codigo='Art.33';
UPDATE fw_controles SET descricao='O nível de proteção adequado do país de destino é avaliado pela ANPD considerando normas gerais e setoriais, natureza dos dados, garantias e medidas de segurança vigentes.' WHERE framework_codigo='lgpd' AND codigo='Art.34';

UPDATE frameworks SET total_controles=(SELECT count(*) FROM fw_controles WHERE framework_codigo='lgpd'),
       descricao='Lei Geral de Proteção de Dados Pessoais — obrigações da organização (princípios, bases legais, direitos do titular, RoPA, encarregado, incidentes e governança).'
 WHERE codigo='lgpd';
COMMIT;
BEGIN;
UPDATE fw_controles SET dominio='Encarregado' WHERE framework_codigo='lgpd' AND dominio='ENCARREGADO';

-- ── RoPA (Art. 37): atividade de tratamento pendurada no ATIVO PRIMÁRIO ──
CREATE TABLE IF NOT EXISTS ropa_atividades(
  id                 BIGSERIAL PRIMARY KEY,
  codigo             TEXT UNIQUE,
  nome               TEXT NOT NULL,
  ativo_codigo       TEXT REFERENCES ativos(codigo) ON DELETE SET NULL,
  papel              TEXT DEFAULT 'Controlador',      -- Controlador | Operador | Ambos
  finalidade         TEXT,
  base_legal         TEXT,                            -- Art. 7º
  base_legal_sensivel TEXT,                           -- Art. 11 (se houver dados sensíveis)
  lia_realizado      BOOLEAN DEFAULT FALSE,           -- teste de balanceamento (legítimo interesse)
  categorias_dados   TEXT,
  categorias_titulares TEXT,
  qtd_titulares      TEXT,
  dados_sensiveis    BOOLEAN DEFAULT FALSE,
  dados_criancas     BOOLEAN DEFAULT FALSE,
  decisao_automatizada BOOLEAN DEFAULT FALSE,         -- Art. 20
  compartilhamento   TEXT,                            -- destinatários
  operadores         TEXT,                            -- suboperadores / Art. 39
  transferencia_internacional BOOLEAN DEFAULT FALSE,  -- Art. 33
  paises             TEXT,
  salvaguarda_transferencia TEXT,
  retencao_prazo     TEXT,                            -- Art. 15/16
  eliminacao_forma   TEXT,
  medidas_seguranca  TEXT,                            -- Art. 46
  ripd_necessario    BOOLEAN DEFAULT FALSE,           -- Art. 38
  ripd_link          TEXT,
  responsavel        TEXT,
  status             TEXT DEFAULT 'Ativa',            -- Ativa | Suspensa | Encerrada
  revisado_em        DATE,
  criado_em          TIMESTAMPTZ DEFAULT now(),
  atualizado_em      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ropa_ativo ON ropa_atividades(ativo_codigo);

-- ── Extensão de PRIVACIDADE na ocorrência (incidente Art.48 / DSAR Art.18-19) ──
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS envolve_dados_pessoais BOOLEAN DEFAULT FALSE;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS titulares_afetados     TEXT;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS qtd_titulares          INTEGER;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS risco_relevante        BOOLEAN;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS anpd_comunicado_em     DATE;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS anpd_protocolo         TEXT;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS titulares_comunicados_em DATE;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS ropa_id                BIGINT REFERENCES ropa_atividades(id) ON DELETE SET NULL;
-- solicitação de titular (nova natureza no intake unificado)
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS titular_nome           TEXT;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS titular_contato        TEXT;
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS direito_solicitado     TEXT;   -- Art. 18
ALTER TABLE incidentes ADD COLUMN IF NOT EXISTS respondido_titular_em  DATE;

-- ── Encarregado (Art. 41): registro único, chave/valor já existente em config ──
COMMIT;

-- ── Marcador "onde parei" na avaliação de maturidade ───────────────────────
-- Fica no servidor (e não no navegador) para acompanhar o avaliador se ele
-- trocar de máquina. Uma linha por usuário × framework.
CREATE TABLE IF NOT EXISTS avaliacao_marcador(
  usuario          TEXT NOT NULL,
  framework_codigo TEXT NOT NULL,
  controle_id      BIGINT,
  atualizado_em    TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY(usuario, framework_codigo)
);

-- ── Anexos da Análise Crítica (9.3): a ata É a informação documentada exigida ──
CREATE TABLE IF NOT EXISTS analise_critica_anexos(
  id            BIGSERIAL PRIMARY KEY,
  analise_id    INTEGER NOT NULL REFERENCES analises_criticas(id) ON DELETE CASCADE,
  nome_original TEXT,
  arquivo       TEXT,
  url           TEXT,
  hash_sha256   TEXT,
  texto         TEXT,                       -- extraído (PDF/DOCX/TXT) ou OCR
  evidencia_id  UUID,                       -- quando também publicada em Evidências
  criado_em     TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ac_anexo ON analise_critica_anexos(analise_id);

-- ── Distingue desativação por LICENÇA de desativação pelo ADMINISTRADOR ─────
-- Sem isso, renovar a licença com escopo maior não devolvia os frameworks: a
-- aplicação só sabia desativar, nunca reativar, e o cliente ficava sem ver o
-- que acabou de contratar.
ALTER TABLE frameworks ADD COLUMN IF NOT EXISTS desativado_por_licenca BOOLEAN DEFAULT FALSE;
