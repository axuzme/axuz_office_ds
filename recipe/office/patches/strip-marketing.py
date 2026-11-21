#!/usr/bin/env python3
"""
axuz_ops/office/patches/strip-marketing.py — remove links de marketing/ajuda do ONLYOFFICE do fonte antes do build.

Modified by Axuz (2026-11-14) — este script e uma das modificacoes do ONLYOFFICE Docs CE (AGPL-3.0, secao 5) e esta
listado em NOTICE-AXUZ.txt; a saida (modifications-marketing.tsv) vai junto do artefato.

O QUE: reescreve para `#` toda URL http(s) dos hosts de marketing/ajuda/loja do ONLYOFFICE e a pagina de chave da
  OpenAI, nos arquivos de runtime (js, jsx, json, html, htm) de web-apps, sdkjs, sdkjs-forms e server. O link some
  do que o usuario clica; nenhum dado e enviado a esses hosts (o zero-egress do gate ja valida isso em runtime).
NAO TOCA: (1) linhas de comentario/cabecalho de licenca (AGPL exige manter os avisos); (2) o link da marca
  `brand-logo` das paginas embed (aviso legal "Powered by"); (3) `schemas.onlyoffice.com` e outros namespaces XML
  (nao sao links; sao identificadores); (4) node_modules, .git, build, deploy, vendor.
ONDE: stages/05-prepare.sh, depois de aplicar os patches e antes do build. Idempotente.
SAIDA: <work>/modifications-marketing.tsv (arquivo, ocorrencias).
USO: strip-marketing.py <work-dir> [--dry-run]   (rc 0 ok; rc 2 uso)
"""
import os
import re
import sys

HOST_RE = re.compile(
    r"https?://(?:(?:www|helpcenter|api|support|community|git|bugzilla|forum|teamlab)\.)?onlyoffice\.(?:com|eu)(?:/[^\s\"'<>)\\]*)?"
    r"|https?://onlyoffice(?:-plugins)?\.github\.io(?:/[^\s\"'<>)\\]*)?"
    r"|https?://platform\.openai\.com(?:/[^\s\"'<>)\\]*)?")
SKIP_DIRS = {"node_modules", ".git", "build", "deploy", "vendor", "out", "dist", "translation"}
EXTS = (".js", ".jsx", ".json", ".html", ".htm")
ROOTS = ("web-apps/apps", "sdkjs", "sdkjs-forms", "server/Common/sources", "server/Common/config",
         "server/DocService/sources", "server/welcome")
COMMENT_START = ("*", "//", "/*", "<!--", "#")
KEEP_MARKERS = ("brand-logo", "schemas.onlyoffice.com", "gnu.org/licenses")


def line_is_protected(line: str) -> bool:
    """Linha de comentario/cabecalho ou marca que nao pode ser reescrita."""
    s = line.lstrip()
    if s.startswith(COMMENT_START):
        return True
    return any(m in line for m in KEEP_MARKERS)


def process(path: str, dry: bool) -> int:
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except (UnicodeDecodeError, OSError):
        return 0
    if "onlyoffice" not in text and "openai" not in text:
        return 0
    n = 0
    out = []
    for line in text.split("\n"):
        if line_is_protected(line):
            out.append(line)
            continue
        new, c = HOST_RE.subn("#", line)
        n += c
        out.append(new)
    if n and not dry:
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out))
    return n


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    work = sys.argv[1]
    dry = "--dry-run" in sys.argv
    rows = []
    for root in ROOTS:
        base = os.path.join(work, root)
        for d, dirs, files in os.walk(base):
            dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
            for fn in files:
                if not fn.endswith(EXTS):
                    continue
                p = os.path.join(d, fn)
                c = process(p, dry)
                if c:
                    rows.append((os.path.relpath(p, work), c))
    if not dry:
        with open(os.path.join(work, "modifications-marketing.tsv"), "w") as f:
            f.write("arquivo\tocorrencias_reescritas\n")
            for r in sorted(rows):
                f.write("%s\t%d\n" % r)
    print("strip-marketing: %d arquivos, %d links reescritos%s" % (len(rows), sum(c for _, c in rows), " (dry-run)" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
