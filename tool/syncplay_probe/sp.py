"""SyncPlay server-behaviour probe: fake clients against a Jellyfin server.

Each Client is one Jellyfin session (own device id, own websocket). Frames
are collected on a shared timeline so an experiment reads as a transcript.
The token is never printed.
"""
import json
import os
import ssl
import sys
import threading
import time
import uuid
import warnings
from datetime import datetime, timezone

warnings.filterwarnings("ignore")
import requests  # noqa: E402
import websocket  # noqa: E402

# A server you may create throwaway SyncPlay groups on, and an account on it:
#   JF_PROBE_HOST=host[:port]  JF_PROBE_USER=name  JF_PROBE_PASSWORD=secret
HOST = os.environ.get("JF_PROBE_HOST") or sys.exit("set JF_PROBE_HOST (and JF_PROBE_USER / JF_PROBE_PASSWORD)")
USER = os.environ.get("JF_PROBE_USER", "demo")
PASSWORD = os.environ.get("JF_PROBE_PASSWORD", "demo")
BASE = f"https://{HOST}"
T0 = time.monotonic()
LOCK = threading.Lock()
TIMELINE = []


OFFSET = None  # server clock minus local clock, as a timedelta


def sync_clock():
    """Offset to the server's clock, the way a SyncPlay client measures it."""
    global OFFSET
    best = None
    for _ in range(4):
        t0 = datetime.now(timezone.utc)
        body = requests.get(f"{BASE}/GetUtcTime", timeout=15).json()
        t3 = datetime.now(timezone.utc)
        t1 = parse_dt(body["RequestReceptionTime"])
        t2 = parse_dt(body["ResponseTransmissionTime"])
        ping = ((t3 - t0) - (t2 - t1)) / 2
        offset = ((t1 - t0) + (t2 - t3)) / 2
        if best is None or ping < best[0]:
            best = (ping, offset)
    OFFSET = best[1]
    print(f"clock: server-local offset {OFFSET.total_seconds()*1000:+.0f}ms, ping {best[0].total_seconds()*1000:.0f}ms", flush=True)


def server_now():
    if OFFSET is None:
        sync_clock()
    return datetime.now(timezone.utc) + OFFSET


def now_iso():
    return server_now().strftime("%Y-%m-%dT%H:%M:%S.%f0Z")


def stamp():
    return time.monotonic() - T0


def note(text):
    with LOCK:
        TIMELINE.append((stamp(), "--", text))
    print(f"{stamp():7.3f}  -- {text}", flush=True)


def parse_dt(s):
    s = s.rstrip("Z")
    if "." in s:
        head, frac = s.split(".")
        s = head + "." + frac[:6]
    return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)


def secs(ticks):
    return f"{ticks / 1e7:.3f}s"


