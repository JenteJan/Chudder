"""Load-time benchmark: Chudder (Windows build) against Jellyfin Web (Chrome), on the same PC,
the same demo server and the same 1400x900 window at 0,0.

Every measurement is taken from a screen recording, not from inside either app: ffmpeg's
gdigrab stamps each frame with the wall clock, drive.ps1 logs the wall clock of each click,
and the end of a run is the first frame where the result is on screen (see detect()).

    python bench.py shot chudder|web <name>       # a still of either window, for finding coordinates
    python bench.py run <client> <scenario> <n>   # n recorded runs -> out/bench/<client>-<scenario>-<i>.*
    python bench.py measure <client> <scenario>   # detect end frames, write out/bench/results.json
    python bench.py strip <name> <from> <to> <step>  # frames of a run, for checking a detection by eye

Scenarios: nav (a poster on Home -> the film's page visually complete), play (Play on the film's
page -> the picture moving), episode (next episode in the player -> the next episode on screen).
"""
import json
import os
import subprocess
import sys
import time

import numpy as np

NOWIN = {"creationflags": subprocess.CREATE_NO_WINDOW}  # no console flashing over the capture

HERE = os.path.dirname(os.path.abspath(__file__))
MK = os.path.join(HERE, "..")
OUT = os.path.join(MK, "out", "bench")
sys.path.insert(0, MK)
sys.path.insert(0, HERE)
W, H = 1400, 900
FPS = 60
SMALL = (350, 225)  # frames are analysed at a quarter size

CHARGE = "e822d2f66189bc6caaa81cf69eb5c907"
BONANZA_E5 = "503b570df761c9ed780b7f59a90ad205"
BONANZA_E6 = "088376d4603f35e1cb94296d2350956e"


def web_pid():
    """The benchmark Chrome's browser process (its own profile; never someone's own Chrome)."""
    r = subprocess.run(["powershell", "-NoProfile", "-Command",
                        "Get-CimInstance Win32_Process -Filter \"Name='chrome.exe'\" | "
                        "? { $_.CommandLine -like '*chrome-bench*' -and $_.CommandLine -notlike '*--type=*' } | "
                        "select -First 1 -ExpandProperty ProcessId"], capture_output=True, text=True, **NOWIN)
    return r.stdout.strip()


def drive(client, keys, delay=250):
    target = ["-Process", "chudder"] if client == "chudder" else ["-ProcessId", web_pid()]
    r = subprocess.run(["powershell", "-NoProfile", "-File", os.path.join(MK, "drive.ps1"), *target,
                        "-Delay", str(delay), "-Keys", keys], capture_output=True, text=True, **NOWIN)
    return r.stdout


def click_times(log):
    """Wall-clock seconds of every step: step lines read 'T <s> <step> <unix ms>'."""
    out = []
    for line in log.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[0] == "T":
            out.append((parts[2], int(parts[3]) / 1000.0))
    return out


def record(name, seconds):
    path = os.path.join(OUT, name)
    return subprocess.Popen(
        ["ffmpeg", "-hide_banner", "-y", "-f", "gdigrab", "-framerate", str(FPS), "-draw_mouse", "0",
         "-offset_x", "0", "-offset_y", "0", "-video_size", f"{W}x{H}", "-i", "desktop", "-t", str(seconds),
         # showinfo sees the wall-clock pts (copyts); the file itself starts at zero, one frame per capture
         "-copyts", "-vf", "showinfo,setpts=PTS-STARTPTS", "-fps_mode", "passthrough", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18", "-pix_fmt", "yuv420p", path + ".mkv"],
        stderr=open(path + ".ffmpeg.log", "w"), stdout=subprocess.DEVNULL, **NOWIN)


def frame_clock(name):
    """Wall-clock time of every recorded frame, from showinfo's pts (gdigrab stamps the wall clock)."""
    times = []
    for line in open(os.path.join(OUT, name + ".ffmpeg.log"), encoding="utf-8", errors="replace"):
        i = line.find("pts_time:")
        if i >= 0 and "Parsed_showinfo" in line:
            times.append(float(line[i + 9:].split()[0]))
    return np.array(times)


def frames(name):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(OUT, name + ".mkv"), "-fps_mode", "passthrough",
                          "-vf", f"scale={SMALL[0]}:{SMALL[1]}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, **NOWIN).stdout
    return np.frombuffer(raw, dtype=np.uint8).reshape(-1, SMALL[1], SMALL[0], 3).astype(np.int16)


def shot(client, name):
    drive(client, "wait300")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"shot-{name}.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "gdigrab", "-framerate", "5", "-draw_mouse", "0",
                    "-offset_x", "0", "-offset_y", "0", "-video_size", f"{W}x{H}", "-i", "desktop",
                    "-frames:v", "1", path], **NOWIN)
    print(path)


