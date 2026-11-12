"""Writes pq_steps.yuv: grey bars at known nits, PQ BT.2020 10-bit limited range.

Bars (left to right): 5, 20, 50, 100, 203, 400, 600 nits. Encode with
  ffmpeg -f rawvideo -pix_fmt yuv420p10le -s 1920x1080 -r 30 -i pq_steps.yuv -t 20
    -c:v libx265 -x265-params "lossless=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:hdr10=1:max-cll=600,600"
    pq_steps.mkv
On a display that reaches 600 nits each bar should read nits/80 in scRGB.
"""
import numpy as np

import sys

NITS = [float(v) for v in sys.argv[1].split(",")] if len(sys.argv) > 1 else [5, 20, 50, 100, 203, 400, 600]
OUT = sys.argv[2] if len(sys.argv) > 2 else "pq_steps.yuv"
m1, m2 = 2610 / 16384, 2523 / 4096 * 128
c1, c2, c3 = 3424 / 4096, 2413 / 4096 * 32, 2392 / 4096 * 32


def pq_code(nits):
    y = (nits / 10000) ** m1
    e = ((c1 + c2 * y) / (1 + c3 * y)) ** m2
    return int(round(64 + e * 876))


W, H = 1920, 1080
y_plane = np.zeros((H, W), np.uint16)
for i, n in enumerate(NITS):
    y_plane[:, i * W // len(NITS):(i + 1) * W // len(NITS)] = pq_code(n)
uv = np.full((H // 2, W // 2), 512, np.uint16)
frame = y_plane.tobytes() + uv.tobytes() + uv.tobytes()
with open(OUT, "wb") as f:
    for _ in range(30):
        f.write(frame)
print([pq_code(n) for n in NITS])
