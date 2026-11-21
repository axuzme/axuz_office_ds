#!/usr/bin/env bash
# axuz_ops/office/run-build.sh — orquestra o build do ONLYOFFICE Document Server SEM blob de terceiro (O1.a-pre).
#
# O QUE: roda os stages em ordem, cada um num container com teto de recursos (10g / 6 cpus, AXUZ_JOBS=4):
#   image    imagem de build (ubuntu:24.04 por digest + apt do snapshot) e imagem do sysroot   [00-image.sh]
#   prepare  repos do lock limpos, pins conferidos, patches aplicados, createdb.sql           [05-prepare.sh]
#   sysroot  rootfs xenial reconstruido do archive oficial -> tools/linux/sysroot             [10-sysroot.sh]
#   node     Node 20.19.6 compilado do fonte (+ grunt-cli por lockfile)                       [20-node.sh]
#   qt       Qt 5.9.9 compilado do fonte no sysroot xenial                                    [30-qt.sh]
#   gn       gn e ninja compilados do fonte                                                   [40-gn-ninja.sh]
#   wasm     .wasm do sdkjs (engine/zlib/spell/...) compilados do fonte C++ com emsdk por digest [25-wasm.sh]
#   server   configure/make do build_tools (core + sdkjs + web-apps + server)                 [50-server.sh]
#   mobile   build do editor mobile (word/cell/slide) a partir do src patchado; substitui o dist upstream [52-mobile.sh]
#   heif     libheif-bundle.js (wasm do HEIC) compilado do fonte no lugar do prebuild do npm libheif-js [53-heif.sh]
#   seal     poda blob npm inutil (oracledb, bare-*, win-ca exe) e registra a origem dos binarios que compilamos [55-seal.sh]
#   verify   confere pins, hashes e avisos AGPL no artefato                                   [60-verify.sh]
# ONDE: workspace de build FORA do git: AXUZ_OFFICE_WS (default <repo>/.build/office). Esta pasta e a receita.
#   Chame sob limite: bash axuz_ops/scripts/limitado.sh --perfil build --mem 10G --jobs 1 -- bash axuz_ops/office/run-build.sh <stage...>
# DISCO: aborta se / ficar < 10G livres (checado antes de cada stage).
# Pisos: 29 (build em maquina dev/hml, higiene), 23 (so do git: o que sai daqui nao e promovivel sem build limpo do git).
set -euo pipefail
OFFICE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$OFFICE/../.." && pwd)"
export AXUZ_OFFICE_WS="${AXUZ_OFFICE_WS:-$REPO/.build/office}"
export OFFICE AXUZ_JOBS="${AXUZ_JOBS:-4}" OFFICE_MEM="${OFFICE_MEM:-10g}" OFFICE_CPUS="${OFFICE_CPUS:-6}"
export DEPOT_TOOLS_METRICS=0
AXUZ_OPS_COMMIT="$(git -C "$OFFICE" rev-parse HEAD 2>/dev/null || echo desconhecido)"
AXUZ_OPS_DIRTY="$(git -C "$OFFICE" status --porcelain -- . ../security/office 2>/dev/null | wc -l)"
export AXUZ_OPS_COMMIT AXUZ_OPS_DIRTY
# shellcheck source=lib/lock.sh
source "$OFFICE/lib/lock.sh"

# disco_ok — falha se / tem menos de 10G livres. Onde: antes de cada stage.
disco_ok() {
  local av; av=$(( $(stat -f -c '%a * %S' /) / 1073741824 ))
  (( av >= 10 )) || { echo "DISCO_BAIXO: ${av}G livres em / (<10G); abortando" >&2; exit 4; }
}

# run_in <imagem> <nome> <comando...> — docker run com teto, recipe ro em /recipe, ws em /ws, repos em /work.
# Onde: stages que rodam em container.
run_in() {
  local img="$1" name="$2"; shift 2
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run --rm --name "$name" --memory="$OFFICE_MEM" --memory-swap="$OFFICE_MEM" --cpus="$OFFICE_CPUS" --cpu-shares=128 \
    -e AXUZ_JOBS -e TZ=Etc/UTC -e DEPOT_TOOLS_METRICS=0 -e DEPOT_TOOLS_UPDATE=0 -e AXUZ_BLOB_LOCK=/recipe/blobs.lock \
    -e AXUZ_OPS_COMMIT -e AXUZ_OPS_DIRTY -v "$OFFICE/../security/office:/security:ro" \
    -v "$OFFICE:/recipe:ro" -v "$AXUZ_OFFICE_WS:/ws" -v "$AXUZ_OFFICE_WS/work:/work" -w /work "$img" "$@"
}

stages=("$@")
[[ ${#stages[@]} -gt 0 ]] || stages=(image prepare sysroot node qt gn wasm server mobile heif seal verify)
mkdir -p "$AXUZ_OFFICE_WS/work" "$AXUZ_OFFICE_WS/toolchain/src" "$AXUZ_OFFICE_WS/logs"
for s in "${stages[@]}"; do
  disco_ok
  echo "== stage $s $(date +%T) =="
  case "$s" in
    image)   bash "$OFFICE/stages/00-image.sh" ;;
    prepare) run_in axuz-office-builder:snapshot axuz-office-prepare bash /recipe/stages/05-prepare.sh ;;
    sysroot) bash "$OFFICE/stages/10-sysroot.sh" ;;
    node)    run_in axuz-office-builder:snapshot axuz-office-node bash /recipe/stages/20-node.sh ;;
    qt)      run_in axuz-office-sysroot:xenial axuz-office-qt bash /recipe/stages/30-qt.sh ;;
    gn)      run_in axuz-office-builder:snapshot axuz-office-gn bash /recipe/stages/40-gn-ninja.sh ;;
    wasm)    bash "$OFFICE/stages/25-wasm.sh" ;;
    server)  run_in axuz-office-builder:snapshot axuz-office-build bash /recipe/stages/50-server.sh "${AXUZ_SERVER_MODULES:-server}" ;;
    mobile)  run_in axuz-office-builder:snapshot axuz-office-mobile bash /recipe/stages/52-mobile.sh ;;
    heif)    bash "$OFFICE/stages/53-heif.sh" ;;
    seal)    run_in axuz-office-builder:snapshot axuz-office-seal bash /recipe/stages/55-seal.sh ;;
    verify)  run_in axuz-office-builder:snapshot axuz-office-verify bash /recipe/stages/60-verify.sh ;;
    *) echo "stage desconhecido: $s" >&2; exit 2 ;;
  esac
done
