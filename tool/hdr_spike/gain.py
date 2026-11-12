"""gain.py stock.png hdr.png - estimates the linear-light gain between two captures.

If the HDR window is right on screen but a legacy (GDI) capture maps scRGB 1.0
to white, every unclipped pixel is the stock pixel times one constant in linear
light: the SDR white scale.
"""
import statistics
import sys

from PIL import Image


def lin(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
W, H = a.size
ratios = []
for y in range(45, H - 10, 7):
    for x in range(5, W - 5, 7):
        pa, pb = a.getpixel((x, y)), b.getpixel((x, y))
        for ca, cb in zip(pa, pb):
            la, lb = lin(ca), lin(cb)
            if 0.01 < la and lb < 0.9:  # skip near-black and clipped
                ratios.append(lb / la)
ratios.sort()
q = lambda f: ratios[int(len(ratios) * f)]
print(f"samples {len(ratios)}  gain median {statistics.median(ratios):.3f}  "
      f"p10 {q(0.1):.3f}  p90 {q(0.9):.3f}")
