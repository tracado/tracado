# Guia de cada tela

O que você faz em cada lugar, o que o sistema faz sozinho e o que ele vai
cobrar de você.

## Visão geral

### Dashboard
**Você faz:** nada, é leitura.
**O sistema faz:** resume o estado do SGSI e monta um briefing determinístico
com até três prioridades, correlacionando problema-raiz.
**O sistema cobra:** indicador sem base de dados aparece como "sem dados", em
cinza — nunca em verde. Verde significa medido e dentro da meta.

### Postura GRC
**O sistema faz:** mostra cada framework na natureza dele — ISO por
certificação, CIS por Grupo de Implementação, NIST por função.
**O sistema cobra:** não existe número único somando normas diferentes; seria
média de coisas incomparáveis.

### Frameworks GRC — 6.1.3, 9.1
**Você faz:** avalia a maturidade de cada controle (0 a 5, CMMI) e define a meta.
**O sistema faz:** salva a cada clique, sem botão de gravar; guarda onde você
parou; propõe o mapeamento entre normas.
**O sistema cobra:** framework fora do escopo contratado mostra a cobertura que
ele já herdaria — não é cadeado cego.

### Análise de GAP
**O sistema faz:** ordena a fila por obrigatoriedade, depois risco, depois
distância até a meta.
**O sistema cobra:** requisito mandatório das cláusulas 4 a 10 não atendido
aparece como bloqueador da certificação.

### Relatórios
**O sistema faz:** produz os seis relatórios que um auditor externo pede, com a
marca da instância no cabeçalho.
**O sistema cobra:** o relatório de evolução não traça tendência com um ponto só.

## O SGSI

### Ativos de Informação — A.5.9, A.5.29, ISO 27005
**Você faz:** cadastra ativos primários e de suporte, com dono, criticidade, CID
e dependências.
**O sistema faz:** calcula a saúde de cada ativo somando riscos, NCs e planos
atrasados dele; mostra o RoPA e os cenários de continuidade ali dentro.
**O sistema cobra:** a distinção primário × suporte.

### Contexto do SGSI — 4.1, 4.2, 6.2
**Você faz:** declara partes interessadas com suas exigências e os objetivos de
segurança com meta e prazo.
**O sistema faz:** transforma objetivo e expectativa em risco, herdando o texto.
**O sistema cobra:** objetivo precisa de meta e prazo.

### Análise de Riscos — 6.1.2, 6.1.3
**Você faz:** avalia probabilidade e impacto inerentes, escolhe o tratamento e o
controle, e reavalia o residual.
**O sistema faz:** calcula o nível, monta a matriz clicável e gera plano ou NC.
**O sistema cobra:** aceitar risco exige aprovador nomeado e data (6.1.3f).

### Eventos & Não Conformidades — A.5.24–27, 10.1, LGPD Art. 48
**Você faz:** registra o que aconteceu ou foi encontrado e classifica a natureza.
**O sistema faz:** sugere o risco relacionado; se envolve dado pessoal, inicia
os prazos legais contando dias úteis, com feriados nacionais.
**O sistema cobra:** encerrar NC exige causa raiz registrada e eficácia
avaliada. E avisa se a mesma causa já apareceu antes.

### Planos de Ação — 6.1.3, 10.2
**Você faz:** define o que será feito, por quem e até quando.
**O sistema faz:** marca o atraso sozinho e mostra o plano na NC, no risco, no
ativo e no painel.
**O sistema cobra:** plano sem dono e sem prazo não é plano, é intenção.

### Políticas & Normativos — 7.5, A.5.1
**Você faz:** publica os documentos e amarra cada um aos controles que cobre.
**O sistema faz:** eleva o controle a "Documentado" e propaga a cobertura para
os frameworks equivalentes.
**O sistema cobra:** documento não vira implementação.

### Evidências — A.5.37, 9.1
**Você faz:** anexa a prova operacional, com data de coleta e periodicidade.
**O sistema faz:** lê o conteúdo (PDF, Word, PowerPoint, TXT; imagem por OCR) e
sugere os controles cobertos.
**O sistema cobra:** a sugestão é para você confirmar, nunca automática. E
evidência vencida deixa de contar como cobertura.

### Auditoria Interna — 9.2
**Você faz:** planeja o escopo, designa o auditor e registra achados com método
e amostra.
**O sistema faz:** gera o roteiro do que a organização declarou no SOA e
converte achado em NC com o contexto.
**O sistema cobra:** sinaliza conflito de imparcialidade (9.2.2c) e exige
parecer do auditor antes de concluir.

### Análise Crítica — 9.3
**Você faz:** registra a reunião da direção, anexa a ata e escreve as decisões.
**O sistema faz:** congela um retrato dos indicadores e confere a ata contra as
oito entradas da 9.3, citando o trecho de cada uma.
**O sistema cobra:** sem ata anexada, a 9.3 fica sem a informação documentada
que ela exige reter.

### Privacidade (LGPD) — Art. 37, 41, 48
**Você faz:** mantém o RoPA dentro dos ativos primários e designa o Encarregado.
**O sistema faz:** conta os prazos legais e mostra o que está por vencer.
**O sistema cobra:** dado sensível exige base do Art. 11, não do Art. 7.
Legítimo interesse exige o teste de balanceamento.

## Três coisas que valem saber

**A inteligência artificial roda na sua máquina.** Nenhum conteúdo do seu SGSI
sai da sua rede. Desligando o serviço de IA, o produto continua funcionando
inteiro — ela é acessória, não estrutural.

**O que a IA sugere, você confirma.** Correlação de evidência, rascunho de
parecer e proposta de mapeamento são sugestões. Medimos o acerto contra um
conjunto de documentos rotulados à mão: ela acerta a maioria e recusa o que não
é evidência, mas erra o suficiente para que a confirmação humana não seja
opcional.

**Seus dados são seus.** Cada registro tem exportação em CSV, e a exportação
continua disponível mesmo com a licença vencida — nesse caso o sistema entra em
somente leitura, sem nunca reter o que é seu.
