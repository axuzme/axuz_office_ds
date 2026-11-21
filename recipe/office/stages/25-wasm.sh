#!/usr/bin/env bash
# axuz_ops/office/stages/25-wasm.sh — compila do fonte C++ os .wasm que o sdkjs versiona como binario e os instala na arvore do sdkjs.
#
# O QUE: para cada office/wasm/<modulo>/build.sh presente (engine, zlib, spell, fonts, drawingfile...), roda
#   `build.sh --core <core> --sdkjs <sdkjs> --out <saida>` — em PARALELO (AXUZ_WASM_PAR, default min(nproc,4); a
#   instalacao e sempre paralela, piso 15) — e copia cada arquivo gerado por cima do arquivo de mesmo caminho do sdkjs
#   (caminho relativo ao sdkjs primeiro; senao pelo nome, que tem de ser unico na arvore). Modulos sem build.sh
#   continuam com o binario pinado no blobs.lock (o check-no-blob.sh o confere). Registra sha256 de cada saida.
# ONDE: roda no HOST (como image/sysroot: cada build.sh sobe o seu container emsdk por digest), depois de `prepare`
#   (que deixa /work/sdkjs limpo) e ANTES de `server` (que empacota o sdkjs). run-build.sh: stage `wasm`.
# EFEITO: <ws>/work/sdkjs/**.wasm substituidos (arvore de trabalho; o HEAD do sdkjs nao muda); <ws>/wasm-out/<modulo>/;
#   <ws>/logs/wasm-built.tsv. Falha se um build.sh falhar ou se um arquivo gerado nao achar destino unico.
set -euo pipefail
OFFICE="${OFFICE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WS="${AXUZ_OFFICE_WS:?AXUZ_OFFICE_WS nao definido (use run-build.sh)}"
CORE="$WS/work/core"; SDKJS="$WS/work/sdkjs"
[[ -f "$WS/work/prepare.ok" ]] || { echo "AXUZ-WASM: rode o stage prepare antes" >&2; exit 3; }
LOCK="${LOCK_FILE:-$OFFICE/blobs.lock}"
PAR="${AXUZ_WASM_PAR:-$(( $(nproc) < 4 ? $(nproc) : 4 ))}"
mkdir -p "$WS/wasm-out" "$WS/logs"

