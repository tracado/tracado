#!/usr/bin/env python3
"""Triagem de nome de marca: Registro.br + INPI (radical, classes 9/42) + GitHub + .com.

Um nome só passa se estiver limpo nos quatro. Uso:
    python3 scripts/triagem-marca.py vesta fides zelo
"""
import json, re, sys, time, unicodedata, urllib.request, urllib.parse, http.cookiejar

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126"
CLASSES = ["9", "42"]          # 9 = software gravado, 42 = serviços de TI/SaaS
VIVA = ("em vigor", "aguardando", "depositado", "sobrestamento", "apresenta")

_op = urllib.request.build_opener(
    urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
_op.addheaders = [("User-Agent", UA)]


def _get(url, data=None, ref=None):
    h = {"Referer": ref} if ref else {}
    req = urllib.request.Request(url, data=data, headers=h)
    with _op.open(req, timeout=45) as r:
        return r.read()


def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


# ---------------------------------------------------------------- Registro.br
def _whois_livre(fq):
    """Fonte autoritativa. O JSON do Registro.br estrangula em rajada e devolve 'tomado'
    falso — descartar nome bom por isso é pior que o contrário, então todo 'tomado'
    passa por aqui antes de virar veredito."""
    import subprocess
    try:
        out = subprocess.run(["whois", "-h", "whois.registro.br", fq],
                             capture_output=True, timeout=30).stdout.decode(
            "utf-8", "replace")
    except Exception:
        return None
    return not re.search(r"^owner:", out, re.M | re.I)


def registro_br(nome):
    """status 0 = livre, 2 = ocupado, 3 = bloqueado por sintaxe similar (acento)."""
    fq = sem_acento(nome).lower() + ".com.br"
    time.sleep(1.2)                        # sem isto o Registro.br estrangula e mente
    d = json.loads(_get("https://registro.br/v2/ajax/avail/raw/" + fq))
    st = d.get("status")
    if st == 0:
        return True, f"{fq} livre"
    # 2=registrado  3=preso à variante acentuada  5=caducou, na fila de liberação (vai a
    # sorteio quando abrir — não se pode contar com ele)
    motivo = "; ".join(d.get("reasons") or []) or {
        2: "já registrado", 3: "preso a variante similar",
        5: "aguardando processo de liberação (sorteio)"}.get(st, f"status {st}")
    if st in (2, 3, 5):
        return False, f"{fq} — {motivo}"
    if _whois_livre(fq):                   # confirma antes de descartar
        return True, f"{fq} livre (Registro.br disse '{motivo}'; whois desmente)"
    return False, f"{fq} — {motivo}"


# ----------------------------------------------------------------------- INPI
def _sessao_inpi():
    _get("https://busca.inpi.gov.br/pePI/servlet/LoginController?action=login")


# A página de resultado SEMPRE traz um destes marcadores. Sem marcador, a resposta
# não é um resultado — é sessão caída ou erro. Ler isso como "zero marcas" faria o
# portão mentir a favor do nome, que é o erro que ele existe para impedir.
_MARCADOR = re.compile(r"Foram encontrad|N[aã]o foi encontrad|Nenhum resultado|nenhum processo", re.I)


def _busca(corpo, tentativas=3):
    for i in range(tentativas):
        raw = _get("https://busca.inpi.gov.br/pePI/servlet/MarcasServletController", corpo,
                   "https://busca.inpi.gov.br/pePI/jsp/marcas/Pesquisa_classe_basica.jsp")
        html = raw.decode("iso-8859-1", "replace")
        if _MARCADOR.search(html):
            return html
        time.sleep(3 * (i + 1))
        _sessao_inpi()                     # sessão caiu: refaz e tenta de novo
    raise RuntimeError("INPI não devolveu página de resultado — resultado INDETERMINADO, "
                       "nunca tratar como limpo")


def inpi(nome, radical=None):
    """Busca por RADICAL — é ela que pega CUSTODI dentro de TRAÇADO."""
    base = sem_acento(radical or nome).lower()
    achados = []
    for cl in CLASSES:
        corpo = urllib.parse.urlencode({
            "buscaExata": "nao", "marca": base, "classeInter": cl,
            "registerPerPage": "100", "Action": "searchMarca",
            "tipoPesquisa": "BY_MARCA_CLASSIF_BASICA"}).encode()
        html = _busca(corpo)
        for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.S | re.I):
            cel = [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", c)).replace("\xa0", " ").strip()
                   for c in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S | re.I)]
            if len(cel) < 7 or not re.match(r"^\d{9}$", cel[0]):
                continue
            marca, sit, tit = cel[3], cel[5], cel[6]
            if not any(v in sit.lower() for v in VIVA):
                continue                      # extinto/arquivado não bloqueia
            achados.append((cl, cel[0], marca, sit, tit))
        m = re.search(r"encontrados?\s*(?:</?[^>]*>\s*)*(\d+)\s*processos", html)
        if m and int(m.group(1)) > 100:
            raise RuntimeError(f"{base} cl.{cl}: {m.group(1)} processos, página trunca em 100 "
                               "— refinar antes de concluir")
        time.sleep(2.5)
    return (not achados), achados


# --------------------------------------------------------------- GitHub / com
def github_org(nome):
    slug = sem_acento(nome).lower()
    try:
        _get("https://api.github.com/users/" + slug)
        return False, f"github.com/{slug} ocupado"
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return True, f"github.com/{slug} livre"
        return None, f"github.com/{slug} — HTTP {e.code} (indeterminado)"


def dot_com(nome):
    fq = sem_acento(nome).lower() + ".com"
    try:
        _get("https://rdap.verisign.com/com/v1/domain/" + fq)
        return False, f"{fq} registrado"
    except urllib.error.HTTPError as e:
        return (True, f"{fq} livre") if e.code == 404 else (None, f"{fq} — HTTP {e.code}")


# ----------------------------------------------------------------------- main
def triagem(nome, radical=None):
    print(f"\n{'='*72}\n  {nome.upper()}\n{'='*72}")
    veredito = True
    for rot, (ok, det) in [("Registro.br", registro_br(nome)),
                           ("GitHub org ", github_org(nome)),
                           (".com       ", dot_com(nome))]:
        print(f"  {'PASSA' if ok else 'BLOQUEIA' if ok is False else '  ?  '}  {rot}  {det}")
        if ok is False and rot.strip() == "Registro.br":
            veredito = False
    ok, achados = inpi(nome, radical)
    print(f"  {'PASSA' if ok else 'BLOQUEIA'}  INPI cl.9/42  "
          f"radical '{sem_acento(radical or nome).lower()}' — "
          f"{len(achados)} marca(s) viva(s)")
    for cl, num, marca, sit, tit in achados:
        print(f"          cl{cl:>3}  {num}  {marca[:34]:34}  {sit[:24]:24}  {tit[:30]}")
        veredito = False
    print(f"  ── {'VIÁVEL' if veredito else 'DESCARTADO'}")
    return veredito


if __name__ == "__main__":
    _sessao_inpi()
    viaveis = [n for n in sys.argv[1:] if triagem(n)]
    print(f"\n\n{'='*72}\n  VIÁVEIS: {', '.join(viaveis) if viaveis else '(nenhum)'}\n{'='*72}")
