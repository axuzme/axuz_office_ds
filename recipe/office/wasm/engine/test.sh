#!/usr/bin/env bash
# axuz_ops/office/wasm/engine/test.sh — prova de equivalencia do engine.wasm (offline, em container, sem rede).
# Uso: test.sh --built DIR --sdkjs DIR [--red]    (DIR contem o engine.wasm gerado pelo build.sh)
#   --red: roda tambem os casos que DEVEM falhar (export removido do glue; byte do wasm adulterado) e exige a falha.
set -euo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$D/../test-lib/run.sh"
hzs_test_main engine engine.wasm common/hash/hash/engine.wasm common/hash/hash/engine.js "$@"
