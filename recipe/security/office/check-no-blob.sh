#!/usr/bin/env bash
# axuz_ops/security/office/check-no-blob.sh
#
# O QUE: garante que o build do ONLYOFFICE Document Server nao baixa NENHUM binario sem hash fixado ou fora da
#   lista de fontes. Decisao do dono (2026-11-14): a troca dos binarios pre-compilados de terceiros bloqueia a O1.a.
#   Quatro verificacoes:
#   1. LOCK (`blobs.lock`): todo id tem classe valida, pin no formato da classe (sha256 de 64 hex; commit de 40 hex),
#      licenca e fonte preenchidas, status `ok` ou `[~]` (a linha `pendente` reprova; `[~]` e item on-hold JA com hash).
#   2. RECEITA: scripts/Dockerfiles/patches NAO podem baixar por fora do lock: `curl`/`wget`/`pip install`/
#      `npm install -g`/nodesource/yao-pkg/pkg-fetch/cipd/clang do Google/qt_binary/python3.tar.gz sao barrados
#      (so lib/lock.sh chama curl, e a conferencia de sha256 mora la). Linhas ADICIONADAS por patch com URL fora do
#      lock (e fora dos hosts de fonte git permitidos) reprovam.
#   3. ARTEFATO (--artifact <dir>): todo ELF, .wasm, .node, .jar, .exe/.dll do artefato precisa estar na allowlist de
#      binarios que NOS compilamos (`artifact-binaries.allow`, regex por caminho relativo) ou, se for .wasm, ter o
#      sha256 do lock (classe wasm) ou vir de node_modules (integridade sha512 do npm-shrinkwrap).
#      E nenhum artefato gerado pelo emscripten pode vir de fora do nosso build: arquivo `*_ie.js`/`*.js.mem` (asm.js do IE11,
#      removido por patch) reprova; todo .js com marca de runtime emscripten (Module["asm"], wasmBinaryFile, "use asm",
#      _emscripten_, __ATPOSTRUN__) precisa ter o sha256 de uma linha classe `glue` do lock (= saida do stage 25-wasm).
#      node_modules fica de fora (integridade sha512 do npm-shrinkwrap).
#      Binario compilado por NOS (C++ do core, ICU, sharp via node-gyp) entra pelo manifesto `built-from-source.tsv`
#      (sha256, caminho no artefato, origem na arvore de build; gerado pelo stage seal, lib/seal.sh): vale se o sha256 do
#      arquivo bate E a origem existe na arvore (--built-tree, default = --verify-tree) com o MESMO hash. Sem origem = reprova.
#   4. ARVORE (--verify-tree <work>): HEAD de cada repo-*/3p-* do lock == commit fixado (pos-build).
#
# ONDE: tests/unit.d/60-office-sem-blob-e-agpl.sh; stages/60-verify.sh (com --artifact e --verify-tree); a mao antes
#   de promover o artefato do DS.
# AUTO-TESTE: --self-check cria receita suja e limpa e exige reprovar a primeira e aprovar a segunda.
#
# USO:   check-no-blob.sh [--root <axuz_ops/office>] [--artifact <dir>] [--verify-tree <work>] [--built-tree <work>] [--built <tsv>] [--built-ws <ws>] [--self-check]
# SAIDA: 0 = limpo. 1 = achado. 2 = erro de uso / self-check falhou.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=""   # default (axuz_ops/office) so se resolve se --root nao vier: no container o script mora em /security (sem ../../office)
ARTIFACT=""; TREE=""; SELF=0; BUILT_TREE=""; BUILT=""; BUILT_WS="/ws"
while (($#)); do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --artifact) ARTIFACT="$2"; shift 2 ;;
    --verify-tree) TREE="$2"; shift 2 ;;
    --built-tree) BUILT_TREE="$2"; shift 2 ;;
    --built) BUILT="$2"; shift 2 ;;
    --built-ws) BUILT_WS="$2"; shift 2 ;;
    --self-check) SELF=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "uso invalido: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$ROOT" && "$SELF" != 1 ]]; then ROOT="$(cd "$HERE/../../office" 2>/dev/null && pwd)" || { echo "--root ausente e $HERE/../../office nao existe" >&2; exit 2; }; fi

