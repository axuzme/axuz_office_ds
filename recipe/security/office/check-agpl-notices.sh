#!/usr/bin/env bash
# axuz_ops/security/office/check-agpl-notices.sh
#
# O QUE: cumpre por gate as obrigacoes de modificacao da AGPL-3.0 (secao 5) e os termos adicionais do ONLYOFFICE
#   (ADR docs-online-editor, secao 4): quem modifica o fonte do ONLYOFFICE Docs CE tem de AVISAR que modificou, com
#   data, manter os avisos de copyright upstream e entregar licenca e aviso junto do artefato.
#   1. RECEITA: para cada patch em office/patches/*.patch, todo arquivo que aceita comentario (.js .jsx .py .html
#      .sh .css .less .ts) precisa ter ao menos uma linha ADICIONADA com "Modified by Axuz" ou "AXUZ" (o aviso na
#      propria modificacao). Todo patch e script de transformacao (patches/*.py) precisa ser CITADO por nome em
#      NOTICE-AXUZ.txt (cobre json/htm, que nao tem comentario). NOTICE-AXUZ.txt tem de dizer AGPL, a data da
#      modificacao e onde esta o fonte correspondente (SOURCE-COMMIT).
#   2. ARTEFATO (--artifact <dir>): NOTICE-AXUZ.txt na raiz, texto da licenca AGPL em server/LICENSE.txt, e os
#      cabecalhos de copyright "Ascensio System SIA" preservados em arquivos de amostra (web-apps/apps/api/documents/api.js).
#
# ONDE: tests/unit.d/60-office-sem-blob-e-agpl.sh; stages/60-verify.sh (com --artifact); a mao antes de publicar o DS.
# AUTO-TESTE: --self-check cria patch sem aviso (deve reprovar) e com aviso (deve passar).
#
# USO:   check-agpl-notices.sh [--root <axuz_ops/office>] [--artifact <dir>] [--self-check]
# SAIDA: 0 = ok. 1 = achado. 2 = erro de uso / self-check falhou.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""   # default (axuz_ops/office) so se resolve se --root nao vier: no container o script mora em /security (sem ../../office)
ARTIFACT=""; SELF=0
while (($#)); do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --artifact) ARTIFACT="$2"; shift 2 ;;
    --self-check) SELF=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "uso invalido: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$ROOT" && "$SELF" != 1 ]]; then ROOT="$(cd "$HERE/../../office" 2>/dev/null && pwd)" || { echo "--root ausente e $HERE/../../office nao existe" >&2; exit 2; }; fi
COMMENT_EXT_RE='\.(js|jsx|py|html|sh|css|less|ts)$'

# scan_recipe <office-dir> — avisos nos patches e citacao no NOTICE; retorna 1 se houve achado.
# Onde: main e self_check.
scan_recipe() {
  local d="$1" hits=0 notice="$1/NOTICE-AXUZ.txt" p name file added
  if [[ ! -s "$notice" ]]; then echo "NOTICE-AXUZ.txt ausente ou vazio em $d"; hits=1; fi
  if [[ -s "$notice" ]]; then
    grep -qi 'AGPL' "$notice" || { echo "NOTICE-AXUZ.txt nao cita a AGPL"; hits=1; }
    grep -q '2026-' "$notice" || { echo "NOTICE-AXUZ.txt sem data de modificacao"; hits=1; }
    grep -q 'SOURCE-COMMIT\|[0-9a-f]\{40\}' "$notice" || { echo "NOTICE-AXUZ.txt sem o fonte correspondente (SOURCE-COMMIT)"; hits=1; }
  fi
  while IFS= read -r p; do
    name="$(basename "$p")"
    if [[ -s "$notice" ]] && ! grep -qF "$name" "$notice"; then echo "$name: patch nao citado em NOTICE-AXUZ.txt"; hits=1; fi
    [[ "$p" == *.patch ]] || continue
    # arquivos tocados que aceitam comentario precisam de linha adicionada com o aviso
    while IFS= read -r file; do
      [[ "$file" =~ $COMMENT_EXT_RE ]] || continue
      added="$(awk -v f="b/$file" '
        /^diff --git / { cur = ($4 == f) }
        cur && /^\+[^+]/ { print }' "$p")"
      if ! grep -qiE 'Modified by Axuz|AXUZ' <<<"$added"; then
        echo "$name: $file alterado sem aviso 'Modified by Axuz' (AGPL secao 5)"; hits=1
      fi
    done < <(grep -E '^\+\+\+ b/' "$p" | sed 's#^+++ b/##' | sort -u)
  done < <(find "$d/patches" -type f \( -name '*.patch' -o -name 'strip-marketing.py' \) 2>/dev/null | sort)
  return $hits
}

# scan_artifact <artifact-dir> — NOTICE, licenca e cabecalho upstream no artefato; retorna 1 se houve achado.
# Onde: main (--artifact) e stages/60-verify.sh.
scan_artifact() {
  local a="$1" hits=0
  [[ -d "$a" ]] || { echo "artefato inexistente: $a"; return 1; }
  [[ -s "$a/NOTICE-AXUZ.txt" ]] || { echo "artefato sem NOTICE-AXUZ.txt na raiz"; hits=1; }
  if [[ -s "$a/server/LICENSE.txt" ]]; then
    grep -qi 'AFFERO' "$a/server/LICENSE.txt" || { echo "server/LICENSE.txt nao e a AGPL"; hits=1; }
  else
    echo "artefato sem server/LICENSE.txt (texto da AGPL)"; hits=1
  fi
  if [[ -f "$a/web-apps/apps/api/documents/api.js" ]]; then
    grep -q 'Ascensio System SIA' "$a/web-apps/apps/api/documents/api.js" || { echo "api.js perdeu o copyright upstream"; hits=1; }
  else
    echo "artefato sem web-apps/apps/api/documents/api.js (amostra do cabecalho upstream)"; hits=1
  fi
  return $hits
}

# self_check — patch sem aviso reprova; com aviso passa.
# Onde: --self-check.
self_check() {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/patches"
  printf 'AGPL-3.0 2026-11-14 SOURCE-COMMIT\nsx.patch\n' > "$t/NOTICE-AXUZ.txt"
  printf 'diff --git a/x.js b/x.js\n--- a/x.js\n+++ b/x.js\n@@ -1 +1,2 @@\n a\n+b\n' > "$t/patches/sx.patch"
  if scan_recipe "$t" >/dev/null; then echo "self-check: patch .js sem aviso NAO foi detectado"; rm -rf "$t"; return 1; fi
  printf 'diff --git a/x.js b/x.js\n--- a/x.js\n+++ b/x.js\n@@ -1 +1,2 @@\n a\n+// Modified by Axuz\n' > "$t/patches/sx.patch"
  scan_recipe "$t" >/dev/null || { echo "self-check: patch com aviso foi reprovado"; rm -rf "$t"; return 1; }
  rm -rf "$t"; return 0
}

if ((SELF)); then
  self_check || exit 2
  echo "check-agpl-notices: self-check ok"; exit 0
fi
rc=0
scan_recipe "$ROOT" || rc=1
[[ -n "$ARTIFACT" ]] && { scan_artifact "$ARTIFACT" || rc=1; }
((rc)) && echo "check-agpl-notices: REPROVADO" >&2 || echo "check-agpl-notices: ok"
exit "$rc"
