#!/bin/bash
cflags="-Wall -O3 -g -std=gnu11 -fno-strict-aliasing"

if [[ $* == *windows* ]]; then
  platform="windows"
  outfile="mkfontmap.exe"
  compiler="x86_64-w64-mingw32-gcc"
else
  platform="unix"
  outfile="mkfontmap"
  compiler="gcc"
fi

if command -v ccache >/dev/null; then
  compiler="ccache $compiler"
fi

echo "Compiling ($platform)..."
$compiler $cflags mkfontmap.c -lm -o $outfile

