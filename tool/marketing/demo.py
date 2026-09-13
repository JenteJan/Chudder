"""Small client for the demo Jellyfin server the marketing material is shot on.

The server address comes from local.json next to this file ({"server": "https://..."}),
which is gitignored: the repository is public and the address stays out of it.
Logs in as the demo user; the token is cached under out/ and never printed.

    python demo.py /Users/{user}/Items/Resume
    python demo.py /Items SearchTerm=Charge IncludeItemTypes=Movie Recursive=true
"""
import json
import os
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "local.json")
CACHE = os.path.join(HERE, "out", "demo_token.json")
AUTH = 'MediaBrowser Client="Chudder marketing", Device="marketing", DeviceId="chudder-marketing", Version="1"'

if not os.path.exists(CONFIG):
    raise SystemExit(f"missing {CONFIG}: create it with {{\"server\": \"https://your-demo-server\"}}")
SERVER = json.load(open(CONFIG))["server"].rstrip("/")


def _request(path, data=None, token=None, **query):
    url = SERVER + path + ("?" + urllib.parse.urlencode(query) if query else "")
    headers = {"Authorization": AUTH + (f', Token="{token}"' if token else ""), "Content-Type": "application/json"}
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=30) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}


def login():
    if os.path.exists(CACHE):
        return json.load(open(CACHE))
    error = None
    for password in ("demo", ""):
        try:
            result = _request("/Users/AuthenticateByName", {"Username": "demo", "Pw": password})
            session = {"token": result["AccessToken"], "user": result["User"]["Id"]}
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            json.dump(session, open(CACHE, "w"))
            return session
        except Exception as e:  # noqa: BLE001 - try the next password
            error = e
    raise SystemExit(f"login failed: {error}")


SESSION = login()
USER = SESSION["user"]


def get(path, **query):
    return _request(path.replace("{user}", USER), token=SESSION["token"], **query)


def post(path, data=None, **query):
    return _request(path.replace("{user}", USER), data if data is not None else {}, token=SESSION["token"], **query)


def set_position(item_id, seconds, played_now=False):
    """Leaves an item part-watched at `seconds`, so its page offers Resume. With played_now it also
    becomes the most recently played item, which puts it first in Continue Watching."""
    data = {"PlaybackPositionTicks": int(seconds * 10_000_000), "Played": False}
    if played_now:
        import datetime
        data["LastPlayedDate"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0000000Z")
    return post(f"/UserItems/{item_id}/UserData", data)


if __name__ == "__main__":
    args = dict(a.split("=", 1) for a in sys.argv[2:])
    print(json.dumps(get(sys.argv[1], **args), indent=1)[: int(os.environ.get("MAX", "6000"))])