def web_go(path, wait):
    import webctl
    webctl.Page().eval(f"location.href = {json.dumps(webctl.SERVER + path)}; 1")
    time.sleep(wait)


# ---- scenarios. Coordinates are screen pixels of a 1400x900 window at 0,0. ----
SECONDS = {"nav": 5.0, "play": 9.0, "episode": 9.0}


def setup(client, scenario):
    import demo
    # Charge first in Continue Watching on both clients: the row reorders after every playback
    demo.set_position(CHARGE, 84, played_now=True)
    time.sleep(1)
    if client == "chudder":
        if scenario == "nav":
            drive(client, "click:64,128 wait1200 click:64,128 wait2500 move:30,780 wait300")
        elif scenario == "play":
            drive(client, "click:64,128 wait1200 click:64,128 wait2000 click:160,806 wait4000 move:30,780 wait300")
        elif scenario == "episode":
            demo.set_position(BONANZA_E5, 30)
            demo.set_position(BONANZA_E6, 0)
            # the Shows library, not Continue Watching: that row reorders after every run
            drive(client, "click:64,128 wait1200 click:64,676 wait2500 click:392,450 wait3500 click:244,842 wait6000")
    else:
        if scenario == "nav":
            web_go("/web/#/home", 5)
            drive(client, "move:30,880 wait300")
        elif scenario == "play":
            web_go(f"/web/#/details?id={CHARGE}", 5)
            drive(client, "move:30,880 wait300")
        elif scenario == "episode":
            demo.set_position(BONANZA_E5, 30)
            demo.set_position(BONANZA_E6, 0)
            web_go(f"/web/#/details?id={BONANZA_E5}", 4)
            drive(client, "click:1166,368 wait7000")


TIMED = {
    ("chudder", "nav"): "click:160,806",
    ("chudder", "play"): "click:246,842",
    ("chudder", "episode"): "move:700,450 wait80 move:852,818 wait250 click:852,818",
    ("web", "nav"): "click:202,596",
    ("web", "play"): "click:1066,368",
    ("web", "episode"): "move:700,450 wait80 move:260,844 wait250 click:260,844",
}


def teardown(client, scenario):
    if client == "chudder":
        if scenario == "play":
            drive(client, "move:700,450 wait100 move:704,452 wait600 click:842,818 wait2000")
        elif scenario == "episode":
            drive(client, "move:700,450 wait100 move:704,452 wait600 click:914,818 wait2000")
        drive(client, "click:64,676 wait1200 click:64,676 wait1200 click:64,128 wait1200 click:64,128 wait1200")
    else:
        web_go("/web/#/home", 3)


def run(client, scenario, n):
    os.makedirs(OUT, exist_ok=True)
    for i in range(1, n + 1):
        name = f"{client}-{scenario}-{i}"
        setup(client, scenario)
        rec = record(name, SECONDS[scenario])
        time.sleep(0.8)
        log = drive(client, TIMED[(client, scenario)])
        clicks = [t for k, t in click_times(log) if k.startswith("click:")]
        json.dump({"click": clicks[-1]}, open(os.path.join(OUT, name + ".json"), "w"))
        rec.wait()
        teardown(client, scenario)
        print(name, "recorded", flush=True)


# ---- detection ----
def region_diff(f, a, b, box):
    x0, y0, x1, y1 = box
    return np.abs(f[a, y0:y1, x0:x1] - f[b, y0:y1, x0:x1]).mean()


