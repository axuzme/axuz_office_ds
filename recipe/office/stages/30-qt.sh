#!/usr/bin/env bash
# axuz_ops/office/stages/30-qt.sh — compila o Qt 5.9.9 do FONTE dentro do rootfs xenial (gcc 5.4, glibc 2.23).
#
# O QUE: substitui o `qt_binary_5.9.9_gcc_64.7z` opaco (sha256 84181f98...). O tarball de fonte vem pelo lock
#   (sha256 conferido). Parametros de tools/linux/qt_binary_build.py do build_tools, exceto -no-gstreamer (o rootfs xenial nao tem gstreamer-dev; o server nao usa qtmultimedia). Instala em
#   /work/build_tools/tools/linux/qt_build/Qt-5.9.9/gcc_64 (o mesmo caminho que o build do server usa via --qt-dir).
# ONDE: roda no container axuz-office-sysroot:xenial (run-build.sh, stage qt). Pula se qmake ja existe.
# EFEITO: Qt em qt_build/ do workspace; o diretorio de build e removido ao fim. Tempo ~1-2h a -j4.
set -euo pipefail
source /recipe/lib/lock.sh
SRC=/ws/toolchain/src
PREFIX=/work/build_tools/tools/linux/qt_build/Qt-5.9.9/gcc_64
if [[ -x "$PREFIX/bin/qmake" && -f "$PREFIX/.axuz-qt-from-source" ]]; then echo "qt ja compilado do fonte"; exit 0; fi
lock_fetch qt-src "$SRC/qt-everywhere-opensource-src-5.9.9.tar.xz"
B=/ws/toolchain/qt-build
rm -rf "$B" "$PREFIX"; mkdir -p "$B"
tar -xf "$SRC/qt-everywhere-opensource-src-5.9.9.tar.xz" -C "$B"
cd "$B/qt-everywhere-opensource-src-5.9.9"
./configure -opensource -confirm-license -release -shared -accessibility -prefix "$PREFIX" \
  -qt-zlib -qt-libpng -qt-libjpeg -qt-xcb -qt-pcre -no-sql-sqlite -no-qml-debug -no-gstreamer \
  -nomake examples -nomake tests -skip qtenginio -skip qtlocation -skip qtserialport -skip qtsensors \
  -skip qtxmlpatterns -skip qt3d -skip qtwebview -skip qtwebengine
make -j"${AXUZ_JOBS:-4}"
make install
date -u +%FT%TZ > "$PREFIX/.axuz-qt-from-source"
cd /; rm -rf "$B"
chown -R 1000:1000 "$PREFIX"
"$PREFIX/bin/qmake" -v
