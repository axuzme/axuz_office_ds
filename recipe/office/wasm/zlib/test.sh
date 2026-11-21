#!/usr/bin/env bash
# axuz_ops/office/wasm/zlib/test.sh — prova de equivalencia do zlib.wasm (offline, em container, sem rede).
# Uso: test.sh --built DIR --sdkjs DIR --aux <repo document-templates> [--red]
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../test-lib/run.sh"
hzs_test_main zlib zlib.wasm common/zlib/engine/zlib.wasm common/zlib/engine/zlib.js "$@"
