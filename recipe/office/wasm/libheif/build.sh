#!/usr/bin/env bash
# office/wasm/libheif/build.sh — compila libheif (+ libde265) do FONTE para wasm: o `libheif-bundle.js` que o heic-decode do DocService carrega.
#
# O QUE: o npm `libheif-js` traz um .wasm pre-compilado (binario de terceiro). O DocService so usa `libheif-js/wasm-bundle`
#   (= libheif-wasm/libheif-bundle.js, wasm em base64 dentro do JS). Aqui compilamos o mesmo artefato: libheif (commit do blobs.lock,
#   3p-heif-libheif) + libde265 (3p-heif-libde265) com emscripten por digest (emsdk.lock), usando o post.js e a receita do proprio
#   libheif (build-emscripten.sh): -lembind, MODULARIZE, EXPORT_NAME=libheif, +SINGLE_FILE para embutir o wasm. So decodificador HEVC (libde265):
#   sem x265/aom/dav1d/encoders, sem plugin loading (igual ao libheif-js).
# USO: build.sh --core DIR --out DIR [--jobs N]
#   --core  checkout do ONLYOFFICE/core (Common/3dParty/heif/{libheif,libde265} nos commits do lock; somente leitura)
#   --out   saida: libheif-bundle.js, BUILD-INFO.txt
# REDE: nenhuma alem da imagem emsdk por digest (docker pull so se ausente).
# DETERMINISMO: caminhos fixos no container, SOURCE_DATE_EPOCH fixo, -j so afeta tempo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { printf 'AXUZ-LIBHEIF: %s\n' "$*" >&2; exit 3; }
CORE="" OUT="" JOBS="${AXUZ_JOBS:-4}"
while (($#)); do
  case "$1" in --core) CORE="$2"; shift 2;; --out) OUT="$2"; shift 2;; --jobs) JOBS="$2"; shift 2;; *) die "argumento desconhecido: $1";; esac
done
H="$CORE/Common/3dParty/heif"
[[ -d "$H/libheif/libheif" && -d "$H/libde265/libde265" ]] || die "--core invalido: $CORE"
[[ -f "$H/libheif/post.js" ]] || die "post.js do libheif ausente"
[[ -n "$OUT" ]] || die "--out obrigatorio"
LOCK="${LOCK_FILE:-$HERE/../../blobs.lock}"
# pin: o HEAD de cada fonte tem de ser o commit do lock (fail-closed)
for pair in libheif:3p-heif-libheif libde265:3p-heif-libde265; do
  d="${pair%%:*}"; id="${pair##*:}"; pin="$(awk -F'\t' -v i="$id" '$1==i{print $5}' "$LOCK")"
  [[ "$(git -C "$H/$d" rev-parse HEAD)" == "$pin" ]] || die "HEAD de $d != $pin (lock $id)"
done
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
# shellcheck source=/dev/null
source "$HERE/emsdk.lock"
docker image inspect "$EMSDK_IMAGE" >/dev/null 2>&1 || docker pull -q "$EMSDK_IMAGE" >/dev/null || die "pull $EMSDK_IMAGE falhou"
WORK="$(mktemp -d "${AXUZ_OFFICE_WORK:-${TMPDIR:-/var/tmp}}/libheif-work.XXXXXX")"
trap 'docker run --rm -v "$WORK":/x alpine:3 sh -c "rm -rf /x/* /x/.[!.]*" >/dev/null 2>&1 || true; rmdir "$WORK" 2>/dev/null || true' EXIT
RAW="$WORK/out"; mkdir -p "$RAW" "$WORK/w"
docker run --rm --memory="${OFFICE_MEM:-6g}" --cpus="${OFFICE_CPUS:-4}" \
  -e SOURCE_DATE_EPOCH=1700000000 -e TZ=UTC -e LC_ALL=C -e JOBS="$JOBS" \
  -v "$H/libheif":/src/libheif:ro -v "$H/libde265":/src/libde265:ro -v "$HERE":/recipe:ro -v "$WORK/w":/w -v "$RAW":/out "$EMSDK_IMAGE" \
  bash /recipe/inner.sh
cp "$RAW/libheif-bundle.js" "$OUT/libheif-bundle.js"
{
  echo "emsdk=$EMSDK_IMAGE"
  echo "libheif=$(git -C "$H/libheif" rev-parse HEAD)"; echo "libde265=$(git -C "$H/libde265" rev-parse HEAD)"
  echo "libheif-bundle.js sha256=$(sha256sum "$OUT/libheif-bundle.js" | cut -d' ' -f1)"
} > "$OUT/BUILD-INFO.txt"
cat "$OUT/BUILD-INFO.txt"
