#!/usr/bin/env python3
# Chudder promo v10 - the v9 cut (recovered from the session transcripts after its scratchpad was wiped)
# reshot on 2026-09-13 for the new sidebar, Search and Settings tabs and the cheese play button. Same grid
# (Werq, 125 BPM, drop on bar 3) and shots; new takes, new timings, Bonanza on the show page.
#
# Footage: out/fr/<take>/ at 30 fps, from take_flow.sh / take.sh (desktop build, 1400x900 and 1940x1099
# windows) and webtake.py (web build). Run: python render10.py [preview t ...], then mux10.sh.
import os, sys, glob, inspect
from multiprocessing import Pool
from PIL import Image, ImageDraw
import render7 as R
import render8 as R8
from render7 import (W, H, BEAT, BAR, LIGHT, SEMI, REG, ACCENT, WHITE, MUTE, c01, eo, eio, lerp, spring,
                     rrect, alpha_img, text, paste_center, panel, place, logo, phone, tablet, PCY, KY)

FPS = 60; OUT = os.path.join(R.HERE, "out10")
R8.OUT = OUT

# ---- footage geometry (all takes are the app's client area, no title bar to crop) ----
CROP_16x9 = (0, 0, 1924, 1082)      # play_desk / detail_desk are 1924x1090
R.CROP_DESK = CROP_16x9; R.CROP_PLAY = CROP_16x9; R8.CROP_169 = CROP_16x9
R.BADGE = (1180, 656, 1352, 694)    # "Direct · SDR 4K" pills in the flow take
R8.OPEN_T0 = 18.0                   # play_desk: the robot's pink glow
CAST_T0 = 19.0                      # play_desk moment that lights up the TV in the cast shot
S_TOP = 718                         # top edge of the real "Play to a device" sheet in cast_phone


