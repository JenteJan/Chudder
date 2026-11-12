"""f16.py - compare float (scRGB) captures from hdrcap.

  f16.py stats a.f16                      -> value range, share above 1.0
  f16.py compare a.f16 b.f16 [x0 y0 x1 y1] -> per-pixel difference in scRGB,
                                              optionally only inside a box
  f16.py region a.f16 x0 y0 x1 y1          -> mean / max in a box
"""
import sys

import numpy as np


def load(path):
    with open(path, "rb") as f:
        header = f.readline().split()
        w, h = int(header[1]), int(header[2])
        data = np.frombuffer(f.read(), dtype=np.float16, count=w * h * 4)
    return data.reshape(h, w, 4).astype(np.float32)[:, :, :3]


def interior(img):
    # Skip the title bar and the 2px window border, which show the desktop.
    return img[40:-6, 2:-2]


cmd = sys.argv[1] if __name__ == "__main__" else ""
if cmd == "stats":
    img = interior(load(sys.argv[2]))
    print(f"min {img.min():.4f}  max {img.max():.4f}  mean {img.mean():.4f}  "
          f"share > 1.0: {(img.max(axis=2) > 1.0).mean() * 100:.3f}%")
elif cmd == "compare":
    a, b = load(sys.argv[2]), load(sys.argv[3])
    if len(sys.argv) > 4:
        x0, y0, x1, y1 = map(int, sys.argv[4:8])
        a, b = a[y0:y1, x0:x1], b[y0:y1, x0:x1]
    else:
        a, b = interior(a), interior(b)
    d = np.abs(a - b)
    rel = d / np.maximum(np.maximum(a, b), 1e-3)
    print(f"abs diff: max {d.max():.4f} mean {d.mean():.5f} | "
          f"relative: p99 {np.percentile(rel, 99) * 100:.2f}%  max {rel.max() * 100:.1f}%  "
          f"| pixels off by >2%: {(rel.max(axis=2) > 0.02).mean() * 100:.3f}%")
elif cmd == "region":
    a = load(sys.argv[2])
    x0, y0, x1, y1 = map(int, sys.argv[3:7])
    r = a[y0:y1, x0:x1]
    print(f"region mean {r.reshape(-1, 3).mean(axis=0)}  max {r.max():.3f}")
