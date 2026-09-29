#!/bin/bash
# render.sh name [w h]  -> out/name.png
cd "$(dirname "$0")"; mkdir -p out
n=$1; { cat head.html; echo "<script src=\"$n.js\"></script></body></html>"; } > $n.html; w=${2:-2560}; h=${3:-1600}; extra=${4:-}
chromium --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files --force-device-scale-factor=1 $extra \
  --window-size=$w,$h --screenshot=out/$n.png --virtual-time-budget=20000 "file://$PWD/$n.html" 2>&1 | grep -v -E "dbus|Fontconfig|GPU|gpu|sandbox" | tail -3
chromium --headless=new --disable-gpu --allow-file-access-from-files --enable-logging=stderr --v=0 --window-size=$w,$h --virtual-time-budget=20000 --dump-dom "file://$PWD/$n.html" 2>&1 | grep -E "CONSOLE|<title" | head -5
