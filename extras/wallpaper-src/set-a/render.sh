#!/bin/bash
# usage: render.sh name  -> renders name.html to out/name.png
cd "$(dirname "$0")"; mkdir -p out
chromium --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --allow-file-access-from-files \
  --window-size=2560,1600 --virtual-time-budget=${VT:-15000} --screenshot="$PWD/out/$1.png" "file://$PWD/$1.html" 2>/dev/null
