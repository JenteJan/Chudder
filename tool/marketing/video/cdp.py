#!/usr/bin/env python3
"""Drive and record the Chudder web build through the Chrome DevTools Protocol.

Nothing here touches the desktop: the page is rendered in a headless Chrome, input
is dispatched into the page, and frames come from Chrome's own screencast. So no
window of the user's can end up in a take, and no take can be spoiled by one.
"""
import base64, json, os, shutil, subprocess, sys, threading, time, urllib.request
import websocket

HERE = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out"))
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PROFILE = os.path.join(HERE, "chudder-cdp-profile")
PORT = 9339
URL = "http://localhost:8765/"


def launch(width, height):
    subprocess.run(["powershell", "-NoProfile", "-Command",
                    "Get-CimInstance Win32_Process -Filter \"Name='chrome.exe'\" | "
                    "? { $_.CommandLine -like '*chudder-cdp-profile*' } | "
                    "% { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"],
                   capture_output=True)
    time.sleep(1)
    subprocess.Popen([CHROME, "--headless=new", f"--remote-debugging-port={PORT}", "--remote-allow-origins=*",
                      f"--user-data-dir={PROFILE}", f"--window-size={width},{height}",
                      "--force-device-scale-factor=1", "--lang=en-US", "--no-first-run",
                      "--autoplay-policy=no-user-gesture-required", "--hide-scrollbars",
                      "--disable-features=TranslateUI", "--mute-audio", URL],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(60):
        try:
            pages = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json"))
            for p in pages:
                if p.get("type") == "page":
                    return p["webSocketDebuggerUrl"]
        except Exception:
            pass
        time.sleep(0.5)
    raise SystemExit("chrome did not come up")


class Tab:
    def __init__(self, ws_url, width, height):
        self.ws = websocket.create_connection(ws_url, timeout=30)
        self.i = 0
        self.frames = []
        self._recording = False
        self.w, self.h = width, height
        self.send("Page.enable"); self.send("Runtime.enable")
        self.send("Emulation.setDeviceMetricsOverride",
                  width=width, height=height, deviceScaleFactor=1, mobile=False)

    def send(self, method, **params):
        self.i += 1
        self.ws.send(json.dumps({"id": self.i, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.i:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
            self._event(msg)

    def _event(self, msg):
        if msg.get("method") == "Page.screencastFrame":
            p = msg["params"]
            self.ws.send(json.dumps({"id": 100000 + len(self.frames), "method": "Page.screencastFrameAck",
                                     "params": {"sessionId": p["sessionId"]}}))
            if self._recording:
                self.frames.append((time.time(), p["data"]))

    def pump(self, seconds):
        end = time.time() + seconds
        self.ws.settimeout(0.4)
        while time.time() < end:
            try:
                self._event(json.loads(self.ws.recv()))
            except websocket.WebSocketTimeoutException:
                pass
            except Exception:
                break
        self.ws.settimeout(30)

    # --- interaction -----------------------------------------------------
    def click(self, x, y):
        for kind in ("mousePressed", "mouseReleased"):
            self.send("Input.dispatchMouseEvent", type=kind, x=x, y=y, button="left",
                      clickCount=1, buttons=1 if kind == "mousePressed" else 0)
            time.sleep(0.03)

    def move(self, x, y):
        self.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y, buttons=0)

    def type(self, text):
        for ch in text:
            self.send("Input.dispatchKeyEvent", type="keyDown", text=ch, key=ch)
            self.send("Input.dispatchKeyEvent", type="keyUp", key=ch)
            time.sleep(0.06)

    def key(self, key, code=None, vk=None):
        for kind in ("keyDown", "keyUp"):
            self.send("Input.dispatchKeyEvent", type=kind, key=key, code=code or key,
                      windowsVirtualKeyCode=vk or 0, nativeVirtualKeyCode=vk or 0)

    def scroll(self, x, y, dy):
        self.send("Input.dispatchMouseEvent", type="mouseWheel", x=x, y=y, deltaX=0, deltaY=dy)

    def eval(self, expr):
        r = self.send("Runtime.evaluate", expression=expr, returnByValue=True)
        return r.get("result", {}).get("value")

    def video(self):
        return self.eval("(() => {const v=document.querySelector('video');"
                         "return v? {paused:v.paused, t:+v.currentTime.toFixed(2), d:+(v.duration||0).toFixed(1)} : null;})()")

    def shot(self, path):
        data = self.send("Page.captureScreenshot", format="png")["data"]
        open(path, "wb").write(base64.b64decode(data))
        return path

    # --- recording -------------------------------------------------------
    def record_start(self):
        self.frames = []; self._recording = True; self.t0 = time.time()
        self.send("Page.startScreencast", format="jpeg", quality=95,
                  maxWidth=self.w, maxHeight=self.h, everyNthFrame=1)

    def record_stop(self, name, fps=30):
        self._recording = False
        try: self.send("Page.stopScreencast")
        except Exception: pass
        out = os.path.join(HERE, "fr", name)
        shutil.rmtree(out, ignore_errors=True); os.makedirs(out, exist_ok=True)
        if not self.frames:
            print("no frames captured"); return 0
        # Wall clock, not frame arrivals: a page that stops changing stops sending
        # frames, and the take still has to last as long as it was recorded for.
        t0 = self.t0; dur = time.time() - t0
        n = max(1, int(dur * fps))
        # Chrome only emits a frame when the page changes, so resample onto a
        # constant grid: every output frame is the newest frame at its moment.
        j = 0
        for k in range(n):
            t = t0 + k / fps
            while j + 1 < len(self.frames) and self.frames[j + 1][0] <= t:
                j += 1
            open(os.path.join(out, f"{k + 1:05d}.jpg"), "wb").write(base64.b64decode(self.frames[j][1]))
        print(f"{name}: {len(self.frames)} raw -> {n} frames ({dur:.1f}s)")
        return n
