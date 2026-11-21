#!/usr/bin/env bash
# axuz_ops/office/wasm/zlib/inner.sh — compila sdkjs/common/zlib/engine/zlib.wasm (zip/unzip do editor + decodificacao/encode de imagens).
#
# O QUE: o zlib.wasm do sdkjs e a variante "image" do modulo OfficeUtils/js (zlib_image.json): minizip + zlib 1.2.11 +
#   CxImage/libpng/libtiff/jasper... + Metafile (WMF/EMF) + as funcoes Zlib_* e Raster_*/Image_GetFormat. O fonte exato
#   (core 9a6e7e2dc3, 2022-08-10, commit que fixou o zlib_image.json do binario versionado, sdkjs 0fd923384f) sai da
#   HISTORIA do core (clone completo; os scripts wasm foram removidos do HEAD em 2da2866862/b77b3dc7e2) via git archive
#   no sha pinado; o zlib_image.json vem do proprio snapshot. Build com emcc-json.py --legacy (= make.py de 2022-08).
# ONDE: roda DENTRO do container emsdk (zlib/build.sh -> hzs_docker). /core, /sdkjs ro; /recipe ro; /out rw.
# NOTA: o json lista `CWmfInterpretator.cpp` e o arquivo e `cwmfinterpretator.cpp` (upstream compilava em FS insensivel a
#   caixa); emcc-json.py resolve a caixa do ultimo componente.
set -euo pipefail
SNAP=9a6e7e2dc3c388788fad38d2781118f2ca7d1897
W=/tmp/w; mkdir -p "$W"
# git antigo da imagem 3.1.10 ignora `-c safe.directory`; so a config global vale (efeito so dentro do container)
git config --global --add safe.directory '*'
git -c safe.directory='*' -C /core cat-file -e "$SNAP^{commit}" 2>/dev/null \
  || { echo "AXUZ-WASM: core sem a historia (precisa de clone completo) para $SNAP" >&2; exit 3; }
git -c safe.directory='*' -C /core archive "$SNAP" OfficeUtils Common \
  DesktopEditor/cximage DesktopEditor/raster DesktopEditor/graphics DesktopEditor/common DesktopEditor/xml \
  DesktopEditor/agg-2.4 DesktopEditor/freetype-2.10.4 DesktopEditor/fontengine DesktopEditor/doctrenderer | tar -x -C "$W"
cd "$W/OfficeUtils/js"
python3 /recipe/emcc-json.py zlib_image.json . /tmp/res --legacy
cp /tmp/res/zlib.wasm /out/zlib.wasm; cp /tmp/res/zlib.emcc.js /out/zlib.emcc.js
chown "$HZS_UID:$HZS_GID" /out/zlib.wasm /out/zlib.emcc.js
