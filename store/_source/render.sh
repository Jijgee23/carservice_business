#!/bin/sh
# usage: render.sh out.png W H scale "query"
CH="/c/Program Files/Google/Chrome/Application/chrome.exe"
T="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
B="${BRAND:-file:///C:/Users/jijge/Documents/GitHub/carcare.mn/public/brand}"
"$CH" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --force-device-scale-factor=$4 --window-size=$2,$3 --default-background-color=00000000 \
  --virtual-time-budget=8000 --user-data-dir="${TMPDIR:-/tmp}/cs-store-prof" \
  --screenshot="$1" "file:///$T/template.html?brand=$B&$5" >/dev/null 2>&1
