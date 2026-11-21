#!/usr/bin/env bash
# Gera AllFonts.js / fontes web / temas dentro do rootfs de teste (equivale ao documentserver-generate-allfonts.sh do pacote).
set -euo pipefail
DIR=/var/www/onlyoffice/documentserver
export LD_LIBRARY_PATH=$DIR/server/FileConverter/bin
mkdir -p "$DIR/fonts"
"$DIR/server/tools/allfontsgen" --input="$DIR/core-fonts" --allfonts-web="$DIR/sdkjs/common/AllFonts.js" \
  --allfonts="$DIR/server/FileConverter/bin/AllFonts.js" --images="$DIR/sdkjs/common/Images" \
  --selection="$DIR/server/FileConverter/bin/font_selection.bin" --output-web="$DIR/fonts" --use-system="false"
"$DIR/server/tools/allthemesgen" --converter-dir="$DIR/server/FileConverter/bin" --src="$DIR/sdkjs/slide/themes" \
  --output="$DIR/sdkjs/common/Images"
echo FONTS_OK
