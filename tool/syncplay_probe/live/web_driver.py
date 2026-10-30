"""Real jellyfin-web in a muted headless Chrome with a throwaway profile, as one SyncPlay member.

Joins the group named on the command line as soon as it appears, then writes what the page's
<video> is doing, the SyncPlay requests it sends and its console warnings to web_log.txt.
Ends when stop.txt appears. Touches nothing but its own Chrome process.
"""
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import warnings

warnings.filterwarnings("ignore")
import requests  # noqa: E402
import websocket  # noqa: E402

HOST = "https://jellyfin-demo.jentejan.uk"
HERE = os.path.dirname(os.path.abspath(__file__))
PROFILE = os.path.join(HERE, "profile")
LOG = os.path.join(HERE, "web_log.txt")
STOP = os.path.join(HERE, "stop.txt")
GROUP = sys.argv[1] if len(sys.argv) > 1 else "live-web"
PORT = 9333
DEVICE = f"web-probe-{int(time.time())}"

log_lock = threading.Lock()
out = open(LOG, "w", encoding="utf8", buffering=1)


def log(text):
    now = time.time()
    with log_lock:
        out.write(f"{now:.3f} {text}\n")


r = requests.post(
    f"{HOST}/Users/AuthenticateByName",
    headers={
        "Authorization": f'MediaBrowser Client="Jellyfin Web", Device="Chrome", DeviceId="{DEVICE}", Version="12.2.0"',
        "Content-Type": "application/json",
    },
    data=json.dumps({"Username": "demo", "Pw": "demo"}),
    timeout=20,
)
auth = r.json()
TOKEN, UID = auth["AccessToken"], auth["User"]["Id"]
SERVER = requests.get(f"{HOST}/System/Info/Public", timeout=20).json()["Id"]
creds = {
    "Servers": [
        {
            "ManualAddress": HOST,
            "LastConnectionMode": 2,
            "Name": "Demo",
            "Id": SERVER,
            "DateLastAccessed": int(time.time() * 1000),
            "UserId": UID,
            "AccessToken": TOKEN,
        }
    ]
}

shutil.rmtree(PROFILE, ignore_errors=True)
chrome = subprocess.Popen(
    [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        "--headless=new",
        f"--user-data-dir={PROFILE}",
        f"--remote-debugging-port={PORT}",
        "--remote-allow-origins=*",
        "--mute-audio",
        "--autoplay-policy=no-user-gesture-required",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-timer-throttling",
        "--disable-renderer-backgrounding",
        "--window-size=960,540",
        "about:blank",
    ],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)

try:
    target = None
    for _ in range(60):
        try:
            pages = requests.get(f"http://127.0.0.1:{PORT}/json", timeout=2).json()
            target = next((p for p in pages if p["type"] == "page"), None)
            if target:
                break
        except Exception:
            pass
        time.sleep(0.25)
    ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=30)
    next_id = [0]
    replies = {}
    cond = threading.Condition()

    def send(method, **params):
        with cond:
            next_id[0] += 1
            cid = next_id[0]
        ws.send(json.dumps({"id": cid, "method": method, "params": params}))
        return cid

    def call(method, timeout=15, **params):
        cid = send(method, **params)
        end = time.time() + timeout
        with cond:
            while cid not in replies and time.time() < end:
                cond.wait(0.1)
            return replies.pop(cid, None)

    def reader():
        while True:
            try:
                msg = json.loads(ws.recv())
            except Exception:
                return
            if "id" in msg:
                with cond:
                    replies[msg["id"]] = msg
                    cond.notify_all()
                continue
            method = msg.get("method")
            params = msg.get("params", {})
            if method == "Runtime.consoleAPICalled":
                text = " ".join(str(a.get("value", a.get("description", ""))) for a in params.get("args", []))
                if params.get("type") in ("warning", "error") or "SyncPlay" in text:
                    if "SyncPlay" in text or "TypeError" in text or "Cannot" in text:
                        log(f"CONSOLE {params.get('type')}: {text[:260]}")
            elif method == "Network.requestWillBeSent":
                req = params.get("request", {})
                if "/SyncPlay/" in req.get("url", "") and req.get("method") == "POST":
                    log(f"POST {req['url'].split('/SyncPlay/')[1]} {str(req.get('postData', ''))[:150]}")
            elif method == "Runtime.exceptionThrown":
                log(f"EXCEPTION {json.dumps(params.get('exceptionDetails', {}))[:260]}")

    threading.Thread(target=reader, daemon=True).start()
    call("Page.enable")
    call("Runtime.enable")
    call("Network.enable")
    seed = (
        f"localStorage.setItem('jellyfin_credentials', {json.dumps(json.dumps(creds))});"
        f"localStorage.setItem('_deviceId2', {json.dumps(DEVICE)});"
    )
    call("Page.addScriptToEvaluateOnNewDocument", source=seed)
    call("Page.navigate", url=f"{HOST}/web/index.html")

    def evaluate(expr):
        reply = call("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True, timeout=10)
        return (reply or {}).get("result", {}).get("result", {}).get("value")

    for _ in range(120):
        if evaluate("!!(window.ApiClient && window.ApiClient.isLoggedIn && window.ApiClient.isLoggedIn())"):
            break
        time.sleep(0.25)
    log(f"READY logged-in={evaluate('window.ApiClient && window.ApiClient.isLoggedIn()')}")

    headers = {"Authorization": f'MediaBrowser Token="{TOKEN}"'}
    joined = False
    probe = (
        "(()=>{const v=document.querySelector('video');return v?JSON.stringify({t:v.currentTime,p:v.paused,r:v.readyState,"
        "e:v.ended,s:(v.currentSrc||'').split('/Videos/')[1]?.slice(0,32)}):''})()"
    )
    last = ""
    next_list = 0
    while not os.path.exists(STOP):
        now = time.time()
        if not joined and now >= next_list:
            next_list = now + 0.5
            groups = requests.get(f"{HOST}/SyncPlay/List", headers=headers, timeout=10).json()
            match = next((g for g in groups if g.get("GroupName") == GROUP), None)
            if match:
                log(f"JOINING {match['GroupId']} state={match.get('State')}")
                body = json.dumps({"GroupId": match["GroupId"]})
                evaluate(
                    f"fetch('/SyncPlay/Join',{{method:'POST',headers:{{'Content-Type':'application/json',"
                    f"'Authorization':'MediaBrowser Token=\"{TOKEN}\"'}},body:{json.dumps(body)}}}).then(r=>r.status)"
                )
                joined = True
        cmd_file = os.path.join(HERE, "cmd.txt")
        if os.path.exists(cmd_file):
            try:
                command = open(cmd_file, encoding="utf8").read().strip()
                os.remove(cmd_file)
            except OSError:
                command = ""
            if command:
                log(f"CMD {command}")
                # What the web client's own controls send.
                path, _, payload = command.partition(" ")
                body = payload or "{}"
                evaluate(
                    f"fetch('/SyncPlay/{path}',{{method:'POST',headers:{{'Content-Type':'application/json',"
                    f"'Authorization':'MediaBrowser Token=\"{TOKEN}\"'}},body:{json.dumps(body)}}}).then(r=>r.status)"
                )
        state = evaluate(probe)
        if state:
            log(f"VIDEO {state}")
        elif last:
            log("VIDEO none")
        last = state or ""
        time.sleep(0.2)
finally:
    log("END")
    chrome.terminate()
    try:
        chrome.wait(5)
    except Exception:
        chrome.kill()
