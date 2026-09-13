"""Records takes from the web build in the headless Chrome that web.py runs.

One connection holds the viewport override for the whole take (an override dies with the DevTools
session that set it), and Chrome's screencast is resampled onto a steady 30 fps grid by wall clock:
Chrome only sends a frame when the page changes.

    from webtake import Take
    t = Take(424, 918, touch=True)       # CSS size at 1x, like the renders expect
    t.go("/#/dashboard/details?id=...")  # or t.click / t.type / t.key / t.wheel / t.eval
    t.record_start(); t.pump(2); t.click(345, 44); t.pump(4); t.record_stop("cast_phone")
"""
import base64
import json
import os
import shutil
import sys
import time

import websocket

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import web  # noqa: E402

OUT = os.path.join(HERE, "..", "out")


class Take:
    def __init__(self, width, height, touch=False, scale=2):
        self.ws = websocket.create_connection(web._page_ws(), timeout=30, suppress_origin=True)
        self.i = 0
        self.frames = []
        self.recording = False
        self.w, self.h, self.touch = width, height, touch
        self.send("Page.enable")
        self.send("Runtime.enable")
        self.send("Emulation.setDeviceMetricsOverride", width=width, height=height, deviceScaleFactor=scale, mobile=touch)
        self.send("Emulation.setTouchEmulationEnabled", enabled=touch, maxTouchPoints=5 if touch else 1)
        self.pump(1.0)

    # --- protocol ---------------------------------------------------------
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
            self.ws.send(json.dumps({"id": 900000 + len(self.frames), "method": "Page.screencastFrameAck",
                                     "params": {"sessionId": p["sessionId"]}}))
            if self.recording:
                self.frames.append((time.time(), p["data"]))

    def pump(self, seconds):
        end = time.time() + seconds
        self.ws.settimeout(0.2)
        while time.time() < end:
            try:
                self._event(json.loads(self.ws.recv()))
            except websocket.WebSocketTimeoutException:
                pass
        self.ws.settimeout(30)

    # --- input ------------------------------------------------------------
    def go(self, path, wait=4.0):
        self.eval(f"location.hash = {json.dumps(path.split('#', 1)[-1])}; 1")
        self.pump(wait)

    def click(self, x, y):
        if self.touch:
            self.send("Input.dispatchTouchEvent", type="touchStart", touchPoints=[{"x": x, "y": y}])
            time.sleep(0.05)
            self.send("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
        else:
            self.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)
            self.send("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
            time.sleep(0.05)
            self.send("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)

    def move(self, x, y):
        self.send("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)

    def wheel(self, x, y, dy):
        self.send("Input.dispatchMouseEvent", type="mouseWheel", x=x, y=y, deltaX=0, deltaY=dy)

    def type(self, text):
        for ch in text:
            self.send("Input.insertText", text=ch)
            time.sleep(0.07)

    def eval(self, expr):
        r = self.send("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        return r.get("result", {}).get("value")

    def video(self):
        return self.eval("(() => {const v=document.querySelector('video');"
                         "return v? {paused:v.paused, t:+v.currentTime.toFixed(2)} : null;})()")

    def shot(self, name):
        os.makedirs(os.path.join(OUT, "shots"), exist_ok=True)
        path = os.path.join(OUT, "shots", f"{name}.png")
        open(path, "wb").write(base64.b64decode(self.send("Page.captureScreenshot", format="png")["data"]))
        return path

    # --- recording --------------------------------------------------------
    def record_start(self):
        self.frames = []
        self.recording = True
        self.t0 = time.time()
        self.send("Page.startScreencast", format="jpeg", quality=95, maxWidth=self.w, maxHeight=self.h, everyNthFrame=1)

    def mark(self, label):
        print(f"  {time.time() - self.t0:6.2f}s {label}", flush=True)

    def record_stop(self, name, fps=30):
        self.recording = False
        try:
            self.send("Page.stopScreencast")
        except Exception:  # noqa: BLE001 - nothing to stop
            pass
        out = os.path.join(OUT, "fr", name)
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out, exist_ok=True)
        if not self.frames:
            print("no frames captured")
            return 0
        dur = time.time() - self.t0
        n = max(1, int(dur * fps))
        j = 0
        for k in range(n):
            t = self.t0 + k / fps
            while j + 1 < len(self.frames) and self.frames[j + 1][0] <= t:
                j += 1
            open(os.path.join(out, f"{k + 1:05d}.jpg"), "wb").write(base64.b64decode(self.frames[j][1]))
        print(f"{name}: {len(self.frames)} raw -> {n} frames ({dur:.1f}s)")
        return n
