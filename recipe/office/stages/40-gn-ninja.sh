#!/usr/bin/env bash
# axuz_ops/office/stages/40-gn-ninja.sh — compila gn e ninja do FONTE, nos commits fixados no lock.
#
# O QUE: o V8 (gclient/depot_tools) baixaria `gn` (cipd, binario Google) e `ninja` (cipd) prontos. Aqui os dois sao
#   compilados do git (gn no commit `gn_version` do DEPS do V8 8.9.255.25; ninja na tag v1.12.1) e instalados em
#   /ws/toolchain/bin. O stage server poe esse diretorio ANTES do depot_tools no PATH e sobrescreve buildtools/linux64/gn.
# ONDE: roda no container axuz-office-builder:snapshot (run-build.sh, stage gn). Idempotente (pula se ja existe).
# EFEITO: /ws/toolchain/bin/gn e /ws/toolchain/bin/ninja.
set -euo pipefail
source /recipe/lib/lock.sh
T=/ws/toolchain; B="$T/bin"; S="$T/src-git"
mkdir -p "$B" "$S"
if [[ ! -x "$B/ninja" ]]; then
  lock_git ninja-src "$S/ninja"
  # estatico: o V8 roda gn/ninja com LD_LIBRARY_PATH do sysroot xenial (libc 2.23), que quebraria um binario dinamico
  ( cd "$S/ninja" && LDFLAGS="-static" python3 configure.py --bootstrap && cp ninja "$B/ninja" )
fi
if [[ ! -x "$B/gn" ]]; then
  lock_git gn-src "$S/gn"
  ( cd "$S/gn" && CC=gcc CXX=g++ AR=ar LDFLAGS="-static" python3 build/gen.py && "$B/ninja" -C out -j"${AXUZ_JOBS:-4}" gn && cp out/gn "$B/gn" )
fi
"$B/ninja" --version
"$B/gn" --version || true
echo "gn/ninja ok"
