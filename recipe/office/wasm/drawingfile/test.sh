#!/usr/bin/env bash
# office/wasm/drawingfile/test.sh — prova que o drawingfile.wasm que NOS compilamos se comporta como o do upstream (sdkjs).
#
# O QUE: (1) gera o corpus sintetico (gen_corpus.py) e junta PDFs livres da arvore do ONLYOFFICE (zlib.3.pdf, templates do
#   document-server-integration, doc do hyphen); (2) no container emsdk (node, `--network none`, offline) roda test/harness.js, que
#   carrega upstream e nosso (cada um com a SUA glue) e compara por arquivo: erro/tipo, paginas, info, outline, links, glifos/texto,
#   formularios, anotacoes (+AP), pixmaps (sha256, tolerancia ZERO) e edicao (Split/Merge/Redact/BuildPdf); e confere que a tabela de
#   exports do wasm cobre TODA chamada Module["_X"] do wrapper do sdkjs; (3) mostra os casos VERMELHOS: o mesmo harness com um export
#   removido e com um pixel adulterado DEVE falhar (se passar, o teste esta cego e o script falha).
# USO: test.sh --ours DIR [--sdkjs DIR] [--core DIR] [--templates DIR]
#   --ours  saida do build.sh (drawingfile.wasm + drawingfile.js)
#   --sdkjs checkout do sdkjs com o drawingfile.{wasm,js} upstream (default: <ws>/work/sdkjs)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { printf 'AXUZ-DRAWINGFILE-TEST: %s\n' "$*" >&2; exit 3; }
WS="${AXUZ_OFFICE_WS:-$(cd "$HERE/../../.." && pwd)/.build/office}"
OURS="" SDKJS="$WS/work/sdkjs" CORE="$WS/work/core" TEMPLATES="$WS/work/document-server-integration"
while (($#)); do
  case "$1" in
    --ours) OURS="$2"; shift 2;; --sdkjs) SDKJS="$2"; shift 2;; --core) CORE="$2"; shift 2;; --templates) TEMPLATES="$2"; shift 2;;
    *) die "argumento desconhecido: $1";;
  esac
done
[[ -f "$OURS/drawingfile.wasm" && -f "$OURS/drawingfile.js" ]] || die "--ours sem drawingfile.{wasm,js}: $OURS"
UP="$SDKJS/pdf/src/engine"
[[ -f "$UP/drawingfile.wasm" && -f "$UP/drawingfile.js" ]] || die "upstream ausente em $UP"
# shellcheck source=/dev/null
source "$HERE/emsdk.lock"
docker image inspect "$EMSDK_IMAGE" >/dev/null 2>&1 || docker pull -q "$EMSDK_IMAGE" >/dev/null || die "imagem $EMSDK_IMAGE indisponivel"
T="$(mktemp -d "${TMPDIR:-/var/tmp}/drawingfile-test.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/corpus"
FONT="$(find "$WS/work/core-fonts/liberation" -name 'LiberationSansNarrow-Regular.ttf' 2>/dev/null | head -1)"
python3 -I "$HERE/test/gen_corpus.py" "$T/corpus" ${FONT:+--font "$FONT"}
# PDFs livres da arvore (licencas abertas; so entram se existirem)
add() { [[ -f "$1" ]] && cp "$1" "$T/corpus/$2" || echo "aviso: $1 ausente (fora do corpus)"; }
add "$CORE/OfficeUtils/src/zlib-1.2.11/zlib.3.pdf" real-zlib3.pdf
add "$TEMPLATES/web/documentserver-example/nodejs/public/assets/document-templates/new/new.pdf" real-new.pdf
add "$TEMPLATES/web/documentserver-example/nodejs/public/assets/document-templates/sample/sample.pdf" real-sample.pdf
add "$CORE/Common/3dParty/hyphen/hyphen/doc/tb87nemeth.pdf" real-nemeth.pdf
ls -la "$T/corpus" | sed 's/^/  corpus: /'
run_node() {   # run_node <args-extra...>  — roda o harness offline no container
  docker run --rm --network none -v "$HERE/test":/t:ro -v "$T/corpus":/c:ro -v "$OURS":/ours:ro -v "$UP":/up:ro -v "$T":/o \
    "$EMSDK_IMAGE" node /t/harness.js --up-glue /up/drawingfile.js --up-wasm /up/drawingfile.wasm \
    --our-glue /ours/drawingfile.js --our-wasm /ours/drawingfile.wasm --corpus /c "$@"
}
echo "== 1) comparacao upstream x nosso (tolerancia zero)"
run_node --json /o/result.json
echo "== 2) VERMELHO: export removido (BuildPdf) — o harness DEVE falhar"
if run_node --red export >"$T/red-export.log" 2>&1; then cat "$T/red-export.log"; die "RED export PASSOU: o teste esta cego"; fi
grep -E "COBERTURA|FALHAS" "$T/red-export.log" | head -3 | sed 's/^/  vermelho(export): /'
echo "== 3) VERMELHO: pixel adulterado — o harness DEVE falhar"
if run_node --red pixel >"$T/red-pixel.log" 2>&1; then cat "$T/red-pixel.log"; die "RED pixel PASSOU: o teste esta cego"; fi
grep -E "DIFF|FALHAS" "$T/red-pixel.log" | head -3 | sed 's/^/  vermelho(pixel): /'
echo "OK: drawingfile.wasm nosso == upstream no corpus; vermelhos confirmados"
