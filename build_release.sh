#!/bin/bash
./build.sh
./build.sh windows
rm plugin.zip 2>/dev/null

strip mkfontmap.exe
zip plugin.zip init.lua utfhelper.lua mkfontmap mkfontmap.exe -r