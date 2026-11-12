"""compare.py a.png b.png diff.png - pixel difference report between two captures."""
import sys

from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
if a.size != b.size:
    print(f"SIZE MISMATCH {a.size} vs {b.size}")
    sys.exit(2)
diff = ImageChops.difference(a, b)
px = list(diff.getdata())
changed = [max(p) for p in px if max(p) > 0]
total = len(px)
print(f"pixels: {total}, differing: {len(changed)} ({100 * len(changed) / total:.4f}%)")
if changed:
    print(f"max channel delta: {max(changed)}, mean delta of differing: {sum(changed) / len(changed):.2f}")
    over8 = sum(1 for c in changed if c > 8)
    print(f"differing by more than 8/255: {over8} ({100 * over8 / total:.4f}%)")
    print(f"bbox of differences: {diff.getbbox()}")
# Amplified diff for eyeballing.
diff.point(lambda v: min(255, v * 16)).save(sys.argv[3])