# Padroes proibidos na receita (cada um e um download sem hash / binario opaco conhecido).
DENY_RE='(curl|wget)[[:space:]]+-|pip3?[[:space:]]+install|npm[[:space:]]+(install|i)[[:space:]]+(-g|--global)|nodesource|setup_[0-9]+\.x|yao-pkg|pkg-fetch|chrome-infra-packages|commondatastorage|chromium-browser-clang|storage\.googleapis\.com|qt_binary_5|python3\.tar\.gz|build_tools_data/raw/refs/heads/master/(python|sysroot|qt/qt_binary)|ubuntu16-(amd64|arm64)-sysroot\.tar|Kitware/CMake/releases|ensure_bootstrap'
# Hosts de FONTE git permitidos em URL adicionada por patch (clone de codigo, checkout por sha no lock).
GIT_HOST_RE='^https?://(github\.com/(ONLYOFFICE|boostorg|openssl|google|harfbuzz|hunspell|GNOME|mity|strukturag|socketio|unicode-org|ninja-build|Multicorewareinc|g-truc|LibreOffice|Distrotech|kohei-us|jasenhuang)/|chromium\.googlesource\.com/|gn\.googlesource\.com/)'

# scan_recipe <office-dir> — imprime achados "arquivo:linha: motivo"; retorna 1 se houve algum.
# Onde: main e self_check.
scan_recipe() {
  local d="$1" hits=0 f rel out lock
  lock="$d/blobs.lock"
  [[ -f "$lock" ]] || { echo "blobs.lock ausente em $d"; return 1; }
  # 1. lock
  awk -F'\t' '
    BEGIN { split("oci apt tarball git git-file npm-lock wasm glue", c, " "); for (i in c) ok[c[i]] = 1 }
    NR == 1 { next }
    NF != 9 { printf "blobs.lock:%d: %d colunas (esperado 9)\n", NR, NF; bad = 1; next }
    { id = $1; cl = $2; pin = $5 }
    seen[id]++ { printf "blobs.lock:%d: id duplicado %s\n", NR, id; bad = 1 }
    !(cl in ok) { printf "blobs.lock:%d: %s classe invalida (%s)\n", NR, id, cl; bad = 1 }
    cl == "git" && pin !~ /^[0-9a-f]{40}$/ { printf "blobs.lock:%d: %s pin git precisa de commit 40 hex\n", NR, id; bad = 1 }
    (cl == "tarball" || cl == "git-file" || cl == "npm-lock" || cl == "wasm" || cl == "glue" || cl == "oci") && pin !~ /^sha256:[0-9a-f]{64}$/ { printf "blobs.lock:%d: %s pin precisa de sha256:<64 hex>\n", NR, id; bad = 1 }
    cl == "apt" && pin !~ /^(sha256:[0-9a-f]{64}|ver apt-.*)$/ { printf "blobs.lock:%d: %s pin apt invalido\n", NR, id; bad = 1 }
    $6 == "" || $7 == "" { printf "blobs.lock:%d: %s sem licenca/fonte\n", NR, id; bad = 1 }
    $8 != "ok" && $8 != "[~]" { printf "blobs.lock:%d: %s status %s (so ok ou [~])\n", NR, id, $8; bad = 1 }
    END { exit bad }' "$lock" || hits=1
  # 2. receita (scripts, Dockerfiles, run-build) — lib/lock.sh e quem chama curl
  while IFS= read -r f; do
    rel="${f#"$d"/}"
    [[ "$rel" == lib/lock.sh ]] && continue
    out="$(grep -nE "$DENY_RE" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#|axuz-check-ok' || true)"
    if [[ -n "$out" ]]; then
      while IFS= read -r l; do echo "$rel:$l: download/blob proibido na receita"; done <<<"$out"
      hits=1
    fi
  done < <(find "$d" -type f \( -name '*.sh' -o -name 'Dockerfile*' -o -name '*.py' \) -not -path '*/patches/strip-marketing.py' -not -path '*/.git/*' 2>/dev/null)
  # 2b. patches: so linhas ADICIONADAS
  while IFS= read -r f; do
    rel="${f#"$d"/}"
    out="$(grep -nE '^\+' "$f" | grep -vE '^[0-9]+:\+\+\+' | grep -vE '^[0-9]+:\+[[:space:]]*(#|//)' | grep -E "$DENY_RE" || true)"
    if [[ -n "$out" ]]; then
      while IFS= read -r l; do echo "$rel:$l: patch adiciona download/blob proibido"; done <<<"$out"
      hits=1
    fi
    # URL adicionada precisa estar no lock (origem) ou ser host de fonte git
    while IFS= read -r url; do
      [[ -z "$url" ]] && continue
      url="${url%%[\"\')\\]*}"
      if ! awk -F'\t' -v u="$url" 'NR>1 && index($4, u) == 1 {f=1} END{exit !f}' "$lock" && ! [[ "$url" =~ $GIT_HOST_RE ]]; then
        echo "$rel: URL adicionada fora do lock: $url"; hits=1
      fi
    done < <(grep -E '^\+' "$f" | grep -vE '^\+\+\+' | grep -vE '^\+[[:space:]]*(#|//|\*)' | grep -oE "https?://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+" | sort -u)
  done < <(find "$d/patches" -name '*.patch' 2>/dev/null)
  return $hits
}

