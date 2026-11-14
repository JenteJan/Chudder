"""Runs the cast probes against a television with the desktop app's login.

    python tool/cast_probe/run.py <tv address> <item id> [image subtitle index
                                   [text-subtitle item id, its subtitle index]]
    python tool/cast_probe/run.py --chromecast <chromecast address> <item id> [subtitle index]

The first form drives the DLNA player (dlna_tv_test.dart), the second the
Jellyfin receiver on a Chromecast (chromecast_tv_test.dart). The login is read
from the installed Chudder's settings and passed in the environment; it is
never printed. Plays a few minutes of the item on the TV.
"""
import json
import os
import subprocess
import sys

FLUTTER = os.environ.get("FLUTTER", r"C:\Users\jente\fvm\versions\3.47.9\bin\flutter.bat")


def main():
    # The app's log lines carry arrows and quotes a Windows console code page lacks.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = sys.argv[1:]
    chromecast = bool(args) and args[0] == "--chromecast"
    if chromecast:
        args = args[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    prefs = json.load(open(os.path.expandvars(r"%APPDATA%\JenteJan\chudder\shared_preferences.json"), encoding="utf-8"))
    accounts = prefs["flutter.loginCredentialsKey"]
    if isinstance(accounts, str):
        accounts = json.loads(accounts)
    accounts = [json.loads(a) if isinstance(a, str) else a for a in accounts]
    account = max(accounts, key=lambda a: a.get("lastUsed", ""))
    env = dict(os.environ)
    env.update({
        "JF_BASE": account["credentials"]["url"].rstrip("/"),
        "JF_TOKEN": account["credentials"]["token"],
        "JF_USER": account["id"],
        "JF_SERVER_ID": account["credentials"].get("serverId") or "",
        "CAST_ITEM": args[1],
    })
    if chromecast:
        env["CAST_HOST"] = args[0]
        if len(args) > 2:
            env["CAST_SUBTITLE"] = args[2]
        test = "tool/cast_probe/chromecast_tv_test.dart"
    else:
        env["CAST_TV_HOST"] = args[0]
        if len(args) > 2:
            env["CAST_SUBTITLE"] = args[2]
        if len(args) > 4:
            env["CAST_TEXT_ITEM"] = args[3]
            env["CAST_TEXT_SUBTITLE"] = args[4]
        test = "tool/cast_probe/dlna_tv_test.dart"
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    token = env["JF_TOKEN"]
    run = subprocess.Popen([FLUTTER, "test", test, "--reporter", "expanded"],
                           cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                           encoding="utf-8", errors="replace")
    for line in run.stdout:
        print(line.rstrip().replace(token, "***"), flush=True)
    sys.exit(run.wait())


if __name__ == "__main__":
    main()
