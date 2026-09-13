#!/bin/bash
# grab.sh <name> [WxH]
# One frame of the running Chudder window into out/shots/<name>.png, by window
# handle: a title grab breaks on non-ASCII titles and a screen-region grab shows
# whatever window is on top. With WxH the frame is Lanczos-scaled to that size.
set -e
cd "$(dirname "$0")"
mkdir -p out/shots
name=$1
size=$2
hwnd=$(powershell -NoProfile -Command "(Get-Process chudder | ? { \$_.MainWindowHandle -ne 0 } | select -First 1).MainWindowHandle" | tr -d '\r')
[ -n "$hwnd" ] || { echo "no Chudder window"; exit 1; }
raw="out/shots/$name.raw.png"
ffmpeg -v error -y -f gdigrab -framerate 5 -draw_mouse 0 -i "hwnd=$hwnd" -frames:v 1 "$raw"
if [ -n "$size" ]; then
  ffmpeg -v error -y -i "$raw" -vf "scale=${size/x/:}:flags=lanczos" "out/shots/$name.png"
else
  cp "$raw" "out/shots/$name.png"
fi
python -c "from PIL import Image; print('$name', Image.open('$raw').size, '->', Image.open('out/shots/$name.png').size)"
