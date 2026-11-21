#!/usr/bin/env bash
# axuz_ops/office/lib/lock.sh — leitura do blobs.lock e download/clone verificados (biblioteca, SOURCEAVEL).
#
# O QUE: unica porta de entrada para baixar qualquer coisa no build do ONLYOFFICE DS. Todo download passa por
#   lock_fetch (tarball: confere sha256) ou lock_git (confere o commit). Id ausente do lock => erro (fail-closed).
# ONDE: stages/*.sh e run-build.sh. O lado Python (build_tools) tem o equivalente em patches/build_tools-0003.
# FORMATO: TSV com cabecalho: id classe destino origem pin licenca fonte status nota.
# Sourceado: nao liga set -e por conta propria.

LOCK_FILE="${AXUZ_BLOB_LOCK:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/blobs.lock}"

# lock_die <msg> — erro fatal. Onde: todas as funcoes desta lib.
lock_die() { printf 'AXUZ-NO-BLOB: %s\n' "$*" >&2; exit 3; }

# lock_field <id> <coluna 1-based> — imprime o campo ou vazio. Onde: lock_pin/lock_url e os stages.
lock_field() { awk -F'\t' -v id="$1" -v c="$2" 'NR>1 && $1==id {print $c; exit}' "$LOCK_FILE"; }

# lock_pin <id> — pin (sha256:<hex> ou sha1 de commit) ou erro se o id nao existe. Onde: lock_fetch/lock_git.
lock_pin() {
  local p; p="$(lock_field "$1" 5)"
  [[ -n "$p" ]] || lock_die "id '$1' ausente de $LOCK_FILE"
  printf '%s' "$p"
}

# lock_fetch <id> <destino> — baixa a origem do id e CONFERE o sha256 do lock; falha apaga o arquivo.
# Efeito: cria <destino>. Onde: stages 20/30 (tarballs de fonte).
lock_fetch() {
  local id="$1" dst="$2" url pin got
  url="$(lock_field "$id" 4)"; pin="$(lock_pin "$id")"
  [[ "$pin" == sha256:* ]] || lock_die "id '$id' nao e tarball com sha256 (pin=$pin)"
  if [[ -f "$dst" ]] && [[ "sha256:$(sha256sum "$dst" | cut -d' ' -f1)" == "$pin" ]]; then return 0; fi
  curl -fL --retry 3 -o "$dst.part" "$url" || lock_die "download falhou: $url"
  got="sha256:$(sha256sum "$dst.part" | cut -d' ' -f1)"
  if [[ "$got" != "$pin" ]]; then rm -f "$dst.part"; lock_die "sha256 divergente para $id: $got != $pin"; fi
  mv "$dst.part" "$dst"
}

# lock_git <id> <dir> — clona a origem do id em <dir> e faz checkout do commit do lock (verifica HEAD).
# Efeito: cria <dir>. Onde: stage 40 (gn, ninja).
lock_git() {
  local id="$1" dir="$2" url pin
  url="$(lock_field "$id" 4)"; pin="$(lock_pin "$id")"
  [[ "$pin" =~ ^[0-9a-f]{40}$ ]] || lock_die "id '$id' nao tem commit de 40 hex (pin=$pin)"
  [[ -d "$dir/.git" ]] || git clone --quiet "$url" "$dir" || lock_die "clone falhou: $url"
  git -C "$dir" checkout --quiet "$pin" || lock_die "checkout $pin falhou em $dir"
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$pin" ]] || lock_die "HEAD de $dir diverge de $pin"
}
