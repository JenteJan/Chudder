"""How far apart two players are on screen, matching the pictures themselves.

Finds the moving area of each window (the video, not the browser or the controls),
scales both to one small size and slides one along the other in time.
  screen_gap.py x y w h  ax ay aw ah  bx by bw bh  [seconds]     live
  screen_gap.py --selftest
Positive: A is ahead of B. Frames stay in memory.
"""
import subprocess
import sys
import time

import numpy as np

SCALE = 4
W, H = 64, 27


def active_box(f):
    """The rectangle that moves over time."""
    std = f[::10].std(axis=0)
    rows = np.where(std.mean(axis=1) > std.mean(axis=1).max() * 0.35)[0]
    cols = np.where(std.mean(axis=0) > std.mean(axis=0).max() * 0.35)[0]
    return rows[0], rows[-1] + 1, cols[0], cols[-1] + 1


def shrink(f, box):
    t, b, l, r = box
    ys = np.linspace(t, b, H + 1).astype(int)
    xs = np.linspace(l, r, W + 1).astype(int)
    out = np.zeros((len(f), H, W), np.float32)
    for i in range(H):
        for j in range(W):
            out[:, i, j] = f[:, ys[i]:max(ys[i + 1], ys[i] + 1), xs[j]:max(xs[j + 1], xs[j] + 1)].mean(axis=(1, 2))
    # Each frame judged on its own pattern: brightness and contrast differ per player.
    out -= out.mean(axis=(1, 2), keepdims=True)
    out /= out.std(axis=(1, 2), keepdims=True) + 1e-6
    return out


def lag_ms(a, b, fps, reach_s=4.0):
    n = min(len(a), len(b))
    reach = min(int(reach_s * fps), n // 3)
    scores = np.zeros(2 * reach + 1)
    for idx, k in enumerate(range(-reach, reach + 1)):
        x, y = (a[:n - k], b[k:n]) if k >= 0 else (a[-k:n], b[:n + k])
        scores[idx] = float((x * y).mean())
    i = int(scores.argmax())
    shift = 0.0
    if 0 < i < len(scores) - 1:
        l, c, r = scores[i - 1], scores[i], scores[i + 1]
        if l - 2 * c + r:
            shift = 0.5 * (l - r) / (l - 2 * c + r)
    return (i - reach + shift) * 1000 / fps, float(scores[i])


def report(fa, fb, fps):
    ba, bb = active_box(fa), active_box(fb)
    print(f'picture A rows {ba[0]}-{ba[1]} cols {ba[2]}-{ba[3]} (aspect {(ba[3]-ba[2])/(ba[1]-ba[0]):.2f})')
    print(f'picture B rows {bb[0]}-{bb[1]} cols {bb[2]}-{bb[3]} (aspect {(bb[3]-bb[2])/(bb[1]-bb[0]):.2f})')
    a, b = shrink(fa, ba), shrink(fb, bb)
    # Motion, so a still scene does not match everything at once.
    da, db = np.diff(a, axis=0), np.diff(b, axis=0)
    whole = lag_ms(da, db, fps)
    still = lag_ms(a, b, fps)
    print(f'{len(fa)} frames at {fps:.1f} fps')
    print(f'A ahead of B by {whole[0]:.0f} ms on motion (match {whole[1]:.2f}), {still[0]:.0f} ms on pictures (match {still[1]:.2f})')
    parts = 6
    step = len(da) // parts
    for i in range(parts):
        p = lag_ms(da[i * step:(i + 1) * step], db[i * step:(i + 1) * step], fps)
        print(f'  {i * step / fps:4.0f}s: {p[0]:7.0f} ms (match {p[1]:.2f})')


def selftest():
    rng = np.random.default_rng(1)
    fps = 60
    n = 1200
    shots = rng.integers(0, 255, (40, 9, 16), dtype=np.uint8).astype(float)
    cuts = np.cumsum(rng.uniform(0.5, 3, 40))
    def picture(t, h, w):
        s = shots[int(np.searchsorted(cuts, max(t, 0))) % 40]
        film = int(max(t, 0) * 24) / 24
        ys = (np.arange(h) * 9 // h)
        xs = ((np.arange(w) * 16 // w) + int(film * 3)) % 16
        return s[np.ix_(ys, xs)]
    for true_ms in (0, 80, 180, -250, 900):
        fa = np.zeros((n, 90, 160), np.uint8)
        fb = np.zeros((n, 70, 120), np.uint8)
        for i in range(n):
            t = i / fps
            fa[i, 5:85, :] = np.clip(picture(t, 80, 160), 0, 255)
            fb[i, 8:62, :] = np.clip(picture(t - true_ms / 1000, 54, 120) * 0.8 + 10, 0, 255)
        got = lag_ms(np.diff(shrink(fa, active_box(fa)), axis=0), np.diff(shrink(fb, active_box(fb)), axis=0), fps)
        print(f'true {true_ms:5d} ms, measured {got[0]:7.1f} ms, match {got[1]:.2f}')


def check(x, y, w, h, seconds):
    """Real footage from one window against a shifted, recropped, regraded copy."""
    frames, fps = grab(x, y, w, h, seconds)
    box = active_box(frames)
    print(f'picture rows {box[0]}-{box[1]} cols {box[2]}-{box[3]}, {len(frames)} frames at {fps:.1f} fps')
    for true_ms in (0, 50, 100, 200, -150, 900):
        k = round(true_ms * fps / 1000)
        a = frames[max(k, 0) + 60:len(frames) - 60 + min(k, 0)]
        b = frames[max(-k, 0) + 60:len(frames) - 60 + min(-k, 0)]
        b = (b[:, ::2, ::2] * 0.7 + 12).astype(np.uint8)
        got = lag_ms(np.diff(shrink(a, active_box(a)), axis=0), np.diff(shrink(b, active_box(b)), axis=0), fps)
        print(f'true {k * 1000 / fps:6.0f} ms, measured {got[0]:7.1f} ms, match {got[1]:.2f}')


def grab(x, y, w, h, seconds):
    outw, outh = w // SCALE, h // SCALE
    command = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'gdigrab', '-framerate', '60',
               '-offset_x', str(x), '-offset_y', str(y), '-video_size', f'{w}x{h}', '-draw_mouse', '0',
               '-i', 'desktop', '-t', str(seconds), '-vf', f'scale={outw}:{outh}:flags=area,format=gray',
               '-f', 'rawvideo', '-']
    start = time.time()
    raw = subprocess.run(command, stdout=subprocess.PIPE, check=True).stdout
    took = time.time() - start
    return np.frombuffer(raw, np.uint8).reshape(-1, outh, outw), len(raw) / (outw * outh) / took


def main():
    if sys.argv[1] == '--selftest':
        selftest()
        return
    if sys.argv[1] == '--check':
        check(*[int(v) for v in sys.argv[2:7]])
        return
    n = [int(v) for v in sys.argv[1:13]]
    seconds = int(sys.argv[13]) if len(sys.argv) > 13 else 30
    x, y, w, h = n[:4]
    frames, fps = grab(x, y, w, h, seconds)
    cut = lambda r: frames[:, (r[1] - y) // SCALE:(r[1] - y + r[3]) // SCALE, (r[0] - x) // SCALE:(r[0] - x + r[2]) // SCALE]
    report(cut(n[4:8]), cut(n[8:12]), fps)


main()
