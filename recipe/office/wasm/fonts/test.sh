#!/usr/bin/env bash
# office/wasm/fonts/test.sh [--out DIR] [--sdkjs DIR] [--fonts DIR] [--red] [--repro] — prova fonts.wasm (do fonte) x upstream.
#
# O QUE: offline (docker --network none), node no container emscripten fixado por digest: carrega o fonts.wasm NOSSO (--out, saida de
#   build.sh) e o upstream (<sdkjs>/common/libfont/engine/fonts.wasm) e compara metricas, bitmaps rasterizados, kerning e shaping
#   (HarfBuzz) de fontes livres (TTF, OTF/CFF, TTC) e a cobertura de exports usados pelo sdkjs. Ver test.js.
# --red   : induz uma divergencia (load-mode diferente num lado) e EXIGE que o teste falhe (prova de que ele enxerga diferenca).
# --repro : alem disso, confere que a saida em --out e identica a um segundo build (arquivo OUT2 via env REPRO_OUT).
# ENV: AXUZ_OFFICE_WS (default <repo>/.build/office) localiza work/sdkjs e work/core-fonts quando nao passados.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WS="${AXUZ_OFFICE_WS:-$(cd "$HERE/../../../.." && pwd)/.build/office}"
OUT="" SDKJS="$WS/work/sdkjs" FONTS="$WS/work/core-fonts" RED=0 REPRO=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --sdkjs) SDKJS="$2"; shift 2 ;;
    --fonts) FONTS="$2"; shift 2 ;;
    --red) RED=1; shift ;;
    --repro) REPRO=1; shift ;;
    *) echo "uso: $0 [--out DIR] [--sdkjs DIR] [--fonts DIR] [--red] [--repro]" >&2; exit 2 ;;
  esac
done
[[ -n "$OUT" && -f "$OUT/fonts.wasm" && -f "$OUT/fonts.js" ]] || { echo "ERRO: --out precisa conter fonts.wasm e fonts.js (rode build.sh)" >&2; exit 2; }
lock() { sed -n "s/^$1=//p" "$HERE/emsdk.lock" | head -1; }
IMG="$(lock image)@$(lock digest)"
UP="$SDKJS/common/libfont/engine"
[[ -f "$UP/fonts.wasm" && -f "$UP/fonts.js" ]] || { echo "ERRO: upstream ausente em $UP" >&2; exit 2; }
OUT="$(cd "$OUT" && pwd)"
echo "ours    sha256 $(sha256sum "$OUT/fonts.wasm" | cut -d' ' -f1)"
echo "upstream sha256 $(sha256sum "$UP/fonts.wasm" | cut -d' ' -f1)"
if [[ "$REPRO" == 1 ]]; then
  [[ -n "${REPRO_OUT:-}" && -f "$REPRO_OUT/fonts.wasm" ]] || { echo "ERRO: --repro exige REPRO_OUT=<dir do 2o build>" >&2; exit 2; }
  for f in fonts.wasm fonts.js; do
    cmp "$OUT/$f" "$REPRO_OUT/$f" || { echo "FALHOU reprodutibilidade: $f difere entre dois builds" >&2; exit 1; }
  done
  echo "reprodutibilidade: fonts.wasm e fonts.js identicos entre dois builds"
fi
ARGS=()
[[ "$RED" == 1 ]] && ARGS+=(--red)
set +e
docker run --rm --network none -v "$HERE:/recipe:ro" -v "$OUT:/ours:ro" -v "$UP:/up:ro" -v "$SDKJS:/sdkjs:ro" -v "$FONTS:/fonts:ro" "$IMG" \
  node /recipe/test.js /ours /up /sdkjs /fonts /recipe/test-fonts.txt "${ARGS[@]}"
rc=$?
set -e
if [[ "$RED" == 1 ]]; then
  if [[ $rc -eq 1 ]]; then echo "RED confirmado: o teste falhou como deveria (rc=1)"; exit 0; fi
  echo "ERRO: --red deveria falhar (rc=1) mas rc=$rc: o teste esta cego" >&2; exit 1
fi
exit $rc
