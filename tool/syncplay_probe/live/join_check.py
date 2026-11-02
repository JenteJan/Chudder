"""Judges join_test: at each CHECK, are Chudder, web and the server together?"""
import json
import sys

W = sys.argv[1]
web = []
for line in open(f"{W}/web_log.txt", encoding="utf8"):
    parts = line.split(" ", 2)
    if len(parts) == 3 and parts[1] == "VIDEO":
        text = parts[2].strip()
        web.append((float(parts[0]), None if text == "none" else json.loads(text)))

samples = []
for line in open(f"{W}/chudder_log.txt", encoding="utf8"):
    parts = line.split()
    if parts[1].startswith("CHECK") or parts[1] == "PHASE":
        ts = float(parts[0])
        before = [s for s in samples if s[0] <= ts]
        if parts[1].startswith("CHECK"):
            want = parts[2]
            name = " ".join(parts[3:] if parts[1] == "CHECK" else parts[2:])
            c = before[-1] if before else None
            v = next((x[1] for x in reversed(web) if x[0] <= ts), None)
            pos, running, item, says, server = c[1:]
            if parts[1] == "CHECK-SOLO":
                print(f"{name}: chudder pos={pos} running={running} item={item[:6]} says={says} server={server}")
                continue
            problems = []
            if v is None:
                problems.append("web has no video")
            else:
                gap = pos - v["t"]
                if abs(gap) > 1.0:
                    problems.append(f"apart {gap:+.2f} s")
                if v.get("s") != item:
                    problems.append(f"item web {str(v.get('s'))[:6]} chudder {item[:6]}")
                if (not v["p"]) != running:
                    problems.append(f"web running={not v['p']} chudder running={running}")
            if server.lower() != want.lower():
                problems.append(f"want {want}, server {server}")
            if says.lower() != server.lower():
                problems.append(f"says {says}, server {server}")
            if server.lower() == "waiting":
                problems.append("still waiting")
            shown = f"gap {pos - v['t']:+.3f} s" if v else "-"
            print(f"{'ok  ' if not problems else 'FAIL'} {name}: {shown} {server} {problems or ''}")
        continue
    samples.append((float(parts[0]), float(parts[1]), parts[2] == "true", parts[3], parts[4], parts[5].split("=")[1]))
