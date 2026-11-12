"""steps.py capture.f16 - reads the seven pq_steps bars and compares with nits/80."""
import sys

import numpy as np

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from f16 import load  # noqa: E402

NITS = [float(v) for v in sys.argv[2].split(",")] if len(sys.argv) > 2 else [5, 20, 50, 100, 203, 400, 600]
a = load(sys.argv[1])
H, W, _ = a.shape
row = a[H // 2 - 40:H // 2 + 40].mean(axis=(0, 2))
cols = np.where(row > 0.001)[0]
x0, x1 = cols.min(), cols.max()
step = (x1 - x0) / len(NITS)
print(f"video spans x {x0}..{x1}")
for i, n in enumerate(NITS):
    cx = int(x0 + (i + 0.5) * step)
    v = a[H // 2 - 40:H // 2 + 40, cx - 20:cx + 20].mean(axis=(0, 1))
    got = v.mean() * 80
    print(f"{n:6.0f} nits -> {got:7.1f} nits  (x{got / n:5.2f})")
