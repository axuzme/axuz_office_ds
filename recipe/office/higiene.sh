#!/usr/bin/env bash
# axuz_ops/office/higiene.sh — higiene do workspace de build do office (piso 29c): dry-run por padrao, --apply explicito.
#
# O QUE: apaga SO (1) intermediarios de .build/office (scratch-*, dfscratch, stage-test, release dry-run, logs de build
#   antigos) e (2) volumes Docker ANONIMOS (nome = 64 hex) sem container. Imprime bytes liberados e disco antes/depois.
# NUNCA: volume nomeado, banco, .env, work/ (fontes pinadas), toolchain/, cache/ (downloads pinados), wasm-out, imagens
#   (emsdk fixados), o artefato (work/build_tools/out), nada fora de AXUZ_OFFICE_WS.
# ONDE: a mao e o fim de cada ciclo de build/teste do office. USO: higiene.sh [--apply] [--ws <dir>]
set -euo pipefail
APPLY=0; WS="${AXUZ_OFFICE_WS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.build/office}"
while (($#)); do case "$1" in --apply) APPLY=1; shift ;; --ws) WS="$2"; shift 2 ;; *) echo "uso: $0 [--apply] [--ws dir]" >&2; exit 2 ;; esac; done
[[ -d "$WS" ]] || { echo "ws inexistente: $WS" >&2; exit 2; }
# --no-docker (teste e hosts sem docker): so os diretorios do ws
NODOCKER="${AXUZ_HIGIENE_NO_DOCKER:-0}"
used_kb() { df -k --output=used / | tail -1 | tr -d ' '; }
before="$(used_kb)"; total=0
echo "modo: $([[ $APPLY == 1 ]] && echo APPLY || echo dry-run) ws=$WS"
for p in scratch-fonts scratch-wasm dfscratch stage-test release mobile-orig; do
  d="$WS/$p"; [[ -e "$d" ]] || continue
  sz="$(du -sk "$d" | cut -f1)"; total=$((total + sz)); echo "  dir $p: $((sz/1024)) MiB"
  [[ $APPLY == 1 ]] && rm -rf -- "$d"
done
[[ "$NODOCKER" == 1 ]] || while IFS= read -r v; do
  [[ "$v" =~ ^[0-9a-f]{64}$ ]] || continue
  echo "  volume anonimo ${v:0:12}"
  [[ $APPLY == 1 ]] && docker volume rm "$v" >/dev/null 2>&1 || true
done < <(docker volume ls -q -f dangling=true)
if [[ $APPLY == 1 ]]; then
  [[ "$NODOCKER" == 1 ]] || docker image prune -f >/dev/null   # so imagens dangling; nunca containers de outros projetos
  after="$(used_kb)"; echo "liberado: $(( (before - after) / 1024 )) MiB (disco antes=$((before/1048576))G depois=$((after/1048576))G)"
else
  echo "dry-run: dirs $((total/1024)) MiB + volumes anonimos (docker system df: ver 'Local Volumes')"
fi
