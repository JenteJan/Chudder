"""Minimal SVG renderer for the brand art: flat fills, M/L/C/Z only.

Not a general SVG implementation - just enough to turn
icons/chudder_icon.svg into rasters without pulling in a native
rendering stack. See tool/brand_assets.py for what it feeds.
"""

import re

from PIL import Image, ImageChops, ImageDraw

TOKEN = re.compile(r'([MmLlCcZzHhVv])|(-?\d*\.?\d+(?:e-?\d+)?)')


def parse(d):
    """Path data -> list of subpaths, each a list of (x, y). Curves flattened."""
    items = []
    for cmd, num in TOKEN.findall(d):
        items.append(cmd if cmd else float(num))

    subpaths, cur = [], []
    x = y = 0.0
    sx = sy = 0.0
    op = None
    i = 0
    while i < len(items):
        it = items[i]
        if isinstance(it, str):
            op = it
            i += 1
            if op in 'Zz':
                if cur:
                    subpaths.append(cur)
                    cur = []
                x, y = sx, sy
            continue
        rel = op.islower()
        if op in 'Mm':
            nx, ny = items[i], items[i + 1]
            i += 2
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            if cur:
                subpaths.append(cur)
            cur = [(x, y)]
            sx, sy = x, y
            op = 'l' if rel else 'L'
        elif op in 'Ll':
            nx, ny = items[i], items[i + 1]
            i += 2
            x, y = (x + nx, y + ny) if rel else (nx, ny)
            cur.append((x, y))
        elif op in 'Hh':
            nx = items[i]
            i += 1
            x = x + nx if rel else nx
            cur.append((x, y))
        elif op in 'Vv':
            ny = items[i]
            i += 1
            y = y + ny if rel else ny
            cur.append((x, y))
        elif op in 'Cc':
            c = items[i:i + 6]
            i += 6
            if rel:
                x1, y1, x2, y2, x3, y3 = (x + c[0], y + c[1], x + c[2], y + c[3], x + c[4], y + c[5])
            else:
                x1, y1, x2, y2, x3, y3 = c
            for s in range(1, 17):
                t = s / 16
                u = 1 - t
                cur.append((
                    u ** 3 * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 * x3,
                    u ** 3 * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3 * y3,
                ))
            x, y = x3, y3
        else:
            i += 1
    if cur:
        subpaths.append(cur)
    return subpaths


def render(paths, size, bbox=None, ss=3, pad=0.0):
    """[paths] is [(d, '#rrggbb')]; returns an RGBA image of [size] square."""
    if bbox is None:
        xs, ys = [], []
        for d, _ in paths:
            for sp in parse(d):
                xs += [p[0] for p in sp]
                ys += [p[1] for p in sp]
        bbox = (min(xs), min(ys), max(xs), max(ys))
    x0, y0, x1, y1 = bbox
    span = max(x1 - x0, y1 - y0) * (1 + pad * 2)
    s = size * ss
    k = s / span
    ox = (s - (x1 - x0) * k) / 2 - x0 * k
    oy = (s - (y1 - y0) * k) / 2 - y0 * k

    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    for d, fill in paths:
        mask = Image.new("L", (s, s), 0)
        for sp in parse(d):
            if len(sp) < 3:
                continue
            layer = Image.new("L", (s, s), 0)
            ImageDraw.Draw(layer).polygon([(px * k + ox, py * k + oy) for px, py in sp], fill=255)
            # Even-odd accumulation: traced holes are wound the other way, which
            # comes out the same as nonzero for shapes that don't self-intersect.
            mask = ImageChops.difference(mask, layer)
        colour = Image.new("RGBA", (s, s), fill)
        colour.putalpha(mask)
        out = Image.alpha_composite(out, colour)
    return out.resize((size, size), Image.LANCZOS)


def load(path, drop=("#E6E6E5", "#B9B8B8")):
    src = open(path, encoding="utf-8").read()
    found = re.findall(r'<path\s+d="([^"]+)"\s+fill="([^"]+)"', src)
    return [(d, f) for d, f in found if f.upper() not in [c.upper() for c in drop]]
