"""Generates the Chudder brand art from one parametric mark.

The mark is a play button that is also a wedge of cheese -- which is the joke,
and also just what a play triangle looks like. Holes and a rind sell it.
Everything below derives from that single geometry, so every size, platform
and variant stays in register. Units are a 1024 canvas; SS supersamples
before downscaling.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFont

U = 1024          # design units
SS = 4            # supersample factor

TRI = [(286.0, 236.0), (804.0, 512.0), (286.0, 788.0)]
TRI_ROUND = 76.0  # corner rounding, applied as a round-jointed outline
RIND_X = 286.0    # back edge; the rind is a band just inside it
RIND_W = 84.0
HOLES = [(438.0, 424.0, 54.0), (612.0, 486.0, 36.0), (498.0, 626.0, 44.0)]

PROD = ("#FFC93C", "#F0820F")     # cheddar
DEV = ("#BFC5CC", "#7C8794")      # grey, so dev builds are obvious
RIND = "#C25A05"
RIND_DEV = "#55606B"
BG_DEEP = "#2A1608"
BG_WARM = "#4A2408"

REPO = os.environ.get("REPO", os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))


def mark_mask(size, scale=1.0, hollow=False, holes=True):
    """The mark as an L-mode alpha mask, [scale] of the canvas."""
    s = size * SS
    img = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(img)
    k = (s / U) * scale
    off = (s - U * k) / 2.0

    def p(x, y):
        return (off + x * k, off + y * k)

    tri = [p(x, y) for x, y in TRI]
    if hollow:
        d.line(tri + [tri[0]], fill=255, width=max(1, int(round(40 * k))), joint="curve")
    else:
        d.polygon(tri, fill=255)
        # A round-jointed outline of the same paint rounds the corners.
        d.line(tri + [tri[0]], fill=255, width=max(1, int(round(TRI_ROUND * k))), joint="curve")

    if holes:
        for hx, hy, hr in HOLES:
            d.ellipse([p(hx - hr, hy - hr), p(hx + hr, hy + hr)], fill=0)

    return img.resize((size, size), Image.LANCZOS)


def rind_mask(size, scale=1.0):
    """The darker band along the wedge's back edge, clipped to the wedge."""
    s = size * SS
    img = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(img)
    k = (s / U) * scale
    off = (s - U * k) / 2.0

    def p(x, y):
        return (off + x * k, off + y * k)

    d.line(
        [p(RIND_X + RIND_W / 2, TRI[0][1] - 40), p(RIND_X + RIND_W / 2, TRI[2][1] + 40)],
        fill=255,
        width=max(1, int(round(RIND_W * k))),
    )
    band = img.resize((size, size), Image.LANCZOS)
    return Image.composite(band, Image.new("L", (size, size), 0), mark_mask(size, scale, holes=False))


def gradient(size, colours, angle=45):
    """Linear gradient across [size], at [angle] degrees."""
    a, b = (Image.new("RGB", (1, 1), c).getpixel((0, 0)) for c in colours)
    g = Image.new("RGB", (size, size))
    px = g.load()
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    span = abs(dx) * size + abs(dy) * size
    for y in range(size):
        for x in range(size):
            t = ((x * dx + y * dy) + (span - (dx * size + dy * size)) / 2) / span
            t = min(1.0, max(0.0, t))
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return g


def logo(size, colours, scale=0.78, hollow=False):
    """The gradient wedge, rind and all, on transparency."""
    out = gradient(size, colours).convert("RGBA")
    out.putalpha(mark_mask(size, scale, hollow))
    if not hollow:
        rind = Image.new("RGBA", (size, size), RIND if colours is PROD else RIND_DEV)
        rind.putalpha(rind_mask(size, scale))
        out = Image.alpha_composite(out, rind)
        out.putalpha(mark_mask(size, scale))
    return out