def monitor(shot, sw):
    """render7.monitor, but the screen keeps the take's own aspect instead of the old 1924x1202 one."""
    S = 2; sw2 = sw * S; sh2 = int(sw2 * shot.height / shot.width)
    b = max(6, int(sw2 * 0.011)); chin = int(sw2 * 0.04); r = int(sw2 * 0.012)
    stand_h = int(sw2 * 0.075); base_w = int(sw2 * 0.28); base_h = max(6, int(sw2 * 0.012))
    fw, fh = sw2 + 2 * b, sh2 + 2 * b + chin + stand_h + base_h
    p = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); d = ImageDraw.Draw(p)
    d.polygon([(fw // 2 - int(sw2 * 0.045), sh2 + 2 * b + chin), (fw // 2 + int(sw2 * 0.045), sh2 + 2 * b + chin),
               (fw // 2 + int(sw2 * 0.06), fh - base_h), (fw // 2 - int(sw2 * 0.06), fh - base_h)], fill=(34, 36, 44, 255))
    d.rounded_rectangle([fw // 2 - base_w // 2, fh - base_h - 2, fw // 2 + base_w // 2, fh - 1], radius=base_h // 2, fill=(46, 49, 58, 255))
    body = Image.new("RGBA", (fw, sh2 + 2 * b + chin), (18, 19, 24, 255)); body.putalpha(rrect(fw, sh2 + 2 * b + chin, r + b)); p.alpha_composite(body)
    s = shot.resize((sw2, sh2), Image.LANCZOS).convert("RGBA"); s.putalpha(rrect(sw2, sh2, r)); p.alpha_composite(s, (b, b))
    d.rounded_rectangle([0, 0, fw - 1, sh2 + 2 * b + chin - 1], radius=r + b, outline=(100, 106, 120, 180), width=2)
    return p.resize((fw // S, fh // S), Image.LANCZOS)


R.monitor = monitor

# ---- render7.s_cast with the new film in its "now playing" card and the new sheet geometry ----
_src = inspect.getsource(R.s_cast)
for _a, _b in (('"Caminandes: Llamigos"', '"Charge"'),
               ('"2016  ·  2m 30s  ·  Blender Foundation"', '"2022  ·  4m 22s  ·  Blender Studio"'),
               ('S_TOP = 727', 'S_TOP = %d' % S_TOP),
               ('rf("play_desk", 12.0 + (lt - t_on), CROP_PLAY)', 'rf("play_desk", %s + (lt - t_on), CROP_PLAY)' % CAST_T0),
               ('rf("play_desk", 12.0 + max(0.0, lt - t_on), CROP_PLAY)', 'rf("play_desk", %s + max(0.0, lt - t_on), CROP_PLAY)' % CAST_T0)):
    assert _a in _src, _a
    _src = _src.replace(_a, _b)
exec(_src, R.__dict__)          # rebinds R.s_cast inside render7's namespace (rf, tv, phone, AA, ...)

# render7.s_play maps its own take window (11.95 -> 16.7) onto the shot; the new take plays with its controls up 12.6 -> 17.0
_ps = inspect.getsource(R.s_play)
assert "ft = 11.95 + (16.7 - 11.95) * c01(lt / dur)" in _ps
_ps = _ps.replace("ft = 11.95 + (16.7 - 11.95) * c01(lt / dur)", "ft = 12.6 + (17.0 - 12.6) * c01(lt / dur)")
exec(_ps, R.__dict__)

R8.COPY.update({
    "Direct play": ("Direct play", "Your server's 4K file, untouched. No transcoding."),
})


# ---- opener: same choreography as v8, but the three small screens are spaced evenly around the centre ----
def s_open(img, lt, dur, A):
    b = lt / BEAT
    shot = R8.rf("play_desk", R8.OPEN_T0 + lt, CROP_16x9)
    u = eio((b - 2.0) / 1.0)
    k, off = 0.80, 150
    s = lerp(1920 / 720.0, 1.0, u); sw = int(720 * s)
    cx, cy = W // 2, lerp(H / 2, 300 * k + off, u)
    p = R8.tv8(shot, sw)
    place(img, p, cx, cy, A, shadow_a=int(170 * u), lift=40)
    if u < 1: img.alpha_composite(alpha_img(R8.scrim(), (1 - u) * A))
    drift = eo((lt - 3 * BEAT) / (dur - 3 * BEAT))

    def entry(t0): return spring((lt - t0) / 0.7), c01((lt - t0) / 0.22)
    mon = monitor(R8.rf("detail_desk", 1.0, CROP_16x9), int(560 * k))
    tab = tablet(R8.rf("ipad", 1.0), int(480 * k))
    ph = phone(R8.rf("cast_phone", 1.0), int(200 * k))
    # equal gaps between the three frames, the row as a whole centred under the TV
    gap = 96; total = mon.width + tab.width + ph.width + 2 * gap; x = W / 2 - total / 2
    cxs = []
    for q in (mon, tab, ph): cxs.append(int(x + q.width / 2)); x += q.width + gap
    e, a = entry(3.0 * BEAT); place(img, mon, cxs[0] + int(-14 * drift), int(775 * k) + off + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(3.5 * BEAT); place(img, tab, cxs[1] + int(4 * drift), int(765 * k) + off + int(lerp(70, 0, e)), A * a, scale=lerp(0.92, 1.0, e))
    e, a = entry(4.0 * BEAT); place(img, ph, cxs[2] + int(18 * drift), int(750 * k) + off + int(lerp(80, 0, e)), A * a, scale=lerp(0.9, 1.0, e))
    ha = c01((lt - 0.35) / 0.4); hy = int(lerp(16, 0, eo((lt - 0.35) / 0.6)))
    paste_center(img, logo(40), W // 2 - 78, 52 + hy, A * ha)
    text(img, (W // 2 - 50, 52 + hy), "Chudder", SEMI(30), WHITE, A * ha, anchor="lm", track=1)
    text(img, (W // 2, 90 + hy), "Your Jellyfin, on every screen.", LIGHT(60), WHITE, A * ha, anchor="ma", track=1)
    la = c01((lt - 5 * BEAT) / 0.4)
    text(img, (W // 2, 972), "WINDOWS  ·  MACOS  ·  LINUX  ·  ANDROID  ·  ANDROID TV  ·  IOS  ·  WEB", SEMI(28), WHITE, A * la, anchor="ma", track=2.5)
    text(img, (W // 2, 1016), "Free and open source", REG(26), MUTE, A * la, anchor="ma")


# ---- a take made of several segments of one recording, played back to back ----
def take_seg(seq, segs, kick, head, label_from=0.0):
    total = sum(t1 - t0 for t0, t1 in segs)

    def remap(u):
        for t0, t1 in segs:
            if u < t1 - t0: return t0 + u
            u -= t1 - t0
        return segs[-1][1]

    def fn(img, lt, dur, A):
        ft = remap(total * c01(lt / dur))
        sc = 1.0 + 0.03 * c01(lt / dur)
        place(img, panel(R8.rf(seq, ft, R.CROP_FLOW)), W // 2, PCY, A, scale=sc, shadow_a=170)
        R8.kicker(img, W // 2, KY, kick, head, A * c01((lt - label_from) / 0.3))
    return fn


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
    text(img, (W // 2, H - 64), "Music: \"Werq\" Kevin MacLeod (incompetech.com), CC BY 4.0   ·   Film: \"Charge\", Blender Studio, CC BY 4.0", REG(18), (90, 95, 110), A, anchor="ma")


SHOTS = [
    ("open",     2.0, s_open),
    ("s_hook",   1.0, R8.statement(["Direct play first.", "Transcodes only when it must."], hi=0, size=84)),
    ("play",     2.5, R.s_play),                                                                               # the drop
    ("mini",     2.0, R8.take("flow", 20.8, 25.8, "Playback follows you", "Shrink the player and keep browsing. It never stops.",
                              ripples=((21.75, 48, 79), (24.45, 64, 128)))),
    ("cast",     4.0, R.s_cast),
    ("sync",     3.0, R8.s_sync),
    ("search",   2.0, R8.take("flow", 2.6, 8.6, "Search that forgives", "Misspell it. Chudder finds it anyway.",
                              ripples=((3.1, 64, 186), (4.68, 658, 73), (7.75, 238, 159)))),
    ("episodes", 1.5, take_seg("episodes", [(3.0, 4.6), (5.3, 7.9), (9.3, 11.3)], "Show pages you don't get lost in", "Seasons and episodes on one screen. Never lose your place.")),
    ("nav",      1.5, take_seg("nav", [(3.6, 6.8), (7.6, 10.6)], "Instant navigation", "Open, back, open. No spinners, no waiting.")),
    ("settings", 1.5, R8.take("settings", 3.8, 8.8, "Settings search", "Find any setting by name, across every page.")),
    ("recap",    2.0, R8.s_recap),
    ("outro",    3.0, s_outro),
]
R8.SHOTS = SHOTS


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "*")): os.remove(f)
    starts, total = R8.timeline(); nf = int(round(total * FPS))
    print("total %.2fs %d frames; music starts at %.3fs in track" % (total, nf, R8.MUSIC_START))
    for (n, d, _), st in zip(SHOTS, starts): print("  %-8s %6.2fs  (%s bars)" % (n, st, d))
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        picks = sorted(set(int(float(x) * FPS) for x in sys.argv[2:]))
        for f in picks: R8.render_frame(f)
        print("preview frames:", picks); return
    with Pool(8) as p:
        for k, _ in enumerate(p.imap_unordered(R8.render_frame, range(nf), chunksize=16)):
            if k % 300 == 0: print("frame", k, flush=True)
    print("done", nf)


if __name__ == "__main__": main()
