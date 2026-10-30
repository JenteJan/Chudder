"""Chudder's position against the real web client's, phase by phase."""
import bisect
import json
import os
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
chud, phases = [], []
for line in open(os.path.join(HERE, "chudder_log.txt"), encoding="utf8"):
    p = line.split()
    if len(p) >= 3 and p[1] == "PHASE":
        phases.append((float(p[0]), p[2]))
    elif len(p) >= 5:
        chud.append((float(p[0]), float(p[1]), p[2] == "true", p[3], p[4]))
web, notes = [], []
for line in open(os.path.join(HERE, "web_log.txt"), encoding="utf8"):
    t, _, rest = line.rstrip().partition(" ")
    if rest.startswith("VIDEO {"):
        d = json.loads(rest[6:])
        web.append((float(t), d["t"], not d["p"], d.get("s"), d["r"]))
    elif rest.startswith(("POST Ready", "POST Buffering", "CMD", "EXCEPTION", "JOINING")) or "TypeError" in rest:
        notes.append((float(t), rest[:120]))
times = [c[0] for c in chud]
print(f"{'phase':14}{'secs':>6}{'gap ms at end':>15}{'chudder':>10}{'web':>10}  same item")
for i, (start, name) in enumerate(phases[:-1]):
    end = phases[i + 1][0]
    tail = [w for w in web if end - 1.5 <= w[0] <= end]
    gaps, same = [], []
    for w in tail:
        c = chud[min(bisect.bisect(times, w[0]), len(chud) - 1)]
        gaps.append(abs(c[1] - w[1]) * 1000)
        same.append(bool(w[3]) and c[3] is not None and w[3] == c[3])
    c = chud[min(bisect.bisect(times, end), len(chud) - 1)]
    w = tail[-1] if tail else None
    print(f"{name:14}{end - start:6.1f}{(statistics.median(gaps) if gaps else float('nan')):15.0f}"
          f"{c[1]:10.1f}{(w[1] if w else float('nan')):10.1f}  {all(same) if same else '-'}  c={'run' if c[2] else 'stop'}/{c[4]} w={'run' if w and w[2] else 'stop'}")
print()
for t, n in notes:
    label = max((p for p in phases if p[0] <= t), key=lambda p: p[0], default=(0, "-"))
    print(f"{t - label[0]:6.2f} {label[1]:14} {n}")
