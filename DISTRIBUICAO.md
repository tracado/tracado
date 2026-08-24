# Distribuição do Traçado

## O que o cliente recebe

Uma **imagem assinada**, não o repositório. O `install.sh` puxa a imagem do
registro em vez de construir a partir do código.

```
ghcr.io/tracado/tracado-portal:<versão>
```

A imagem carrega a procedência nos rótulos OCI: versão, **commit exato**, data
de build e um id de build. Pegando um contêiner rodando em qualquer cliente,
volta-se ao commit que o gerou:

```bash
docker image inspect ghcr.io/tracado/tracado-portal:2.1.0 \
  --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

## Como gerar um release

```bash
VERSION=2.1.0 PUBLICAR=sim scripts/build-release.sh
```

O script recusa seguir em silêncio se a árvore de trabalho estiver suja —
imagem gerada de código não commitado não tem procedência verificável, porque o
commit gravado não descreve o que foi construído.

Com `PUBLICAR=sim` ele envia ao registro e assina com **cosign**. Sem cosign
instalado, ele publica e avisa em letras claras que a imagem saiu sem
assinatura.

O cliente verifica com:

```bash
cosign verify ghcr.io/tracado/tracado-portal@sha256:<digest> \
  --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*'
```

## Compilação do miolo

A imagem distribuída **não contém o código-fonte** dos módulos onde mora a
decisão de negócio. O build tem dois estágios: o primeiro compila com Cython,
o segundo monta a imagem final só com os binários.

Compilados: `calc`, `reports`, `analise_ia`, `recomendacoes`, `licenca`,
`ia_llm` — 4.680 linhas. Verificável na imagem:

```bash
docker run --rm --entrypoint sh <imagem> -c "ls /app/*.py /app/*.so"
```

Ficam legíveis por opção: `app.py` (rotas) e o encanamento. **Não são
protegidos** os templates Jinja e o esquema do banco. A compilação eleva o
custo de cópia; não a torna impossível.

## Marca da instância

Toda instalação exibe, no rodapé de cada tela e no cabeçalho de **cada
relatório impresso ou salvo em PDF**:

```
Traçado v2.1.0 · Licenciado para <cliente> · LIC-000123 · instância C3D3E2957821
```

A impressão da instância é derivada da **licença assinada** (cliente + código
emitido) mais um identificador local gerado uma vez. Isso importa: falsificar a
marca exige falsificar a assinatura Ed25519 — a marca não é enfeite, é a mesma
prova que autoriza o uso.

Licença de parceiro acrescenta uma tarja que acompanha o papel:

```
Instância de DEMONSTRAÇÃO · <parceiro> — não destinada a produção
```

O efeito é comportamental antes de ser técnico: quem sabe que a cópia é
rastreável até ele se comporta diferente.

## Onde cada coisa roda

| componente | onde | vai para o cliente? |
|---|---|---|
| Imagem do portal | registro do fornecedor | sim, assinada |
| Compose, Caddy, realm, instaladores | repositório público | sim |
| `licenciador/` (chave privada Ed25519) | infra do fornecedor | **nunca** |
| Registro de licenças emitidas | banco do licenciador | **nunca** |
