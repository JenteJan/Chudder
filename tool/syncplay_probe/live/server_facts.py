"""Server facts for tonight's log, measured on the demo server (throwaway groups only)."""
import sys
import uuid

sys.path.insert(0, r"C:\Users\jente\Development\FladderFork\Fladder\tool\syncplay_probe")
from sp import (Client, cleanup, group_position, make_clients, movie_ids, note, parse_dt, secs, start_group, wait, now_iso)  # noqa: E402

S = 10_000_000
c = Client("Setup")
c.login()
films = sorted(movie_ids(c, 50), key=lambda f: -f[2])
LONG, LONGNAME, LONGRUN = films[0]
print("film", LONGNAME, secs(LONGRUN))


def x1_timeout():
    """A plays, B joins and stays silent. When does the server let go, and what is ignored after?"""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        wait(2)
        b.join(gid)
        wait(33, "B silent; waiting past 30 s")
        note("B Buffering after the forced release")
        b.buffering(group_position(a))
        wait(2)
        note("A Buffering after the forced release")
        a.buffering(group_position(a))
        wait(2)
        note("B Ready, far behind")
        b.ready(600 * S)
        wait(2)
        note("A Pause + Unpause: does buffering count again?")
        a.post("/SyncPlay/Pause")
        wait(1)
        a.post("/SyncPlay/Unpause")
        wait(1.5)
        a.ready(group_position(a))
        b.ready(group_position(a))
        wait(1.5)
        b.buffering(group_position(a))
        wait(2)
    finally:
        cleanup(a, b)


def _playing(a, pos):
    play_id = uuid.uuid4().hex
    body = {"ItemId": LONG, "PositionTicks": pos, "CanSeek": True, "IsPaused": False, "PlaySessionId": play_id,
            "PlayMethod": "DirectStream"}
    a.post("/Sessions/Playing", body)
    a.post("/Sessions/Playing/Progress", body)


def x2_create_while_playing():
    """A is playing outside any group and creates one; A never says Ready. B joins. (Chudder's case.)"""
    a, b = make_clients("A", "B")
    try:
        _playing(a, 76 * S)
        wait(1)
        a.post("/SyncPlay/New", {"GroupName": f"probe-{uuid.uuid4().hex[:5]}"})
        wait(1)
        gid = None
        for _, m in reversed(a.frames):
            if m.get("MessageType") == "SyncPlayGroupUpdate" and m["Data"].get("Type") == "GroupJoined":
                gid = m["Data"]["GroupId"]
                break
        wait(4)
        b.join(gid)
        wait(5)
        note("A Pause during the wait, 14 s before the deadline region")
        a.post("/SyncPlay/Pause")
        wait(23, "waiting for the deadline")
        note("A Unpause")
        a.post("/SyncPlay/Unpause")
        wait(2)
    finally:
        cleanup(a, b)


def x3_create_ready_no_item():
    """Same start, but A says Ready with no PlaylistItemId (what Chudder's body has with no queue)."""
    a, = make_clients("A")
    try:
        _playing(a, 76 * S)
        wait(1)
        a.post("/SyncPlay/New", {"GroupName": f"probe-{uuid.uuid4().hex[:5]}"})
        wait(2)
        r = a.post("/SyncPlay/Ready", {"When": now_iso(), "PositionTicks": 79 * S, "IsPlaying": True})
        note(f"Ready without item -> {r.status_code}")
        wait(2)
    finally:
        cleanup(a)


def x4_past_runtime():
    """Both run past the item's runtime, B reports Buffering; A's Ready names the true file end."""
    a, b = make_clients("A", "B")
    try:
        start = LONGRUN - 4 * S
        gid = start_group(a, [LONG], start)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2)
        a.ready(group_position(a))
        wait(7, "group position runs past RunTimeTicks")
        pos = group_position(a)
        note(f"group position {secs(pos)} runtime {secs(LONGRUN)}")
        b.buffering(pos)
        wait(0.3)
        note("A Ready 100 ms before the group, as Chudder at EOF did")
        a.ready(group_position(a) - S // 10)
        wait(3.5)
        a.ready(a.last_command()["PositionTicks"] - S // 10)
        wait(3.5)
    finally:
        cleanup(a, b)


def x5_ready_behind_claims_playing():
    """B buffers; A Ready; B Ready 10 s behind with IsPlaying true, as Chudder always says."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2)
        a.ready(group_position(a))
        wait(3)
        pos = group_position(a)
        b.buffering(pos)
        wait(0.3)
        a.ready(pos)
        wait(0.5)
        b.ready(pos - 10 * S, playing=True)
        wait(12, "does B itself get anything?")
    finally:
        cleanup(a, b)


def y1_adopt_playing():
    """New flow: created while playing, queue handed over at once, Ready paused at the start."""
    a, = make_clients("A")
    try:
        _playing(a, 76 * S)
        wait(1)
        a.post("/SyncPlay/New", {"GroupName": f"probe-{uuid.uuid4().hex[:5]}"})
        wait(0.3)
        a.post("/SyncPlay/SetNewQueue", {"PlayingQueue": [LONG, films[1][0]], "PlayingItemPosition": 0, "StartPositionTicks": 80 * S})
        wait(0.5)
        a.ready(80 * S, playing=False)
        wait(2)
    finally:
        cleanup(a)


def y2_adopt_paused():
    """Same, the player paused: the group must end up Paused and not start."""
    a, = make_clients("A")
    try:
        _playing(a, 76 * S)
        wait(1)
        a.post("/SyncPlay/New", {"GroupName": f"probe-{uuid.uuid4().hex[:5]}"})
        wait(0.3)
        a.post("/SyncPlay/SetNewQueue", {"PlayingQueue": [LONG, films[1][0]], "PlayingItemPosition": 0, "StartPositionTicks": 80 * S})
        wait(0.5)
        a.ready(80 * S, playing=False)
        a.post("/SyncPlay/Pause")
        wait(2)
    finally:
        cleanup(a)


def y3_last_in_paused_gets_unpause():
    """x5 with the truthful flag: the last member paused 300 ms behind is sent the Unpause too."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start(), playing=False)
        wait(2.5)
        pos = group_position(a)
        b.buffering(pos)
        wait(0.3)
        cmd = a.last_command()["PositionTicks"]
        a.ready(cmd, playing=False)
        wait(0.5)
        b.ready(cmd - 3 * S // 10, playing=False)
        wait(2.5)
    finally:
        cleanup(a, b)


def y4_past_runtime_paused_claim():
    """Past the runtime a paused member keeps the running claim, and the group resumes."""
    a, b = make_clients("A", "B")
    try:
        start = LONGRUN - 2 * S
        gid = start_group(a, [LONG], start)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start(), playing=False)
        wait(6, "past the runtime")
        pos = group_position(a)
        b.buffering(pos)
        wait(0.3)
        cmd = a.last_command()["PositionTicks"]
        a.ready(cmd, playing=True)
        wait(0.3)
        b.ready(cmd, playing=True)
        wait(9)
    finally:
        cleanup(a, b)


for name in sys.argv[1:]:
    print(f"\n===== {name}: {globals()[name].__doc__}", flush=True)
    globals()[name]()
