"""Every wait a group went through in cast_log.txt: how long, and what ended it."""
import re
import statistics
import sys
from datetime import datetime

path = sys.argv[1]
state = re.compile(r"^(\S+) \[INFO\] SyncPlay: SyncPlay: State update: (\w+) \(reason: (\w+)")
ts = lambda s: datetime.fromisoformat(s)
waits = []
cur = None
lands = []
speed = []
for line in open(path, encoding="utf-8", errors="replace"):
    m = state.match(line)
    if m:
        t, s, r = ts(m[1]), m[2], m[3]
        if s == "Waiting":
            if cur is None:
                cur = (t, r)
        elif cur is not None:
            waits.append((cur[0], (t - cur[0]).total_seconds(), cur[1], s, r))
            cur = None
        continue
    if "Resume: came out" in line:
        lands.append(int(re.search(r"came out (-?\d+)ms", line)[1]))
    m2 = re.search(r"SpeedToSync applied \(speed=([\d.]+), diffMs=(-?[\d.]+)", line)
    if m2:
        speed.append(float(m2[2]))

print(f"{len(waits)} waits")
for w in waits:
    if w[1] >= 3:
        print(f"{w[0]:%m-%d %H:%M:%S}  {w[1]:6.1f}s  began {w[2]:8} ended {w[3]}/{w[4]}")
d = [w[1] for w in waits]
print("median", round(statistics.median(d), 2), "max", round(max(d), 1), ">=3s:", sum(x >= 3 for x in d), ">=25s:", sum(x >= 25 for x in d))
print("first landing after a resume (ms, + = behind):", len(lands), "median", statistics.median(lands), "min", min(lands), "max", max(lands))
print("SpeedToSync diffs:", len(speed), "median abs", statistics.median(abs(x) for x in speed), "max abs", max(abs(x) for x in speed))
