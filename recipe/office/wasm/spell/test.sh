#!/usr/bin/env bash
# axuz_ops/office/wasm/spell/test.sh — prova de equivalencia do spell.wasm (offline, em container, sem rede).
# Uso: test.sh --built DIR --sdkjs DIR --aux <repo dictionaries> [--red]
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../test-lib/run.sh"
hzs_test_main spell spell.wasm common/spell/spell/spell.wasm common/spell/spell/spell.js "$@"
