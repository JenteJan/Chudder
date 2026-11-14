"""Runs dlna_tv_test.dart against a television with the desktop app's login.

    python tool/cast_probe/run.py <tv address> <item id> [image subtitle index
                                   [text-subtitle item id, its subtitle index]]

The login is read from the installed Chudder's settings and passed in the
environment; it is never printed. Plays a few minutes of the item on the TV.
"""
import json
import os
import subprocess
import sys

FLUTTER = os.environ.get("FLUTTER", r"C:\Users\jente\fvm\versions\3.47.9\bin\flutter.bat")


def main():
    if len(sys.argv) < 3:
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
        "CAST_TV_HOST": sys.argv[1],
        "CAST_ITEM": sys.argv[2],
    })
    if len(sys.argv) > 3:
        env["CAST_SUBTITLE"] = sys.argv[3]
    if len(sys.argv) > 5:
        env["CAST_TEXT_ITEM"] = sys.argv[4]
        env["CAST_TEXT_SUBTITLE"] = sys.argv[5]
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    token = env["JF_TOKEN"]
    run = subprocess.Popen([FLUTTER, "test", "tool/cast_probe/dlna_tv_test.dart", "--reporter", "expanded"],
                           cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                           encoding="utf-8", errors="replace")
    for line in run.stdout:
        print(line.rstrip().replace(token, "***"), flush=True)
    sys.exit(run.wait())


if __name__ == "__main__":
    main()