def detect(client, scenario, name):
    f = frames(name)
    clock = frame_clock(name)[: len(f)]
    click = json.load(open(os.path.join(OUT, name + ".json")))["click"]
    c = int(np.searchsorted(clock, click))          # first frame at or after the click
    full = (0, 0, SMALL[0], SMALL[1])
    end = None
    if scenario == "nav":
        # visually complete: the last frame that still differs from the one 3 frames before it
        end = c
        for i in range(c + 3, len(f)):
            if region_diff(f, i, i - 3, full) > 0.6:
                end = i
    elif scenario == "play":
        # the picture keeps moving on one side or the other for half a second (spinners sit in the middle)
        left, right = (20, 60, 110, 180), (240, 60, 330, 180)
        for i in range(c + 3, len(f) - 33):
            if all(region_diff(f, j, j - 3, left) > 2.5 or region_diff(f, j, j - 3, right) > 2.5 for j in range(i, i + 30)):
                end = i
                break
    elif scenario == "episode":
        # the episode title burned into the demo file changes from S01E05 to S01E06
        x0, y0, x1, y1 = (80, 95, 270, 125)
        ref = f[max(0, c - 5), y0:y1, x0:x1]
        for i in range(c + 1, len(f) - 10):
            cur = f[i, y0:y1, x0:x1]
            # the demo file's own frame: light text on a dark ground (not a backdrop or poster flashing past)
            has_text = (cur.max(axis=2) > 120).sum() > 60 and cur.mean() < 60
            if has_text and np.abs(cur - ref).mean() > 6 and \
                    all(np.abs(f[j, y0:y1, x0:x1] - cur).mean() < 6 for j in range(i, i + 10)):
                end = i
                break
    ms = None if end is None else round((clock[end] - click) * 1000)
    return {"name": name, "click_frame": c, "end_frame": end, "ms": ms}


def measure(client, scenario):
    path = os.path.join(OUT, "results.json")
    results = json.load(open(path)) if os.path.exists(path) else {}
    runs = []
    i = 1
    while os.path.exists(os.path.join(OUT, f"{client}-{scenario}-{i}.json")):
        r = detect(client, scenario, f"{client}-{scenario}-{i}")
        print(r, flush=True)
        runs.append(r)
        i += 1
    ok = [r["ms"] for r in runs[1:] if r["ms"] is not None]   # run 1 is the warm-up
    results[f"{client}-{scenario}"] = {"runs": runs, "median_ms": float(np.median(ok)) if ok else None,
                                       "mean_ms": float(np.mean(ok)) if ok else None}
    json.dump(results, open(path, "w"), indent=1)
    print(client, scenario, "median", results[f"{client}-{scenario}"]["median_ms"])


