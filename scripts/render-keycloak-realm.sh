#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
d={}
for line in Path('.env').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        k,v=line.split('=',1); d[k]=v
s=Path('keycloak/realm-sgsi.template.json').read_text()
s=s.replace('${KEYCLOAK_CLIENT_SECRET}',d['KEYCLOAK_CLIENT_SECRET'])
s=s.replace('${MASTER_PASSWORD}',d['MASTER_PASSWORD'])
s=s.replace('${PORTAL_PUBLIC_URL}',d.get('PORTAL_PUBLIC_URL','http://localhost:8080'))
s=s.replace('${MASTER_EMAIL}',d.get('MASTER_EMAIL','admin@sgsi.local'))
Path('keycloak/realm-sgsi.json').write_text(s)
PY