# in_allow <caminho-relativo> <arquivo-allow> — 0 se algum regex (linha, ancorado) casa; ignora vazias e # comentarios.
# Onde: scan_artifact.
in_allow() {
  local rel="$1" file="$2" re
  [[ -f "$file" ]] || return 1
  while IFS= read -r re; do
    [[ -z "$re" || "$re" == \#* ]] && continue
    [[ "$rel" =~ ^($re)$ ]] && return 0
  done < "$file"
  return 1
}

# built_ok <rel> <arquivo> <manifesto> <arvore> — 0 se o manifesto tem (sha256 do arquivo, rel) e, com <arvore>, a origem
# registrada existe la com o mesmo sha256 (manifesto forjado nao cola). Onde: scan_artifact.
built_ok() {
  local rel="$1" f="$2" man="$3" tree="$4" sha src
  [[ -f "$man" ]] || return 1
  sha="$(sha256sum "$f" | cut -d' ' -f1)"
  src="$(awk -F'\t' -v s="$sha" -v r="$rel" '$1==s && $2==r {print $3; exit}' "$man")"
  [[ -n "$src" ]] || return 1
  if [[ "$src" == /ws/* ]]; then   # toolchain do container (/ws/toolchain/node/...): no host, --built-ws aponta o workspace
    src="${BUILT_WS%/}/${src#/ws/}"
    [[ -f "$src" && "$(sha256sum "$src" | cut -d' ' -f1)" == "$sha" ]]; return
  fi
  if [[ "$src" == /* ]]; then [[ -f "$src" && "$(sha256sum "$src" | cut -d' ' -f1)" == "$sha" ]]; return; fi   # outra origem absoluta: no proprio caminho
  [[ -n "$tree" ]] || return 0
  [[ -f "$tree/$src" && "$(sha256sum "$tree/$src" | cut -d' ' -f1)" == "$sha" ]]
}

# scan_artifact <office-dir> <artifact-dir> [manifesto] [arvore] — binarios do artefato vs allowlist/lock; retorna 1 se houve achado.
# Onde: main (--artifact) e stages/60-verify.sh.
scan_artifact() {
  local d="$1" art="$2" man="${3:-$2/built-from-source.tsv}" tree="${4:-}" hits=0 f rel magic allow sha
  allow="$d/artifact-binaries.allow"
  [[ -d "$art" ]] || { echo "artefato inexistente: $art"; return 1; }
  while IFS= read -r f; do
    rel="${f#"$art"/}"
    magic="$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
    case "$magic" in
      7f454c46) ;;                         # ELF
      0061736d)                            # wasm
        sha="$(sha256sum "$f" | cut -d' ' -f1)"
        if awk -F'\t' -v s="sha256:$sha" '$2=="wasm" && $5==s {f=1} END{exit !f}' "$d/blobs.lock"; then continue; fi
        if [[ "$rel" == server/*/node_modules/* ]]; then continue; fi   # npm: integridade sha512 do shrinkwrap (lock npm-lock)
        echo "$rel: wasm sem hash no lock (sha256:$sha)"; hits=1; continue ;;
      4d5a*|cafebabe|504b0304)             # PE / classe java / zip-jar
        case "$rel" in *.jar|*.exe|*.dll|*.class) ;; *) continue ;; esac ;;
      *) case "$rel" in *.node|*.exe|*.dll|*.jar|*.dylib) ;; *) continue ;; esac ;;
    esac
    if in_allow "$rel" "$allow"; then continue; fi
    if built_ok "$rel" "$f" "$man" "$tree"; then continue; fi
    echo "$rel: binario fora da allowlist (artifact-binaries.allow) — nao compilado por nos / sem hash"; hits=1
  done < <(find "$art" -type f -not -name '*.map' 2>/dev/null)
  scan_emscripten "$d" "$art" || hits=1
  scan_mobile "$art" || hits=1
  scan_npm_overrides "$d" "$art" || hits=1
  return $hits
}

# scan_npm_overrides <office-dir> <artifact-dir> — arquivo do lock (classe wasm/glue) com destino DENTRO de node_modules e
# o prebuild npm que ele substitui: o arquivo do artefato tem de ter o sha256 do lock (saida do NOSSO build; ex.: libheif-bundle.js,
# stage 53-heif), e o libheif.wasm pre-compilado do pacote npm libheif-js nao pode ficar no artefato.
# Onde: scan_artifact. Retorna 1 se houve achado.
scan_npm_overrides() {
  local d="$1" art="$2" hits=0 rel pin sha f
  while IFS=$'\t' read -r rel pin; do
    [[ -f "$art/$rel" ]] || continue
    sha="$(sha256sum "$art/$rel" | cut -d' ' -f1)"
    [[ "sha256:$sha" == "$pin" ]] || { echo "$rel: sha256:$sha difere do lock ($pin) — nao e a saida do nosso build"; hits=1; }
  done < <(awk -F'\t' '($2=="wasm"||$2=="glue") && $4 ~ /\/node_modules\// {print $4 "\t" $5}' "$d/blobs.lock")
  while IFS= read -r f; do
    echo "${f#"$art"/}: wasm pre-compilado do npm libheif-js (o nosso e o libheif-bundle.js do stage 53-heif)"; hits=1
  done < <(find "$art" -path '*/node_modules/libheif-js/*' -name '*.wasm' -type f 2>/dev/null)
  return $hits
}

# MOBILE_MARK — marcador gravado pelo patch web-apps-0004 em cada editor mobile; sobrevive a minificacao.
MOBILE_MARK='axuz-mobile-edit-v1'

# scan_mobile <artifact-dir> — todo dist mobile (word/cell/slide) do artefato tem de ser build do NOSSO src patchado
# (stage 52-mobile): o bundle upstream pre-compilado nao tem o marcador e reprova. Sem dist mobile no artefato, nada a checar.
# Onde: scan_artifact. Retorna 1 se houve achado.
scan_mobile() {
  local art="$1" hits=0 dist e
  for e in documenteditor spreadsheeteditor presentationeditor; do
    dist="$art/web-apps/apps/$e/mobile/dist"
    [[ -d "$dist" ]] || continue
    if ! grep -rqF "$MOBILE_MARK" "$dist" 2>/dev/null; then
      echo "web-apps/apps/$e/mobile/dist: sem o marcador $MOBILE_MARK (bundle upstream pre-compilado, nao build do nosso src; rode o stage mobile)"; hits=1
    fi
  done
  return $hits
}

# EMSCRIPTEN_RE — marcas do runtime que o emcc gera num .js (glue de .wasm ou asm.js). Onde: scan_emscripten.
EMSCRIPTEN_RE='Module\["asm"\]|wasmBinaryFile|"use asm"|_emscripten_|__ATPOSTRUN__'

# scan_emscripten <office-dir> <artifact-dir> — todo JS gerado pelo emscripten no artefato tem de ser saida do NOSSO build:
# `*_ie.js` e `*.js.mem` sao proibidos; .js com marca de runtime precisa do sha256 de uma linha `glue` do lock.
# Onde: scan_artifact. Retorna 1 se houve achado.
scan_emscripten() {
  local d="$1" art="$2" hits=0 f rel sha
  while IFS= read -r f; do
    rel="${f#"$art"/}"
    case "$rel" in */node_modules/*) continue ;; esac
    case "$rel" in
      *_ie.js|*.js.mem) echo "$rel: asm.js/emscripten legado (IE11) nao permitido no artefato"; hits=1; continue ;;
    esac
    grep -qE "$EMSCRIPTEN_RE" "$f" 2>/dev/null || continue
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    if ! awk -F'\t' -v s="sha256:$sha" '$2=="glue" && $5==s {f=1} END{exit !f}' "$d/blobs.lock"; then
      echo "$rel: JS gerado pelo emscripten sem hash glue no lock (nao e saida do nosso build; sha256:$sha)"; hits=1
    fi
  done < <(find "$art" -type f \( -name '*.js' -o -name '*.mem' \) -not -name '*.map' 2>/dev/null)
  return $hits
}

# scan_tree <office-dir> <work-dir> — HEAD dos repos do lock == pin; retorna 1 se divergir.
# Onde: main (--verify-tree) pos-build.
scan_tree() {
  local d="$1" w="$2" hits=0 id cl url pin dir head
  while IFS=$'\t' read -r id cl _ url pin _; do
    case "$id" in repo-*) dir="$w/${id#repo-}" ;; 3p-*) continue ;; *) continue ;; esac
    [[ "$cl" == git ]] || continue
    head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo ausente)"
    if [[ "$head" != "$pin" ]]; then echo "$id: HEAD $head != $pin"; hits=1; fi
  done < <(tail -n +2 "$d/blobs.lock")
  return $hits
}

# self_check — receita suja deve reprovar, limpa deve passar, wasm/ELF fora da allowlist deve reprovar.
# Onde: --self-check.
self_check() {
  local t good bad
  t="$(mktemp -d)"; good="$t/good"; bad="$t/bad"
  mkdir -p "$good/stages" "$good/patches" "$good/lib" "$bad/stages" "$bad/patches" "$bad/lib"
  printf 'id\tclasse\tdestino\torigem\tpin\tlicenca\tfonte\tstatus\tnota\nx\ttarball\tbuild\thttps://e.org/x\tsha256:%s\tMIT\tf\tok\tn\n' "$(printf 'a%.0s' {1..64})" > "$good/blobs.lock"
  cp "$good/blobs.lock" "$bad/blobs.lock"
  printf '#!/bin/sh\nlock_fetch x /tmp/x\n' > "$good/stages/s.sh"
  printf '#!/bin/sh\ncurl -L -o /tmp/x https://e.org/x\n' > "$bad/stages/s.sh"
  scan_recipe "$good" >/dev/null || { echo "self-check: receita limpa foi reprovada"; rm -rf "$t"; return 1; }
  if scan_recipe "$bad" >/dev/null; then echo "self-check: curl solto NAO foi detectado"; rm -rf "$t"; return 1; fi
  rm -rf "$t"; return 0
}

if ((SELF)); then
  self_check || exit 2
  echo "check-no-blob: self-check ok"; exit 0
fi
rc=0
scan_recipe "$ROOT" || rc=1
[[ -n "$ARTIFACT" ]] && { scan_artifact "$ROOT" "$ARTIFACT" "${BUILT:-$ARTIFACT/built-from-source.tsv}" "${BUILT_TREE:-$TREE}" || rc=1; }
[[ -n "$TREE" ]] && { scan_tree "$ROOT" "$TREE" || rc=1; }
((rc)) && echo "check-no-blob: REPROVADO" >&2 || echo "check-no-blob: ok"
exit "$rc"
