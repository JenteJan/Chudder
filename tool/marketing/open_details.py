"""Opens an item's page in the web build, retrying until the backdrop it picks
is the one wanted - the app picks one of an item's backdrops at random.

    python open_details.py <item id> [backdrop index] [tab path, default dashboard]
"""
import sys
import time

import web

item = sys.argv[1]
want = sys.argv[2] if len(sys.argv) > 2 else None
tab = sys.argv[3] if len(sys.argv) > 3 else "dashboard"

cdp = web.Cdp()
for attempt in range(12):
    cdp.eval(f"performance.clearResourceTimings(); location.hash = '#/{tab}'; 1")
    time.sleep(1.5)
    cdp.eval(f"location.hash = '#/{tab}/details?id={item}'; 1")
    backdrop = None
    for _ in range(40):
        time.sleep(0.5)
        names = cdp.eval(
            "performance.getEntriesByType('resource').filter(e => e.responseEnd > 0).map(e => e.name)"
            f".filter(n => n.includes('{item}/Images/Backdrop/'))"
        ) or []
        if names:
            backdrop = names[0].split("/Images/Backdrop/")[1].split("?")[0]
            break
    print(f"attempt {attempt + 1}: backdrop {backdrop}")
    if want is None or backdrop == want:
        break
else:
    raise SystemExit("never got the wanted backdrop")