def strip(name, a, b, step):
    from PIL import Image, ImageDraw
    f = frames(name)
    idx = list(range(max(0, a), min(len(f), b), step))
    cols = 6
    s = Image.new("RGB", (SMALL[0] * cols, (SMALL[1] + 14) * ((len(idx) + cols - 1) // cols)))
    d = ImageDraw.Draw(s)
    for k, i in enumerate(idx):
        x, y = (k % cols) * SMALL[0], (k // cols) * (SMALL[1] + 14)
        s.paste(Image.fromarray(f[i].astype(np.uint8)), (x, y + 14))
        d.text((x + 2, y), str(i), fill=(255, 255, 0))
    out = os.path.join(MK, "out", "shots", "_w.png")
    s.save(out)
    print(out)


if __name__ == "__main__" and sys.argv[1] not in ("cold", "measure-cold", "coldpage", "epswitch", "settle", "shown"):
    cmd = sys.argv[1]
    if cmd == "shot":
        shot(sys.argv[2], sys.argv[3])
    elif cmd == "run":
        run(sys.argv[2], sys.argv[3], int(sys.argv[4]))
    elif cmd == "measure":
        measure(sys.argv[2], sys.argv[3])
    elif cmd == "strip":
        strip(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]))


# ---- cold start: nothing running -> Home visually complete (the last frame that still changes) ----
def cold(client, n):
    import webctl
    exe = os.path.abspath(os.path.join(MK, "..", "..", "build", "windows", "x64", "runner", "Release", "chudder.exe"))
    kill_web = ("Get-CimInstance Win32_Process -Filter \"Name='chrome.exe'\" | ? { $_.CommandLine -like '*chrome-bench*' } | "
                "% { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }")
    # the other client off the screen for the whole set
    if client == "chudder":
        subprocess.run(["powershell", "-NoProfile", "-Command", kill_web], **NOWIN)
    else:
        subprocess.run(["powershell", "-NoProfile", "-Command", "Get-Process chudder -ErrorAction SilentlyContinue | Stop-Process -Force"], **NOWIN)
    for i in range(1, n + 1):
        name = f"{client}-cold-{i}"
        if client == "chudder":
            subprocess.run(["powershell", "-NoProfile", "-Command", "Get-Process chudder -ErrorAction SilentlyContinue | Stop-Process -Force"], **NOWIN)
        else:
            subprocess.run(["powershell", "-NoProfile", "-Command", kill_web], **NOWIN)
        time.sleep(3)
        rec = record(name, 12.0)
        time.sleep(1.0)
        t = time.time()
        if client == "chudder":
            subprocess.Popen([exe], cwd=os.path.dirname(exe))
        else:
            profile = os.path.abspath(os.path.join(MK, "out", "chrome-bench"))
            subprocess.Popen([r"C:\Program Files\Google\Chrome\Application\chrome.exe", f"--user-data-dir={profile}",
                              "--remote-debugging-port=9444", "--lang=en-US", "--no-first-run", "--no-default-browser-check",
                              "--force-device-scale-factor=1", "--window-position=0,0", "--window-size=1400,900",
                              f"--app={webctl.SERVER}/web/#/home"])
        json.dump({"click": t}, open(os.path.join(OUT, name + ".json"), "w"))
        rec.wait()
        print(name, "recorded", flush=True)


def detect_cold(name):
    f = frames(name)
    clock = frame_clock(name)[: len(f)]
    t = json.load(open(os.path.join(OUT, name + ".json")))["click"]
    c = int(np.searchsorted(clock, t))
    end = c
    for i in range(c + 3, len(f)):
        if region_diff(f, i, i - 3, (0, 0, SMALL[0], SMALL[1])) > 0.6:
            end = i
    return {"name": name, "click_frame": c, "end_frame": end, "ms": round((clock[end] - t) * 1000)}


if __name__ == "__main__" and sys.argv[1] in ("cold", "measure-cold"):
    if sys.argv[1] == "cold":
        cold(sys.argv[2], int(sys.argv[3]))
    else:
        rs = []
        i = 1
        while os.path.exists(os.path.join(OUT, f"{sys.argv[2]}-cold-{i}.json")):
            rs.append(detect_cold(f"{sys.argv[2]}-cold-{i}")); print(rs[-1]); i += 1
        print(sys.argv[2], "cold median", float(np.median([r["ms"] for r in rs[1:]])))


# ---- cold page: the client just started, Home drawn, then the first Continue Watching film opened for the first
# time -> its page visually complete. A different film each run, the same film for both clients. ----
COLD_FILMS = ["5cac0eb7f98e4d06105b013db2dceefa", "f79b7e943048db6db72bc5775f393fd0", "852ac947278f14ad5984feeeb217677b",
              "ad1dfce6b4f1a541a8c427c5121cdfaf", "1063e54afc08d3157fb0571e50a6b590", CHARGE, "5cac0eb7f98e4d06105b013db2dceefa"]


def start_client(client):
    import webctl
    exe = os.path.abspath(os.path.join(MK, "..", "..", "build", "windows", "x64", "runner", "Release", "chudder.exe"))
    kill_web = ("Get-CimInstance Win32_Process -Filter \"Name='chrome.exe'\" | ? { $_.CommandLine -like '*chrome-bench*' } | "
                "% { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }")
    subprocess.run(["powershell", "-NoProfile", "-Command", kill_web], **NOWIN)
    subprocess.run(["powershell", "-NoProfile", "-Command", "Get-Process chudder -ErrorAction SilentlyContinue | Stop-Process -Force"], **NOWIN)
    time.sleep(3)
    if client == "chudder":
        subprocess.Popen([exe], cwd=os.path.dirname(exe))
        time.sleep(10)
        subprocess.run(["powershell", "-NoProfile", "-File", os.path.join(MK, "window.ps1"), "-X", "0", "-Y", "0", "-W", "1400", "-H", "900"],
                       capture_output=True, **NOWIN)
        time.sleep(3)
    else:
        profile = os.path.abspath(os.path.join(MK, "out", "chrome-bench"))
        subprocess.Popen([r"C:\Program Files\Google\Chrome\Application\chrome.exe", f"--user-data-dir={profile}",
                          "--remote-debugging-port=9444", "--lang=en-US", "--no-first-run", "--no-default-browser-check",
                          "--force-device-scale-factor=1", "--window-position=0,0", "--window-size=1400,900",
                          f"--app={webctl.SERVER}/web/#/home"])
        time.sleep(10)


def coldpage(client, n):
    import demo
    for i in range(1, n + 1):
        name = f"{client}-coldpage-{i}"
        demo.set_position(COLD_FILMS[i - 1], 60, played_now=True)
        time.sleep(1)
        start_client(client)
        drive(client, "move:30,880 wait500" if client == "web" else "move:30,780 wait500")
        rec = record(name, 6.0)
        time.sleep(0.8)
        log = drive(client, "click:160,806" if client == "chudder" else "click:202,596")
        clicks = [t for k, t in click_times(log) if k.startswith("click:")]
        json.dump({"click": clicks[-1]}, open(os.path.join(OUT, name + ".json"), "w"))
        rec.wait()
        print(name, "recorded", flush=True)


# ---- episode switch: the next episode picked on the page (Chudder: the show page's episode row swaps the header in
# place; Jellyfin Web: the "More from Season" row opens the next episode's page) -> visually complete ----
def epswitch(client, n):
    for i in range(1, n + 1):
        name = f"{client}-epswitch-{i}"
        drive(client, "move:30,880 wait900" if client == "web" else "move:30,780 wait900")
        rec = record(name, 4.0)
        time.sleep(0.8)
        log = drive(client, "move:700,560 wait80 click:700,740" if client == "chudder" else "move:600,560 wait80 click:730,775")
        clicks = [t for k, t in click_times(log) if k.startswith("click:")]
        json.dump({"click": clicks[-1]}, open(os.path.join(OUT, name + ".json"), "w"))
        rec.wait()
        time.sleep(1.5)
        print(name, "recorded", flush=True)


def settle(name, click_offset_frames=3, threshold=0.6):
    """Visually complete: the last frame that still differs from the one 3 frames before it."""
    f = frames(name)
    clock = frame_clock(name)[: len(f)]
    t = json.load(open(os.path.join(OUT, name + ".json")))["click"]
    c = int(np.searchsorted(clock, t))
    end = c
    for i in range(c + click_offset_frames, len(f)):
        if region_diff(f, i, i - 3, (0, 0, SMALL[0], SMALL[1])) > threshold:
            end = i
    return {"name": name, "click_frame": c, "end_frame": end, "ms": round((clock[end] - t) * 1000)}


if __name__ == "__main__" and sys.argv[1] in ("coldpage", "epswitch", "settle", "shown"):
    if sys.argv[1] == "coldpage":
        coldpage(sys.argv[2], int(sys.argv[3]))
    elif sys.argv[1] == "epswitch":
        epswitch(sys.argv[2], int(sys.argv[3]))
    else:
        rs = []
        i = 1
        while os.path.exists(os.path.join(OUT, f"{sys.argv[2]}-{i}.json")):
            rs.append(settle(f"{sys.argv[2]}-{i}")); print(rs[-1]); i += 1
        ms = [r["ms"] for r in rs]
        print(sys.argv[2], "all", ms, "median", float(np.median(ms)))


def content_shown(name, box):
    """First frame after the click where a text region (the episode's title line) has changed and then holds still."""
    f = frames(name)
    clock = frame_clock(name)[: len(f)]
    t = json.load(open(os.path.join(OUT, name + ".json")))["click"]
    c = int(np.searchsorted(clock, t))
    x0, y0, x1, y1 = box
    ref = f[max(0, c - 2), y0:y1, x0:x1]
    for i in range(c + 1, len(f) - 8):
        cur = f[i, y0:y1, x0:x1]
        if np.abs(cur - ref).mean() > 4 and all(np.abs(f[j, y0:y1, x0:x1] - cur).mean() < 4 for j in range(i, i + 8)):
            return {"name": name, "click_frame": c, "end_frame": i, "ms": round((clock[i] - t) * 1000)}
    return {"name": name, "click_frame": c, "end_frame": None, "ms": None}


if __name__ == "__main__" and sys.argv[1] == "shown":
    box = tuple(int(v) for v in sys.argv[3].split(","))
    rs = []
    i = 1
    while os.path.exists(os.path.join(OUT, f"{sys.argv[2]}-{i}.json")):
        rs.append(content_shown(f"{sys.argv[2]}-{i}", box)); print(rs[-1]); i += 1
    ms = [r["ms"] for r in rs if r["ms"] is not None]
    print(sys.argv[2], "title shown", ms, "median", float(np.median(ms)) if ms else None)
