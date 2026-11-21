#!/usr/bin/env bash
# axuz_ops/office/wasm/zlib/build.sh — compila zlib.wasm (zip + imagens do sdkjs) do fonte C++ do core.
# Uso: build.sh --core DIR --sdkjs DIR --out DIR   (escreve OUT/zlib.wasm). Ver _hzs-common.sh e inner.sh.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../_hzs-common.sh"
hzs_args "$@"
hzs_docker "$D"
hzs_glue zlib common/zlib/engine/zlib.js
[[ -s "$HZS_OUT/zlib.wasm" ]] || hzs_die "zlib.wasm nao gerado"
echo "zlib.wasm ok: sha256 $(sha256sum "$HZS_OUT/zlib.wasm" | cut -d' ' -f1)"
