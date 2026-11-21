#!/usr/bin/env bash
# axuz_ops/office/wasm/test-lib/run.sh — corpo comum dos test.sh (engine, zlib, spell).
# O QUE: roda <modulo>/test.js dentro da imagem emsdk do modulo (node embutido), offline, com o wasm novo, o wasm
#   upstream (do sdkjs) e o glue; sha256 novo vs upstream vai para a saida. Com --red, prova que o teste fica
#   VERMELHO: (a) o glue pede um export inexistente, (b) um byte do wasm novo e adulterado.
# Sourceado. Uso: hzs_test_main <modulo> <arq.wasm> <wasm-no-sdkjs> <glue-no-sdkjs> --built DIR --sdkjs DIR [--red]
source "$(dirname "${BASH_SOURCE[0]}")/../_hzs-common.sh"

# hzs_test_main — ver cabecalho. Onde: <modulo>/test.sh.
hzs_test_main() {
  local mod="$1" wasm="$2" up_rel="$3" glue_rel="$4"; shift 4
  local built="" sdkjs="" red=0 aux=""
  while (( $# )); do case "$1" in --built) built="$2"; shift 2;; --sdkjs) sdkjs="$2"; shift 2;; --red) red=1; shift;; --aux) aux="$2"; shift 2;; *) hzs_die "arg: $1";; esac; done
  [[ -f "$built/$wasm" && -f "$sdkjs/$up_rel" && -f "$sdkjs/$glue_rel" ]] || hzs_die "faltam arquivos (built/$wasm, sdkjs/$up_rel, sdkjs/$glue_rel)"
  built="$(cd "$built" && pwd)"; sdkjs="$(cd "$sdkjs" && pwd)"
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local ref; ref="$(hzs_image "$here/$mod/emsdk.lock")"
  echo "sha256 novo      : $(sha256sum "$built/$wasm" | cut -d' ' -f1)"
  echo "sha256 upstream  : $(sha256sum "$sdkjs/$up_rel" | cut -d' ' -f1)"
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  cp "$built/$wasm" "$tmp/ours.wasm"; cp "$sdkjs/$up_rel" "$tmp/up.wasm"; cp "$sdkjs/$glue_rel" "$tmp/glue.js"; cp "$sdkjs/$glue_rel" "$tmp/glue_up.js"   # glue_up: o do sdkjs (upstream) carrega o wasm upstream
  # glue regenerado pelo build (par wasm+glue quando os nomes minificados mudam) tem precedencia sobre o do sdkjs
  [[ ! -f "$built/$(basename "$glue_rel")" ]] || { cp "$built/$(basename "$glue_rel")" "$tmp/glue.js"; echo "glue: $(basename "$glue_rel") do build (par)"; }
  chmod -R a+rX "$tmp"
  local mounts=(-v "$here:/recipe:ro" -v "$tmp:/t:ro"); local extra=()
  [[ -z "$aux" ]] || { mounts+=(-v "$(cd "$aux" && pwd):/aux:ro"); extra=(/aux); }
  local run=(docker run --rm --network=none "${mounts[@]}" -w "/recipe/$mod" "$ref" node)
  echo "== verde: novo vs upstream"
  "${run[@]}" test.js /t/ours.wasm /t/up.wasm /t/glue.js /t/glue_up.js "${extra[@]}" 2>&1 | sed 's/^/   /'
  [[ "${PIPESTATUS[0]}" == 0 ]] || return 1
  (( red )) || return 0
  echo "== vermelho (a): glue pede export que o wasm nao tem"
  python3 - "$tmp/glue.js" "$tmp/glue_red.js" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
n = re.sub(r'(Module\["\w+"\]=function\(\)\{return\(\w+=Module\["\w+"\]=Module\["asm"\]\[")(\w+)("\]\))', r'\1zz_inexistente\3', s, count=1)
assert n != s; open(sys.argv[2], 'w').write(n)
PY
  if "${run[@]}" test.js /t/ours.wasm /t/up.wasm /t/glue_red.js /t/glue_up.js "${extra[@]}" >"$tmp/red_a.log" 2>&1; then echo "ERRO: deveria falhar"; return 1; else sed 's/^/   /' "$tmp/red_a.log" | head -3; echo "   (falhou como esperado)"; fi
  echo "== vermelho (b): wasm novo adulterado (1 byte no meio)"
  python3 - "$tmp/ours.wasm" "$tmp/bad.wasm" <<'PY'
import sys
b = bytearray(open(sys.argv[1], 'rb').read()); b[len(b) // 2] ^= 0xFF; open(sys.argv[2], 'wb').write(b)
PY
  if "${run[@]}" test.js /t/bad.wasm /t/up.wasm /t/glue.js /t/glue_up.js "${extra[@]}" >"$tmp/red_b.log" 2>&1; then echo "ERRO: deveria falhar"; return 1; else sed 's/^/   /' "$tmp/red_b.log" | head -3; echo "   (falhou como esperado)"; fi
}
