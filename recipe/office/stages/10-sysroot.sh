#!/usr/bin/env bash
# axuz_ops/office/stages/10-sysroot.sh — exporta o rootfs xenial da imagem axuz-office-sysroot:xenial para
#   <ws>/work/build_tools/tools/linux/sysroot/ubuntu16-amd64-sysroot e aplica os ajustes de linker/symlink do
#   fetch.py original (funcao patch_linker_scripts), sem baixar o tarball opaco do ONLYOFFICE-data.
# ONDE: run-build.sh (stage sysroot). Efeito: recria a pasta do sysroot (somente dentro do workspace de build).
set -euo pipefail
WS="${AXUZ_OFFICE_WS:?}"
dst="$WS/work/build_tools/tools/linux/sysroot"
[[ -d "$dst" ]] || { echo "build_tools ausente em $dst" >&2; exit 2; }
cid="$(docker create axuz-office-sysroot:xenial)"
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
rm -rf "$dst/ubuntu16-amd64-sysroot" "$dst"/ubuntu16-*-sysroot* 2>/dev/null || docker run --rm -v "$dst:/out" axuz-office-builder:snapshot sh -c 'rm -rf /out/ubuntu16-*; true'  # axuz-check-ok: limpa o sysroot antigo
mkdir -p "$dst/ubuntu16-amd64-sysroot"
docker export "$cid" | docker run -i --rm -v "$dst:/out" axuz-office-builder:snapshot sh -c 'tar -x -C /out/ubuntu16-amd64-sysroot --exclude=./dev/* && chown -R 1000:1000 /out/ubuntu16-amd64-sysroot'
# symlinks absolutos do export -> relativos ao sysroot (senao o ld resolve libgcc_s no host, glibc 2.35)
python3 -I "$OFFICE/lib/relativize-symlinks.py" "$dst/ubuntu16-amd64-sysroot"
# ajustes do fetch.py do build_tools (linker scripts relativos ao sysroot, symlinks)
( cd "$dst" && python3 - <<'PY'
import importlib.util, sys
sys.path.append('../../../scripts')
spec = importlib.util.spec_from_file_location('fetch', 'fetch.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.patch_linker_scripts('ubuntu16-amd64-sysroot', 'amd64')
PY
)
echo "sysroot ok: $(du -sh "$dst/ubuntu16-amd64-sysroot" | cut -f1)"
