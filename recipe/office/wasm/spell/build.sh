#!/usr/bin/env bash
# axuz_ops/office/wasm/spell/build.sh — compila spell.wasm (Hunspell do sdkjs) do fonte C++ do core + hunspell.
# Uso: build.sh --core DIR --sdkjs DIR --out DIR   (escreve OUT/spell.wasm). Ver _hzs-common.sh e inner.sh.
# O glue spell.js sai de glue.py (runtime emcc nosso + wrapper do sdkjs); sem spell_ie.js/.mem (asm.js removido por patch).
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
source "$D/../_hzs-common.sh"
hzs_args "$@"
hzs_docker "$D"
hzs_glue spell common/spell/spell/spell.js
[[ -s "$HZS_OUT/spell.wasm" ]] || hzs_die "spell.wasm nao gerado"
echo "spell.wasm ok: sha256 $(sha256sum "$HZS_OUT/spell.wasm" | cut -d' ' -f1)"
