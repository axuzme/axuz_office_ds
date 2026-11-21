#!/usr/bin/env bash
# office/wasm/drawingfile/build.sh — compila sdkjs/pdf/src/engine/drawingfile.{wasm,js} do FONTE C++ do ONLYOFFICE core.
#
# O QUE: emscripten 3.1.48 (imagem por digest, emsdk.lock) compila ~800 unidades do core (PdfFile, XpsFile, DjVuFile, OFDFile,
#   graphics, freetype, ICU, libxml2, ...) em drawingfile.wasm e monta o drawingfile.js (glue) = runtime emcc nosso + wrapper do
#   sdkjs (compose_glue.js). Determinístico: caminhos fixos no container, macros de data neutralizadas, ordem de link fixa.
# USO: build.sh --core DIR --sdkjs DIR --out DIR [--jobs N] [--ie]
#   --core  checkout do ONLYOFFICE/core no commit do blobs.lock (somente leitura)
#   --sdkjs checkout do ONLYOFFICE/sdkjs (so le pdf/src/engine/drawingfile.js: wrapper JS)
#   --out   saida: drawingfile.wasm, drawingfile.js, BUILD-INFO.txt
# REDE: so para buscar ICU e libxml2 pelo commit do deps.lock (cache em $AXUZ_OFFICE_CACHE) e a imagem emsdk por digest.
# PISOS: 23 (so do git), 29 (build em maquina de build; rode sob limitado.sh --perfil build).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { printf 'AXUZ-DRAWINGFILE: %s\n' "$*" >&2; exit 3; }
CORE="" SDKJS="" OUT="" JOBS="${AXUZ_JOBS:-4}" IE=""
while (($#)); do
  case "$1" in
    --core) CORE="$2"; shift 2;; --sdkjs) SDKJS="$2"; shift 2;; --out) OUT="$2"; shift 2;;
    --jobs) JOBS="$2"; shift 2;; --ie) IE="--ie"; shift;;
    *) die "argumento desconhecido: $1";;
  esac
done
[[ -d "$CORE/PdfFile" && -d "$CORE/DesktopEditor" ]] || die "--core invalido: $CORE"
[[ -f "$SDKJS/pdf/src/engine/drawingfile.js" ]] || die "--sdkjs invalido: $SDKJS"
[[ -n "$OUT" ]] || die "--out obrigatorio"
CORE="$(cd "$CORE" && pwd)"; SDKJS="$(cd "$SDKJS" && pwd)"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
# shellcheck source=/dev/null
source "$HERE/emsdk.lock"
CACHE="${AXUZ_OFFICE_CACHE:-$(cd "$HERE/../../.." && pwd)/.build/office/cache}/drawingfile"
mkdir -p "$CACHE"

# fetch_pinned <id> — clona o terceiro no commit do deps.lock (git fetch por sha; confere HEAD) em $CACHE/<id>.
fetch_pinned() {
  local id="$1" url sha dir
  url="$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$HERE/deps.lock")"; sha="$(awk -F'\t' -v i="$id" '$1==i{print $3}' "$HERE/deps.lock")"
  [[ -n "$url" && -n "$sha" ]] || die "dep $id ausente do deps.lock"
  dir="$CACHE/$id-$sha"
  if [[ ! -f "$dir/.axuz-commit" ]]; then
    rm -rf "$dir.tmp"; git init -q "$dir.tmp"
    git -C "$dir.tmp" fetch -q --depth 1 "$url" "$sha" || die "fetch $id $sha falhou"
    git -C "$dir.tmp" checkout -q FETCH_HEAD
    [[ "$(git -C "$dir.tmp" rev-parse HEAD)" == "$sha" ]] || die "HEAD de $id != $sha"
    rm -rf "$dir.tmp/.git"; printf '%s' "$sha" > "$dir.tmp/.axuz-commit"; mv "$dir.tmp" "$dir"
  fi
  printf '%s' "$dir"
}
ICU="$(fetch_pinned icu)"; LIBXML="$(fetch_pinned libxml2)"

# imagem por digest (pull so se ausente)
docker image inspect "$EMSDK_IMAGE" >/dev/null 2>&1 || docker pull -q "$EMSDK_IMAGE" >/dev/null || die "pull $EMSDK_IMAGE falhou"
WORK="$(mktemp -d "${AXUZ_OFFICE_WORK:-${TMPDIR:-/var/tmp}}/drawingfile-work.XXXXXX")"
trap 'docker run --rm -v "$WORK":/x alpine:3 sh -c "rm -rf /x/* /x/.[!.]*" >/dev/null 2>&1 || true; rmdir "$WORK" 2>/dev/null || true' EXIT
RAW="$WORK/out"; mkdir -p "$RAW" "$WORK/w"
docker run --rm --memory="${OFFICE_MEM:-8g}" --cpus="${OFFICE_CPUS:-4}" \
  -e SOURCE_DATE_EPOCH=1700000000 -e TZ=UTC -e LC_ALL=C \
  -v "$CORE":/core:ro -v "$SDKJS":/sdkjs:ro -v "$ICU":/icu:ro -v "$LIBXML":/libxml:ro -v "$HERE":/recipe:ro \
  -v "$WORK/w":/w -v "$RAW":/out "$EMSDK_IMAGE" \
  bash -c "set -euo pipefail
    python3 /recipe/make_wasm.py --core /core --icu /icu --libxml /libxml --recipe /recipe --work /w --out /out --jobs $JOBS $IE
    node /recipe/compose_glue.js /out/obj-wasm/drawingfile.js /sdkjs/pdf/src/engine/drawingfile.js /out/drawingfile.js
    chown -R $(id -u):$(id -g) /out"
cp "$RAW/obj-wasm/drawingfile.wasm" "$OUT/drawingfile.wasm"
cp "$RAW/drawingfile.js" "$OUT/drawingfile.js"
{
  echo "emsdk=$EMSDK_IMAGE"; echo "core_head=$(git -C "$CORE" rev-parse HEAD 2>/dev/null || echo desconhecido)"
  echo "icu=$(cat "$ICU/.axuz-commit")"; echo "libxml2=$(cat "$LIBXML/.axuz-commit")"
  echo "drawingfile.wasm sha256=$(sha256sum "$OUT/drawingfile.wasm" | cut -d' ' -f1)"
  echo "drawingfile.js sha256=$(sha256sum "$OUT/drawingfile.js" | cut -d' ' -f1)"
} > "$OUT/BUILD-INFO.txt"
cat "$OUT/BUILD-INFO.txt"
