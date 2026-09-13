#!/bin/bash
# take.sh <name> <seconds> "<drive.ps1 keys>" [delay-ms]
# Records the Chudder window by handle while drive.ps1 plays the keys, then
# splits the take into frames. SCALE=1920:1080 scales the recording (the television window is 2560x1440). Output: out/cap/<name>.mp4, .log (a "T <s> <key>"
# line per step), .t0 (wall clock at the first step) and out/fr/<name>/.
set -e
cd "$(dirname "$0")"
mkdir -p out/cap out/fr
name=$1; seconds=$2; keys=$3; delay=${4:-120}
hwnd=$(powershell -NoProfile -Command "(Get-Process chudder | ? { \$_.MainWindowHandle -ne 0 } | select -First 1).MainWindowHandle" | tr -d '\r')
[ -n "$hwnd" ] || { echo "no Chudder window"; exit 1; }
ffmpeg -v error -y -f gdigrab -framerate 30 -draw_mouse 0 -i "hwnd=$hwnd" -t "$seconds" \
  -vf "${SCALE:+scale=$SCALE:flags=lanczos,}crop=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p "out/cap/$name.mp4" &
recorder=$!
sleep 1.2
date +%s.%N > "out/cap/$name.t0"
powershell -NoProfile -File drive.ps1 -Delay "$delay" -Keys "$keys" > "out/cap/$name.log" || true
tail -1 "out/cap/$name.log"
wait $recorder
rm -rf "out/fr/$name"; mkdir -p "out/fr/$name"
ffmpeg -v error -y -i "out/cap/$name.mp4" -qscale:v 2 "out/fr/$name/%05d.jpg"
echo "$name $(ffprobe -v error -show_entries stream=width,height:format=duration -of csv=p=0 "out/cap/$name.mp4" | tr '\n' ' ') frames=$(ls "out/fr/$name" | wc -l)"
