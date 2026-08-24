#!/usr/bin/env python3
"""Gera o par de chaves Ed25519 do LICENCIAMENTO (uso do FORNECEDOR).

  • A chave PRIVADA fica com o fornecedor (nunca sai daqui, nunca vai no produto).
  • A chave PÚBLICA vai no .env do appliance como LICENSE_PUBLIC_KEY.

Com isso o cliente consegue VERIFICAR a licença, mas não consegue EMITIR —
diferente do HMAC, em que o mesmo segredo faz as duas coisas.

    python3 scripts/gerar-par-licenca.py                 # cria o par
    python3 scripts/gerar-par-licenca.py --assinar \
        avancado ACME 2027-12-31 --privada <hex>         # emite uma licença
"""
import argparse, re, sys
from datetime import date
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey, Ed25519PublicKey)
from cryptography.hazmat.primitives import serialization

def _raw(k, priv=False):
    if priv:
        return k.private_bytes(serialization.Encoding.Raw,
                               serialization.PrivateFormat.Raw,
                               serialization.NoEncryption()).hex()
    return k.public_bytes(serialization.Encoding.Raw,
                          serialization.PublicFormat.Raw).hex()

ap = argparse.ArgumentParser()
ap.add_argument('--assinar', nargs=3, metavar=('PLANO','CLIENTE','VALIDADE'),
                help='emite uma licença (VALIDADE em YYYY-MM-DD ou "perpetua")')
ap.add_argument('--privada', help='chave privada em hex (para --assinar)')
a = ap.parse_args()

if not a.assinar:
    sk = Ed25519PrivateKey.generate()
    print('PRIVADA (guarde em cofre, NUNCA distribua):\n  ' + _raw(sk, True))
    print('\nPUBLICA (coloque no .env do appliance):\n  LICENSE_PUBLIC_KEY=' + _raw(sk.public_key()))
    sys.exit(0)

if not a.privada:
    sys.exit('✖ --assinar exige --privada <hex>')
plano, cliente, validade = a.assinar
plano = plano.strip().lower()
cliente = re.sub(r'[^A-Z0-9]', '', cliente.upper()) or 'CLIENTE'
if validade.lower() in ('perpetua', 'perpétua', ''):
    val = 'PERPETUA'
else:
    date.fromisoformat(validade)
    val = validade.replace('-', '')
sk = Ed25519PrivateKey.from_private_bytes(bytes.fromhex(a.privada))
base = f'{plano}|{cliente}|{val}'.lower()
assin = sk.sign(base.encode()).hex().upper()
print(f'TRACADO-{plano.upper()}-{cliente}-{val}-{assin}')
