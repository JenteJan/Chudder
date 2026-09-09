"""Renders every Chudder raster from icons/chudder_icon.svg.

The mark is a wedge of cheese that also points like a play button, which is
the joke the name was asking for. That SVG is the only source of truth; run
this after editing it:

    python tool/brand_assets.py

Then regenerate the platform icon sets, which read the PNGs this writes:

    dart run icons_launcher:create --path icons_launcher-production.yaml
    dart run flutter_native_splash:create
"""

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import svg_render  # noqa: E402

REPO = os.environ.get("REPO", os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
MASTER = os.path.join(REPO, "icons", "chudder_icon.svg")

# Greys for the development flavour, so a dev build is obvious on the launcher.
DEV_MAP = {"#FCBC41": "#C9CDD2", "#EE8F1A": "#A2A9B2", "#C26D11": "#79818B"}

# Backgrounds follow the app's accent (ColorThemes.fladder), not the cheese:
# blue is the mark's complement, so the wedge reads as deliberate contrast.
BG_DEEP = "#0A1A30"
BG_WARM = "#1B4587"

# A path this small is a hole or a highlight rather than part of the body.
HOLE_MAX = 120.0
HIGHLIGHT_MAX = 20.0


def paths(dev=False):
    found = svg_render.load(MASTER, drop=())
    if dev:
        found = [(d, DEV_MAP.get(f.upper(), f)) for d, f in found]
    return found


def extent(d):
    xs, ys = [], []
    for sp in svg_render.parse(d):
        xs += [p[0] for p in sp]
        ys += [p[1] for p in sp]
    return max(max(xs) - min(xs), max(ys) - min(ys))


def fitted(img, size, fill):
    """Scales [img] so its ink spans [fill] of a [size] canvas.

    Sizing by ink rather than by canvas: the art doesn't fill its own bounding
    square, so a plain scale factor leaves launcher and taskbar icons floating
    in a margin while every other app's icon runs edge to edge.
    """
    box = img.getbbox()
    ink = img.crop(box)
    k = (size * fill) / max(ink.size)
    ink = ink.resize((max(1, round(ink.width * k)), max(1, round(ink.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(ink, ((size - ink.width) // 2, (size - ink.height) // 2))
    return out


def brand(size, fill=0.92, dev=False):
    """The mark in colour, on transparency."""
    return fitted(svg_render.render(paths(dev), max(size, 512)), size, fill)


def silhouette(size, colour=(255, 255, 255, 255), fill=0.92):
    """One flat colour, with the holes knocked out so it still reads as cheese.

    For the themed launcher icon and the status bar, where Android throws the
    artwork away and keeps only the alpha.
    """
    art = paths()
    body = [(d, "#FFFFFF") for d, _ in art if extent(d) >= HOLE_MAX]
    holes = [(d, "#FFFFFF") for d, _ in art if HIGHLIGHT_MAX <= extent(d) < HOLE_MAX]
    full = svg_render.render(art, 1024)
    mask = svg_render.render(body, 1024, bbox=_bbox(art)).getchannel("A")
    if holes:
        mask = ImageChops.subtract(mask, svg_render.render(holes, 1024, bbox=_bbox(art)).getchannel("A"))
    out = Image.new("RGBA", full.size, colour)
    out.putalpha(mask)
    return fitted(out, size, fill)


def _bbox(art):
    xs, ys = [], []
    for d, _ in art:
        for sp in svg_render.parse(d):
            xs += [p[0] for p in sp]
            ys += [p[1] for p in sp]
    return (min(xs), min(ys), max(xs), max(ys))


def gradient(size, colours, angle=45):
    import math

    a, b = (Image.new("RGB", (1, 1), c).getpixel((0, 0)) for c in colours)
    g = Image.new("RGB", (size, size))
    px = g.load()
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    span = abs(dx) * size + abs(dy) * size
    for y in range(size):
        for x in range(size):
            t = min(1.0, max(0.0, ((x * dx + y * dy) + (span - (dx * size + dy * size)) / 2) / span))
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return g


def rounded_rect_mask(size, inset, radius, ss=4):
    m = Image.new("L", (size * ss, size * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [inset * ss, inset * ss, (size - inset) * ss - 1, (size - inset) * ss - 1], radius=radius * ss, fill=255
    )
    return m.resize((size, size), Image.LANCZOS)


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


def banner(w=320, h=180, text="Chudder"):
    bg = gradient(max(w, h), (BG_DEEP, BG_WARM), angle=30).convert("RGBA").resize((w, h))
    art = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    box = 124
    m = brand(box, 0.98)
    art.paste(m, (12, (h - box) // 2), m)
    d = ImageDraw.Draw(art)
    # Shrink to fit rather than run off the 320px banner.
    x, size = 12 + box + 8, 38
    f = font(size)
    while size > 20 and d.textlength(text, font=f) > w - x - 14:
        size -= 2
        f = font(size)
    d.text((x, h / 2), text, font=f, fill=(255, 255, 255, 255), anchor="lm")
    return Image.alpha_composite(bg, art)


def marketing_banner(w, h, tagline=None, mark_h=None, word_px=None, tag_px=None):
    """The wide lockup: wedge on the left, wordmark and an optional tagline.

    Sized off the height so the same composition serves the GitHub social
    preview (1280x640), the Play feature graphic (1024x500) and the Android
    TV banner (1280x720).
    """
    mark_h = mark_h or int(h * 0.47)
    word_px = word_px or int(h * 0.26)
    tag_px = tag_px or int(h * 0.0625)
    ink, muted = (236, 240, 247, 255), (160, 178, 206, 255)
    bg = gradient(max(w, h), (BG_DEEP, BG_WARM), angle=30).convert("RGBA").resize((w, h))
    art = brand(mark_h * 2, 1.0)
    art = art.crop(art.getbbox())
    art = art.resize((int(art.width * mark_h / art.height), mark_h), Image.LANCZOS)
    d = ImageDraw.Draw(bg)
    wf = font(word_px)
    wb = d.textbbox((0, 0), "Chudder", font=wf)
    ww, wh = wb[2] - wb[0], wb[3] - wb[1]
    tw = th = 0
    if tagline:
        tf = font(tag_px)
        tb = d.textbbox((0, 0), tagline, font=tf)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
    gap, tag_gap = int(h * 0.075), int(h * 0.028)
    x0 = (w - (art.width + gap + max(ww, tw))) // 2
    y_mark = (h - art.height) // 2
    # A soft drop under the wedge so it sits on the ground instead of floating.
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (x0, y_mark + h // 36, x0 + art.width, y_mark + h // 36 + art.height), art)
    bg = Image.alpha_composite(bg, shadow.filter(ImageFilter.GaussianBlur(h / 23)))
    bg.paste(art, (x0, y_mark), art)
    d = ImageDraw.Draw(bg)
    tx = x0 + art.width + gap
    y_text = (h - (wh + (tag_gap + th if tagline else 0))) // 2
    d.text((tx - wb[0], y_text - wb[1]), "Chudder", font=wf, fill=ink)
    if tagline:
        d.text((tx - tb[0], y_text + wh + tag_gap - tb[1]), tagline, font=tf, fill=muted)
    return bg.convert("RGB")


def dmg_background(w=800, h=500, app_xy=(210, 250), drop_xy=(603, 250)):
    """The macOS disk image window: create_dmg.sh puts the app at [app_xy] and
    the Applications link at [drop_xy], so the arrow runs between the two."""
    bg = gradient(max(w, h), (BG_DEEP, BG_WARM), angle=30).convert("RGBA").resize((w, h))
    d = ImageDraw.Draw(bg)
    ink = (236, 240, 247, 255)
    muted = (160, 178, 206, 255)
    x0, x1, y = app_xy[0] + 70, drop_xy[0] - 70, app_xy[1]
    d.line([(x0, y), (x1 - 14, y)], fill=ink, width=5)
    d.polygon([(x1, y), (x1 - 26, y - 14), (x1 - 26, y + 14)], fill=ink)
    f = font(int(h * 0.05))
    d.text((w / 2, y + 100), "Drag Chudder to Applications", font=f, fill=muted, anchor="mm")
    return bg.convert("RGB")


def wizard_image(w, h):
    """Inno Setup's WizardImageFile: the tall strip on the welcome page."""
    tile = gradient(max(w, h), (BG_DEEP, BG_WARM), angle=60).convert("RGBA").crop((0, 0, w, h))
    mark = brand(int(w * 0.72), 1.0)
    tile.alpha_composite(mark, ((w - mark.width) // 2, (h - mark.height) // 2))
    return tile.convert("RGB")


def save(img, *parts):
    path = os.path.join(REPO, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, REPO), img.size)


def main():
    # Fills are of the mark's own ink: launcher and taskbar icons want to run
    # nearly edge to edge, while adaptive and monochrome ones have to stay
    # inside the middle ~66% that launchers mask away.
    for folder, dev in (("production", False), ("development", True)):
        # Legacy Android launcher icon: drawn into a masked tile, and the
        # convention is a margin around it (48dp icon in a 48dp box with 4dp
        # of padding), so it should not run edge to edge like a taskbar icon.
        save(brand(1024, 0.82, dev), "icons", folder, "chudder_icon.png")
        save(brand(1024, 0.96, dev), "icons", folder, "chudder_icon_desktop.png")
        # Adaptive and themed icons are masked to the middle 72dp of a 108dp
        # canvas, and to a circle on Pixel. Anything approaching that 0.66 gets
        # clipped at the corners; 0.50 sits inside the 60dp key shape.
        save(brand(1024, 0.50, dev), "icons", folder, "chudder_icon_foreground.png")
        save(silhouette(1024, fill=0.50), "icons", folder, "chudder_adaptive_icon.png")
        tile = gradient(1024, (BG_DEEP, BG_WARM) if not dev else ("#3C4149", "#22262B"), angle=30).convert("RGBA")
        tile.putalpha(rounded_rect_mask(1024, 100, 185))
        save(Image.alpha_composite(tile, brand(1024, 0.60, dev)), "icons", folder, "chudder_macos_icon.png")
        store = Image.alpha_composite(
            gradient(1024, (BG_DEEP, BG_WARM), angle=30).convert("RGBA"), brand(1024, 0.70, dev)
        )
        save(store.convert("RGB"), "icons", folder, "chudder_store_icon.png")
    save(brand(512, 0.92), "icons", "production", "chudder_icon_512.png")

    ico = os.path.join(REPO, "icons", "production", "chudder_icon.ico")
    brand(256, 0.96).save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote icons/production/chudder_icon.ico")

    save(silhouette(1310, fill=0.86), "icons", "chudder_notification_icon.png")

    for scale, (w, h) in ((100, (164, 314)), (125, (202, 386)), (150, (240, 459))):
        save(wizard_image(w, h), "assets", "windows-installer", f"chudder-installer-{scale}.bmp")
    save(banner(), "android", "app", "src", "main", "res", "drawable-nodpi", "app_banner.png")

    # The Play Store wants an opaque 512 with the artwork inside, not the
    # transparent launcher icon icons_launcher leaves behind.
    for folder, dev in (("production", False), ("development", True)):
        store = Image.alpha_composite(
            gradient(512, (BG_DEEP, BG_WARM), angle=30).convert("RGBA"), brand(512, 0.70, dev)
        )
        save(store.convert("RGB"), "android", "app", "src", folder, "ic_launcher-playstore.png")
        if not dev:
            save(store.convert("RGB"), "assets", "marketing", "play_store_icon.png")
            save(store.convert("RGB"), "fastlane", "metadata", "android", "en-US", "images", "icon.png")

    # Wide lockups: the GitHub social preview, the Play feature graphic and
    # the Android TV banner. Same composition, three sizes.
    tagline = "Your Jellyfin, on every screen."
    save(marketing_banner(1280, 640, tagline), "assets", "marketing", "banner.png")
    save(marketing_banner(1024, 500, tagline), "assets", "marketing", "banner_store.png")
    save(marketing_banner(1280, 720), "assets", "marketing", "tv_banner.png")
    save(dmg_background(), "assets", "macos-dmg", "Chudder-DMG-Background.jpg")


if __name__ == "__main__":
    main()
