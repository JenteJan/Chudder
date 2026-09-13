"""Setup helper for the Jellyfin Web side of the benchmark: a real, visible Chrome window (its own
profile, remote debugging on 9444) that the benchmark drives with the real mouse. This only
navigates, logs in and inspects - nothing timed goes through it.

    python webctl.py eval "location.href"
    python webctl.py go "/web/#/details?id=..."
    python webctl.py login
"""
import json
import os
import sys
import time
import urllib.request

import websocket

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = json.load(open(os.path.join(HERE, "..", "local.json")))["server"].rstrip("/")
PORT = 9444


class Page:
    def __init__(self):
        pages = [p for p in json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json"))
                 if p["type"] == "page" and SERVER in p["url"]]
        self.ws = websocket.create_connection(pages[0]["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
        self.i = 0

    def call(self, method, **params):
        self.i += 1
        self.ws.send(json.dumps({"id": self.i, "method": method, "params": params}))
        while True:
            m = json.loads(self.ws.recv())
            if m.get("id") == self.i:
                return m.get("result", {})

    def eval(self, expr):
        r = self.call("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        return r.get("result", {}).get("value")


def main(argv):
    p = Page()
    cmd = argv[0]
    if cmd == "eval":
        print(json.dumps(p.eval(" ".join(argv[1:])), indent=1))
    elif cmd == "go":
        p.eval(f"location.href = {json.dumps(SERVER + argv[1])}; 1")
    elif cmd == "login":
        # the manual login form: user name, password, submit
        p.eval("""(async () => {
            const wait = ms => new Promise(r => setTimeout(r, ms));
            for (let i = 0; i < 40 && !document.querySelector('#txtManualName'); i++) {
                const manual = document.querySelector('.btnManual'); if (manual) manual.click();
                await wait(250);
            }
            const set = (sel, v) => { const e = document.querySelector(sel); e.value = v; e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true})); };
            set('#txtManualName', 'demo'); set('#txtManualPassword', 'demo');
            document.querySelector('.manualLoginForm button[type=submit]').click();
            return 'submitted';
        })()""")
        time.sleep(5)
        print(p.eval("location.href"))


if __name__ == "__main__":
    main(sys.argv[1:])
