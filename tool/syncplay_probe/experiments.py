"""Server-behaviour experiments, each a transcript of what two sessions are sent.

Usage: python experiments.py            list them
       python experiments.py e1 f3 ...  run some

Items are picked from the server's own films; set JF_PROBE_ITEMS=id,id to choose.
"""
import os
import re
import sys

from sp import (cleanup, group_position, make_clients, note, secs, start_group, wait)

def _items():
    chosen = [i for i in os.environ.get("JF_PROBE_ITEMS", "").split(",") if i]
    if len(chosen) >= 2:
        return chosen[:2]
    from sp import Client, movie_ids
    c = Client("Setup")
    c.login()
    films = sorted(movie_ids(c, 50), key=lambda f: -f[2])
    return [films[0][0], films[1][0]]


LONG, OTHER = _items()  # the two longest films: positions up to 1500 s are used
S = 10_000_000


def e1_join_hold():
    """A plays. B joins and stays silent. Is A held? For how long? Then B Ready."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        wait(3, "A playing alone")
        note(f"group position by A's clock: {secs(group_position(a))}")
        b.join(gid)
        wait(6, "B joined, says nothing - is A held?")
        note(f"B reports Ready at the PlayQueue start position")
        b.ready(b.queue_start())
        wait(3)
    finally:
        cleanup(a, b)


def e2_absorb():
    """A plays, B joins, A immediately asks Unpause. Then B Buffering, then B Ready."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        wait(3, "A playing alone")
        b.join(gid)
        wait(0.3)
        a.post("/SyncPlay/Unpause")
        wait(2, "did the group resume without B?")
        b.buffering(605 * S)
        wait(2, "B reported Buffering in the resumed group - is A paused?")
        b.ready(group_position(a))
        wait(2, "B reported Ready - does B get the Unpause back?")
        b.buffering(group_position(a))
        wait(2, "second Buffering from B after its Ready - still ignored?")
        b.ready(group_position(a))
        wait(2)
    finally:
        cleanup(a, b)


def e3_rejoin_same_group():
    """Both playing. B POSTs Join for the group it is already in."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(3, "both playing")
        note("B joins the SAME group again")
        b.join(gid)
        wait(4, "what did A see?")
        b.ready(b.queue_start())
        wait(3)
        note(f"participants: {[g.get('Participants') for g in a.groups()]}")
    finally:
        cleanup(a, b)


def e4_socket_drop():
    """Both playing. B's socket closes without leaving. Does the server drop B?"""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(3, "both playing")
        b.close_socket()
        wait(8, "does A hear anything?")
        note(f"participants: {[g.get('Participants') for g in a.groups()]}")
        a.post("/SyncPlay/Pause")
        wait(1.5)
        a.post("/SyncPlay/Unpause")
        wait(4, "A pause+unpause with B's socket gone - does the group wait for B?")
        note("B reconnects its socket (same device id), no rejoin")
        b.connect()
        wait(1)
        a.post("/SyncPlay/Pause")
        wait(1.5, "does B's new socket get group commands without a join?")
        a.post("/SyncPlay/Unpause")
        wait(3)
        note("B sends a Ready on the new socket")
        b.ready(group_position(a))
        wait(2)
    finally:
        cleanup(a, b)


def e5_ready_positions():
    """After a Seek, the two members report Ready at different positions."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(3, "both playing")
        a.post("/SyncPlay/Seek", {"PositionTicks": 1200 * S})
        wait(0.5)
        a.ready(1200 * S)
        wait(0.3)
        note("B reports Ready at 30s instead of the seek target 1200s")
        b.ready(30 * S)
        wait(3, "where does the group resume?")
        note("B reports Ready at 95s while the group is PLAYING")
        b.ready(95 * S)
        wait(3, "does that move the group?")
        note("B reports Buffering at 95s while the group is PLAYING")
        b.buffering(95 * S)
        wait(2, "group paused where?")
        b.ready(95 * S)
        wait(3)
    finally:
        cleanup(a, b)


def e6_ping_delay():
    """How far ahead is an Unpause scheduled, as a function of reported ping."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2)
        for ping in (5, 200, 400, 5):
            a.ping(5)
            b.ping(ping)
            wait(0.3)
            a.post("/SyncPlay/Pause")
            wait(1)
            a.post("/SyncPlay/Unpause")
            wait(2.5, f"B ping={ping}: see when-emitted on the Unpause")
        note("B leaves and joins again WITHOUT reporting a ping; A plays on (absorb)")
        b.ping(400)
        wait(0.3)
        b.leave()
        wait(1)
        b.join(gid)
        wait(0.3)
        a.post("/SyncPlay/Unpause")
        wait(3)
    finally:
        cleanup(a, b)


