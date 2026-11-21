#!/usr/bin/env bash
# axuz_ops/office/stages/05-prepare.sh — deixa os repos do build exatamente no estado do lock, com os nossos patches.
#
# O QUE: para cada repo-* do blobs.lock: `git reset --hard` + `git clean -xfd` (descarta saida de build anterior),
#   confere HEAD == commit do lock (fail-closed), aplica os patches de axuz_ops/office/patches (cada um via
#   `git apply --check` antes), restaura schema/postgresql/createdb.sql do commit e45d6029 (sha256 conferido),
#   roda strip-marketing.py e copia os patches para o workspace (evidencia). Tambem expoe o build_tools sem os
#   blobs de tools/linux (python3, qt, sysroot saem do disco: sao reconstruidos pelos stages 10/30).
# ONDE: roda no container axuz-office-builder:snapshot (run-build.sh, stage prepare). Mexe SO em /work (workspace).
# EFEITO: /work/<repo> limpos e patchados; /work/modifications-marketing.tsv; /work/prepare.ok.
set -euo pipefail
source /recipe/lib/lock.sh
git config --global --add safe.directory '*'
W=/work
P=/recipe/patches

# repo_of <id> — nome do repo a partir de repo-<nome>
reset_repo() {
  local id="$1" name pin
  name="${id#repo-}"; pin="$(lock_pin "$id")"
  [[ -d "$W/$name/.git" ]] || lock_die "repo $name ausente em $W (clone por tag nao e feito aqui: sem rede de fonte nao ha pin)"
  git -C "$W/$name" reset -q --hard
  if [[ "$name" == build_tools ]]; then
    # sysroot e Qt sao reconstruidos por stages proprios e ficam no workspace entre execucoes do prepare
    git -C "$W/$name" clean -q -xfd -e tools/linux/sysroot -e tools/linux/qt_build
  else
    git -C "$W/$name" clean -q -xfd
  fi
  [[ "$(git -C "$W/$name" rev-parse HEAD)" == "$pin" ]] || lock_die "HEAD de $name != $pin (lock)"
}
# apply <repo> <patch> — checa e aplica.
apply() {
  local repo="$1" patch="$2"
  git -C "$W/$repo" apply --check "$P/$patch" || lock_die "patch $patch nao aplica em $repo"
  git -C "$W/$repo" apply "$P/$patch"
  echo "patch ok: $repo <- $patch"
}

while IFS=$'\t' read -r id _; do
  [[ "$id" == repo-* ]] && reset_repo "$id"
done < <(tail -n +2 "$LOCK_FILE")

for p in build_tools-0001-jobs-por-env build_tools-0002-pin-depot_tools-e-ninja-jobs build_tools-0003-lock-de-blobs \
         build_tools-0004-v8-sem-cipd-clang-gn build_tools-0005-server-sem-pkg-e-sem-marketplace build_tools-0006-npm-ci-estrito build_tools-0007-sysroot-sem-fetch build_tools-0008-python-do-sistema build_tools-0009-sem-cef-fora-do-desktop build_tools-0010-cmake-do-host-fora-do-ld-path-do-sysroot; do
  apply build_tools "$p.patch"
done
apply web-apps web-apps-0001-mobile-edit.patch
apply web-apps web-apps-0002-mobile-forceview-main.patch
apply web-apps web-apps-0003-sem-imagemin-binario.patch
apply web-apps web-apps-0004-mobile-npm-ci-e-marcador.patch
apply server server-0001-ia-desligada.patch
apply sdkjs sdkjs-0001-sem-asmjs-ie.patch

# schema postgres do commit fixado (a tag v10.0.0.156 nao o contem)
want="$(lock_pin server-createdb)"
mkdir -p "$W/server/schema/postgresql"
git -C "$W/server" show "e45d6029b057aa17d4206fc61c8638924adf67d9:schema/postgresql/createdb.sql" > "$W/server/schema/postgresql/createdb.sql"
[[ "sha256:$(sha256sum "$W/server/schema/postgresql/createdb.sql" | cut -d' ' -f1)" == "$want" ]] || lock_die "createdb.sql diverge do lock"

# wasm/glue do sdkjs: os binarios upstream NAO sao conferidos aqui — o stage 25-wasm os SUBSTITUI por saida do nosso build e
# confere o sha256 do que gerou contra o blobs.lock (classes wasm e glue).

# lockfiles npm: o sha256 do lock vale para o arquivo do repo
while IFS=$'\t' read -r id classe _ origem pin _; do
  [[ "$classe" == npm-lock && "$id" != npm-tools-lock ]] || continue
  got="sha256:$(sha256sum "$W/$origem" | cut -d' ' -f1)"
  [[ "$got" == "$pin" ]] || lock_die "lockfile $origem diverge do lock ($got != $pin)"
done < <(tail -n +2 "$LOCK_FILE")

python3 "$P/strip-marketing.py" "$W"

# blobs opacos do build_tools saem do disco (reconstruidos pelos stages 10/30; nada de python3.tar.gz/qt.7z/sysroot.tar.gz)
purge=(
  "$W/build_tools/tools/linux/python3"  # axuz-check-ok: remocao do blob antigo
  "$W/build_tools/tools/linux/sysroot/ubuntu16-arm64-sysroot"  # axuz-check-ok
  "$W/build_tools/tools/linux/sysroot/ubuntu16-arm64-sysroot.tar.gz"  # axuz-check-ok
  "$W/build_tools/tools/linux/sysroot/ubuntu16-amd64-sysroot.tar.gz"  # axuz-check-ok
  "$W/build_tools/tools/linux/qt_build/Qt-5.9.9/qt_binary_5.9.9_gcc_64.7z"  # axuz-check-ok
  "$W/build_tools/tools/linux/qt_build/Qt-5.9.9/qt_binary_5.9.9_gcc_arm64.7z"  # axuz-check-ok
)
rm -rf "${purge[@]}"
chown -R 1000:1000 "$W" 2>/dev/null || true
date -u +%FT%TZ > "$W/prepare.ok"
echo "prepare ok"
