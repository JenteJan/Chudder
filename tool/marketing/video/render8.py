#!/usr/bin/env python3
# Chudder promo v8 — 1920x1080 / 60 fps, on the beat grid of "Werq" (125 BPM), drop on bar 3.
# Builds on render7 (device frames, cast + play shots) and replaces the opener, copy, transitions,
# SyncPlay link, tour shots, recap and outro.
import os, sys, math, glob
from multiprocessing import Pool
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import render7 as R
from render7 import (W, H, BEAT, BAR, bar, LIGHT, SEMI, REG, ACCENT, WHITE, MUTE, INK, c01, eo, eio, smooth, lerp, spring,
                     background, rrect, shadow, alpha_img, text, measure, paste_center, AA, panel, place, logo, ripple,
                     phone, tablet, monitor, CROP_TV, CROP_DESK, CROP_PLAY, CROP_FLOW, PCY, KY)

FPS = 60                      # output rate; footage was extracted at 30
SRC_FPS = 30
OUT = os.path.join(R.HERE, "out8")
DROP_BAR = 3.0
MUSIC_START = R.DROP_IN_TRACK - DROP_BAR * BAR

def rf(n, t, crop=None):
    fs = R.frames(n); i = min(len(fs) - 1, max(0, int(round(t * SRC_FPS))))
    k = (n, i, crop)
    if k in R._fc: return R._fc[k]
    im = Image.open(fs[i]).convert("RGB")
    if crop: im = im.crop(crop)
    if len(R._fc) > 40: R._fc.clear()
    R._fc[k] = im; return im
R.rf = rf

# ---- copy ---------------------------------------------------------------------
# Shots inherited from render7 call kicker() with their old strings; this table rewrites them.
COPY = {
    "Direct play": ("Direct play", "Full quality, straight from your server. No transcoding."),
    "The only Jellyfin client with Chromecast, AirPlay and DLNA":
        ("Chromecast  ·  AirPlay  ·  DLNA  —  from every platform", "Pick a screen on your phone. It plays on the TV."),
    "SyncPlay that just works": ("SyncPlay", "Pause here, it pauses there. Built for friends who aren't in the room."),
}
def kicker(dst, cx, y, kick, head, a):
    kick, head = COPY.get(kick, (kick, head))
    text(dst, (cx, y), kick.upper(), SEMI(30), ACCENT, a, anchor="ma", track=4.5)
    text(dst, (cx, y + 44), head, REG(44), WHITE, a, anchor="ma")
R.kicker = kicker

# ---- opener: the film full-frame, pulled back into a TV, the other screens land ----
CROP_169 = (22, 0, 1902, 1058)     # 16:9 window of the 1924x1058 desktop player take
OPEN_T0 = 7.3                      # play_desk: the llama running with the berries
SCRIM = None
def scrim():
    global SCRIM
    if SCRIM is None:
        s = Image.new("RGBA", (W, 300), (0, 0, 0, 0)); px = s.load()
        for y in range(300):
            a = int(150 * (1 - y / 300) ** 1.6)
            for x in range(W): px[x, y] = (0, 0, 0, a)
        SCRIM = s
    return SCRIM

