"""f16_where.py a.f16 b.f16 out.png - where and which way two float captures differ."""
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from f16 import load  # noqa: E402

a, b = load(sys.argv[1])[40:-6, 2:-2], load(sys.argv[2])[40:-6, 2:-2]
la, lb = a.mean(axis=2), b.mean(axis=2)
rel = (lb - la) / np.maximum(la, 1e-3)
print(f"signed relative diff (b vs a): mean {rel.mean() * 100:+.3f}%  "
      f"median {np.median(rel) * 100:+.3f}%")

# Flat regions (no local gradient in a) versus gradient regions.
gy, gx = np.gradient(la)
flat = (np.abs(gx) + np.abs(gy)) < 1e-4
print(f"flat pixels {flat.mean() * 100:.1f}% -> |rel| p99 {np.percentile(np.abs(rel[flat]), 99) * 100:.2f}%")
print(f"other pixels -> |rel| p99 {np.percentile(np.abs(rel[~flat]), 99) * 100:.2f}%")

# Does the difference look like dither noise (alternating sign) or a bias?
row = rel[400, 200:260]
print("row 400, x 200..260:", " ".join(f"{v * 100:+.1f}" for v in row[:20]))

vis = np.clip(0.5 + rel * 10, 0, 1)  # grey = equal, white = b brighter
Image.fromarray((vis * 255).astype(np.uint8)).save(sys.argv[3])
