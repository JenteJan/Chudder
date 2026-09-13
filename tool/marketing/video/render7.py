#!/usr/bin/env python3
# Chudder promo v7 (Reddit cut) — 1920x1080 / 30fps, cut on the beat grid of "Werq" (125 BPM).
# Footage = real Chudder windows captured from the demo server (Caminandes: Llamigos, CC-BY Blender).
import os, sys, math, glob
from multiprocessing import Pool
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

W, H, FPS = 1920, 1080, 30
# Footage (fr/), music and renders live in tool/marketing/out, which is gitignored.
HERE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out"))
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(HERE, "out7")

# ---- music grid -----------------------------------------------------------
BPM = 125.0
BEAT = 60.0 / BPM            # 0.48 s
BAR = 4 * BEAT               # 1.92 s
DROP_IN_TRACK = 93.182       # downbeat of the drop in Werq.mp3
DROP_BAR = 2.5               # video bar on which the drop lands (the player picture)
MUSIC_START = DROP_IN_TRACK - DROP_BAR * BAR
def bar(b): return b * BAR

FT = "C:/Windows/Fonts/"
LIGHT = lambda s: ImageFont.truetype(FT + "segoeuil.ttf", s)
SEMI  = lambda s: ImageFont.truetype(FT + "seguisb.ttf", s)
REG   = lambda s: ImageFont.truetype(FT + "segoeui.ttf", s)
ACCENT = (76, 134, 255); WHITE = (248, 249, 252); MUTE = (146, 152, 166); INK = (6, 7, 9)

def c01(x): return 0.0 if x < 0 else 1.0 if x > 1 else x
def eo(t): t = c01(t); return 1 - (1 - t) ** 3
def eio(t): t = c01(t); return 4 * t * t * t if t < .5 else 1 - (-2 * t + 2) ** 3 / 2
def smooth(t): t = c01(t); return t * t * (3 - 2 * t)
def lerp(a, b, t): return a + (b - a) * t
def spring(t):
    t = c01(t); return 1 - math.exp(-6 * t) * math.cos(9 * t) * (1 - t)

# ---- background -----------------------------------------------------------
BASE = None
def make_base():
    base = Image.new("RGB", (W, H), INK); px = base.load()
    for y in range(H):
        k = int(lerp(16, 5, y / H)); row = (k, k + 1, k + 4)
        for x in range(W): px[x, y] = row
    g = Image.new("L", (W, H), 0); ImageDraw.Draw(g).ellipse([W // 2 - 900, -600, W // 2 + 900, 560], fill=48)
    g = g.filter(ImageFilter.GaussianBlur(240))
    base = Image.composite(Image.new("RGB", (W, H), (22, 28, 44)), base, g)
    vv = Image.new("L", (W, H), 0); ImageDraw.Draw(vv).ellipse([-380, -260, W + 380, H + 260], fill=255)
    vv = vv.filter(ImageFilter.GaussianBlur(230))
    return Image.composite(base, Image.new("RGB", (W, H), (0, 0, 0)), vv).convert("RGBA")
def background():
    global BASE
    if BASE is None: BASE = make_base()
    return BASE.copy()

# ---- primitives -----------------------------------------------------------
_m = {}
def rrect(w, h, r):
    k = (w, h, r)
    if k not in _m:
        m = Image.new("L", (w * 2, h * 2), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 2 - 1, h * 2 - 1], radius=r * 2, fill=255)
        _m[k] = m.resize((w, h), Image.LANCZOS)
    return _m[k]
_sh = {}
def shadow(w, h, r, blur, a):
    k = (w, h, r, blur, a)
    if k not in _sh:
        s = Image.new("RGBA", (w + blur * 4, h + blur * 4), (0, 0, 0, 0)); mm = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mm).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=a); s.paste((0, 0, 0, a), (blur * 2, blur * 2), mm)
        _sh[k] = (s.filter(ImageFilter.GaussianBlur(blur)), blur * 2)
    return _sh[k]
def alpha_img(img, a):
    if a >= 1: return img
    im = img.copy(); im.putalpha(im.getchannel("A").point(lambda p: int(p * c01(a)))); return im
def text(dst, xy, s, fnt, color, a=1.0, anchor="la", track=0.0):
    if a <= 0: return
    l = Image.new("RGBA", dst.size, (0, 0, 0, 0)); d = ImageDraw.Draw(l)
    if track and "\n" not in s:
        widths = [d.textlength(ch, font=fnt) for ch in s]; total = sum(widths) + track * (len(s) - 1)
        x = xy[0] - total / 2 if anchor[0] == "m" else xy[0]
        va = anchor[1] if len(anchor) > 1 else "a"
        for ch, wd in zip(s, widths):
            d.text((x, xy[1]), ch, font=fnt, fill=(*color, int(255 * c01(a))), anchor="l" + va); x += wd + track
    else:
        d.text(xy, s, font=fnt, fill=(*color, int(255 * c01(a))), anchor=anchor)
    dst.alpha_composite(l)
def measure(s, fnt):
    b = ImageDraw.Draw(Image.new("RGB", (4, 4))).textbbox((0, 0), s, font=fnt); return b[2] - b[0], b[3] - b[1]
def paste_center(dst, img, cx, cy, a=1.0):
    dst.alpha_composite(alpha_img(img, a), (int(cx - img.width / 2), int(cy - img.height / 2)))