def tv8(shot, sw, power=1.0):
    """render7.tv, but built at 1x when it is already huge (the full-frame moment)."""
    S = 1 if sw > 1200 else 2
    sw2 = sw * S; sh2 = int(sw2 * 9 / 16); scr = shot.resize((sw2, sh2), Image.LANCZOS)
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
    return p if S == 1 else p.resize((fw // S, fh // S), Image.LANCZOS)

def s_open(img, lt, dur, A):
    b = lt / BEAT
    shot = rf("play_desk", OPEN_T0 + lt, CROP_169)
    u = eio((b - 2.0) / 1.0)                       # beats 2 -> 3: full frame -> the TV in the cluster
    k, off = 0.80, 150
    s = lerp(1920 / 720.0, 1.0, u); sw = int(720 * s)
    cx, cy = W // 2, lerp(H / 2, 300 * k + off, u)
    p = tv8(shot, sw)
    place(img, p, cx, cy, A, shadow_a=int(170 * u), lift=40)
    if u < 1: img.alpha_composite(alpha_img(scrim(), (1 - u) * A))
    # the other screens
    drift = eo((lt - 3 * BEAT) / (dur - 3 * BEAT))
    def entry(t0): return spring((lt - t0) / 0.7), c01((lt - t0) / 0.22)
    e, a = entry(3.0 * BEAT); q = monitor(rf("detail_desk", 1.0, CROP_DESK), int(560 * k))
    place(img, q, int(W // 2 - (W // 2 - 330) * k) + int(-14 * drift), int(775 * k) + off + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(3.5 * BEAT); q = tablet(rf("ipad", 1.0), int(480 * k))
    place(img, q, int(W // 2 - 10 * k) + int(8 * drift), int(765 * k) + off + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(4.0 * BEAT); q = phone(rf("cast_phone", 1.0), int(200 * k))
    place(img, q, int(W // 2 + 620 * k) + int(18 * drift), int(750 * k) + off + int(lerp(80, 0, e)), A * a, scale=lerp(0.9, 1.0, e))
    # words
    ha = c01((lt - 0.35) / 0.4); hy = int(lerp(16, 0, eo((lt - 0.35) / 0.6)))
    paste_center(img, logo(40), W // 2 - 78, 52 + hy, A * ha)
    text(img, (W // 2 - 50, 52 + hy), "Chudder", SEMI(30), WHITE, A * ha, anchor="lm", track=1)
    text(img, (W // 2, 90 + hy), "Your Jellyfin, on every screen.", LIGHT(60), WHITE, A * ha, anchor="ma", track=1)
    la = c01((lt - 5 * BEAT) / 0.4)
    text(img, (W // 2, 972), "WINDOWS  ·  MACOS  ·  LINUX  ·  ANDROID  ·  ANDROID TV  ·  IOS  ·  WEB", SEMI(28), WHITE, A * la, anchor="ma", track=2.5)
    text(img, (W // 2, 1016), "Free and open source", REG(26), MUTE, A * la, anchor="ma")

# ---- statement card with staggered lines and an underline that draws itself ----
def statement(lines, hi=None, size=84):
    def fn(img, lt, dur, A):
        y = H // 2 - (len(lines) * (size + 6)) // 2
        for i, l in enumerate(lines):
            t0 = i * 0.22; a = c01((lt - t0) / 0.35); yo = int(lerp(26, 0, eo((lt - t0) / 0.6)))
            col = ACCENT if hi == i else WHITE
            text(img, (W // 2, y + i * (size + 8) + yo), l, LIGHT(size), col, A * a, anchor="ma", track=1.5)
        if hi is not None:
            w = measure(lines[hi], LIGHT(size))[0]; ln = int(w * eo((lt - 0.45) / 0.5))
            yy = y + hi * (size + 8) + size + 28
            if ln > 0: ImageDraw.Draw(img).rounded_rectangle([W // 2 - ln // 2, yy, W // 2 + ln // 2, yy + 4], radius=2, fill=(*ACCENT, int(200 * A)))
    return fn

# ---- a captured take at 1:1, slow push-in, optional click ripples ----
def take(seq, t0, t1, kick, head, ripples=(), label_from=0.0):
    def fn(img, lt, dur, A):
        ft = t0 + (t1 - t0) * c01(lt / dur)
        sc = 1.0 + 0.03 * c01(lt / dur)
        pnl = panel(rf(seq, ft, CROP_FLOW))
        place(img, pnl, W // 2, PCY, A, scale=sc, shadow_a=170)
        if ripples:
            aa = AA(img.size)
            for tt, px, py in ripples:
                st = (tt - t0) / (t1 - t0) * dur
                ripple(aa, W // 2 + (px - 692) * sc, PCY + (py - 429) * sc, st - 0.1, lt, rmax=48)
            aa.done(img, A)
        kicker(img, W // 2, KY, kick, head, A * c01((lt - label_from) / 0.3))
    return fn

# ---- SyncPlay: two phones joined by an arc the events travel along ----
def bez(a, c, b, t):
    return (lerp(lerp(a[0], c[0], t), lerp(c[0], b[0], t), t), lerp(lerp(a[1], c[1], t), lerp(c[1], b[1], t), t))

def s_sync(img, lt, dur, A):
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
    la = c01((lt - 2 * BEAT) / 0.3)
    for cx, nm in ((cx1, "You"), (cx2, "A friend, 800 km away")):
        w, h = measure(nm, SEMI(24)); yy = cy - sh // 2 - 62
        aa.rrect([cx - w // 2 - 18, yy - 8, cx + w // 2 + 18, yy + h + 14], 18, fill=(255, 255, 255, int(24 * la)))
        aa.text((cx, yy + 2), nm, SEMI, 24, (*WHITE, int(255 * la)), anchor="ma")
    lk = c01((lt - 2 * BEAT) / 0.4)
    a_, b_ = (cx1 + sw // 2 + 40, cy), (cx2 - sw // 2 - 40, cy); c_ = ((cx1 + cx2) / 2, cy - 190)
    if lk > 0:
        grow = eo((lt - 2 * BEAT) / 0.6)
        for i in range(31):
            t = i / 30
            if t > grow: break
            x, y = bez(a_, c_, b_, t); aa.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(*ACCENT, int(120 * lk)))
        phs = (lt % BEAT) / BEAT; src_left = lt < t_pause - 0.1
        for k in (0.0, 0.5):
            u = (phs + k) % 1.0
            if u > grow: continue
            x, y = bez(a_, c_, b_, u if src_left else 1 - u)
            g = 9 + 5 * (1 - u); aa.ellipse([x - g, y - g, x + g, y + g], fill=(*ACCENT, int(230 * (1 - u * 0.6) * lk)))
        label = "SKIPPED AHEAD  ·  on both" if lt >= t_seek else ("PAUSED  ·  on both" if paused else "SYNCPLAY")
        w, h = measure(label, SEMI(22)); mx, my = bez(a_, c_, b_, 0.5); my -= 46
        aa.rrect([mx - w // 2 - 20, my - 12, mx + w // 2 + 20, my + h + 16], 16, fill=(12, 14, 20, int(235 * lk)), outline=(*ACCENT, int(180 * lk)), width=1)
        aa.text((mx, my - 4), label, SEMI, 22, (*(WHITE if label == "SYNCPLAY" else ACCENT), int(255 * lk)), anchor="ma")
    ripple(aa, cx2, cy, t_pause - 0.22, lt, rmax=80); ripple(aa, cx2, cy, t_resume - 0.22, lt, rmax=80)
    if t_seek - 0.3 <= lt < t_seek + 0.6:
        by = cy - sh // 2 + int(sh * 0.945); bx0, bx1 = cx2 - sw // 2 + int(sw * 0.015), cx2 + sw // 2 - int(sw * 0.015)
        u = c01((lt - (t_seek - 0.3)) / 0.3); fx = lerp(bx0 + (bx1 - bx0) * 0.30, bx0 + (bx1 - bx0) * 0.42, u); fa = 1 - c01((lt - t_seek - 0.25) / 0.3)
        aa.ellipse([fx - 15, by - 15, fx + 15, by + 15], fill=(*WHITE, int(120 * fa)))
        aa.rrect([fx - 36, by - 60, fx + 36, by - 28], 10, fill=(*ACCENT, int(255 * fa)))
        aa.text((fx, by - 56), "+30 s", SEMI, 20, (*WHITE, int(255 * fa)), anchor="ma")
    aa.done(img, A)
    kicker(img, W // 2, KY, "SyncPlay that just works", "", A * c01((lt - 3 * BEAT) / 0.4))

# ---- recap: six tiles, one per half-beat ----
def icon(aa, kind, cx, cy, col):
    if kind == "play":
        aa.polygon([(cx - 9, cy - 13), (cx + 13, cy), (cx - 9, cy + 13)], fill=col)
    elif kind == "cast":
        aa.rrect([cx - 15, cy - 11, cx + 15, cy + 11], 3, outline=col, width=3)
        aa.arc([cx - 30, cy - 4, cx - 2, cy + 24], -90, 0, fill=col, width=3); aa.ellipse([cx - 17, cy + 9, cx - 12, cy + 14], fill=col)
    elif kind == "sync":
        aa.ellipse([cx - 19, cy - 9, cx - 1, cy + 9], outline=col, width=3); aa.ellipse([cx + 1, cy - 9, cx + 19, cy + 9], outline=col, width=3)
    elif kind == "mini":
        aa.rrect([cx - 16, cy - 12, cx + 16, cy + 12], 3, outline=col, width=3); aa.rrect([cx + 1, cy + 1, cx + 13, cy + 9], 2, fill=col)
    elif kind == "remote":
        aa.rrect([cx - 8, cy - 18, cx + 8, cy + 18], 6, outline=col, width=3); aa.ellipse([cx - 4, cy - 10, cx + 4, cy - 2], fill=col)
        aa.rect([cx - 4, cy + 5, cx + 4, cy + 7], fill=col); aa.rect([cx - 4, cy + 10, cx + 4, cy + 12], fill=col)
    elif kind == "search":
        aa.ellipse([cx - 15, cy - 15, cx + 7, cy + 7], outline=col, width=3); aa.polygon([(cx + 5, cy + 8), (cx + 8, cy + 5), (cx + 17, cy + 14), (cx + 14, cy + 17)], fill=col)

TILES = [("play", "Direct play", "Original files, no transcoding"), ("cast", "Cast", "Chromecast, AirPlay, DLNA"),
         ("sync", "SyncPlay", "Watch together, anywhere"), ("mini", "Mini player", "Playback follows you"),
         ("remote", "Made for TV", "Every screen works from a remote"), ("search", "Smart search", "Forgives typos, finds people")]
def s_recap(img, lt, dur, A):
    ha = c01(lt / 0.35); hy = int(lerp(20, 0, eo(lt / 0.6)))
    text(img, (W // 2, 128 + hy), "Everything in one client", LIGHT(64), WHITE, A * ha, anchor="ma", track=1)
    tw, th, gx, gy = 520, 168, 34, 30; cols = 3
    x0 = W // 2 - (cols * tw + (cols - 1) * gx) // 2; y0 = 300
    aa = AA(img.size)
    for i, (kind, name, sub) in enumerate(TILES):
        t0 = 0.5 * BEAT + i * 0.5 * BEAT; e = spring((lt - t0) / 0.6); a = c01((lt - t0) / 0.2)
        if a <= 0: continue
        r, c = divmod(i, cols); x = x0 + c * (tw + gx); y = y0 + r * (th + gy) + int(lerp(34, 0, e))
        aa.rrect([x, y, x + tw, y + th], 22, fill=(255, 255, 255, int(16 * a)), outline=(255, 255, 255, int(38 * a)), width=1)
        aa.ellipse([x + 30, y + th // 2 - 34, x + 98, y + th // 2 + 34], fill=(*ACCENT, int(255 * a)))
        icon(aa, kind, x + 64, y + th // 2, (*WHITE, int(255 * a)))
        aa.text((x + 126, y + 46), name, SEMI, 32, (*WHITE, int(255 * a)))
        aa.text((x + 126, y + 96), sub, REG, 23, (*MUTE, int(255 * a)))
    aa.done(img)
    la = c01((lt - 4 * BEAT) / 0.4)
    text(img, (W // 2, 760), "And the hundred small things that make an app feel like yours.", REG(30), MUTE, A * la, anchor="ma")

def s_outro(img, lt, dur, A):
    def fade(t0, d=0.4): return A * c01((lt - t0) / d)
    ly = int(lerp(18, 0, eo(lt / 0.6)))
    paste_center(img, logo(120), W // 2, H // 2 - 262 + ly, A)
    text(img, (W // 2, H // 2 - 150 + ly), "Complete.  Free.  Everywhere.", LIGHT(78), WHITE, A, anchor="ma", track=1.5)
    ln = int(120 * eio((lt - 0.3) / 0.7))
    if ln > 0: ImageDraw.Draw(img).rounded_rectangle([W // 2 - ln // 2, H // 2 - 40, W // 2 + ln // 2, H // 2 - 36], radius=2, fill=(*ACCENT, int(220 * A)))
    text(img, (W // 2, H // 2 - 8), "github.com/JenteJan/Chudder", SEMI(60), WHITE, fade(0.5), anchor="ma", track=0.5)
    text(img, (W // 2, H // 2 + 92), "WINDOWS  ·  MACOS  ·  LINUX  ·  ANDROID  ·  ANDROID TV  ·  IOS  ·  WEB", SEMI(26), (200, 205, 216), fade(0.9), anchor="ma", track=2.5)
    text(img, (W // 2, H // 2 + 142), "Free & open source  ·  GPL-3  ·  an opinionated fork of Fladder", REG(28), MUTE, fade(1.1), anchor="ma")
    text(img, (W // 2, H - 64), "Music: \"Werq\" Kevin MacLeod (incompetech.com), CC BY 4.0   ·   Footage: Caminandes: Llamigos, Blender Foundation, CC BY", REG(18), (90, 95, 110), A, anchor="ma")

SHOTS = [
    ("open",     2.0, s_open),
    ("s_hook",   1.0, statement(["Direct play first.", "Transcodes only when it must."], hi=0, size=84)),
    ("play",     2.5, R.s_play),                                                                               # the drop
    ("mini",     2.0, take("flow", 16.7, 22.4, "Playback follows you", "Shrink the player and keep browsing. It never stops.",
                           ripples=((16.85, 40, 43), (19.70, 55, 203)))),
    ("cast",     4.0, R.s_cast),
    ("sync",     3.0, s_sync),
    ("search",   2.0, take("flow", 0.9, 6.7, "Search that forgives", "Misspell it. Chudder finds it anyway.",
                           ripples=((1.75, 55, 133), (4.85, 212, 431)))),
    ("episodes", 1.5, take("episodes", 1.2, 6.3, "Show pages you don't get lost in", "Seasons and episodes on one screen. Never lose your place.")),
    ("nav",      1.5, take("nav", 0.4, 5.6, "Instant navigation", "Open, back, open. No spinners, no waiting.")),
    ("settings", 1.5, take("settings", 0.5, 5.6, "Settings search", "Find any setting by name, across every page.")),
    ("recap",    2.0, s_recap),
    ("outro",    3.0, s_outro),
]
TIN, TOUT = 0.30, 0.18
HARD = {"play"}   # lands on the drop: no rise, a punch-in instead

def timeline():
    starts = []; acc = 0.0
    for _, d, _ in SHOTS: starts.append(acc); acc += bar(d)
    return starts, acc

def layer(fn, lt, di):
    l = Image.new("RGBA", (W, H), (0, 0, 0, 0)); fn(l, lt, di, 1.0); return l

def render_frame(f):
    starts, total = timeline(); t = f / FPS; img = background()
    i = 0
    for k, st in enumerate(starts):
        if st <= t < st + bar(SHOTS[k][1]): i = k; break
    name, db, fn = SHOTS[i]; di = bar(db); lt = t - starts[i]
    # the previous shot slides up and out while this one rises in
    if i > 0 and lt < TOUT and name not in HARD:
        pn, pdb, pfn = SHOTS[i - 1]; u = lt / TOUT
        lp = layer(pfn, t - starts[i - 1], bar(pdb))
        img.alpha_composite(alpha_img(lp, smooth(1 - u)), (0, int(-34 * eo(u))))
    lc = layer(fn, lt, di)
    if name in HARD and lt < 0.3:
        z = 1 + 0.045 * (1 - eo(lt / 0.3)); zw, zh = int(W * z), int(H * z)
        lz = lc.resize((zw, zh), Image.BICUBIC).crop(((zw - W) // 2, (zh - H) // 2, (zw - W) // 2 + W, (zh - H) // 2 + H))
        img.alpha_composite(lz)
    elif lt < TIN and name != "open":
        u = lt / TIN; img.alpha_composite(alpha_img(lc, smooth(u)), (0, int(44 * (1 - eo(u)))))
    else:
        img.alpha_composite(lc)
    if name == "open" and lt < 0.3: img = Image.blend(Image.new("RGBA", (W, H), (0, 0, 0, 255)), img, smooth(lt / 0.3))
    if name == "outro" and lt > di - 1.0: img = Image.blend(Image.new("RGBA", (W, H), (0, 0, 0, 255)), img, smooth((di - lt) / 1.0))
    img.convert("RGB").save(os.path.join(OUT, f"{f:05d}.png"), compress_level=1)
    return f

def main():
    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "*")): os.remove(f)
    starts, total = timeline(); nf = int(round(total * FPS))
    print(f"total {total:.2f}s {nf} frames; music starts at {MUSIC_START:.3f}s in track")
    for (n, d, _), st in zip(SHOTS, starts): print(f"  {n:8s} {st:6.2f}s  ({d} bars)")
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        picks = sorted(set(int(float(x) * FPS) for x in sys.argv[2:]))
        for f in picks: render_frame(f)
        print("preview frames:", picks); return
    with Pool(8) as p:
        for k, _ in enumerate(p.imap_unordered(render_frame, range(nf), chunksize=16)):
            if k % 300 == 0: print("frame", k, flush=True)
    print("done", nf)

if __name__ == "__main__": main()