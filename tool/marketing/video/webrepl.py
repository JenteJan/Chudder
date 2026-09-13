"""Persistent headless tab: executes python snippets dropped into cmd/<n>.py, writes cmd/<n>.out.
Keeps one Chrome + CDP session alive between my shell calls. `t` is the cdp.Tab."""
import sys, os, time, glob, io, contextlib, traceback, cdp
W, H = int(sys.argv[1]), int(sys.argv[2])
t = cdp.Tab(cdp.launch(W, H), W, H)
os.makedirs("cmd", exist_ok=True)
for f in glob.glob("cmd/*"): os.remove(f)
open("cmd/READY", "w").write(f"{W}x{H}")
while True:
    for f in sorted(glob.glob("cmd/*.py")):
        code = open(f).read(); os.remove(f)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            try: exec(code, {"t": t, "time": time, "cdp": cdp, "W": W, "H": H})
            except Exception: traceback.print_exc(file=buf)
        if code.strip() == "quit": open(f[:-3] + ".out", "w").write("bye"); sys.exit(0)
        open(f[:-3] + ".out", "w").write(buf.getvalue())
    t.pump(0.3)
