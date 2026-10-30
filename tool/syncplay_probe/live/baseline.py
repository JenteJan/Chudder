"""What the old Chudder sent, against real jellyfin-web: first a lone episode, then the whole show."""
import os
import sys
import time

sys.path.insert(0, r"C:\Users\jente\Development\FladderFork\Fladder\tool\syncplay_probe")
from sp import (cleanup, make_clients, note, wait)  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
a, = make_clients("A")
try:
    shows = a.get(f"/Users/{a.user_id}/Items", IncludeItemTypes="Series", Recursive="true", SortBy="SortName", Limit="1").json()
    sid = shows["Items"][0]["Id"]
    eps = [e["Id"] for e in a.get(f"/Shows/{sid}/Episodes", UserId=a.user_id).json()["Items"]]
    a.post("/SyncPlay/New", {"GroupName": "live-web"})
    wait(4, "web joins")
    t0 = time.time()
    print("LONE", t0, flush=True)
    a.post("/SyncPlay/SetNewQueue", {"PlayingQueue": [eps[3]], "PlayingItemPosition": 0, "StartPositionTicks": 0})
    wait(0.8)
    a.ready(0)
    wait(35, "does web ever start? the server gives up at 30 s")
    print("WHOLE", time.time(), flush=True)
    a.post("/SyncPlay/SetNewQueue", {"PlayingQueue": eps, "PlayingItemPosition": 3, "StartPositionTicks": 0})
    wait(0.8)
    a.ready(0)
    wait(14, "the same episode, as a queue")
finally:
    cleanup(a)
    open(os.path.join(HERE, "stop.txt"), "w").close()