class AA:
    """Anti-aliased vector layer: draws at 2x, composites downsampled."""
    def __init__(self, size):
        self.w, self.h = size; self.l = Image.new("RGBA", (self.w * 2, self.h * 2), (0, 0, 0, 0)); self.d = ImageDraw.Draw(self.l)
    def _b(self, box): return [v * 2 for v in box]
    def ellipse(self, box, **kw):
        if "width" in kw: kw["width"] *= 2
        self.d.ellipse(self._b(box), **kw)
    def rrect(self, box, radius, **kw):
        if "width" in kw: kw["width"] *= 2
        self.d.rounded_rectangle(self._b(box), radius=radius * 2, **kw)
    def rect(self, box, **kw): self.d.rectangle(self._b(box), **kw)
    def polygon(self, pts, **kw): self.d.polygon([(x * 2, y * 2) for x, y in pts], **kw)
    def arc(self, box, a0, a1, **kw):
        if "width" in kw: kw["width"] *= 2
        self.d.arc(self._b(box), a0, a1, **kw)
    def text(self, xy, s, fontfn, size, fill, anchor="la"):
        self.d.text((xy[0] * 2, xy[1] * 2), s, font=fontfn(size * 2), fill=fill, anchor=anchor)
    def paste(self, img, xy):
        self.l.alpha_composite(img.resize((img.width * 2, img.height * 2), Image.LANCZOS), (int(xy[0] * 2), int(xy[1] * 2)))
    def done(self, dst, a=1.0):
        dst.alpha_composite(alpha_img(self.l.resize((self.w, self.h), Image.LANCZOS), a))

# ---- footage --------------------------------------------------------------
_seq = {}
def frames(n):
    if n not in _seq: _seq[n] = sorted(glob.glob(os.path.join(HERE, "fr", n, "*.jpg")))
    return _seq[n]
_fc = {}
def rf(n, t, crop=None):
    fs = frames(n); i = min(len(fs) - 1, max(0, int(round(t * FPS))))
    k = (n, i, crop)
    if k in _fc: return _fc[k]
    im = Image.open(fs[i]).convert("RGB")
    if crop: im = im.crop(crop)
    if len(_fc) > 40: _fc.clear()
    _fc[k] = im; return im

CROP_PHONE = (0, 0, 424, 918)
CROP_TAB   = (0, 0, 1104, 828)
CROP_DESK  = (0, 0, 1924, 1202)
CROP_TV    = (0, 0, 1920, 1080)
CROP_PLAY  = (0, 0, 1924, 1058)
CROP_FLOW  = (0, 0, 1384, 858)

# ---- device frames (built at 2x, downsampled) ------------------------------
def _fit(shot, sw, sh): return shot.resize((sw, sh), Image.LANCZOS)

