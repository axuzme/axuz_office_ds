#!/usr/bin/env bash
# axuz_ops/office/wasm/_hzs-common.sh — biblioteca dos build.sh de engine, zlib e spell (SOURCEAVEL, sem set -e proprio).
#
# O QUE: parse de `--core DIR --sdkjs DIR --out DIR`, leitura do emsdk.lock (imagem por DIGEST) e `hzs_docker`, que roda
#   o script interno do modulo (inner.sh) dentro da imagem emsdk fixada, com core/sdkjs somente-leitura, teto de memoria,
#   sem rede, e devolve o resultado em OUT com o dono do chamador.
# ONDE: sourceado por office/wasm/{engine,zlib,spell}/build.sh; stage 25-wasm.sh chama esses build.sh.
# DETERMINISMO: sem timestamps (emcc nao grava data no .wasm); a imagem e fixada por digest; sem rede no container.

HZS_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# hzs_die <msg> — erro fatal rc 3 (mesmo codigo do lock.sh). Onde: todas as funcoes abaixo.
hzs_die() { printf 'AXUZ-WASM: %s\n' "$*" >&2; exit 3; }

# hzs_args <args...> — preenche HZS_CORE, HZS_SDKJS, HZS_OUT (caminhos absolutos) ou morre. Onde: inicio de cada build.sh.
hzs_args() {
  HZS_CORE=""; HZS_SDKJS=""; HZS_OUT=""
  while (( $# )); do
    case "$1" in
      --core)  HZS_CORE="$2";  shift 2 ;;
      --sdkjs) HZS_SDKJS="$2"; shift 2 ;;
      --out)   HZS_OUT="$2";   shift 2 ;;
      *) hzs_die "argumento desconhecido: $1 (uso: build.sh --core DIR --sdkjs DIR --out DIR)" ;;
    esac
  done
  [[ -d "$HZS_CORE" && -d "$HZS_SDKJS" && -n "$HZS_OUT" ]] || hzs_die "uso: build.sh --core DIR --sdkjs DIR --out DIR"
  HZS_CORE="$(cd "$HZS_CORE" && pwd)"; HZS_SDKJS="$(cd "$HZS_SDKJS" && pwd)"
  mkdir -p "$HZS_OUT"; HZS_OUT="$(cd "$HZS_OUT" && pwd)"
}

# hzs_image <emsdk.lock> — imprime a referencia `imagem@sha256:...` do lock (1a linha nao-comentario); exige digest.
# Onde: hzs_docker.
hzs_image() {
  local ref; ref="$(grep -vE '^\s*(#|$)' "$1" | head -1 | tr -d '[:space:]')"
  [[ "$ref" =~ ^[a-z0-9./_-]+@sha256:[0-9a-f]{64}$ ]] || hzs_die "emsdk.lock sem imagem@sha256 valido: $1"
  printf '%s' "$ref"
}

# hzs_docker <modulo-dir> <inner.sh args...> — roda <modulo-dir>/inner.sh na imagem do emsdk.lock.
# Montagens: /core e /sdkjs (ro), /recipe = office/wasm (ro), /out (rw). Rede desligada (so o que o lock traz).
# Efeito: arquivos novos em HZS_OUT, com o uid/gid de quem chamou. Falha se a imagem nao estiver local (docker pull
# <ref> e feito uma vez, fora do build; com digest o conteudo e verificavel).
hzs_docker() {
  local mod="$1"; shift
  local ref; ref="$(hzs_image "$mod/emsdk.lock")"
  docker image inspect "$ref" >/dev/null 2>&1 || docker pull -q "$ref" >/dev/null || hzs_die "nao consegui obter $ref"
  docker run --rm --network=none --memory="${HZS_MEM:-6g}" --cpus="${HZS_CPUS:-4}" \
    -e HZS_UID="$(id -u)" -e HZS_GID="$(id -g)" -e HZS_JOBS="${AXUZ_JOBS:-4}" -e EM_FROZEN_CACHE=0 \
    -v "$HZS_CORE:/core:ro" -v "$HZS_SDKJS:/sdkjs:ro" -v "$(cd "$mod/.." && pwd):/recipe:ro" -v "$HZS_OUT:/out" \
    "$ref" bash "/recipe/$(basename "$mod")/inner.sh" "$@"
}

# hzs_glue <modulo> <glue-no-sdkjs> — gera OUT/<modulo>.js: troca o runtime emscripten do wrapper do sdkjs pelo NOSSO (glue.py)
# e descarta o .emcc.js cru. Onde: build.sh de engine/spell/zlib, apos hzs_docker. Efeito: HZS_OUT/<modulo>.js.
hzs_glue() {
  python3 "$HZS_HERE/glue.py" "$HZS_OUT/$1.emcc.js" "$HZS_SDKJS/$2" "$HZS_OUT/$1.js" || hzs_die "glue de $1 falhou"
  rm -f "$HZS_OUT/$1.emcc.js"
}
