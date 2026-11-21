#!/usr/bin/env bash
# axuz_ops/office/wasm/engine/build.sh — compila engine.wasm (hash de senha do sdkjs) do fonte C++ do core.
# Uso: build.sh --core DIR --sdkjs DIR --out DIR   (escreve OUT/engine.wasm)
# O QUE/ONDE: ver _hzs-common.sh e inner.sh; chamado por stages/25-wasm.sh antes do build do sdkjs.
# O glue engine.js sai de glue.py (runtime emcc nosso + wrapper do sdkjs); sem engine_ie.js (asm.js removido por patch).
set -euo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$D/../_hzs-common.sh"
hzs_args "$@"
hzs_docker "$D"
hzs_glue engine common/hash/hash/engine.js
[[ -s "$HZS_OUT/engine.wasm" ]] || hzs_die "engine.wasm nao gerado"
echo "engine.wasm ok: sha256 $(sha256sum "$HZS_OUT/engine.wasm" | cut -d' ' -f1)"
