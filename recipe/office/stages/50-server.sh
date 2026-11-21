#!/usr/bin/env bash
# axuz_ops/office/stages/50-server.sh — configure + make do build_tools para o modulo server (core + sdkjs + web-apps
#   + server), com a toolchain NOSSA (node, gn, ninja, Qt, sysroot compilados/reconstruidos dos stages anteriores).
#
# O QUE: no lugar do tools/linux/automate.py do upstream (que baixa python3.tar.gz, Qt .7z, sysroot .tar.gz, cmake
#   e instala node via nodesource + pkg), chama direto configure.py/make.py do build_tools patchado, com --update 0
#   (os repos ja estao nos commits do lock, ver 05-prepare.sh). Depois grava o NOTICE/lock/version.json no artefato.
# ONDE: roda no container axuz-office-builder:snapshot (run-build.sh, stage server), teto 10g/6cpus, AXUZ_JOBS=4.
# EFEITO: /work/build_tools/out/linux_64/onlyoffice/documentserver (artefato). Falha se a toolchain nao for a nossa.
set -euo pipefail
source /recipe/lib/lock.sh
T=/ws/toolchain
MODULES="${1:-server}"
Q=/work/build_tools/tools/linux/qt_build/Qt-5.9.9
SYSROOT=/work/build_tools/tools/linux/sysroot/ubuntu16-amd64-sysroot
[[ -f /work/prepare.ok ]] || lock_die "rode o stage prepare antes"
[[ -x "$T/node/bin/node" ]] || lock_die "node proprio ausente (stage node)"
[[ -x "$T/bin/gn" && -x "$T/bin/ninja" ]] || lock_die "gn/ninja proprios ausentes (stage gn)"
[[ -f "$Q/gcc_64/.axuz-qt-from-source" ]] || lock_die "Qt compilado do fonte ausente (stage qt)"
[[ -x "$SYSROOT/usr/bin/gcc" ]] || lock_die "sysroot reconstruido ausente (stage sysroot)"

export PATH="$T/node/bin:$T/npm-tools/node_modules/.bin:$T/bin:$PATH"
export AXUZ_TOOLBIN="$T/bin" AXUZ_NODE_PREFIX="$T/node"
export DEPOT_TOOLS_METRICS=0 DEPOT_TOOLS_UPDATE=0 DEPOT_TOOLS_BOOTSTRAP_PYTHON3=0
git config --global --add safe.directory '*'
ln -sf "$(command -v python3)" /usr/local/bin/python   # o build_tools chama `python`; e o python3 da imagem (apt do snapshot)
echo "toolchain: node $(node -v), python $(python3 -V), gn $("$T/bin/gn" --version 2>&1 | head -1), ninja $("$T/bin/ninja" --version)"

cd /work/build_tools
python3 ./configure.py --branch tags/v10.0.0.176 --module "$MODULES" --sysroot 1 --update 0 --qt-dir "$Q" --multiprocess 1
python3 ./make.py

OUT=/work/build_tools/out/linux_64/onlyoffice/documentserver
[[ -d "$OUT" ]] || lock_die "artefato nao gerado em $OUT"
# avisos AGPL, lock e versoes: entram NO artefato (o fonte correspondente e ofertado a quem usa o editor, AGPL s.13)
sed "s/SOURCE-COMMIT/${AXUZ_OPS_COMMIT:-SOURCE-COMMIT}/" /recipe/NOTICE-AXUZ.txt > "$OUT/NOTICE-AXUZ.txt"
cp /recipe/blobs.lock "$OUT/blobs.lock"
cp /work/modifications-marketing.tsv "$OUT/modifications-marketing.tsv"
{
  printf '{\n  "axuz_ops_commit": "%s",\n  "axuz_ops_dirty": "%s",\n  "built_at": "%s",\n  "node": "%s",\n  "repos": {\n' \
    "${AXUZ_OPS_COMMIT:-desconhecido}" "${AXUZ_OPS_DIRTY:-?}" "$(date -u +%FT%TZ)" "$(node -v)"
  first=1
  for r in build_tools core sdkjs sdkjs-forms web-apps server document-formats document-templates core-fonts dictionaries onlyoffice.github.io; do
    [[ $first -eq 1 ]] || printf ',\n'; first=0
    printf '    "%s": "%s"' "$r" "$(git -C "/work/$r" rev-parse HEAD)"
  done
  printf '\n  }\n}\n'
} > "$OUT/version.json"
chown -R 1000:1000 /work /ws/toolchain 2>/dev/null || true
echo "server ok: $(du -sh "$OUT" | cut -f1)"