def e7_next_item():
    """Two members ask for NextItem at once with the same playlist item id."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG, OTHER, LONG, OTHER], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2, "both playing item 0 of 4")
        item = a.last_playlist_item()
        a.post("/SyncPlay/NextItem", {"PlaylistItemId": item})
        b.post("/SyncPlay/NextItem", {"PlaylistItemId": item})
        wait(3, "did the group step once or twice?")
        note("A asks NextItem again with the STALE id")
        a.post("/SyncPlay/NextItem", {"PlaylistItemId": item})
        wait(2)
        note("nobody reports Ready for the new item; A asks Unpause")
        a.post("/SyncPlay/Unpause")
        wait(3)
        a.ready(0)
        b.ready(0)
        wait(3)
    finally:
        cleanup(a, b)


def e8_playback_reports():
    """Does a member's playback start/stop report disturb the group?"""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2, "both playing")
        b.post("/Sessions/Playing", {"ItemId": LONG, "PositionTicks": 600 * S, "CanSeek": True})
        wait(2, "B reported playback START")
        b.post("/Sessions/Playing/Progress", {"ItemId": LONG, "PositionTicks": 610 * S, "IsPaused": False})
        wait(2, "B reported PROGRESS")
        b.post("/Sessions/Playing/Stopped", {"ItemId": LONG, "PositionTicks": 612 * S})
        wait(4, "B reported playback STOPPED - does A get paused / B dropped?")
        note(f"participants: {[g.get('Participants') for g in a.groups()]}")
        a.post("/SyncPlay/Pause")
        wait(1.5, "does B still get group commands?")
        a.post("/SyncPlay/Unpause")
        wait(2)
    finally:
        cleanup(a, b)


def e9_leave_and_stragglers():
    """B leaves while playing; then B, no longer a member, sends requests."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2, "both playing")
        b.leave()
        wait(3, "is A disturbed by the leave?")
        b.post("/SyncPlay/Pause")
        wait(2, "B, outside the group, asked Pause")
        b.ready(700 * S, item="nope")
        wait(2)
    finally:
        cleanup(a, b)


def e10_new_queue_while_playing():
    """A replaces the queue while both play. What each member must do."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2, "both playing")
        a.post("/SyncPlay/SetNewQueue",
               {"PlayingQueue": [OTHER, LONG], "PlayingItemPosition": 0, "StartPositionTicks": 50 * S})
        wait(1.5, "new queue set; nobody ready yet")
        note("only A reports Ready")
        a.ready(50 * S)
        wait(3, "does the group start without B?")
        note("B reports Ready with the OLD playlist item id")
        b.ready(50 * S, item="00000000000000000000000000000000")
        wait(2)
        note("B reports Ready with the right id")
        b.ready(50 * S)
        wait(3)
    finally:
        cleanup(a, b)


def e11_three_way_pause_race():
    """A pauses and B unpauses within a few ms of each other."""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.5)
        b.ready(b.queue_start())
        wait(2, "both playing")
        a.post("/SyncPlay/Pause")
        b.post("/SyncPlay/Unpause")
        wait(3, "pause from A and unpause from B back to back")
        a.post("/SyncPlay/Seek", {"PositionTicks": 900 * S})
        b.post("/SyncPlay/Seek", {"PositionTicks": 300 * S})
        wait(1, "two different seeks back to back")
        a.ready(group_position(a))
        b.ready(group_position(b))
        wait(3)
    finally:
        cleanup(a, b)


def both_playing(start=600 * S):
    a, b = make_clients("A", "B")
    gid = start_group(a, [LONG], start)
    b.join(gid)
    wait(0.5)
    b.ready(b.queue_start())
    wait(2.5, "both playing")
    return a, b, gid


def f1_stall_release():
    """B stalls in a playing group. Released by Ready(isPlaying=false)? By silence?"""
    a, b, _ = both_playing()
    try:
        pos = group_position(a)
        b.buffering(pos)
        wait(2, "B reported Buffering - group paused?")
        note("B reports Ready with isPlaying=FALSE (what the app sends after the server paused it)")
        b.ready(b.last_command()["PositionTicks"], playing=False)
        wait(3, "does the group resume?")
        note("A also reports Ready (isPlaying=true)")
        a.ready(a.last_command()["PositionTicks"])
        wait(3)
        note("second stall: B Buffering, then B never reports Ready")
        b.buffering(group_position(a))
        wait(5, "silence from B")
        a.post("/SyncPlay/Unpause")
        wait(3, "A pressed play while B is still marked buffering")
        b.buffering(group_position(a))
        wait(2, "B Buffering again after that forced resume - ignored now?")
    finally:
        cleanup(a, b)


