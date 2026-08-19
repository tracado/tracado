#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gerador de chaves de licença do GRC Hub (uso do fornecedor).

Protegido por senha: gerar uma licença exige a senha do fornecedor, para que
apenas quem a conhece possa emitir chaves — mesmo com acesso ao script e ao
LICENSE_SIGNING_KEY.

Uso:
    python3 scripts/gerar-licenca.py definir-senha            # define/troca a senha
    python3 scripts/gerar-licenca.py <plano> [cliente] [validade YYYY-MM-DD]

Exemplos:
    python3 scripts/gerar-licenca.py definir-senha
    python3 scripts/gerar-licenca.py basico
    python3 scripts/gerar-licenca.py intermediario ACME
    python3 scripts/gerar-licenca.py avancado ACME 2027-12-31

Automação/CI (sem prompt): exporte a senha em LICENSE_GEN_PASSWORD.

Defina LICENSE_SIGNING_KEY no ambiente com o MESMO segredo usado no appliance
do cliente (docker-compose) — chaves geradas com segredos diferentes não validam.
"""
import getpass
import hashlib
import hmac
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'dashboard'))
import licenca  # noqa: E402

# ── Senha do fornecedor (gate para emitir licenças) ─────────────────────────
# O hash é lido de LICENSE_GEN_PASSWORD_HASH (ambiente) ou do arquivo local
# scripts/.senha-licenca. A senha em si NUNCA é armazenada — só o hash PBKDF2.
SENHA_FILE = pathlib.Path(__file__).resolve().parent / '.senha-licenca'
PBKDF2_ITER = 200_000
MIN_SENHA = 8


def _hash_senha(senha, salt=None):
    salt = salt or os.urandom(16)
    dk = hashlib.pbkdf2_hmac('sha256', senha.encode(), salt, PBKDF2_ITER)
    return f'pbkdf2_sha256${PBKDF2_ITER}${salt.hex()}${dk.hex()}'


def _verificar_senha(senha, armazenado):
    try:
        _algo, iters, salt_hex, hash_hex = armazenado.strip().split('$')
        dk = hashlib.pbkdf2_hmac('sha256', senha.encode(),
                                 bytes.fromhex(salt_hex), int(iters))
        return hmac.compare_digest(dk.hex(), hash_hex)
    except Exception:
        return False


def _hash_configurado():
    """Hash esperado: ambiente tem prioridade sobre o arquivo local."""
    env = os.getenv('LICENSE_GEN_PASSWORD_HASH', '').strip()
    if env:
        return env
    if SENHA_FILE.exists():
        return SENHA_FILE.read_text(encoding='utf-8').strip()
    return ''


def definir_senha():
    """Cria/troca a senha do fornecedor (subcomando 'definir-senha')."""
    atual = _hash_configurado()
    if atual:
        antiga = getpass.getpass('Senha atual (para confirmar a troca): ')
        if not _verificar_senha(antiga, atual):
            print('✖ Senha atual incorreta.')
            sys.exit(1)
    nova = getpass.getpass('Nova senha: ')
    if len(nova) < MIN_SENHA:
        print(f'✖ A senha precisa ter pelo menos {MIN_SENHA} caracteres.')
        sys.exit(1)
    if nova != getpass.getpass('Confirme a nova senha: '):
        print('✖ As senhas não conferem.')
        sys.exit(1)
    h = _hash_senha(nova)
    SENHA_FILE.write_text(h + '\n', encoding='utf-8')
    try:
        SENHA_FILE.chmod(0o600)
    except OSError:
        pass
    print(f'\n✓ Senha definida e salva em {SENHA_FILE.name} (não versione este arquivo).')
    print('Para usar em CI/automação, exporte também:')
    print(f'  export LICENSE_GEN_PASSWORD_HASH="{h}"')


def exigir_senha():
    """Bloqueia a emissão se a senha não for informada/correta (fail-closed)."""
    esperado = _hash_configurado()
    if not esperado:
        print('✖ Nenhuma senha de emissão configurada.')
        print('  Rode primeiro: python3 scripts/gerar-licenca.py definir-senha')
        sys.exit(1)
    senha = os.getenv('LICENSE_GEN_PASSWORD')
    if senha is None:
        senha = getpass.getpass('Senha do fornecedor: ')
    if not _verificar_senha(senha, esperado):
        print('✖ Senha incorreta — emissão de licença cancelada.')
        sys.exit(1)


def _uso():
    print(__doc__)
    print('Planos disponíveis:')
    for p, d in licenca.PLANOS.items():
        print(f"  {p:<14} — {d['descricao']}")


# ── CLI ──────────────────────────────────────────────────────────────────────
if len(sys.argv) < 2:
    _uso()
    sys.exit(1)

if sys.argv[1] in ('definir-senha', 'set-senha', 'senha'):
    definir_senha()
    sys.exit(0)

if sys.argv[1] not in licenca.PLANOS:
    _uso()
    sys.exit(1)

exigir_senha()

plano = sys.argv[1]
cliente = sys.argv[2] if len(sys.argv) > 2 else ''
validade = sys.argv[3] if len(sys.argv) > 3 else ''

chave = licenca.gerar(plano, cliente, validade)
info = licenca.validar(chave)
print(f"\nPlano:    {info['nome']} — {info['descricao']}")
print(f"Cliente:  {info['cliente']}")
print(f"Validade: {info['validade'].strftime('%d/%m/%Y') if info['validade'] else 'Perpétua'}")
print(f"\nChave:\n{chave}\n")
print('Cole essa chave em ⚙ Configurações → Licença no portal do cliente.')
