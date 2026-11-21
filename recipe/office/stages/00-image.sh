#!/usr/bin/env bash
# axuz_ops/office/stages/00-image.sh — constroi a imagem de build (Dockerfile.builder) e a do sysroot xenial.
# O QUE: docker build das duas imagens, ambas por digest + apt; registra a lista de pacotes em logs/.
# ONDE: run-build.sh (stage image). Roda no host (so docker build, sem codigo do projeto).
set -euo pipefail
OFFICE="${OFFICE:?}"; WS="${AXUZ_OFFICE_WS:?}"
docker build -q -f "$OFFICE/Dockerfile.builder" -t axuz-office-builder:snapshot "$OFFICE" >/dev/null
docker build -q -f "$OFFICE/Dockerfile.sysroot" -t axuz-office-sysroot:xenial "$OFFICE" >/dev/null
docker run --rm axuz-office-builder:snapshot cat /etc/axuz-builder-packages.txt > "$WS/logs/builder-packages.txt"
docker run --rm axuz-office-sysroot:xenial dpkg-query -W | tr '\t' '=' | sed 's/:amd64=/=/' | sort > "$WS/logs/sysroot-packages.txt"
# o sysroot reconstruido tem de ter exatamente os pacote=versao de sysroot-packages.txt (+ dependencias)
missing="$(comm -23 <(sort "$OFFICE/sysroot-packages.txt") "$WS/logs/sysroot-packages.txt" || true)"
[[ -z "$missing" ]] || { echo "sysroot sem pacote=versao pedido:" >&2; echo "$missing" >&2; exit 5; }
echo "imagens ok: $(wc -l < "$WS/logs/builder-packages.txt") pacotes (builder), $(wc -l < "$WS/logs/sysroot-packages.txt") (sysroot)"