def f2_tolerance():
    """How far off may a Ready's position be before the server answers Seek."""
    a, b, _ = both_playing()
    try:
        for off_ms in (300, 450, 600, 1500, -600):
            a.post("/SyncPlay/Pause")
            wait(1)
            a.post("/SyncPlay/Seek", {"PositionTicks": 1200 * S})
            wait(0.6)
            a.ready(1200 * S, playing=False)
            wait(0.4)
            note(f"B Ready {off_ms:+d}ms off the seek target, isPlaying=false")
            b.ready(1200 * S + off_ms * 10_000, playing=False)
            wait(1.5, "accepted (state leaves Waiting) or answered with Seek?")
            b.ready(1200 * S, playing=False)
            wait(1)
    finally:
        cleanup(a, b)


def f3_playerless_member():
    """B has closed its player but stays in the group and answers Ready at 0."""
    a, b, _ = both_playing()
    try:
        a.post("/SyncPlay/Seek", {"PositionTicks": 1200 * S})
        wait(0.6)
        a.ready(1200 * S)
        wait(0.3)
        note("B (no player) answers the Waiting state with Ready at 0")
        b.ready(0)
        wait(4, "is A stuck waiting?")
        note("A presses play")
        a.post("/SyncPlay/Unpause")
        wait(3)
        note("B never answers at all this time: A seeks again")
        a.post("/SyncPlay/Seek", {"PositionTicks": 1500 * S})
        wait(0.6)
        a.ready(1500 * S)
        wait(5, "B silent - A stuck?")
    finally:
        cleanup(a, b)


def f4_ready_while_playing():
    """Ready at a wrong position while the group is genuinely PLAYING."""
    a, b, _ = both_playing()
    try:
        note("B reports Ready at 95s; group is playing near 603s")
        b.ready(95 * S)
        wait(3, "does A notice anything?")
        note("B reports Ready isPlaying=false at the right position")
        b.ready(group_position(a), playing=False)
        wait(3)
    finally:
        cleanup(a, b)


def f5_ignore_buffering_lifetime():
    """After a forced resume ignores Buffering, what turns it back on?"""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        b.join(gid)
        wait(0.3)
        a.post("/SyncPlay/Unpause")
        wait(1.5, "A absorbed the join hold")
        b.ready(group_position(a))
        wait(1.5)
        b.buffering(group_position(a))
        wait(2, "1) Buffering right after the forced resume")
        a.post("/SyncPlay/Pause")
        wait(1)
        a.post("/SyncPlay/Unpause")
        wait(2, "pause + unpause by A")
        b.buffering(group_position(a))
        wait(2, "2) Buffering after a pause/unpause cycle")
        b.ready(b.last_command()["PositionTicks"])
        a.ready(a.last_command()["PositionTicks"])
        wait(3)
        a.post("/SyncPlay/Seek", {"PositionTicks": 900 * S})
        wait(0.5)
        a.ready(900 * S)
        b.ready(900 * S)
        wait(2.5, "seek, both ready")
        b.buffering(group_position(a))
        wait(2, "3) Buffering after a seek cycle")
    finally:
        cleanup(a, b)


def f6_pause_then_join():
    """Group is PAUSED. B joins. Is anything sent to A? What does B need to do?"""
    a, b = make_clients("A", "B")
    try:
        gid = start_group(a, [LONG], 600 * S)
        wait(2)
        a.post("/SyncPlay/Pause")
        wait(1.5, "A paused")
        b.join(gid)
        wait(3, "B joined a paused group")
        b.ready(b.queue_start())
        wait(2, "B ready - does the group stay paused?")
        a.post("/SyncPlay/Unpause")
        wait(3)
    finally:
        cleanup(a, b)


def f7_unpause_needs_ready():
    """From Paused, Unpause puts the group in Waiting. Who must report Ready?"""
    a, b, _ = both_playing()
    try:
        a.post("/SyncPlay/Pause")
        wait(1.5)
        a.post("/SyncPlay/Unpause")
        wait(3, "plain pause/unpause: any Waiting state in between?")
    finally:
        cleanup(a, b)


EXPERIMENTS = {k: v for k, v in globals().items() if re.match(r"[ef]\d+_", k) and callable(v)}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        for name, fn in EXPERIMENTS.items():
            print(f"{name:32} {fn.__doc__}")
        sys.exit(0)
    for arg in sys.argv[1:]:
        fn = next(v for k, v in EXPERIMENTS.items() if k.split("_")[0] == arg or k == arg)
        print(f"===== {fn.__name__}: {fn.__doc__}")
        fn()
