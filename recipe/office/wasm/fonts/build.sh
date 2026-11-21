#!/usr/bin/env bash
# office/wasm/fonts/build.sh --core DIR --sdkjs DIR --out DIR — compila fonts.wasm (+ glue fonts.js/fonts_ie.js/fonts_native.js) do fonte C++.
#
# O QUE: roda build_inner.py num container emscripten fixado POR DIGEST (emsdk.lock); le o fonte do git do core no sha de core.pin.
# ONDE: chamado por office/stages/25-wasm.sh (que roda todo office/wasm/*/build.sh). Chame sob limite:
#   bash axuz_ops/scripts/limitado.sh --perfil build -- bash office/wasm/fonts/build.sh --core ... --sdkjs ... --out ...
# DETERMINISTICO: mesmo digest + mesmo core_commit => mesmos bytes (provado por test.sh/'reprodutibilidade').
# ENV: JOBS (default nproc), WITH_ASM=1 gera fonts_ie.js (asm.js do IE; DESLIGADO por padrao: o sdkjs nao o carrega mais).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="" SDKJS="" OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --core) CORE="$2"; shift 2 ;;
    --sdkjs) SDKJS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "uso: $0 --core DIR --sdkjs DIR --out DIR" >&2; exit 2 ;;
  esac
done
[[ -d "$CORE/.git" && -d "$SDKJS" && -n "$OUT" ]] || { echo "ERRO: --core (com .git), --sdkjs e --out sao obrigatorios" >&2; exit 2; }
lock() { sed -n "s/^$1=//p" "$HERE/$2" | head -1; }
IMG="$(lock image emsdk.lock)@$(lock digest emsdk.lock)"
PIN="$(lock core_commit core.pin)"
HPIN="$(lock hyphen_commit core.pin)"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
docker image inspect "$IMG" >/dev/null 2>&1 || docker pull "$IMG"
docker run --rm -e CORE_PIN="$PIN" -e HYPHEN_PIN="$HPIN" -e JOBS="${JOBS:-$(nproc)}" -e WITH_ASM="${WITH_ASM:-0}" \
  -v "$CORE:/core:ro" -v "$SDKJS:/sdkjs:ro" -v "$HERE:/recipe:ro" -v "$OUT:/out" "$IMG" \
  sh -c 'python3 /recipe/build_inner.py && chown -R '"$(id -u):$(id -g)"' /out'
sha256sum "$OUT/fonts.wasm"