class Client:
    def __init__(self, name):
        self.name = name
        self.device_id = f"probe-{name.lower()}-{uuid.uuid4().hex[:8]}"
        self.token = None
        self.user_id = None
        self.ws = None
        self.frames = []
        self._alive = False

    def _auth(self):
        value = (
            f'MediaBrowser Client="ChudderProbe", Device="Probe{self.name}", '
            f'DeviceId="{self.device_id}", Version="1.0"'
        )
        if self.token:
            value += f', Token="{self.token}"'
        return {"Authorization": value, "Content-Type": "application/json"}

    def login(self):
        r = requests.post(
            f"{BASE}/Users/AuthenticateByName",
            headers=self._auth(),
            data=json.dumps({"Username": USER, "Pw": PASSWORD}),
            timeout=15,
        )
        r.raise_for_status()
        body = r.json()
        self.token = body["AccessToken"]
        self.user_id = body["User"]["Id"]

    def get(self, path, **params):
        r = requests.get(f"{BASE}{path}", headers=self._auth(), params=params, timeout=15)
        return r

    def post(self, path, body=None, quiet=False):
        r = requests.post(
            f"{BASE}{path}", headers=self._auth(), data=json.dumps(body or {}), timeout=15
        )
        if not quiet:
            note(f"{self.name} POST {path} {json.dumps(body) if body else ''} -> {r.status_code}")
        return r

    # --- websocket -------------------------------------------------------
    def connect(self):
        url = f"wss://{HOST}/socket?ApiKey={self.token}&api_key={self.token}&deviceId={self.device_id}"
        self.ws = websocket.create_connection(url, sslopt={"cert_reqs": ssl.CERT_NONE}, timeout=30)
        self._alive = True
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._keepalive, daemon=True).start()

    def close_socket(self):
        self._alive = False
        try:
            self.ws.close()
        except Exception:
            pass
        note(f"{self.name} websocket CLOSED (no leave)")

    def _keepalive(self):
        ws = self.ws
        while self._alive and ws is self.ws:
            time.sleep(10)
            try:
                ws.send(json.dumps({"MessageType": "KeepAlive"}))
            except Exception:
                return

    def _reader(self):
        ws = self.ws
        while self._alive and ws is self.ws:
            try:
                raw = ws.recv()
            except Exception:
                return
            if not raw:
                continue
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            kind = msg.get("MessageType")
            if kind in ("KeepAlive", "ForceKeepAlive"):
                continue
            t = stamp()
            self.frames.append((t, msg))
            text = self._describe(msg)
            if text:
                with LOCK:
                    TIMELINE.append((t, self.name, text))
                print(f"{t:7.3f}  {self.name}< {text}", flush=True)

    def _describe(self, msg):
        kind = msg.get("MessageType")
        data = msg.get("Data")
        if kind == "SyncPlayCommand":
            when = parse_dt(data["When"])
            emitted = parse_dt(data["EmittedAt"])
            lead = (when - emitted).total_seconds() * 1000
            return (
                f"COMMAND {data['Command']:8} pos={secs(data.get('PositionTicks') or 0)} "
                f"when-emitted={lead:+.0f}ms item={str(data.get('PlaylistItemId'))[:6]}"
            )
        if kind == "SyncPlayGroupUpdate":
            typ = data.get("Type")
            inner = data.get("Data")
            if typ == "PlayQueue":
                return (
                    f"UPDATE  PlayQueue reason={inner.get('Reason')} n={len(inner.get('Playlist') or [])} "
                    f"index={inner.get('PlayingItemIndex')} start={secs(inner.get('StartPositionTicks') or 0)} "
                    f"isPlaying={inner.get('IsPlaying')}"
                )
            if typ == "StateUpdate":
                return f"UPDATE  State={inner.get('State')} reason={inner.get('Reason')}"
            if typ == "GroupJoined":
                return f"UPDATE  GroupJoined state={inner.get('State')} participants={inner.get('Participants')}"
            return f"UPDATE  {typ} {inner if not isinstance(inner, dict) else ''}"
        if kind in ("UserDataChanged", "Sessions", "LibraryChanged", "ScheduledTasksInfo", "ActivityLogEntry"):
            return None
        return f"OTHER   {kind}"

    def last_playlist_item(self):
        for _, msg in reversed(self.frames):
            if msg.get("MessageType") == "SyncPlayGroupUpdate" and msg["Data"].get("Type") == "PlayQueue":
                inner = msg["Data"]["Data"]
                pl = inner.get("Playlist") or []
                idx = inner.get("PlayingItemIndex") or 0
                if pl and idx < len(pl):
                    return pl[idx]["PlaylistItemId"]
        return None

    def queue_start(self):
        """StartPositionTicks of the last PlayQueue this session was sent."""
        for _, msg in reversed(self.frames):
            if msg.get("MessageType") == "SyncPlayGroupUpdate" and msg["Data"].get("Type") == "PlayQueue":
                return msg["Data"]["Data"].get("StartPositionTicks") or 0
        return 0

    def last_command(self):
        for _, msg in reversed(self.frames):
            if msg.get("MessageType") == "SyncPlayCommand":
                return msg["Data"]
        return None

    # --- syncplay --------------------------------------------------------
    def ready(self, ticks, playing=True, item=None):
        return self.post(
            "/SyncPlay/Ready",
            {
                "When": now_iso(),
                "PositionTicks": int(ticks),
                "IsPlaying": playing,
                "PlaylistItemId": item or self.last_playlist_item(),
            },
        )

    def buffering(self, ticks, item=None):
        return self.post(
            "/SyncPlay/Buffering",
            {
                "When": now_iso(),
                "PositionTicks": int(ticks),
                "IsPlaying": False,
                "PlaylistItemId": item or self.last_playlist_item(),
            },
        )

    def ping(self, ms):
        return self.post("/SyncPlay/Ping", {"Ping": ms})

    def join(self, group_id):
        return self.post("/SyncPlay/Join", {"GroupId": group_id})

    def leave(self, quiet=False):
        return self.post("/SyncPlay/Leave", quiet=quiet)

    def groups(self):
        r = self.get("/SyncPlay/List")
        return r.json() if r.status_code == 200 else []


def wait(seconds, why=""):
    if why:
        note(f"... wait {seconds}s ({why})")
    time.sleep(seconds)


def group_position(client):
    """Where the group's playhead is, extrapolated from the last command."""
    cmd = client.last_command()
    if not cmd:
        return None
    pos = cmd.get("PositionTicks") or 0
    if cmd["Command"] != "Unpause":
        return pos
    elapsed = (server_now() - parse_dt(cmd["When"])).total_seconds()
    return pos + int(max(elapsed, 0) * 1e7)


def movie_ids(client, n=3):
    r = client.get(
        f"/Users/{client.user_id}/Items",
        IncludeItemTypes="Movie",
        Recursive="true",
        Limit=str(n),
        SortBy="SortName",
    )
    return [(i["Id"], i["Name"], i.get("RunTimeTicks", 0)) for i in r.json().get("Items", [])]


def make_clients(*names):
    clients = []
    for n in names:
        c = Client(n)
        c.login()
        c.connect()
        clients.append(c)
    time.sleep(0.5)
    return clients


def start_group(a, items, start_ticks=0, name=None):
    """A creates a group, queues items, reports ready; returns group id."""
    r = a.post("/SyncPlay/New", {"GroupName": name or f"probe-{uuid.uuid4().hex[:5]}"})
    time.sleep(0.4)
    gid = None
    for g in a.groups():
        gid = g["GroupId"] if gid is None else gid
    for _, msg in reversed(a.frames):
        if msg.get("MessageType") == "SyncPlayGroupUpdate" and msg["Data"].get("Type") == "GroupJoined":
            gid = msg["Data"]["GroupId"]
            break
    a.post(
        "/SyncPlay/SetNewQueue",
        {"PlayingQueue": items, "PlayingItemPosition": 0, "StartPositionTicks": int(start_ticks)},
    )
    time.sleep(0.5)
    a.ready(start_ticks)
    time.sleep(1.5)
    return gid


def cleanup(*clients):
    for c in clients:
        try:
            c.leave(quiet=True)
        except Exception:
            pass
        c._alive = False
        try:
            c.ws.close()
        except Exception:
            pass


if __name__ == "__main__":
    a = Client("A")
    a.login()
    info = requests.get(f"{BASE}/System/Info/Public", timeout=15).json()
    print("server version:", info.get("Version"))
    for mid, name, run in movie_ids(a, 6):
        print(mid, name, secs(run))
    print("groups:", [(g.get("GroupName"), g.get("State"), g.get("Participants")) for g in a.groups()])