def fitted(img, size, fill):
    """Scales [img] so its ink spans [fill] of a [size] canvas.

    The wedge only covers about half of its own design canvas, so asking for a
    scale is not the same as asking for a size: without this the Windows
    taskbar icon sat in a wide transparent margin while every other app's
    icon ran edge to edge.
    """
    box = img.getbbox()
    ink = img.crop(box)
    k = (size * fill) / max(ink.size)
    ink = ink.resize((max(1, round(ink.width * k)), max(1, round(ink.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(ink, ((size - ink.width) // 2, (size - ink.height) // 2))
    return out


def brand(size, colours, fill=0.86):
    """The gradient wedge, sized by how much of the canvas its ink should fill."""
    return fitted(logo(2048, colours, scale=1.0), size, fill)


def silhouette(size, colour, fill=0.86):
    return fitted(flat(2048, colour, scale=1.0), size, fill)


def flat(size, colour, scale=0.78, hollow=False):
    """Single-colour silhouette, holes knocked out."""
    out = Image.new("RGBA", (size, size), colour)
    out.putalpha(mark_mask(size, scale, hollow))
    return out


def rounded_rect_mask(size, inset, radius):
    m = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(
        [inset * SS, inset * SS, (size - inset) * SS - 1, (size - inset) * SS - 1],
        radius=radius * SS,
        fill=255,
    )
    return m.resize((size, size), Image.LANCZOS)


def tile(size, colours, inset, radius, mark_scale):
    """Mark knocked out in white on a rounded, gradient-filled tile."""
    bg = gradient(size, colours).convert("RGBA")
    bg.putalpha(rounded_rect_mask(size, inset, radius))
    return Image.alpha_composite(bg, flat(size, (255, 255, 255, 255), mark_scale))


def font(px):
    for path, variation in (
        (os.path.join(REPO, "assets", "fonts", "rubik", "Rubik-VariableFont_wght.ttf"), "Bold"),
        (os.path.join(REPO, "assets", "fonts", "opensans", "OpenSans.ttf"), None),
    ):
        try:
            f = ImageFont.truetype(path, px)
            if variation:
                try:
                    f.set_variation_by_name(variation)
                except Exception:
                    pass
            return f
        except Exception:
            continue
    return ImageFont.load_default()


def banner(w=320, h=180, colours=PROD, text="Chudder"):
    bg = gradient(max(w, h), (BG_DEEP, BG_WARM), angle=30).convert("RGBA").resize((w, h))
    art = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    box = 116
    m = brand(box, colours, 0.94)
    art.paste(m, (14, (h - box) // 2), m)
    d = ImageDraw.Draw(art)
    # Shrink to fit rather than run off the 320px banner.
    x, size = 14 + box + 8, 36
    f = font(size)
    while size > 20 and d.textlength(text, font=f) > w - x - 14:
        size -= 2
        f = font(size)
    d.text((x, h / 2), text, font=f, fill=(255, 255, 255, 255), anchor="lm")
    return Image.alpha_composite(bg, art)


def save(img, *parts):
    path = os.path.join(REPO, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, REPO), img.size)


def main():
    # Fills are of the icon's own ink, not of the design canvas: launcher and
    # taskbar icons want to run nearly edge to edge, adaptive ones have to stay
    # inside the middle ~66% that launchers don't mask away.
    for folder, colours in (("production", PROD), ("development", DEV)):
        save(brand(1024, colours, 0.92), "icons", folder, "chudder_icon.png")
        save(brand(1024, colours, 0.96), "icons", folder, "chudder_icon_desktop.png")
        save(brand(1024, colours, 0.60), "icons", folder, "chudder_icon_foreground.png")
        save(silhouette(1024, (255, 255, 255, 255), 0.60), "icons", folder, "chudder_adaptive_icon.png")
        tile_bg = gradient(1024, colours).convert("RGBA")
        tile_bg.putalpha(rounded_rect_mask(1024, 100, 185))
        save(Image.alpha_composite(tile_bg, silhouette(1024, (255, 255, 255, 255), 0.52)),
             "icons", folder, "chudder_macos_icon.png")
        store = Image.alpha_composite(
            gradient(1024, (BG_DEEP, BG_WARM), angle=30).convert("RGBA"),
            brand(1024, colours, 0.70),
        )
        save(store.convert("RGB"), "icons", folder, "chudder_store_icon.png")
    save(brand(512, PROD, 0.92), "icons", "production", "chudder_icon_512.png")

    ico = os.path.join(REPO, "icons", "production", "chudder_icon.ico")
    brand(256, PROD, 0.96).save(
        ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    )
    print("wrote icons/production/chudder_icon.ico")

    save(silhouette(1310, (255, 255, 255, 255), 0.80), "icons", "chudder_notification_icon.png")
    save(banner(), "android", "app", "src", "main", "res", "drawable-nodpi", "app_banner.png")


if __name__ == "__main__":
    main()
