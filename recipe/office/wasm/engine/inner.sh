#!/usr/bin/env bash
# axuz_ops/office/wasm/engine/inner.sh — compila sdkjs/common/hash/hash/engine.wasm (hash de senha: MD2/4/5, RMD160, SHA1/2, Whirlpool).
#
# O QUE: reproduz, com o MESMO fonte e o MESMO emsdk do upstream (core 47e72c2210, 2021-11-12; emscripten 2.0.32), o
#   engine.wasm que o sdkjs versiona. Fontes: main.cpp (da historia do core, sha256 conferido) + src/opensslconf.h (copiado do core, ver PROVENANCE.txt) e
#   OpenSSL_1_1_1f do checkout pinado do core (/core/Common/3dParty/openssl/openssl, HEAD, nao a arvore de trabalho).
#   Mesmos flags do make.py upstream => saida byte-identica ao binario versionado (provado pelo test.sh).
#   Exports: _malloc _free _hash _hash2. Mesmos nomes minificados de import/export => o glue do sdkjs nao muda.
# ONDE: roda DENTRO do container emsdk (engine/build.sh -> hzs_docker). /core, /sdkjs ro; /recipe ro; /out rw.
set -euo pipefail
W=/tmp/w; H=$W/hash; O=$W/openssl
mkdir -p "$H/openssl" "$O"
# main.cpp NAO fica versionado aqui (o gitleaks da casa acusa falso positivo em `Utf8_to_utf16le(password, ...)`); vem da
# HISTORIA do core (commit 47e72c2210, o repo pinado e clonado completo) e tem o sha256 conferido (fail-closed).
MAIN_SHA256=377045b1b77049d8c79fb9049b5662daed67d51d8fa2bfa92bd690d4ba9ebda4
git -c safe.directory='*' -C /core show 47e72c221075ec3fc750543c150dc901ce8956ab:DesktopEditor/xmlsec/src/wasm/module/hash/main.cpp > "$H/main.cpp" \
  || { echo "AXUZ-WASM: core sem a historia (precisa de clone completo) para 47e72c2210" >&2; exit 3; }
echo "$MAIN_SHA256  $H/main.cpp" | sha256sum -c - >/dev/null || { echo "AXUZ-WASM: main.cpp divergente do pin" >&2; exit 3; }
cp /recipe/engine/src/opensslconf.h "$H/openssl/"
git -c safe.directory='*' -C /core/Common/3dParty/openssl/openssl archive HEAD | tar -x -C "$O"
cd "$H"
C=../openssl/crypto
emcc -o engine.js -O3 -fno-exceptions -fno-rtti -s WASM=1 -s ALLOW_MEMORY_GROWTH=1 -s FILESYSTEM=0 \
  -s ENVIRONMENT='worker' -s TOTAL_STACK=1MB -s TOTAL_MEMORY=2MB --memory-init-file 0 \
  -I./ -I./../openssl/include -DWIN32 -DNDEBUG \
  -s EXPORTED_FUNCTIONS="['_malloc','_free','_hash','_hash2']" \
  $C/sha/keccak1600.c $C/sha/sha1_one.c $C/sha/sha1dgst.c $C/sha/sha256.c $C/sha/sha512.c \
  $C/md2/md2_dgst.c $C/md2/md2_one.c $C/md4/md4_dgst.c $C/md4/md4_one.c $C/md5/md5_dgst.c $C/md5/md5_one.c \
  $C/ripemd/rmd_dgst.c $C/ripemd/rmd_one.c $C/whrlpool/wp_block.c $C/whrlpool/wp_dgst.c $C/mem_clr.c ./main.cpp
cp engine.wasm /out/engine.wasm; cp engine.js /out/engine.emcc.js
chown "$HZS_UID:$HZS_GID" /out/engine.wasm /out/engine.emcc.js
