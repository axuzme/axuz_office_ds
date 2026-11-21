#!/usr/bin/env bash
# office/wasm/libheif/inner.sh — roda DENTRO do container emsdk: libde265 e libheif por emcmake, depois o link emcc (build.sh o chama).
set -euo pipefail
cd /w
# 1) libde265 (so a biblioteca; sem decoder/encoder de exemplo, sem SSE)
mkdir -p libde265-b && cd libde265-b
emcmake cmake /src/libde265 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DENABLE_DECODER=OFF -DENABLE_ENCODER=OFF \
  -DDISABLE_SSE=ON -DENABLE_SDL=OFF -DCMAKE_INSTALL_PREFIX=/w/prefix -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3"
emmake make -j"$JOBS" install
cd /w
# 2) libheif: so decodificador HEVC (libde265), sem plugin loading (igual a receita do libheif-js)
mkdir -p libheif-b && cd libheif-b
emcmake cmake /src/libheif -DCMAKE_BUILD_TYPE=Release -DENABLE_MULTITHREADING_SUPPORT=OFF -DWITH_GDK_PIXBUF=OFF -DWITH_EXAMPLES=OFF \
  -DBUILD_SHARED_LIBS=OFF -DENABLE_PLUGIN_LOADING=OFF -DWITH_LIBDE265=ON -DWITH_X265=OFF -DWITH_AOM_ENCODER=OFF -DWITH_AOM_DECODER=OFF \
  -DWITH_DAV1D=OFF -DWITH_RAV1E=OFF -DWITH_SvtEnc=OFF -DWITH_KVAZAAR=OFF -DWITH_JPEG_DECODER=OFF -DWITH_JPEG_ENCODER=OFF \
  -DWITH_OpenJPEG_DECODER=OFF -DWITH_OpenJPEG_ENCODER=OFF -DWITH_FFMPEG_DECODER=OFF -DWITH_UNCOMPRESSED_CODEC=OFF -DWITH_OpenH264_DECODER=OFF \
  -DCMAKE_PREFIX_PATH=/w/prefix -DCMAKE_FIND_ROOT_PATH=/w/prefix -DLIBDE265_INCLUDE_DIR=/w/prefix/include -DLIBDE265_LIBRARY=/w/prefix/lib/libde265.a \
  -DCMAKE_C_FLAGS="-O3" -DCMAKE_CXX_FLAGS="-O3"
emmake make -j"$JOBS" heif
# 3) link (flags de build-emscripten.sh do libheif) + SINGLE_FILE: o wasm vai embutido no .js (era o libheif-bundle.js do libheif-js)
EXPORTED="$(/emsdk/upstream/bin/llvm-nm libheif/libheif.a --format=just-symbols | grep '^heif_\|^de265_' | grep '[^:]$' | sed 's/^/_/' | paste -sd ',' -)"
emcc -Wl,--whole-archive libheif/libheif.a -Wl,--no-whole-archive /w/prefix/lib/libde265.a \
  -lembind -o /out/libheif-bundle.js --post-js /src/libheif/post.js -sWASM=1 -sDYNAMIC_EXECUTION=1 -sSINGLE_FILE=1 \
  -sEXPORTED_FUNCTIONS="$EXPORTED,_free,_malloc,_memcpy" -sMODULARIZE -sEXPORT_NAME=libheif -sWASM_ASYNC_COMPILATION=0 \
  -sALLOW_MEMORY_GROWTH -std=c++11 -O3
chown -R "$(stat -c %u /out):$(stat -c %g /out)" /out 2>/dev/null || true
ls -l /out
