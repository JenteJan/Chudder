"""steps.py capture.f16 - reads the seven pq_steps bars and compares with nits/80."""
import sys

import numpy as np

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from f16 import load  # noqa: E402

NITS = [5, 20, 50, 100, 203, 400, 600]
a = load(sys.argv[1])
H, W, _ = a.shape
row = a[H // 2 - 40:H // 2 + 40].mean(axis=(0, 2))
cols = np.where(row > 0.02)[0]
x0, x1 = cols.min(), cols.max()
step = (x1 - x0) / len(NITS)
print(f"video spans x {x0}..{x1}")
for i, n in enumerate(NITS):
    cx = int(x0 + (i + 0.5) * step)
    v = a[H // 2 - 40:H // 2 + 40, cx - 20:cx + 20].mean(axis=(0, 1))
    got = v.mean() * 80
    print(f"{n:4d} nits -> scRGB {v.mean():6.3f} = {got:6.1f} nits ({got / n * 100:5.1f}% of expected)")