# install_outputs <modulo> <outdir> — copia cada arquivo de <outdir> para o destino no sdkjs e registra o sha256.
# Onde: apos cada build.sh. Destino ambiguo ou ausente = erro (nunca "melhor palpite").
install_outputs() {
  local mod="$1" out="$2" f rel dst n sha pin
  while IFS= read -r f; do
    rel="${f#"$out"/}"
    if [[ -f "$SDKJS/$rel" ]]; then dst="$SDKJS/$rel"
    else
      # 1o o caminho EXPLICITO do blobs.lock (classes wasm/glue): o sdkjs tem basenames repetidos (hash/engine.js do modulo
      # engine x libfont/engine.js), entao a busca por nome so vale para o que o lock nao resolve. Resolucao pelo lock tambem
      # tem de ser unica e o arquivo tem de existir no sdkjs.
      mapfile -t cand < <(awk -F'\t' -v b="$(basename "$rel")" -v s="$SDKJS" \
        '($2=="wasm"||$2=="glue") { o=$4; sub(/^sdkjs\//,"",o); n=split(o,p,"/"); if (p[n]==b) print s "/" o }' "$LOCK" | while IFS= read -r c; do [[ -f "$c" ]] && echo "$c"; done)
      if (( ${#cand[@]} == 0 )); then
        mapfile -t cand < <(find "$SDKJS" -name "$(basename "$rel")" -type f -not -path '*/node_modules/*')
      fi
      n="${#cand[@]}"
      (( n == 1 )) || { echo "AXUZ-WASM: $mod: '$rel' tem $n destinos no sdkjs (esperado 1)" >&2; return 3; }
      dst="${cand[0]}"
    fi
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    # a saida do NOSSO build tem de bater com o pin do blobs.lock (classes wasm/glue): build nao deterministico = erro
    pin="$(awk -F'\t' -v o="sdkjs/${dst#"$SDKJS"/}" '($2=="wasm"||$2=="glue") && $4==o {print $5}' "$LOCK")"
    [[ -n "$pin" ]] || { echo "AXUZ-WASM: $mod: ${dst#"$SDKJS"/} sem linha wasm/glue no blobs.lock" >&2; return 3; }
    [[ "$pin" == "sha256:$sha" ]] || { echo "AXUZ-WASM: $mod: ${dst#"$SDKJS"/} sha256:$sha != lock $pin" >&2; return 3; }
    cp "$f" "$dst"
    printf '%s\t%s\t%s\n' "$mod" "$(sha256sum "$f" | cut -d' ' -f1)" "${dst#"$SDKJS"/}" >> "$WS/logs/wasm-built.tsv"
    echo "wasm: $mod -> ${dst#"$SDKJS"/}"
  done < <(find "$out" -type f -not -name BUILD-INFO.txt | sort)
}

: > "$WS/logs/wasm-built.tsv"
mods=()
for b in "$OFFICE"/wasm/*/build.sh; do
  [[ -f "$b" ]] || continue
  m="$(basename "$(dirname "$b")")"
  # AXUZ_WASM_MODULES="engine spell" restringe (teste do stage); vazio = todos os que tem build.sh
  [[ -z "${AXUZ_WASM_MODULES:-}" || " $AXUZ_WASM_MODULES " == *" $m "* ]] && mods+=("$m")
done
(( ${#mods[@]} )) || { echo "AXUZ-WASM: nenhum office/wasm/*/build.sh (nada a compilar)"; exit 0; }
echo "wasm: modulos ${mods[*]} (paralelo $PAR)"

pids=(); names=()
for m in "${mods[@]}"; do
  while (( ${#pids[@]} >= PAR )); do
    wait "${pids[0]}" || { echo "AXUZ-WASM: modulo ${names[0]} falhou (ver $WS/logs/wasm-${names[0]}.log)" >&2; exit 3; }
    pids=("${pids[@]:1}"); names=("${names[@]:1}")
  done
  rm -rf "$WS/wasm-out/$m"; mkdir -p "$WS/wasm-out/$m"
  bash "$OFFICE/wasm/$m/build.sh" --core "$CORE" --sdkjs "$SDKJS" --out "$WS/wasm-out/$m" > "$WS/logs/wasm-$m.log" 2>&1 &
  pids+=("$!"); names+=("$m")
done
for i in "${!pids[@]}"; do
  wait "${pids[$i]}" || { echo "AXUZ-WASM: modulo ${names[$i]} falhou (ver $WS/logs/wasm-${names[$i]}.log)" >&2; tail -20 "$WS/logs/wasm-${names[$i]}.log" >&2; exit 3; }
done
for m in "${mods[@]}"; do install_outputs "$m" "$WS/wasm-out/$m"; done
# asm.js do IE11 (*_ie.js, spell.js.mem): o patch sdkjs-0001 tira os loaders; os arquivos upstream saem da arvore (nao distribuimos
# emscripten versionado que nao geramos). Todo .wasm/glue do lock precisa ter sido regenerado (so sem filtro de modulos).
find "$SDKJS" \( -name '*_ie.js' -o -name '*.js.mem' \) -not -path '*/node_modules/*' -type f -print -delete | sed 's/^/wasm: removido /'
if [[ -z "${AXUZ_WASM_MODULES:-}" ]]; then
  while IFS=$'\t' read -r id classe _ origem _; do
    [[ "$classe" == wasm || "$classe" == glue ]] || continue
    grep -qF "$(printf '\t%s' "${origem#sdkjs/}")" "$WS/logs/wasm-built.tsv" || { echo "AXUZ-WASM: $id ($origem) nao foi gerado pelo build" >&2; exit 3; }
  done < <(tail -n +2 "$LOCK")
fi
echo "wasm ok: ${#mods[@]} modulo(s) compilados do fonte"
