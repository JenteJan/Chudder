"""Drives the web build in headless Chrome over the DevTools protocol, for the
phone, tablet and desktop screenshots (no window chrome, and nobody's mouse).

Chrome and a static server for build/web keep running between commands, so a
shot is a handful of calls:

    python web.py start                 # serve build/web on :8765, start headless Chrome
    python web.py size 1600 1000        # viewport in CSS pixels (renders at 2x)
    python web.py size 424 918 touch    # touch emulation for phone/tablet layouts
    python web.py goto /                # path on the local server
    python web.py click 120 340         # mouse click, or a tap with touch on
    python web.py type Metropolus       # text into the focused field
    python web.py key Enter             # Enter, Escape, Backspace, Tab, ArrowDown, ...
    python web.py wheel 800 500 600     # scroll by 600 px at a point
    python web.py eval "document.title"
    python web.py wait-images Backdrop  # until an image whose URL has this text has loaded
    python web.py shot film 1600x1000   # out/shots/film.png, scaled down from the 2x frame
    python web.py stop

The Chrome profile lives in out/chrome, so a login survives restarts.
"""
import base64
import io
import json
import os
import subprocess
import sys
import time
import urllib.request

import websocket
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "out")
PROFILE = os.path.join(OUT, "chrome")
STATE = os.path.join(OUT, "web_state.json")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PORT_HTTP = 8765
PORT_CDP = 9333
SCALE = 2


def _state():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def _save_state(**kwargs):
    state = _state()
    state.update(kwargs)
    json.dump(state, open(STATE, "w"))


def _page_ws():
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT_CDP}/json", timeout=5) as r:
        targets = json.load(r)
    pages = [t for t in targets if t.get("type") == "page"]
    if not pages:
        raise SystemExit("no page target; run start")
    return pages[0]["webSocketDebuggerUrl"]


class Cdp:
    def __init__(self):
        self.ws = websocket.create_connection(_page_ws(), timeout=60, suppress_origin=True)
        self.next_id = 0

    def call(self, method, **params):
        self.next_id += 1
        self.ws.send(json.dumps({"id": self.next_id, "method": method, "params": params}))
        while True:
            message = json.loads(self.ws.recv())
            if message.get("id") == self.next_id:
                if "error" in message:
                    raise SystemExit(f"{method}: {message['error']}")
                return message.get("result", {})

    def eval(self, expression):
        result = self.call("Runtime.evaluate", expression=expression, returnByValue=True, awaitPromise=True)
        return result.get("result", {}).get("value")


def start():
    os.makedirs(PROFILE, exist_ok=True)
    try:
        _page_ws()
        print("already running")
        return
    except Exception:  # noqa: BLE001 - not running yet
        pass
    server = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(PORT_HTTP), "--bind", "127.0.0.1", "--directory", os.path.join(REPO, "build", "web")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
    )
    chrome = subprocess.Popen(
        [
            CHROME, "--headless=new", f"--remote-debugging-port={PORT_CDP}", f"--user-data-dir={PROFILE}",
            "--no-first-run", "--no-default-browser-check", "--lang=en-US", "--hide-scrollbars",
            "--disable-features=LocalNetworkAccessChecks", "--autoplay-policy=no-user-gesture-required",
            f"--force-device-scale-factor={SCALE}", "--window-size=1600,1000", f"http://127.0.0.1:{PORT_HTTP}/",
        ],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,
    )
    _save_state(server=server.pid, chrome=chrome.pid)
    for _ in range(40):
        try:
            _page_ws()
            break
        except Exception:  # noqa: BLE001 - still starting
            time.sleep(0.5)
    print(f"serving build/web on {PORT_HTTP}, chrome devtools on {PORT_CDP}")


def stop():
    state = _state()
    # Only this profile's Chrome: other Chrome windows on the machine are someone's browser.
    ps = (
        "Get-CimInstance Win32_Process -Filter \"Name='chrome.exe'\" | "
        f"Where-Object {{ $_.CommandLine -like '*{PROFILE}*' }} | "
        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], check=False)
    if state.get("server"):
        subprocess.run(["taskkill", "/PID", str(state["server"]), "/F"], capture_output=True, check=False)
    if os.path.exists(STATE):
        os.remove(STATE)
    print("stopped")


