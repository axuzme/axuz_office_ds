#!/usr/bin/env bash
# axuz_ops/office/stages/20-node.sh — compila o Node 20.19.6 do FONTE e instala o grunt-cli por lockfile.
#
# O QUE: baixa node-v20.19.6.tar.xz via lock (sha256 conferido), compila com o gcc do snapshot e instala em
#   /ws/toolchain/node. Depois `npm ci` do npm-tools (grunt-cli) com integridade sha512 do lockfile. NADA de
#   nodesource, `npm i -g` sem pin nem @yao-pkg/pkg (o `pkg` embute um node pre-compilado de terceiro; saiu do build).
# ONDE: roda no container axuz-office-builder:snapshot (run-build.sh, stage node). Pula se o node ja foi construido.
# EFEITO: /ws/toolchain/node (prefixo), /ws/toolchain/npm-tools (node_modules/.bin/grunt). Tempo ~1h a -j4.
set -euo pipefail
source /recipe/lib/lock.sh
T=/ws/toolchain; SRC=$T/src
NODE_VER=20.19.6
mkdir -p "$SRC"
if [[ ! -x "$T/node/bin/node" ]]; then
  lock_fetch node-src "$SRC/node-v$NODE_VER.tar.xz"
  rm -rf "$T/node-build"; mkdir -p "$T/node-build"
  tar -xf "$SRC/node-v$NODE_VER.tar.xz" -C "$T/node-build"
  cd "$T/node-build/node-v$NODE_VER"
  ./configure --prefix="$T/node"
  make -j"${AXUZ_JOBS:-4}"
  make install
  cd /; rm -rf "$T/node-build"
fi
export PATH="$T/node/bin:$PATH"
[[ "$(node -v)" == "v$NODE_VER" ]] || lock_die "node instalado nao e v$NODE_VER"
# ferramentas npm so de build, por lockfile (npm ci verifica sha512 de cada pacote)
rm -rf "$T/npm-tools"; mkdir -p "$T/npm-tools"
cp /recipe/npm-tools/package.json /recipe/npm-tools/package-lock.json "$T/npm-tools/"
want="$(lock_pin npm-tools-lock)"
got="sha256:$(sha256sum "$T/npm-tools/package-lock.json" | cut -d' ' -f1)"
[[ "$want" == "$got" ]] || lock_die "package-lock.json do npm-tools diverge do lock ($got != $want)"
( cd "$T/npm-tools" && npm ci --ignore-scripts --no-audit --no-fund )
"$T/npm-tools/node_modules/.bin/grunt" --version
echo "node ok: $(node -v) npm $(npm -v)"
