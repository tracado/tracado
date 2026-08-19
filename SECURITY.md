# Política de Segurança — GRC Hub

## Como reportar uma vulnerabilidade

Reporte por e-mail para **seguranca@grchub.com.br**, de preferência com:

- o que acontece e o impacto (o que um atacante consegue fazer);
- como reproduzir, passo a passo;
- a versão do GRC Hub (rodapé de qualquer tela) e o sistema operacional do host;
- se conhecido, o componente afetado.

**Não abra issue pública** para vulnerabilidade. Se o achado envolver dados de
um cliente, não inclua os dados no relato — descreva o caminho e nós reproduzimos.

**Prazos de resposta:** confirmação de recebimento em até 3 dias úteis; avaliação
inicial com severidade e plano em até 10 dias úteis; correção conforme a
severidade (crítica: correção emergencial; alta: próxima versão; demais:
planejada). Informamos o andamento a cada 15 dias até o encerramento.

Agradecemos publicamente quem reporta, se assim desejar. Não há programa de
recompensa financeira.

## Versões suportadas

Recebe correção de segurança a versão **2.1** e a versão imediatamente anterior
em uso por cliente ativo. Instalações com licença vencida continuam recebendo
correção crítica de segurança — segurança não é funcionalidade de plano.

## Superfície e postura do produto

O GRC Hub é um appliance **auto-hospedado**: roda inteiro na infraestrutura do
cliente, sem telemetria e sem envio de dados para o fornecedor. A camada de IA é
local (Ollama), portanto **nenhum conteúdo do SGSI sai da rede do cliente**.

Arquitetura de defesa:

- **Autenticação** por Keycloak (OIDC) com oauth2-proxy à frente do portal. O
  portal não trata senha.
- **Segredo de gateway** (`PORTAL_SHARED_SECRET`): o portal recusa requisição que
  não venha do proxy, e os cabeçalhos de identidade vindos de fora são
  removidos — impede falsificação de identidade por header.
- **CSRF** por verificação de origem em todo método que altera estado.
- **TLS** obrigatório; o instalador gera e confia numa CA local, e o assistente
  de domínio troca por certificado do cliente (Let's Encrypt, upload ou CA
  interna).
- **Trilha de auditoria** de toda ação relevante, incluindo exportações,
  avaliações por controle e bloqueios de CSRF.
- **Contêiner do portal em modo somente leitura**, sem escrita no sistema de
  arquivos além dos volumes declarados.

## O que consideramos vulnerabilidade

Acesso a dados de outro usuário ou de outra instância, execução de código,
escalonamento de privilégio, contorno de autenticação, injeção (SQL, comando,
template), leitura de arquivo arbitrário, e falsificação de licença que conceda
escopo não contratado.

## O que não consideramos

Ausência de cabeçalho de segurança sem impacto demonstrável, resultado bruto de
scanner sem prova de exploração, engenharia social, negação de serviço por
volume, e a leitura do código-fonte — que é intencional: o produto é
source-available (ver LICENSE).
