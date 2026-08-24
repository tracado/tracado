# Como publicar no GitHub — passo a passo

Escrito para quem nunca fez. Cada comando aparece inteiro e explicado. **Você
executa; nada aqui acontece sozinho.**

Ao final você terá:

- três repositórios (um público, dois privados);
- um site de documentação no ar, hospedado de graça pelo próprio GitHub;
- e nenhum segredo publicado.

---

## Antes de começar

**Você precisa de:** uma conta no GitHub (github.com, gratuita) e o Git
instalado — no macOS ele já vem; confira com `git --version`.

**Um conceito só, para o resto fazer sentido.** O Git guarda o histórico do seu
projeto **na sua máquina**. O GitHub é um lugar na internet onde você guarda uma
**cópia** desse histórico. Os três repositórios já existem aqui e já têm
histórico; falta só criar o espelho lá e mandar a cópia. Isso se chama *push*.

---

## Etapa 1 — Autenticar sua máquina no GitHub

Sem isso, o GitHub não sabe que é você e recusa o envio.

**1.1** Instale o cliente oficial do GitHub:

```bash
brew install gh
```

Se não tiver o Homebrew, instale antes com o comando de https://brew.sh.

**1.2** Faça login:

```bash
gh auth login
```

Ele faz perguntas no terminal. Responda:

- *What account do you want to log into?* → **GitHub.com**
- *What is your preferred protocol?* → **HTTPS**
- *Authenticate Git with your GitHub credentials?* → **Yes**
- *How would you like to authenticate?* → **Login with a web browser**

Ele mostra um código de oito caracteres (algo como `1A2B-3C4D`) e abre o
navegador. Cole o código lá, confirme, e volte ao terminal. Deve aparecer
`✓ Logged in as seu-usuario`.

**1.3** Confirme:

```bash
gh auth status
```

---

## Etapa 2 — Criar os dois repositórios PRIVADOS

Comece pelos privados. Se algo der errado, nada sensível estará exposto.

**2.1 — O portal (o miolo do produto):**

```bash
cd ~/tracado-portal
gh repo create tracado-portal --private --source=. --remote=origin --push
```

Lendo o comando: `--private` cria fechado; `--source=.` diz que o conteúdo é
esta pasta; `--remote=origin` registra o endereço remoto; `--push` já envia.

**2.2 — O licenciador:**

```bash
cd ~/tracado-licenciador
gh repo create tracado-licenciador --private --source=. --remote=origin --push
```

**2.3 — Confirme que estão privados:**

```bash
gh repo view tracado-portal --json isPrivate,url
gh repo view tracado-licenciador --json isPrivate,url
```

Ambos devem responder `"isPrivate": true`. **Se algum vier `false`, pare e
avise** — o miolo do produto não pode ficar público.

---

## Etapa 3 — Conferir o repositório PÚBLICO antes de publicar

Este é o único irreversível: uma vez público, considere que alguém já copiou.

**3.1** Veja exatamente o que sairá:

```bash
cd ~/tracado
git ls-files
```

**3.2** Confirme que nada sensível está na lista:

```bash
git ls-files | grep -E "^dashboard/|^licenciador/|\.env$|\.priv$|^backups/" || echo "LIMPO"
```

Precisa imprimir **LIMPO**. Se imprimir qualquer arquivo, **pare**.

**3.3** Só então crie e publique:

```bash
gh repo create tracado --public --source=. --remote=origin --push
```

---

## Etapa 4 — O site de documentação (GitHub Pages)

O GitHub publica um site a partir de uma pasta do repositório, de graça. O
endereço será `https://SEU-USUARIO.github.io/tracado/`.

**4.1** A pasta `docs/` já está pronta neste repositório, com a documentação
convertida do produto. Confirme:

```bash
ls ~/tracado/docs
```

**4.2** Ligue o Pages:

```bash
cd ~/tracado
gh api -X POST repos/:owner/tracado/pages -f "source[branch]=main" -f "source[path]=/docs"
```

Se disser que já existe, está ligado — siga.

**4.3** Espere de um a dois minutos e veja o endereço:

```bash
gh api repos/:owner/tracado/pages --jq .html_url
```

Abra no navegador. Se aparecer 404, espere mais um minuto: a primeira
publicação demora.

**Pelo site do GitHub**, se preferir o caminho visual: abra o repositório →
**Settings** → **Pages** (menu da esquerda) → em *Source* escolha **Deploy from
a branch** → *Branch*: **main**, pasta **/docs** → **Save**.

---

## Etapa 5 — O dia a dia, daqui em diante

Trabalhou no código, quer mandar para o GitHub:

```bash
cd ~/tracado-portal      # ou o repositório que você mexeu
git status               # o que mudou
git add -A               # marca tudo para o próximo commit
git commit -m "descreva em uma linha o que mudou"
git push
```

**Regra de ouro:** rode `git status` antes de `git add -A` e leia a lista. É o
momento em que um arquivo indevido é pego.

---

## Se der errado

**"Permission denied" ou "authentication failed"** → refaça a Etapa 1.2.

**Publiquei algo errado no repositório público** → o arquivo continua no
histórico mesmo se apagado depois. Torne o repositório privado imediatamente
(`gh repo edit tracado --visibility private`), **troque qualquer segredo que
tenha vazado** — ele deve ser considerado comprometido — e só então limpe o
histórico.

**"failed to push some refs"** → alguém (ou outra máquina sua) enviou algo
antes. Traga a alteração e mande de novo:

```bash
git pull --rebase
git push
```

---

## O que NUNCA vai para o GitHub

| arquivo | por quê |
|---|---|
| `.env` e `.env.bak` | senhas do banco, do Keycloak e segredos de sessão |
| `backups/` | dumps do banco, com dados reais de cliente |
| `uploads/` | evidências enviadas pelos usuários |
| `*.priv` | a chave privada Ed25519 que assina as licenças |
| `dashboard/` e `licenciador/` no repositório público | são os repositórios privados |

Os arquivos `.gitignore` de cada repositório já bloqueiam tudo isso. A conferência
da Etapa 3.2 existe porque conferir custa dez segundos e o erro custa caro.