def phone(shot, sw, landscape=False):
    """A modern slab phone: thin bezel, big corner radius, punch-hole camera, side keys."""
    S = 2; sw2 = sw * S
    sh2 = int(sw2 * 9 / 16) if landscape else int(sw2 * 918 / 424)
    b = max(6, int(sw2 * 0.035)); r = int(sw2 * (0.10 if landscape else 0.15))
    key = max(2, int(sw2 * 0.012))
    fw, fh = sw2 + 2 * b + 2 * key, sh2 + 2 * b
    p = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); d = ImageDraw.Draw(p)
    ox = key
    if not landscape:
        d.rounded_rectangle([0, int(fh * 0.22), key + 2, int(fh * 0.30)], radius=key, fill=(40, 42, 50, 255))
        d.rounded_rectangle([0, int(fh * 0.32), key + 2, int(fh * 0.40)], radius=key, fill=(40, 42, 50, 255))
        d.rounded_rectangle([fw - key - 3, int(fh * 0.26), fw - 1, int(fh * 0.38)], radius=key, fill=(40, 42, 50, 255))
    body = Image.new("RGBA", (sw2 + 2 * b, sh2 + 2 * b), (22, 23, 28, 255)); body.putalpha(rrect(sw2 + 2 * b, sh2 + 2 * b, r + b)); p.alpha_composite(body, (ox, 0))
    d.rounded_rectangle([ox, 0, ox + sw2 + 2 * b - 1, fh - 1], radius=r + b, outline=(120, 124, 138, 200), width=2)
    d.rounded_rectangle([ox + 2, 2, ox + sw2 + 2 * b - 3, fh - 3], radius=r + b - 2, outline=(8, 8, 10, 255), width=3)
    s = _fit(shot, sw2, sh2).convert("RGBA"); s.putalpha(rrect(sw2, sh2, r)); p.alpha_composite(s, (ox + b, b))
    if not landscape:
        cr = max(3, int(sw2 * 0.025)); cx, cy = ox + b + sw2 // 2, b + int(sw2 * 0.06)
        d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(6, 6, 8, 255)); d.ellipse([cx - cr // 2, cy - cr // 2, cx + cr // 2, cy + cr // 2], fill=(28, 30, 46, 255))
    gl = Image.new("L", (sw2, sh2), 0); gd = ImageDraw.Draw(gl)
    gd.polygon([(0, 0), (int(sw2 * 0.55), 0), (0, int(sh2 * 0.45))], fill=22); gl = gl.filter(ImageFilter.GaussianBlur(sw2 * 0.08))
    gl = Image.composite(gl, Image.new("L", (sw2, sh2), 0), rrect(sw2, sh2, r))
    glass = Image.new("RGBA", (sw2, sh2), (255, 255, 255, 0)); glass.putalpha(gl); p.alpha_composite(glass, (ox + b, b))
    return p.resize((fw // S, fh // S), Image.LANCZOS)

def tablet(shot, sw):
    S = 2; sw2 = sw * S; sh2 = int(sw2 * shot.height / shot.width)
    b = max(10, int(sw2 * 0.04)); r = int(sw2 * 0.045)
    fw, fh = sw2 + 2 * b, sh2 + 2 * b
    p = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); d = ImageDraw.Draw(p)
    body = Image.new("RGBA", (fw, fh), (20, 21, 26, 255)); body.putalpha(rrect(fw, fh, r + b)); p.alpha_composite(body)
    d.rounded_rectangle([0, 0, fw - 1, fh - 1], radius=r + b, outline=(112, 116, 130, 190), width=2)
    s = _fit(shot, sw2, sh2).convert("RGBA"); s.putalpha(rrect(sw2, sh2, r)); p.alpha_composite(s, (b, b))
    cr = max(3, int(sw2 * 0.008)); cx, cy = b // 2, fh // 2
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(8, 8, 10, 255))
    return p.resize((fw // S, fh // S), Image.LANCZOS)

def monitor(shot, sw):
    S = 2; sw2 = sw * S; sh2 = int(sw2 * 1202 / 1924)
    b = max(6, int(sw2 * 0.011)); chin = int(sw2 * 0.04); r = int(sw2 * 0.012)
    stand_h = int(sw2 * 0.075); base_w = int(sw2 * 0.28); base_h = max(6, int(sw2 * 0.012))
    fw, fh = sw2 + 2 * b, sh2 + 2 * b + chin + stand_h + base_h
    p = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); d = ImageDraw.Draw(p)
    d.polygon([(fw // 2 - int(sw2 * 0.045), sh2 + 2 * b + chin), (fw // 2 + int(sw2 * 0.045), sh2 + 2 * b + chin),
               (fw // 2 + int(sw2 * 0.06), fh - base_h), (fw // 2 - int(sw2 * 0.06), fh - base_h)], fill=(34, 36, 44, 255))
    d.rounded_rectangle([fw // 2 - base_w // 2, fh - base_h - 2, fw // 2 + base_w // 2, fh - 1], radius=base_h // 2, fill=(46, 49, 58, 255))
    body = Image.new("RGBA", (fw, sh2 + 2 * b + chin), (18, 19, 24, 255)); body.putalpha(rrect(fw, sh2 + 2 * b + chin, r + b)); p.alpha_composite(body)
    s = _fit(shot, sw2, sh2).convert("RGBA"); s.putalpha(rrect(sw2, sh2, r)); p.alpha_composite(s, (b, b))
    d.rounded_rectangle([0, 0, fw - 1, sh2 + 2 * b + chin - 1], radius=r + b, outline=(100, 106, 120, 180), width=2)
    return p.resize((fw // S, fh // S), Image.LANCZOS)

def tv(shot, sw, power=1.0):
    S = 2; sw2 = sw * S; sh2 = int(sw2 * 9 / 16); scr = _fit(shot, sw2, sh2)
    if power < 1: scr = ImageEnhance.Brightness(scr).enhance(power)
    b = max(4, int(sw2 * 0.006)); r = max(4, int(sw2 * 0.006))
    foot_h = int(sw2 * 0.02); foot_w = int(sw2 * 0.06)
    fw, fh = sw2 + 2 * b, sh2 + 2 * b + foot_h
    p = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); d = ImageDraw.Draw(p)
    for fx in (int(sw2 * 0.14), fw - int(sw2 * 0.14) - foot_w):
        d.polygon([(fx, fh - 1), (fx + foot_w, fh - 1), (fx + foot_w - int(foot_w * 0.3), sh2 + 2 * b - 2), (fx + int(foot_w * 0.3), sh2 + 2 * b - 2)], fill=(40, 42, 50, 255))
    body = Image.new("RGBA", (fw, sh2 + 2 * b), (10, 11, 14, 255)); body.putalpha(rrect(fw, sh2 + 2 * b, r + b)); p.alpha_composite(body)
    s = scr.convert("RGBA"); s.putalpha(rrect(sw2, sh2, r)); p.alpha_composite(s, (b, b))
    d.rounded_rectangle([0, 0, fw - 1, sh2 + 2 * b - 1], radius=r + b, outline=(90, 96, 110, 170), width=2)
    return p.resize((fw // S, fh // S), Image.LANCZOS)

def panel(shot, r=14):
    p = shot.convert("RGBA"); p.putalpha(rrect(p.width, p.height, r))
    ov = Image.new("RGBA", p.size, (0, 0, 0, 0)); ImageDraw.Draw(ov).rounded_rectangle([0, 0, p.width - 1, p.height - 1], radius=r, outline=(70, 76, 92, 150), width=1)
    p.alpha_composite(ov); return p

def place(dst, pnl, cx, cy, a=1.0, scale=1.0, shadow_a=150, lift=34):
    if scale != 1.0:
        pnl = pnl.resize((max(1, int(pnl.width * scale)), max(1, int(pnl.height * scale))), Image.LANCZOS)
    x = int(cx - pnl.width / 2); y = int(cy - pnl.height / 2)
    s, off = shadow(pnl.width, pnl.height, 18, 46, int(shadow_a * a)); dst.alpha_composite(s, (x - off, y - off + lift))
    dst.alpha_composite(alpha_img(pnl, a), (x, y))

LOGO = None
def logo(sz):
    global LOGO
    if LOGO is None: LOGO = Image.open(os.path.join(REPO, "icons", "production", "chudder_store_icon.png")).convert("RGBA")
    return LOGO.resize((sz, int(sz * LOGO.height / LOGO.width)), Image.LANCZOS)

def kicker(dst, cx, y, kick, head, a):
    text(dst, (cx, y), kick.upper(), SEMI(30), ACCENT, a, anchor="ma", track=4.5)
    text(dst, (cx, y + 44), head, REG(44), WHITE, a, anchor="ma")

def ripple(aa, cx, cy, t0, t, color=WHITE, rmax=70):
    u = (t - t0) / 0.55
    if u < 0 or u > 1: return
    r = lerp(14, rmax, eo(u)); a = int(200 * (1 - u))
    aa.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(*color, a), width=3)
    aa.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=(*color, int(a * 0.8)))

# ---- shots ------------------------------------------------------------------
def s_logo(img, lt, dur, A):
    sz = int(lerp(112, 128, eio(lt / 1.6)))
    paste_center(img, logo(sz), W // 2, H // 2 - 110, A)
    text(img, (W // 2, H // 2 + 16), "Chudder", LIGHT(104), WHITE, A, anchor="ma", track=2)
    ln = int(110 * eio((lt - 0.6) / 0.8))
    if ln > 0: ImageDraw.Draw(img).rounded_rectangle([W // 2 - ln // 2, H // 2 + 154, W // 2 + ln // 2, H // 2 + 158], radius=2, fill=(*ACCENT, int(220 * A)))
    text(img, (W // 2, H // 2 + 190), "A Jellyfin client for every screen in the house", REG(30), MUTE, A * eo((lt - 1.0) / 0.6), anchor="ma")

# The interaction take, time-remapped so that the picture appears exactly on the drop.
FLOW_MAP = [  # (take_from, take_to, shot_from_bar, shot_to_bar)
    (0.90, 9.97, 0.0, 4.1),     # dashboard → search → type → results → detail → click Play
    (9.97, 11.95, 4.1, 4.5),    # "Loading" flashes past
    (11.95, 16.70, 4.5, 6.75),  # playing
    (16.70, 22.40, 6.75, 8.5),  # shrink to mini-player, back home, browse
]
def flow_time(lt):
    b = lt / BAR
    for tf, tt, sf, st in FLOW_MAP:
        if b < st: return tf + (tt - tf) * c01((b - sf) / (st - sf))
    tf, tt, sf, st = FLOW_MAP[-1]; return tt
def take_to_shot(tt):
    for tf, t2, sf, st in FLOW_MAP:
        if tf <= tt <= t2: return (sf + (st - sf) * (tt - tf) / (t2 - tf)) * BAR
    return -10

def s_flow(img, lt, dur, A):
    ft = flow_time(lt)
    shot = rf("flow", ft, CROP_FLOW); pnl = panel(shot)
    cx, cy = W // 2, 458
    place(img, pnl, cx, cy, A, shadow_a=170)
    b = lt / BAR
    labels = [(0.0, 4.5, "Search that forgives you", "Misspell it, skip the accents — Chudder still finds it. Then just press play."),
              (4.5, 6.75, "Direct play", "No transcoding, full quality — the file your server has, straight to the screen"),
              (6.75, 9.0, "Playback follows you around", "Shrink the player and keep browsing — it keeps playing")]
    for f, t, k, h in labels:
        a = c01((b - f) / 0.18) * (1 - c01((b - t + 0.18) / 0.18))
        if a > 0: kicker(img, cx, 918, k, h, A * a)
    aa = AA(img.size); ox, oy = cx - 692, cy - 429
    for tt, px, py in ((1.75, 55, 133), (4.85, 212, 431), (6.60, 212, 431), (9.95, 293, 808), (16.85, 40, 43), (19.70, 55, 203)):
        ripple(aa, ox + px, oy + py, take_to_shot(tt) - 0.15, lt, rmax=46)
    aa.done(img, A)

def statement(lines, hi=None, size=88):
    def fn(img, lt, dur, A):
        y = H // 2 - (len(lines) * (size + 6)) // 2; yo = int(lerp(18, 0, eo(lt / .5)))
        for i, l in enumerate(lines):
            col = ACCENT if hi == i else WHITE
            text(img, (W // 2, y + i * (size + 8) + yo), l, LIGHT(size), col, A, anchor="ma", track=1.5)
    return fn

def take(seq, t0, t1, kick, head, label_from=0.0):
    """Show a captured 1400x900 take at 1:1 pixels, time-remapped linearly onto the shot."""
    def fn(img, lt, dur, A):
        ft = t0 + (t1 - t0) * c01(lt / dur)
        pnl = panel(rf(seq, ft, CROP_FLOW))
        place(img, pnl, W // 2, PCY, A, shadow_a=170)
        kicker(img, W // 2, KY, kick, head, A * c01((lt - label_from) / 0.3))
    return fn

def s_hero(img, lt, dur, A):
    t_tv, t_dk, t_tb, t_ph = 0.0, BEAT, 2 * BEAT, 3 * BEAT
    drift = eo(lt / dur)
    def entry(t0): return spring((lt - t0) / 0.75), c01((lt - t0) / 0.25)
    e, a = entry(t_tv); p = tv(rf("detail_tv", 1.0, CROP_TV), 900)
    place(img, p, W // 2 + int(-8 * drift), 300 + int(lerp(60, 0, e)), A * a, scale=lerp(0.94, 1.0, e), shadow_a=170, lift=40)
    e, a = entry(t_dk); p = monitor(rf("detail_desk", 1.0, CROP_DESK), 560)
    place(img, p, 330 + int(-18 * drift), 775 + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(t_tb); p = tablet(rf("ipad", 1.0), 480)
    place(img, p, 950 + int(10 * drift), 765 + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(t_ph); p = phone(rf("cast_phone", 1.0), 200)
    place(img, p, 1580 + int(22 * drift), 750 + int(lerp(80, 0, e)), A * a, scale=lerp(0.9, 1.0, e))
    la = c01((lt - 4 * BEAT) / 0.4)
    text(img, (W // 2, 980), "One client for every screen in the house — free and open source", REG(32), WHITE, A * la, anchor="ma")
    text(img, (W // 2, 1030), "WINDOWS  ·  MACOS  ·  LINUX  ·  ANDROID  ·  ANDROID TV  ·  IOS  ·  WEB", SEMI(26), WHITE, A * la, anchor="ma", track=2)

def s_sync(img, lt, dur, A):
    """Two clients, one playhead. Real Chudder player chrome, captured 16:9 at 960x540:
    playing 0-6s (controls visible, then hidden), paused 7-10.5s, resumed after."""
    t_pause = 1.25 * BAR; t_resume = 2 * BAR; t_seek = 2.5 * BAR; JUMP = 2.3
    if lt < t_pause: ft = 1.5 + lt
    elif lt < t_resume: ft = 8.6
    elif lt < t_seek: ft = 11.4 + (lt - t_resume)
    else: ft = 11.4 + (lt - t_resume) + JUMP
    shot = rf("play_land", ft); paused = t_pause <= lt < t_resume
    sw = 720; ph = phone(shot, sw, landscape=True); sh = int(sw * 9 / 16)
    e1, a1 = spring(lt / 0.7), c01(lt / 0.25); e2, a2 = spring((lt - BEAT) / 0.7), c01((lt - BEAT) / 0.25)
    cx1, cx2, cy = 470, 1450, 455
    place(img, ph, cx1, cy + int(lerp(50, 0, e1)), A * a1, scale=lerp(0.94, 1, e1))
    place(img, ph, cx2, cy + int(lerp(50, 0, e2)), A * a2, scale=lerp(0.94, 1, e2))
    aa = AA(img.size)
    # No pause glyph is drawn over the picture: the app's own controls are in the
    # take and already show the paused state, and a second one contradicts them.
    la = c01((lt - 2 * BEAT) / 0.3)
    for cx, nm in ((cx1, "You"), (cx2, "A friend, 800 km away")):
        w, h = measure(nm, SEMI(24)); yy = cy - sh // 2 - 62
        aa.rrect([cx - w // 2 - 18, yy - 8, cx + w // 2 + 18, yy + h + 14], 18, fill=(255, 255, 255, int(24 * la)))
        aa.text((cx, yy + 2), nm, SEMI, 24, (*WHITE, int(255 * la)), anchor="ma")
    lk = c01((lt - 2 * BEAT) / 0.4); ly = cy; xa, xb = cx1 + sw // 2 + 44, cx2 - sw // 2 - 44
    for x in range(xa, xb, 18): aa.ellipse([x - 3, ly - 3, x + 3, ly + 3], fill=(*ACCENT, int(120 * lk)))
    if lk > 0:
        phs = (lt % BEAT) / BEAT; src_left = lt < t_pause - 0.1
        for k in (0.0, 0.5):
            u = (phs + k) % 1.0; px = lerp(xa, xb, u) if src_left else lerp(xb, xa, u)
            g = 9 + 5 * (1 - u); aa.ellipse([px - g, ly - g, px + g, ly + g], fill=(*ACCENT, int(230 * (1 - u * 0.6) * lk)))
    label = "SKIPPED AHEAD — on both" if lt >= t_seek else ("PAUSED — on both" if paused else "SYNCPLAY")
    w, h = measure(label, SEMI(22)); mx = (xa + xb) // 2
    aa.rrect([mx - w // 2 - 20, ly - 62, mx + w // 2 + 20, ly - 62 + h + 20], 16, fill=(12, 14, 20, int(235 * lk)), outline=(*ACCENT, int(180 * lk)), width=1)
    aa.text((mx, ly - 54), label, SEMI, 22, (*(WHITE if label == "SYNCPLAY" else ACCENT), int(255 * lk)), anchor="ma")
    ripple(aa, cx2, cy, t_pause - 0.22, lt, rmax=80); ripple(aa, cx2, cy, t_resume - 0.22, lt, rmax=80)
    if t_seek - 0.3 <= lt < t_seek + 0.6:
        by = cy - sh // 2 + int(sh * 0.945); bx0, bx1 = cx2 - sw // 2 + int(sw * 0.015), cx2 + sw // 2 - int(sw * 0.015)
        u = c01((lt - (t_seek - 0.3)) / 0.3); fx = lerp(bx0 + (bx1 - bx0) * 0.30, bx0 + (bx1 - bx0) * 0.42, u); fa = 1 - c01((lt - t_seek - 0.25) / 0.3)
        aa.ellipse([fx - 15, by - 15, fx + 15, by + 15], fill=(*WHITE, int(120 * fa)))
        aa.rrect([fx - 36, by - 60, fx + 36, by - 28], 10, fill=(*ACCENT, int(255 * fa)))
        aa.text((fx, by - 56), "+30 s", SEMI, 20, (*WHITE, int(255 * fa)), anchor="ma")
    aa.done(img, A)
    kicker(img, W // 2, KY, "SyncPlay that just works", "Every play, pause and seek lands on both screens — from anywhere", A * c01((lt - 3 * BEAT) / 0.4))

def s_cast(img, lt, dur, A):
    """Real phone take (web build): detail page, tap the cast icon at ~1.45s, the real sheet slides up.
    The real sheet is extended with device rows in the same Material style, then a Connecting row, then the remote."""
    t_tap, t_pick, t_send, t_on = BEAT, 4 * BEAT, 4.5 * BEAT, 5.5 * BEAT
    pw = 330; px_, py = 430, 520; scale = pw / 424.0
    tk = 1.0 if lt < t_tap else min(6.5, 1.45 + (lt - t_tap))
    shot = rf("cast_phone", tk).convert("RGBA")
    ImageDraw.Draw(shot).rectangle([0, 810, 424, 848], fill=shot.getpixel((6, 829)))
    sheet_ready = lt >= t_tap + 0.9
    S_TOP = 727; EXT = 150
    if sheet_ready and lt < t_on:
        base = rf("cast_phone", 6.0).convert("RGBA")
        ov = AA((424, 918))
        ov.rrect([0, S_TOP - EXT, 424, 918 + 40], 28, fill=(18, 18, 18, 255))
        ov.done(shot)
        hdr = base.crop((0, S_TOP + 2, 424, S_TOP + 108)); shot.alpha_composite(hdr, (0, S_TOP - EXT + 2))
        ov = AA((424, 918)); y0 = S_TOP - EXT + 118
        rows = [("Living room TV", "Chromecast", "cast"), ("Bedroom TV", "DLNA", "tv"), ("Apple TV", "Play video on an Apple TV", "airplay")]
        connecting = lt >= t_pick + 0.35
        if not connecting:
            for i, (nm, kind, ic) in enumerate(rows):
                ry = y0 + i * 62
                if i == 0 and lt >= t_pick: ov.rect([0, ry - 10, 424, ry + 50], fill=(255, 255, 255, 18))
                icx, icy = 40, ry + 20
                if ic == "cast":
                    ov.rrect([icx - 11, icy - 8, icx + 11, icy + 8], 2, outline=(*WHITE, 235), width=2)
                    ov.arc([icx - 22, icy - 4, icx - 2, icy + 16], -90, 0, fill=(*WHITE, 235), width=2)
                elif ic == "tv":
                    ov.rrect([icx - 11, icy - 8, icx + 11, icy + 6], 2, outline=(*WHITE, 235), width=2); ov.rect([icx - 5, icy + 8, icx + 5, icy + 10], fill=(*WHITE, 235))
                else:
                    ov.rrect([icx - 11, icy - 9, icx + 11, icy + 5], 2, outline=(*WHITE, 235), width=2); ov.polygon([(icx - 5, icy + 10), (icx + 5, icy + 10), (icx, icy + 3)], fill=(*WHITE, 235))
                ov.text((66, ry + 1), nm, SEMI, 16, WHITE); ov.text((66, ry + 22), kind, REG, 13, (170, 174, 186))
        else:
            ry = y0; sp = (lt * 6) % (2 * math.pi)
            ov.arc([28, ry + 8, 52, ry + 32], math.degrees(sp), math.degrees(sp) + 270, fill=(*ACCENT, 255), width=2)
            ov.text((62, ry + 10), "Connecting to Living room TV...", SEMI, 16, WHITE)
        ov.done(shot)
    if lt >= t_on:
        u = eo((lt - t_on) / 0.4)
        ov = AA((424, 918))
        ov.rect([0, 0, 424, 918], fill=(14, 15, 20, 255))
        art = rf("play_desk", 12.0 + (lt - t_on), CROP_PLAY).resize((376, 212), Image.LANCZOS).convert("RGBA")
        art.putalpha(rrect(376, 212, 18)); ov.paste(art, (24, 130))
        ov.text((212, 70), "PLAYING ON LIVING ROOM TV", SEMI, 15, (*ACCENT, 255), anchor="ma")
        ov.text((24, 366), "Caminandes: Llamigos", SEMI, 26, (*WHITE, 255))
        ov.text((24, 402), "2016  ·  2m 30s  ·  Blender Foundation", REG, 17, (*MUTE, 255))
        prog = 0.18 + 0.05 * (lt - t_on)
        ov.rrect([24, 460, 400, 465], 3, fill=(255, 255, 255, 60)); ov.rrect([24, 460, 24 + 376 * prog, 465], 3, fill=(*ACCENT, 255))
        ov.text((24, 476), "00:27", REG, 15, (*MUTE, 255)); ov.text((400, 476), "-02:03", REG, 15, (*MUTE, 255), anchor="ra")
        ov.ellipse([212 - 40, 550 - 40, 212 + 40, 550 + 40], fill=(*ACCENT, 255))
        ov.rrect([212 - 14, 550 - 18, 212 - 4, 550 + 18], 2, fill=(*WHITE, 255)); ov.rrect([212 + 4, 550 - 18, 212 + 14, 550 + 18], 2, fill=(*WHITE, 255))
        for sx, dirn in ((110, -1), (314, 1)):
            ov.polygon([(sx - 14 * dirn, 536), (sx + 6 * dirn, 550), (sx - 14 * dirn, 564)], fill=(*WHITE, 220))
            ov.rect([sx + 8 * dirn - 2, 536, sx + 8 * dirn + 2, 564], fill=(*WHITE, 220))
        ov.text((212, 630), "volume  ·  subtitles  ·  audio track", REG, 16, (*MUTE, 255), anchor="ma")
        ov.text((212, 860), "Tap to stop casting", REG, 14, (110, 114, 128, 255), anchor="ma")
        card = ov.l.resize((424, 918), Image.LANCZOS); shot.alpha_composite(alpha_img(card, u))
    ph = phone(shot, pw)
    e1, a1 = spring(lt / 0.7), c01(lt / 0.25)
    place(img, ph, px_, py + int(lerp(50, 0, e1)), A * a1, scale=lerp(0.94, 1, e1))
    e2, a2 = spring((lt - BEAT) / 0.7), c01((lt - BEAT) / 0.25)
    power = 0.06 if lt < t_on else lerp(0.06, 1.0, eo((lt - t_on) / 0.35))
    tp = tv(rf("play_desk", 12.0 + max(0.0, lt - t_on), CROP_PLAY), 1000, power=power)
    tcx, tcy = 1330, 470
    place(img, tp, tcx, tcy + int(lerp(50, 0, e2)), A * a2, scale=lerp(0.96, 1, e2), shadow_a=160)
    aa = AA(img.size)
    if lt < t_on:
        blink = 0.5 + 0.5 * math.sin(lt * 4)
        aa.ellipse([tcx - 4, tcy + 292, tcx + 4, tcy + 300], fill=(255, 90, 80, int(200 * blink * a2)))
        aa.text((tcx, tcy - 20), "Living room TV", REG, 30, (*MUTE, int(140 * a2)), anchor="ma")
    bez = int(pw * 0.035); ph_top = py - ph.height / 2 + lerp(50, 0, e1) + bez; ph_left = px_ - ph.width / 2 + max(2, int(pw * 0.012)) + bez
    ripple(aa, ph_left + 349 * scale, ph_top + 41 * scale, t_tap, lt, rmax=54)
    ripple(aa, px_, ph_top + (S_TOP - EXT + 118 + 20) * scale, t_pick, lt, rmax=54)
    if t_send <= lt < t_on + 0.3:
        u = (lt - t_send) / (t_on - t_send); sx, sy = px_ + pw / 2 + 24, py - 80; ex, ey = tcx - 500, tcy
        for k in range(3):
            ru = c01(u * 1.4 - k * 0.18)
            if 0 < ru < 1:
                r = lerp(20, 160, ru); aa.arc([sx - r, sy - r, sx + r, sy + r], -60, 60, fill=(*ACCENT, int(230 * (1 - ru))), width=5)
        for k in range(6):
            cu = c01(u * 1.25 - k * 0.05)
            if 0 < cu < 1:
                cx = lerp(sx, ex, cu); cy = lerp(sy, ey, cu) - math.sin(cu * math.pi) * 120
                g = 8 - k; aa.ellipse([cx - g, cy - g, cx + g, cy + g], fill=(*ACCENT, int(255 * (1 - k * 0.14))))
    if lt >= t_on:
        fl = 1 - c01((lt - t_on) / 0.5); aa.rect([tcx - 500, tcy - 281, tcx + 500, tcy + 281], fill=(*WHITE, int(90 * fl)))
    aa.done(img, A)
    kicker(img, W // 2, KY, "The only Jellyfin client with Chromecast, AirPlay and DLNA", "Pick a screen on your phone — it starts on the TV", A * c01((lt - BEAT) / 0.4))

def listing(title, items):
    def fn(img, lt, dur, A):
        text(img, (W // 2, H // 2 - 70), title, LIGHT(74), WHITE, A, anchor="ma")
        fnt = REG(36); widths = [measure(p, fnt)[0] for p in items]; gap = 52
        total = sum(widths) + (len(items) - 1) * gap; x = W // 2 - total / 2
        for i, p in enumerate(items):
            ia = c01((lt - 0.15 - i * 0.07) / 0.3)
            text(img, (x, H // 2 + 34), p, fnt, MUTE, A * ia, anchor="la"); x += widths[i]
            if i < len(items) - 1:
                text(img, (x + gap / 2, H // 2 + 48), "•", REG(22), ACCENT, A * ia * 0.8, anchor="ma"); x += gap
    return fn

def s_outro(img, lt, dur, A):
    paste_center(img, logo(136), W // 2, H // 2 - 200, A)
    text(img, (W // 2, H // 2 - 74), "Complete.  Free.  Everywhere.", LIGHT(74), WHITE, A, anchor="ma", track=1.5)
    ln = int(120 * eio((lt - 0.4) / 0.7))
    if ln > 0: ImageDraw.Draw(img).rounded_rectangle([W // 2 - ln // 2, H // 2 + 28, W // 2 + ln // 2, H // 2 + 32], radius=2, fill=(*ACCENT, int(220 * A)))
    text(img, (W // 2, H // 2 + 60), "github.com/JenteJan/Chudder", LIGHT(46), (210, 214, 224), A, anchor="ma", track=1)
    text(img, (W // 2, H // 2 + 122), "Free & open source   ·   GPL-3", REG(28), MUTE, A, anchor="ma")
    text(img, (W // 2, H - 60), "Music: \"Werq\" Kevin MacLeod (incompetech.com), CC BY 4.0   ·   Footage: Caminandes: Llamigos, Blender Foundation, CC BY", REG(18), (90, 95, 110), A, anchor="ma")


PCY, KY = 446, 905   # panel centre / kicker baseline (keeps captions clear of Reddit's scrubber)

def s_open(img, lt, dur, A):
    """Hook: the product on four screens within the first second, headline says what it is."""
    k, off = 0.80, 150
    drift = eo(lt / dur)
    def entry(t0): return spring((lt - t0) / 0.7), c01((lt - t0) / 0.22)
    hy = int(lerp(14, 0, eo(lt / 0.5)))
    paste_center(img, logo(40), W // 2 - 78, 52 + hy, A)
    text(img, (W // 2 - 50, 52 + hy), "Chudder", SEMI(30), WHITE, A, anchor="lm", track=1)
    text(img, (W // 2, 90 + hy), "A Jellyfin client for every screen you own.", LIGHT(60), WHITE, A, anchor="ma", track=1)
    e, a = entry(0); p = tv(rf("detail_tv", 1.0, CROP_TV), int(900 * k))
    place(img, p, W // 2 + int(-6 * drift), int(300 * k) + off + int(lerp(60, 0, e)), A * a, scale=lerp(0.94, 1.0, e), shadow_a=170, lift=40)
    e, a = entry(0.5 * BEAT); p = monitor(rf("detail_desk", 1.0, CROP_DESK), int(560 * k))
    place(img, p, int(W // 2 - (W // 2 - 330) * k) + int(-14 * drift), int(775 * k) + off + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(1.0 * BEAT); p = tablet(rf("ipad", 1.0), int(480 * k))
    place(img, p, int(W // 2 - 10 * k) + int(8 * drift), int(765 * k) + off + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(1.5 * BEAT); p = phone(rf("cast_phone", 1.0), int(200 * k))
    place(img, p, int(W // 2 + 620 * k) + int(18 * drift), int(750 * k) + off + int(lerp(80, 0, e)), A * a, scale=lerp(0.9, 1.0, e))
    la = c01((lt - 2.5 * BEAT) / 0.4)
    text(img, (W // 2, 972), "WINDOWS  ·  MACOS  ·  LINUX  ·  ANDROID  ·  ANDROID TV  ·  IOS  ·  WEB", SEMI(28), WHITE, A * la, anchor="ma", track=2.5)
    text(img, (W // 2, 1016), "Free and open source", REG(26), MUTE, A * la, anchor="ma")

BADGE = (1168, 616, 1362, 670)   # "Direct · SDR HD" pills in the flow take
def s_play(img, lt, dur, A):
    """The drop: full-quality playback, then a magnifier on the app's own Direct badge."""
    ft = 11.95 + (16.7 - 11.95) * c01(lt / dur)
    shot = rf("flow", ft, CROP_FLOW); pnl = panel(shot)
    cx, cy = W // 2, PCY; place(img, pnl, cx, cy, A, shadow_a=170)
    ox, oy = cx - 692, cy - 429
    t0 = 0.75 * BAR; u = spring((lt - t0) / 0.5); va = c01((lt - t0) / 0.2)
    if va > 0:
        bx0, by0, bx1, by1 = BADGE; Z = 2.4
        lens = shot.crop(BADGE).resize((int((bx1 - bx0) * Z), int((by1 - by0) * Z)), Image.LANCZOS).convert("RGBA")
        lw, lh = lens.size; lens.putalpha(rrect(lw, lh, 22))
        fw, fh = lw + 8, lh + 8
        frame = Image.new("RGBA", (fw, fh), (*ACCENT, 255)); frame.putalpha(rrect(fw, fh, 26)); frame.alpha_composite(lens, (4, 4))
        mx = ox + (bx0 + bx1) // 2
        lcx = ox + bx1 - lw // 2 - 34; lcy = oy + by0 - lh // 2 - 78
        aa = AA(img.size)
        aa.rrect([ox + bx0 - 8, oy + by0 - 6, ox + bx1 + 8, oy + by1 + 6], 24, outline=(*ACCENT, int(235 * va)), width=3)
        aa.rect([mx - 1.5, lcy + fh / 2 - 2, mx + 1.5, oy + by0 - 6], fill=(*ACCENT, int(210 * va)))
        aa.done(img, A)
        sc = lerp(0.82, 1.0, u)
        s, so = shadow(fw, fh, 26, 34, int(170 * va)); img.alpha_composite(alpha_img(s, A), (int(lcx - fw / 2) - so, int(lcy - fh / 2) - so + 18))
        place_frame = frame.resize((max(1, int(fw * sc)), max(1, int(fh * sc))), Image.LANCZOS)
        paste_center(img, place_frame, lcx, lcy, A * va)
    kicker(img, W // 2, KY, "Direct play", "Your server's file, untouched — full quality, no transcoding", A)

def s_outro7(img, lt, dur, A):
    def fade(t0, d=0.4): return A * c01((lt - t0) / d)
    paste_center(img, logo(120), W // 2, H // 2 - 262, A)
    text(img, (W // 2, H // 2 - 150), "Complete.  Free.  Everywhere.", LIGHT(78), WHITE, A, anchor="ma", track=1.5)
    ln = int(120 * eio((lt - 0.3) / 0.7))
    if ln > 0: ImageDraw.Draw(img).rounded_rectangle([W // 2 - ln // 2, H // 2 - 40, W // 2 + ln // 2, H // 2 - 36], radius=2, fill=(*ACCENT, int(220 * A)))
    text(img, (W // 2, H // 2 - 8), "github.com/JenteJan/Chudder", SEMI(60), WHITE, fade(0.5), anchor="ma", track=0.5)
    text(img, (W // 2, H // 2 + 92), "WINDOWS  ·  MACOS  ·  LINUX  ·  ANDROID  ·  ANDROID TV  ·  IOS  ·  WEB", SEMI(26), (200, 205, 216), fade(0.9), anchor="ma", track=2.5)
    text(img, (W // 2, H // 2 + 142), "Free & open source  ·  GPL-3  ·  an opinionated fork of Fladder", REG(28), MUTE, fade(1.1), anchor="ma")
    text(img, (W // 2, H - 64), "Music: \"Werq\" Kevin MacLeod (incompetech.com), CC BY 4.0   ·   Footage: Caminandes: Llamigos, Blender Foundation, CC BY", REG(18), (90, 95, 110), A, anchor="ma")

SHOTS = [
    ("open",     1.5, s_open),
    ("s_hook",   1.0, statement(["Direct play first.", "Transcodes only when it must."], hi=0, size=84)),
    ("play",     2.5, s_play),                                                                                              # the drop
    ("mini",     2.0, take("flow", 16.7, 22.4, "Playback follows you around", "Shrink the player and keep browsing — it keeps playing")),
    ("cast",     4.0, s_cast),
    ("sync",     3.0, s_sync),
    ("search",   2.0, take("flow", 0.9, 6.7, "Search that forgives you", "Misspell it, skip the accents — Chudder still finds it")),
    ("episodes", 1.5, take("episodes", 1.2, 6.3, "Seasons and episodes, always in reach", "Pick up any episode without leaving the show")),
    ("nav",      1.5, take("nav", 0.4, 5.6, "Blazing fast page transitions", "Open, back, open — nothing waits on a spinner")),
    ("settings", 1.5, take("settings", 0.5, 5.6, "Settings search", "Every settings page at once — type what you remember")),
    ("outro",    3.0, s_outro7),
]
XD = 0.22

def timeline():
    starts = []; acc = 0.0
    for _, d, _ in SHOTS: starts.append(acc); acc += bar(d)
    return starts, acc

def render_frame(f):
    starts, total = timeline(); t = f / FPS; img = background()
    i = 0
    for k, st in enumerate(starts):
        if st <= t < st + bar(SHOTS[k][1]): i = k; break
    name, db, fn = SHOTS[i]; di = bar(db); lt = t - starts[i]
    ain = smooth(lt / XD) if lt < XD else 1.0
    aout = smooth((di - lt) / XD) if lt > di - XD else 1.0
    if name == "outro": aout = 1.0 if lt < di - 1.0 else smooth((di - lt) / 1.0)
    fn(img, lt, di, min(ain, aout))
    img.convert("RGB").save(os.path.join(OUT, f"{f:05d}.png"), compress_level=1)
    return f

def main():
    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "*")): os.remove(f)
    starts, total = timeline(); nf = int(total * FPS)
    print(f"total {total:.2f}s {nf} frames; music starts at {MUSIC_START:.3f}s in track")
    for (n, d, _), st in zip(SHOTS, starts): print(f"  {n:8s} {st:6.2f}s  ({d} bars)")
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        picks = sorted(set(int(float(x) * FPS) for x in sys.argv[2:])) if len(sys.argv) > 2 else \
            [int((st + bar(d) * fr) * FPS) for (n, d, _), st in zip(SHOTS, starts) for fr in (0.15, 0.55, 0.9)]
        for f in picks: render_frame(f)
        print("preview frames:", picks); return
    with Pool(8) as p:
        for k, _ in enumerate(p.imap_unordered(render_frame, range(nf), chunksize=8)):
            if k % 150 == 0: print("frame", k, flush=True)
    print("done", nf)

if __name__ == "__main__": main()
