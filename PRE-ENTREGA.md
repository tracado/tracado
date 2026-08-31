# Checklist de Pré-Entrega — Traçado

> Itens **obrigatórios** antes de entregar o appliance a um cliente.
> Nada aqui deve ser feito durante o desenvolvimento (só gera fricção) — mas
> **nenhum** item pode ir para produção com o default de dev. Marque tudo antes do envio.

---

## 1. Segredos e `.env` (nunca entregar defaults de dev)

O `generate-secrets.sh` cobre parte, mas **não gera dois segredos críticos**. Confira um a um:

- [x] ~~`LICENSE_SIGNING_KEY`~~ — **não existe mais.** A assinatura passou a ser
      Ed25519: o appliance carrega só `LICENSE_PUBLIC_KEY`, e a privada nunca
      sai do licenciador. Não há segredo de assinatura no `.env` do cliente.
- [ ] `FLASK_SECRET_KEY` — **NÃO** pode ficar no default `tracado-v2-secret`
      (fallback no código do portal). Defina no `.env`: `openssl rand -hex 32`.
      *(Também não é coberto pelo generate-secrets.sh.)*
- [ ] `POSTGRES_PASSWORD`, `KEYCLOAK_ADMIN_PASSWORD`, `KEYCLOAK_CLIENT_SECRET`,
      `MASTER_PASSWORD`, `OAUTH2_PROXY_COOKIE_SECRET` — rodar `./generate-secrets.sh`
      e confirmar que **nenhum** ficou `CHANGE_ME`.
- [ ] `MASTER_EMAIL` — trocar `admin@sgsi.local` pelo e-mail real do admin do cliente.
- [ ] Conferência final: `grep -n 'CHANGE_ME\|padrao\|tracado-v2-secret' .env` deve vir **vazio**.

## 2. Não incluir no pacote entregue

- [x] ~~Remover a pasta `scripts/`~~ — o gerador de licenças saiu do repositório.
      O que resta em `scripts/` é ferramenta de instalação e diagnóstico, útil ao
      cliente: build-release, confiar-ca, render-keycloak-realm, set-env, status-report.
- [ ] Remover artefatos soltos que não fazem parte do runtime:
      `tracado-v2.0 (2).zip`, `grc-platform.html` (protótipo antigo).
- [ ] Nunca incluir a **chave privada** de licença (ver item 4) no pacote do cliente.

## 3. Dados

- [ ] Decidir se entrega **com dados de demonstração** (`postgres/03_demo.sql`) ou
      **limpo**. Para produção real, normalmente subir sem o demo (ou resetar depois).
- [ ] Se reinstalar do zero para limpar: `./install.sh local --reset` (⚠ apaga o banco).

## 4. Endurecimento do licenciamento (adiado do dev — fazer agora)

- [x] **Migrar HMAC → Ed25519** — FEITO (assinatura assimétrica). A privada fica só com você;
      o appliance recebe **apenas a chave pública**. Assim o cliente não consegue
      forjar licença mesmo tendo o código e o `.env`. *(Ver conversa/decisão de projeto.)*
      - Remover `LICENSE_SIGNING_KEY` do `.env` do cliente; trocar por `LICENSE_PUBLIC_KEY`.
- [x] **Entregar imagem Docker pré-buildada**, não o código-fonte — feito: o compose
      puxa `ghcr.io/tracado/tracado-portal` e o código vive em repositório privado.
      Dificulta adulterar o `licenca.py` para burlar o check. Distribuir `.pyc`.
- [ ] **(Opcional) Vínculo por install_id** — a chave carrega um id da instalação e o
      appliance recusa se não bater; impede reuso de licença vazada em outra instalação.
- [x] ~~Senha de emissão do gerador local~~ — o gerador foi removido. A emissão
      acontece no **licenciador** (repositório privado), protegido por login.

## 5. Produção / rede

- [ ] Rodar `./configurar-dominio.sh grc.cliente.com.br` (HTTPS automático via Let's Encrypt).
- [ ] Confirmar `OAUTH2_COOKIE_SECURE=true` (o configurar-dominio.sh ajusta).
- [ ] DNS dos 2 registros apontando e portas 80/443 abertas.
- [ ] No Keycloak: política de senha, MFA/OTP e defesa contra força bruta habilitados.

## 6. Verificação final (fumaça)

- [ ] Subir limpo, logar com o admin, aplicar a licença gerada e confirmar que o
      plano correto ativa os frameworks certos.
- [ ] Testar um framework **fora do plano** → deve aparecer 🔒 e bloquear a rota.
- [ ] Confirmar que a tela de login usa o tema `tracado` e que não há chamada a CDN externa.
