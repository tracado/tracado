# Instalação

O GRC Hub roda em Docker. O instalador cuida de tudo, inclusive de instalar o
Docker se ele não existir.

## Linux e macOS

```bash
git clone https://github.com/GRCHUB/grc-hub.git
cd grc-hub
./install.sh
```

## Windows

Baixe o repositório, clique com o botão direito em `install.bat` e escolha
**Executar como administrador**.

O instalador prepara o WSL2 e o Docker Engine dentro dele. Não é necessário
Docker Desktop — e por isso não há a exigência de licença comercial que ele
impõe a empresas maiores.

## Depois de instalar

Abra <https://localhost>. O instalador cria e confia numa autoridade
certificadora local, então o navegador não reclama do certificado.

Sem chave de licença, o sistema sobe na **Edição Comunidade** — ISO 27001 e
LGPD completos, sem prazo.

## Trocar para o seu domínio

Dentro do produto: **Administração → Domínio & Certificado**. Três caminhos:
Let's Encrypt, certificado próprio enviado por upload, ou autoridade
certificadora interna da empresa. Não é preciso mexer em arquivo de
configuração.

## Requisitos

- 4 GB de RAM (8 GB se for usar a camada de IA)
- 20 GB de disco
- Linux, macOS ou Windows com WSL2