def size(cdp, width, height, touch=False):
    # The window itself, not an emulation override: overrides belong to the
    # DevTools session and vanish when this command disconnects. Chrome runs
    # at SCALE device pixels per CSS pixel from its launch flag.
    window = cdp.call("Browser.getWindowForTarget")["windowId"]
    cdp.call("Browser.setWindowBounds", windowId=window, bounds={"width": width, "height": height})
    time.sleep(0.5)
    inner = cdp.eval("[innerWidth, innerHeight, devicePixelRatio]")
    if inner and (inner[0] != width or inner[1] != height):
        # Headless windows can carry a frame; grow by the difference once.
        cdp.call("Browser.setWindowBounds", windowId=window,
                 bounds={"width": 2 * width - inner[0], "height": 2 * height - inner[1]})
        time.sleep(0.5)
        inner = cdp.eval("[innerWidth, innerHeight, devicePixelRatio]")
    _save_state(touch=touch, width=width, height=height)
    print(f"viewport {inner} touch={touch}")


def click(cdp, x, y):
    if _state().get("touch"):
        point = [{"x": x, "y": y}]
        cdp.call("Input.dispatchTouchEvent", type="touchStart", touchPoints=point)
        time.sleep(0.05)
        cdp.call("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
    else:
        cdp.call("Input.dispatchMouseEvent", type="mouseMoved", x=x, y=y)
        cdp.call("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
        time.sleep(0.05)
        cdp.call("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)


KEYS = {
    "Enter": ("Enter", 13, "\r"), "Escape": ("Escape", 27, ""), "Backspace": ("Backspace", 8, ""),
    "Tab": ("Tab", 9, ""), "ArrowDown": ("ArrowDown", 40, ""), "ArrowUp": ("ArrowUp", 38, ""),
    "ArrowLeft": ("ArrowLeft", 37, ""), "ArrowRight": ("ArrowRight", 39, ""),
}


def key(cdp, name):
    code, vk, text = KEYS[name]
    cdp.call("Input.dispatchKeyEvent", type="keyDown", key=name, code=code, windowsVirtualKeyCode=vk, text=text)
    cdp.call("Input.dispatchKeyEvent", type="keyUp", key=name, code=code, windowsVirtualKeyCode=vk)


def shot(cdp, name, final=None):
    os.makedirs(os.path.join(OUT, "shots"), exist_ok=True)
    data = base64.b64decode(cdp.call("Page.captureScreenshot", format="png")["data"])
    image = Image.open(io.BytesIO(data)).convert("RGB")
    if final:
        w, h = (int(v) for v in final.split("x"))
        image = image.resize((w, h), Image.LANCZOS)
    path = os.path.join(OUT, "shots", f"{name}.png")
    image.save(path)
    print(f"{name} {image.size} -> {path}")


def wait_images(cdp, needle, timeout=30):
    expression = (
        "performance.getEntriesByType('resource')"
        f".filter(e => e.name.includes({json.dumps(needle)}) && e.responseEnd > 0).length"
    )
    end = time.time() + timeout
    while time.time() < end:
        if (cdp.eval(expression) or 0) > 0:
            print(f"loaded: {needle}")
            return
        time.sleep(0.5)
    raise SystemExit(f"timed out waiting for an image matching {needle}")


def main(argv):
    command, args = argv[0], argv[1:]
    if command == "start":
        return start()
    if command == "stop":
        return stop()
    cdp = Cdp()
    if command == "size":
        size(cdp, int(args[0]), int(args[1]), touch=len(args) > 2 and args[2] == "touch")
    elif command == "goto":
        cdp.call("Page.navigate", url=f"http://127.0.0.1:{PORT_HTTP}{args[0]}")
    elif command == "reload":
        cdp.call("Page.reload")
    elif command == "click":
        click(cdp, float(args[0]), float(args[1]))
    elif command == "type":
        cdp.call("Input.insertText", text=" ".join(args))
    elif command == "key":
        for name in args:
            key(cdp, name)
            time.sleep(0.15)
    elif command == "wheel":
        cdp.call("Input.dispatchMouseEvent", type="mouseWheel", x=float(args[0]), y=float(args[1]), deltaX=0, deltaY=float(args[2]))
    elif command == "move":
        cdp.call("Input.dispatchMouseEvent", type="mouseMoved", x=float(args[0]), y=float(args[1]))
    elif command == "eval":
        print(json.dumps(cdp.eval(" ".join(args)), indent=1))
    elif command == "wait-images":
        wait_images(cdp, args[0])
    elif command == "shot":
        shot(cdp, args[0], args[1] if len(args) > 1 else None)
    else:
        raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    main(sys.argv[1:])
