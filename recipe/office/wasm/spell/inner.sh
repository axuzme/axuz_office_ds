#!/usr/bin/env bash
# axuz_ops/office/wasm/spell/inner.sh — compila sdkjs/common/spell/spell/spell.wasm (corretor ortografico Hunspell).
#
# O QUE: reproduz o build do upstream (Common/3dParty/hunspell/make.py do core aefa5038b5, 2021-05-19): Hunspell no commit
#   4ddd8ed5 (arquivo HEAD do core naquela data; vem da HISTORIA do repo hunspell que o core ja traz em
#   Common/3dParty/hunspell/hunspell, sem rede) + os 3 patches do before.py + wrapper wasm (src/, copiado do core) e
#   emcc com os mesmos flags. Exports: malloc free Spellchecker_{Malloc,Free,Create,Destroy,AddDictionary,
#   RemoveDicrionary,Load,Spell,Suggest,RemoveEngine,TotalAllocatedMemory}; nomes minificados iguais ao binario do sdkjs.
# ONDE: roda DENTRO do container emsdk (spell/build.sh -> hzs_docker). /core, /sdkjs ro; /recipe ro; /out rw.
set -euo pipefail
HUN_SHA=4ddd8ed5ca6484b930b111aec50c2750a6119a0f
W=/tmp/w; mkdir -p "$W/hunspell" "$W/wasm"
git -c safe.directory='*' -C /core/Common/3dParty/hunspell/hunspell archive "$HUN_SHA" | tar -x -C "$W/hunspell"
cp /recipe/spell/src/* "$W/wasm/"
cd "$W"
python3 - <<'PY'
# os 3 patches do before.py upstream (filemgr com buffer em memoria; free_utf_tbl vira no-op: a tabela utf tem de ficar)
def rep(f, a, b):
    s = open(f).read(); assert a in s, (f, a); open(f, "w").write(s.replace(a, b, 1))
H = "./hunspell/src/hunspell/"
rep(H + "filemgr.hxx", "FileMgr& operator=(const FileMgr&);", "FileMgr& operator=(const FileMgr&);\n#ifdef HUNSPELL_WASM_MODULE\nstring_buffer_stream memin;\n#endif")
rep(H + "filemgr.hxx", "#include <fstream>", "#include <fstream>\n#ifdef HUNSPELL_WASM_MODULE\n#include \"string_buffer_stream.h\"\n#endif\n")
rep(H + "csutil.cxx", "void free_utf_tbl() {", "void free_utf_tbl() { \n return;\n")
PY
H=./hunspell/src/hunspell
SRC=""; for f in affentry affixmgr csutil dictmgr hashmgr hunspell hunzip phonet replist suggestmgr; do [ -f "$H/$f.cxx" ] && SRC="$SRC $H/$f.cxx"; done
EXP="['_malloc','_free','_Spellchecker_Malloc','_Spellchecker_Free','_Spellchecker_Create','_Spellchecker_Destroy','_Spellchecker_AddDictionary','_Spellchecker_RemoveDicrionary','_Spellchecker_Load','_Spellchecker_Spell','_Spellchecker_Suggest','_Spellchecker_RemoveEngine','_Spellchecker_TotalAllocatedMemory']"
# shellcheck disable=SC2086
emcc -o spell.js -O3 -fno-exceptions -fno-rtti -s WASM=1 -s ALLOW_MEMORY_GROWTH=1 -s FILESYSTEM=0 -s ENVIRONMENT='web,worker' \
  -I"$H" -I./wasm -DWIN32 -DNDEBUG -DHUNSPELL_STATIC -DBUILDING_LIBHUNSPELL -DHUNSPELL_WASM_MODULE \
  -s EXPORTED_FUNCTIONS="$EXP" $SRC ./wasm/filemgr_wrapper_new.cxx ./wasm/base.cpp
cp spell.wasm /out/spell.wasm; cp spell.js /out/spell.emcc.js
chown "$HZS_UID:$HZS_GID" /out/spell.wasm /out/spell.emcc.js
