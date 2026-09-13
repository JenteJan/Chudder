#!/bin/bash
# mux10.sh - the v10 frames (out/out10, 60 fps) + "Werq" from 87.422 s, so the drop lands on bar 3
# (5.76 s). Loudness-normalised for social feeds. Writes out/chudder_showcase_v10.mp4; copying it
# over assets/marketing/chudder_showcase.mp4 is a separate, deliberate step.
set -e
cd "$(dirname "$0")/../out"
D=49.92
ffmpeg -v error -y -framerate 60 -i out10/%05d.png -ss 87.422 -i music/Werq.mp3 \
  -filter_complex "[1:a]loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000,afade=t=in:st=0:d=0.6,afade=t=out:st=47.4:d=2.5[a]" \
  -map 0:v -map "[a]" -t $D -c:v libx264 -preset slow -crf 17 -profile:v high -pix_fmt yuv420p -movflags +faststart \
  -c:a aac -b:a 192k chudder_showcase_v10.mp4
ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 chudder_showcase_v10.mp4 \
  | xargs -I{} echo "chudder_showcase_v10.mp4: {} video frames (expect 2995)"
