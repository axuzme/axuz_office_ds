#!/usr/bin/env bash
# axuz_ops/office/stages/53-heif.sh — libheif-bundle.js (wasm embutido) compilado do FONTE no lugar do prebuild do npm libheif-js.
#
# O QUE: roda office/wasm/libheif/build.sh (libheif + libde265 nos commits do lock, emscripten por digest), confere o sha256 contra a linha
#   `glue-libheif-bundle` do blobs.lock (saida do NOSSO build; diverge = erro) e instala em server/DocService/node_modules/libheif-js/libheif-wasm/.
#   Remove do pacote npm as variantes pre-compiladas que o DocService nao carrega (libheif.wasm, libheif.js, *.mjs, libheif/ asm.js, index/wasm.js):
#   o heic-decode so faz `require('libheif-js/wasm-bundle')`.
# ONDE: roda no HOST (como o stage wasm: o build.sh sobe o container emsdk), depois de `server` (que faz o npm ci) e antes de `seal`.
# EFEITO: artefato sem nenhum wasm/glue de libheif vindo do npm; <ws>/wasm-out/libheif/; linha em <ws>/logs/wasm-built.tsv.
set -euo pipefail
OFFICE="${OFFICE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WS="${AXUZ_OFFICE_WS:?AXUZ_OFFICE_WS nao definido (use run-build.sh)}"
LOCK="${LOCK_FILE:-$OFFICE/blobs.lock}"
OUT="$WS/work/build_tools/out/linux_64/onlyoffice/documentserver"
PKG="$OUT/server/DocService/node_modules/libheif-js"
die() { printf 'AXUZ-HEIF: %s\n' "$*" >&2; exit 3; }
[[ -f "$WS/work/prepare.ok" ]] || die "rode o stage prepare antes"
[[ -d "$PKG" ]] || die "libheif-js ausente do artefato ($PKG): rode o stage server antes"
mkdir -p "$WS/wasm-out/libheif" "$WS/logs"
bash "$OFFICE/wasm/libheif/build.sh" --core "$WS/work/core" --out "$WS/wasm-out/libheif" --jobs "${AXUZ_JOBS:-4}"
sha="$(sha256sum "$WS/wasm-out/libheif/libheif-bundle.js" | cut -d' ' -f1)"
pin="$(awk -F'\t' '$1=="glue-libheif-bundle"{print $5}' "$LOCK")"
[[ -n "$pin" ]] || die "linha glue-libheif-bundle ausente do blobs.lock"
[[ "$pin" == "sha256:$sha" ]] || die "libheif-bundle.js sha256:$sha != lock ($pin)"
rm -rf "$PKG/libheif" "$PKG/libheif-wasm" "$PKG/index.js" "$PKG/wasm.js"
mkdir -p "$PKG/libheif-wasm"
cp "$WS/wasm-out/libheif/libheif-bundle.js" "$PKG/libheif-wasm/libheif-bundle.js"
printf 'glue-libheif-bundle\t%s\t%s\n' "$sha" "server/DocService/node_modules/libheif-js/libheif-wasm/libheif-bundle.js" >> "$WS/logs/wasm-built.tsv"
echo "heif ok: sha256:$sha"
