#!/bin/bash

cflags="-Wall -shared -fPIC -llua -Isrc/lib/lua52"

if [[ $* == *windows* ]]; then
  platform="windows"
  outfile="glyphindex.dll"
  compiler="x86_64-w64-mingw32-gcc"
else
  platform="unix"
  outfile="glyphindex.so"
  compiler="gcc"
fi

if command -v ccache >/dev/null; then
  compiler="ccache $compiler"
fi


echo "compiling ($platform)..."
$compiler $cflags glyphindex.c $outfile
