#!/bin/bash
# take_flow.sh - the desktop interaction take (search -> Charge -> play -> mini player -> Home).
# Window: 1400x900 at 0,0 on the primary monitor. Leaves Chudder on Home with nothing playing.
#
# Charge has two backdrops and the app keeps whichever it picked for as long as it runs; one of them
# prints the title twice. So: restart Chudder, peek at the Charge page, and only take once the clean
# one came up (compared against out/backdrop0_ref.png, a still of the other one at this window size).
set -e
cd "$(dirname "$0")/.."
CHARGE=e822d2f66189bc6caaa81cf69eb5c907
EXE="$(cd ../.. && pwd -W)/build/windows/x64/runner/Release/chudder.exe"

home() {
  # pop the Search tab back to its root, go Home, park the pointer on the empty sidebar
  powershell -NoProfile -File drive.ps1 -Delay 250 -Keys "click:64,186 wait1500 click:64,186 wait1500 click:64,128 wait1500 move:30,780" | tail -1
}

restart() {
  powershell -NoProfile -Command "Get-Process chudder -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2; Start-Process '$EXE' -WorkingDirectory (Split-Path '$EXE'); Start-Sleep 10"
  powershell -NoProfile -File window.ps1 -X 0 -Y 0 -W 1400 -H 900
  sleep 2
}

backdrop_diff() {
  python -c "
from PIL import Image, ImageChops, ImageStat
box = (500, 60, 1380, 560)
a = Image.open('$1').convert('L').crop(box)
b = Image.open('out/backdrop0_ref.png').convert('L').crop(box)
print(int(ImageStat.Stat(ImageChops.difference(a, b)).mean[0]))"
}

for attempt in 1 2 3 4 5 6 7 8; do
  restart
  powershell -NoProfile -File drive.ps1 -Delay 120 -Keys "move:30,780 wait500 click:64,186 wait150 move:900,300 wait1000 click:658,73 wait400 c h r a g e wait1500 click:238,159 wait150 move:900,300 wait3500" | tail -1
  bash grab.sh flow_peek >/dev/null
  d=$(backdrop_diff out/shots/flow_peek.png)
  echo "attempt $attempt: difference from the doubled-title backdrop = $d"
  home
  [ "$d" -gt 25 ] && break
done

python -c "import demo; demo.set_position('$CHARGE', 84)"
sleep 3
bash take.sh flow 31 "move:30,780 wait1200 click:64,186 wait150 move:900,300 wait1000 click:658,73 wait400 c h r a g e wait1500 click:238,159 wait150 move:900,300 wait3000 move:700,700 wait300 click:246,842 wait4000 move:700,450 wait100 move:704,452 wait2500 move:600,400 wait100 move:604,402 wait2500 click:48,79 wait150 move:900,300 wait2200 click:64,128 wait150 move:30,780 wait2500 wheel:700,500,-3 wait150 move:30,780 wait2500" 120
echo "take: difference from the doubled-title backdrop = $(backdrop_diff "$(ls out/fr/flow/*.jpg | sed -n 315p)")"

# close the mini player the take left, back to Home
powershell -NoProfile -File drive.ps1 -Delay 250 -Keys "move:1225,725 wait150 move:1230,730 wait900 click:1336,637 wait1500 move:30,780" | tail -1
home
python -c "import demo; demo.set_position('$CHARGE', 84)"
