"""Load-time benchmark driver for Chudder's Windows release build.

The app measures itself (lib/perf_bench): started with --perf-bench=<config.json> it runs a scripted
scenario from the inside, detects when each step is visually complete, writes a JSON file and exits.
This script builds, prepares profiles, launches runs one process at a time, and compares builds.

    python tool/perf/perfbench.py build --worktree <path> --out <dir>
    python tool/perf/perfbench.py profile-template --exe <Release dir>
    python tool/perf/perfbench.py run --exe <Release dir> --scenarios start-cold,open-movie --runs 5
    python tool/perf/perfbench.py ab --a <Release dir> --b <Release dir> --scenarios ... --runs 8 --label x
    python tool/perf/perfbench.py validate --exe <Release dir> --scenarios ...   # screenshots at ready / +1500 ms
    python tool/perf/perfbench.py list                                             # scenario names
    python tool/perf/perfbench.py discover                                         # item ids per type

Everything machine-wide (locks, profiles, results) lives under ARTIFACTS. See tool/perf/README.md.
Standard library only (Pillow is used by `validate` for contact sheets when it is installed).
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import datetime
import hashlib
import json
import os
import random
import shutil
import socket
import statistics
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ARTIFACTS = r"C:\Users\jente\Development\FladderFork\perf-artifacts"
LOCKS = os.path.join(ARTIFACTS, "locks")
PROFILES = os.path.join(ARTIFACTS, "profiles")
RESULTS = os.path.join(ARTIFACTS, "results")
RUNS = os.path.join(ARTIFACTS, "runs")
TEMPLATE = os.path.join(PROFILES, "template-demo")
FLUTTER = r"C:\Users\jente\fvm\versions\3.44.9\bin\flutter.bat"
RELEASE_ENGINE = r"C:\Users\jente\fvm\versions\3.44.9\bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll"
SCENARIOS = os.path.join(HERE, "scenarios.json")
NOWIN = {"creationflags": subprocess.CREATE_NO_WINDOW}

BUILD_SLOTS = 2
BUILD_STALE_S = 45 * 60
BENCH_STALE_S = 30 * 60


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


# ---------------------------------------------------------------- locks

def _pid_alive(pid):
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    handle = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return False
    code = wt.DWORD()
    ok = ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(handle)
    return bool(ok) and code.value == 259  # STILL_ACTIVE


class Lock:
    """A lock directory created atomically with os.mkdir, with an owner file inside.

    The holder rewrites the owner file every 30 s. A lock is stale when its owner file has not been
    touched for `stale_s`, or when its owner process on this machine is gone."""

    def __init__(self, path, stale_s, what):
        self.path, self.stale_s, self.what = path, stale_s, what
        self._stop = threading.Event()
        self._thread = None

    def _owner(self):
        try:
            with open(os.path.join(self.path, "owner.json"), encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def is_stale(self):
        owner_file = os.path.join(self.path, "owner.json")
        try:
            age = time.time() - os.path.getmtime(owner_file)
        except OSError:
            # A directory without an owner file: someone is between mkdir and writing it, or died there.
            try:
                age = time.time() - os.path.getmtime(self.path)
            except OSError:
                return False
            return age > 60
        owner = self._owner() or {}
        if owner.get("host") == socket.gethostname() and owner.get("pid") and not _pid_alive(owner["pid"]):
            return True
        return age > self.stale_s

    def try_acquire(self, info):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        try:
            os.mkdir(self.path)
        except FileExistsError:
            if self.is_stale():
                log(f"{self.what}: breaking stale lock {self.path} (owner {self._owner()})")
                shutil.rmtree(self.path, ignore_errors=True)
                return self.try_acquire(info)
            return False
        self.info = dict(info, pid=os.getpid(), host=socket.gethostname(), since=datetime.datetime.now().isoformat())
        self._write()
        self._thread = threading.Thread(target=self._heartbeat, daemon=True)
        self._thread.start()
        return True

    def _write(self):
        tmp = os.path.join(self.path, "owner.json.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.info, f)
        os.replace(tmp, os.path.join(self.path, "owner.json"))

    def _heartbeat(self):
        while not self._stop.wait(30):
            try:
                self._write()
            except OSError:
                return

    def release(self):
        self._stop.set()
        shutil.rmtree(self.path, ignore_errors=True)


def acquire_any(paths, stale_s, what, info, max_wait_s=6 * 3600):
    delay, waited, announced = 5, 0, 0
    while True:
        for path in paths:
            lock = Lock(path, stale_s, what)
            if lock.try_acquire(info):
                if waited:
                    log(f"{what}: got {os.path.basename(path)} after {waited:.0f} s")
                return lock
        if waited - announced >= 60 or not announced:
            owners = [Lock(p, stale_s, what)._owner() for p in paths]
            log(f"{what}: busy, waiting (holders: {owners})")
            announced = waited or 1
        if waited > max_wait_s:
            raise SystemExit(f"{what}: gave up after {waited:.0f} s")
        sleep = delay * random.uniform(0.8, 1.2)
        time.sleep(sleep)
        waited += sleep
        delay = min(delay * 1.5, 60)


# ---------------------------------------------------------------- machine state

class _FILETIME(ctypes.Structure):
    _fields_ = [("low", wt.DWORD), ("high", wt.DWORD)]


def _system_times():
    idle, kernel, user = _FILETIME(), _FILETIME(), _FILETIME()
    ctypes.windll.kernel32.GetSystemTimes(ctypes.byref(idle), ctypes.byref(kernel), ctypes.byref(user))
    v = lambda t: (t.high << 32) | t.low  # noqa: E731
    return v(idle), v(kernel), v(user)


def cpu_load(seconds=1.0):
    """Whole-machine CPU use over `seconds`, 0..100."""
    i0, k0, u0 = _system_times()
    time.sleep(seconds)
    i1, k1, u1 = _system_times()
    total = (k1 - k0) + (u1 - u0)  # kernel time includes idle
    return 0.0 if total <= 0 else max(0.0, 100.0 * (1 - (i1 - i0) / total))


def wait_for_quiet_cpu(threshold, need_s=3, max_wait_s=600):
    """Waits until machine CPU load stays under `threshold` % for `need_s` seconds in a row."""
    start, quiet, samples, said = time.time(), 0, [], False
    while True:
        load = cpu_load(1.0)
        samples.append(load)
        quiet = quiet + 1 if load < threshold else 0
        if quiet >= need_s:
            return {"load_pct": round(statistics.mean(samples[-need_s:]), 1), "waited_s": round(time.time() - start, 1)}
        if time.time() - start > max_wait_s:
            return {"load_pct": round(statistics.mean(samples[-need_s:]), 1), "waited_s": round(time.time() - start, 1),
                    "gave_up": True}
        if not said and time.time() - start > 10:
            log(f"waiting for the CPU to calm down (now {load:.0f}%, want < {threshold}%)")
            said = True


def foreground_window():
    return ctypes.windll.user32.GetForegroundWindow()


def window_pid(hwnd):
    pid = wt.DWORD()
    ctypes.windll.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------- build

def cmd_build(args):
    worktree = os.path.abspath(args.worktree)
    out = os.path.abspath(args.out)
    slots = [os.path.join(LOCKS, f"build-slot-{i}") for i in range(1, BUILD_SLOTS + 1)]
    lock = acquire_any(slots, BUILD_STALE_S, "build slot", {"worktree": worktree, "out": out})
    try:
        log(f"building {worktree}")
        started = time.time()
        r = subprocess.run([FLUTTER, "build", "windows", "--release"], cwd=worktree, **NOWIN)
        if r.returncode != 0:
            raise SystemExit(f"flutter build failed ({r.returncode})")
        log(f"built in {time.time() - started:.0f} s")
    finally:
        lock.release()
    release = os.path.join(worktree, "build", "windows", "x64", "runner", "Release")
    fix_engine(release)
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(release, out)
    fix_engine(out)
    log(f"copied to {out}")


def fix_engine(release_dir):
    dll = os.path.join(release_dir, "flutter_windows.dll")
    want = md5(RELEASE_ENGINE)
    if md5(dll) != want:
        log(f"{dll} is not the release engine (a debug engine makes the exe exit with 'Not running in AOT mode'); replacing it")
        shutil.copyfile(RELEASE_ENGINE, dll)
    assert md5(dll) == want


# ---------------------------------------------------------------- scenarios

def load_scenarios():
    with open(SCENARIOS, encoding="utf-8") as f:
        data = json.load(f)
    items = data.get("items", {})

    def expand(value):
        if isinstance(value, str) and value.startswith("$"):
            key = value[1:]
            if key not in items:
                raise SystemExit(f"scenarios.json: unknown item {value}")
            return items[key]
        if isinstance(value, list):
            return [expand(v) for v in value]
        if isinstance(value, dict):
            return {k: expand(v) for k, v in value.items()}
        return value

    scenarios = {name: expand(s) for name, s in data["scenarios"].items() if not name.startswith("//")}
    return data, scenarios


def server_url():
    for path in (os.path.join(HERE, "local.json"), os.path.join(REPO, "tool", "marketing", "local.json")):
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                return json.load(f)["server"].rstrip("/")
    raise SystemExit("no server: put {\"server\": \"https://...\"} in tool/perf/local.json (gitignored)")


# ---------------------------------------------------------------- one run

def launch_app(exe_dir, config, config_path, timeout_s, window):
    """Starts the app with `config`, waits for it to exit, returns (output, info)."""
    exe = os.path.join(exe_dir, "chudder.exe")
    profile = config["profile_dir"]
    temp = os.path.join(profile, "temp")
    os.makedirs(temp, exist_ok=True)
    env = dict(os.environ, TEMP=temp, TMP=temp)
    fg_before = foreground_window()
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=1)
    launch_us = time.perf_counter_ns() // 1000
    config_launch_ms = int(time.time() * 1000)
    proc = subprocess.Popen([exe, f"--perf-bench={config_path}", f"--perf-launch-us={launch_us}",
                             f"--perf-window={window[0]},{window[1]}", "--skipNotifications"],
                            cwd=exe_dir, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    stolen = False
    deadline = time.time() + timeout_s
    while proc.poll() is None:
        if time.time() > deadline:
            proc.kill()  # our own process, by handle
            proc.wait()
            break
        hwnd = foreground_window()
        if hwnd and hwnd != fg_before and window_pid(hwnd) == proc.pid:
            stolen = True
        time.sleep(0.1)
    info = {"exit_code": proc.returncode, "focus_stolen": stolen, "launch_unix_ms": config_launch_ms,
            "timed_out": time.time() > deadline}
    output = None
    if os.path.exists(config["output"]):
        with open(config["output"], encoding="utf-8") as f:
            output = json.load(f)
    return output, info


def base_config(defaults, profile_dir, output, scenario_name, steps):
    config = {k: v for k, v in defaults.items() if k not in ("window", "cpu_quiet_pct", "run_timeout_s")}
    config.update({"profile_dir": profile_dir, "output": output, "scenario": scenario_name, "steps": steps,
                   "window": defaults.get("window", {"x": 3000, "y": 100, "width": 1400, "height": 900})})
    return config


def run_scenario_once(exe_dir, scenario_name, scenario, data, work_dir, screenshots=None, window=None):
    defaults = data.get("defaults", {})
    window = window or (defaults.get("window", {}).get("x", 3000), defaults.get("window", {}).get("y", 100))
    timeout_s = scenario.get("run_timeout_s", defaults.get("run_timeout_s", 150))
    if not os.path.isdir(TEMPLATE):
        raise SystemExit(f"no template profile at {TEMPLATE}: run profile-template first")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir, ignore_errors=True)
    os.makedirs(work_dir)
    profile = os.path.join(work_dir, "profile")
    shutil.copytree(TEMPLATE, profile)
    result = {"scenario": scenario_name}

    if scenario.get("profile") == "warm":
        prime_steps = scenario.get("prime") or scenario["steps"]
        config = base_config(defaults, profile, os.path.join(work_dir, "prime.json"), scenario_name + "-prime",
                             [dict(s, measure=False) for s in prime_steps])
        config["exit_delay_ms"] = 3000  # let the image cache index and preferences reach the disk
        out, info = launch_app(exe_dir, config, os.path.join(work_dir, "prime-config.json"), timeout_s, window)
        result["prime_ok"] = bool(out and out.get("ok"))
        if not result["prime_ok"]:
            result["error"] = f"prime run failed: {info} {out and out.get('error')}"
            return result

    config = base_config(defaults, profile, os.path.join(work_dir, "output.json"), scenario_name, scenario["steps"])
    if screenshots:
        config["screenshot_dir"] = screenshots
    out, info = launch_app(exe_dir, config, os.path.join(work_dir, "config.json"), timeout_s, window)
    result.update(info)
    result["output_path"] = config["output"]
    if out is None:
        result["error"] = f"no output (exit {info['exit_code']})"
        return result
    metric = scenario.get("metric")
    step = next((s for s in out.get("steps", []) if s.get("name") == metric), None)
    result["ok"] = bool(out.get("ok"))
    if out.get("error"):
        result["error"] = out["error"][:500]
    if step is None:
        result["error"] = result.get("error") or f"no step named {metric}"
        return result
    result["ready_ms"] = step.get("ready_ms")
    result["first_frame_ms"] = step.get("first_frame_ms")
    result["requests"] = step.get("requests")
    result["response_bytes"] = step.get("response_bytes")
    result["images_loaded"] = step.get("images_loaded")
    result["step_timed_out"] = step.get("timed_out")
    result["startup"] = out.get("startup")
    result["outside_profile_paths"] = out.get("outside_profile_paths")
    result["view"] = out.get("view")
    result["frame_pacing"] = out.get("frame_pacing")
    if step.get("timed_out") or step.get("error"):
        result["error"] = result.get("error") or f"step {metric} timed out: {step.get('waiting_on')}"
    return result


# ---------------------------------------------------------------- statistics

def median(values):
    return statistics.median(values) if values else None


def bootstrap_delta_ci(a, b, n=4000, seed=7):
    rng = random.Random(seed)
    deltas = []
    for _ in range(n):
        ma = statistics.median(rng.choices(a, k=len(a)))
        mb = statistics.median(rng.choices(b, k=len(b)))
        deltas.append(100.0 * (mb - ma) / ma if ma else 0.0)
    deltas.sort()
    return deltas[int(0.025 * n)], deltas[int(0.975 * n)]


def paired_deltas(runs_a, runs_b):
    """Per-round (B - A) / A in %, for rounds where both runs have a value. A and B run next to each
    other in every round, so this cancels drift that is slower than a round (the server getting busy)."""
    a = {r["round"]: r["ready_ms"] for r in runs_a if r.get("ready_ms") is not None and not r.get("error")}
    b = {r["round"]: r["ready_ms"] for r in runs_b if r.get("ready_ms") is not None and not r.get("error")}
    return [100.0 * (b[k] - a[k]) / a[k] for k in sorted(a) if k in b and a[k]]


def bootstrap_median_ci(values, n=4000, seed=11):
    rng = random.Random(seed)
    meds = sorted(statistics.median(rng.choices(values, k=len(values))) for _ in range(n))
    return meds[int(0.025 * n)], meds[int(0.975 * n)]


def spread_pct(values):
    """(p90 - p10) / median, in %."""
    if len(values) < 3:
        return None
    s = sorted(values)
    p = lambda q: s[min(len(s) - 1, max(0, round((len(s) - 1) * q)))]  # noqa: E731
    return 100.0 * (p(0.9) - p(0.1)) / statistics.median(s)


def flag_noisy(runs, cpu_limit):
    values = [r["ready_ms"] for r in runs if r.get("ready_ms") is not None and not r.get("error")]
    med = median(values)
    mad = median([abs(v - med) for v in values]) if values else None
    for r in runs:
        reasons = []
        if r.get("error"):
            reasons.append("error")
        if r.get("cpu", {}).get("load_pct", 0) >= cpu_limit or r.get("cpu", {}).get("gave_up"):
            reasons.append("cpu")
        if r.get("focus_stolen"):
            reasons.append("focus")
        if r.get("ready_ms") is not None and mad and abs(r["ready_ms"] - med) > 4 * max(mad, 0.02 * med):
            reasons.append("outlier")
        r["noisy"] = reasons


# ---------------------------------------------------------------- run / ab

def resolve_scenarios(names, scenarios):
    if names in ("all", None):
        return list(scenarios)
    out = []
    for name in names.split(","):
        name = name.strip()
        if name.endswith("*"):
            out += [s for s in scenarios if s.startswith(name[:-1])]
        elif name in scenarios:
            out.append(name)
        else:
            raise SystemExit(f"unknown scenario {name}; see `perfbench.py list`")
    return out


def bench_lock(label):
    return acquire_any([os.path.join(LOCKS, "bench")], BENCH_STALE_S, "bench lock", {"label": label, "cwd": os.getcwd()})


def one(exe_dir, name, scenario, data, run_root, tag, cpu_threshold, screenshots=None, window=None, keep=False):
    cpu = wait_for_quiet_cpu(cpu_threshold)
    started = time.time()
    work = os.path.join(run_root, tag)
    r = run_scenario_once(exe_dir, name, scenario, data, work, screenshots=screenshots, window=window)
    r["cpu"] = cpu
    r["wall_s"] = round(time.time() - started, 1)
    # Keep the app's own output (request lists) next to the results; drop the profile.
    out_path = r.get("output_path")
    if out_path and os.path.exists(out_path):
        dest = os.path.join(run_root, f"{tag}.json")
        shutil.copyfile(out_path, dest)
        r["output_path"] = dest
    if not keep:
        shutil.rmtree(work, ignore_errors=True)
    return r


def cmd_run(args):
    data, scenarios = load_scenarios()
    names = resolve_scenarios(args.scenarios, scenarios)
    exe = os.path.abspath(args.exe)
    label = args.label or "run"
    stamp = time.strftime("%Y%m%d-%H%M%S")
    run_root = os.path.join(RUNS, f"{label}-{stamp}")
    cpu_threshold = data.get("defaults", {}).get("cpu_quiet_pct", 20)
    window = tuple(int(v) for v in args.window.split(",")) if args.window else None
    lock = bench_lock(label)
    results = {name: [] for name in names}
    try:
        for round_index in range(args.runs + (0 if args.no_warmup else 1)):
            for name in names:
                tag = f"{name}-r{round_index}"
                r = one(exe, name, scenarios[name], data, run_root, tag, cpu_threshold, window=window, keep=args.keep)
                r["round"] = round_index
                r["warmup"] = round_index == 0 and not args.no_warmup
                results[name].append(r)
                log(f"{tag}: ready {r.get('ready_ms')} ms, requests {r.get('requests')}, cpu {r['cpu']['load_pct']}%"
                    + (f"  ERROR {r['error']}" if r.get("error") else ""))
    finally:
        lock.release()
    summary = {}
    for name, runs in results.items():
        measured = [r for r in runs if not r.get("warmup")]
        flag_noisy(measured, cpu_threshold)
        values = [r["ready_ms"] for r in measured if r.get("ready_ms") is not None and not r.get("error")]
        summary[name] = {"median_ms": median(values), "spread_pct": spread_pct(values), "n": len(values),
                         "requests_median": median([r["requests"] for r in measured if r.get("requests") is not None]),
                         "values": values}
    out = {"label": label, "timestamp": stamp, "exe": exe, "summary": summary, "runs": results}
    path = args.output or os.path.join(RESULTS, f"{label}-{stamp}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print()
    print(f"{'scenario':<24}{'median ms':>11}{'spread %':>10}{'n':>4}{'requests':>10}")
    for name, s in summary.items():
        sp = "-" if s["spread_pct"] is None else f"{s['spread_pct']:.1f}"
        md = "-" if s["median_ms"] is None else f"{s['median_ms']:.0f}"
        print(f"{name:<24}{md:>11}{sp:>10}{s['n']:>4}{str(s['requests_median']):>10}")
    print(f"\nwrote {path}")


def cmd_ab(args):
    data, scenarios = load_scenarios()
    names = resolve_scenarios(args.scenarios, scenarios)
    builds = {"A": os.path.abspath(args.a), "B": os.path.abspath(args.b)}
    for exe in builds.values():
        if not os.path.exists(os.path.join(exe, "chudder.exe")):
            raise SystemExit(f"no chudder.exe in {exe}")
        fix_engine(exe)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    label = args.label
    run_root = os.path.join(RUNS, f"{label}-{stamp}")
    cpu_threshold = data.get("defaults", {}).get("cpu_quiet_pct", 20)
    runs = {name: {"A": [], "B": []} for name in names}
    lock = bench_lock(label)
    try:
        # One warm-up round, discarded, then ABBA: A before B on even rounds, B before A on odd ones.
        for round_index in range(-1, args.runs):
            order = ("A", "B") if round_index % 2 == 0 else ("B", "A")
            for name in names:
                for build in order:
                    tag = f"{name}-{build}-r{round_index + 1}"
                    r = one(builds[build], name, scenarios[name], data, run_root, tag, cpu_threshold)
                    r["round"] = round_index
                    r["build"] = build
                    if round_index >= 0:
                        runs[name][build].append(r)
                    log(f"{tag}{' (warm-up)' if round_index < 0 else ''}: ready {r.get('ready_ms')} ms, "
                        f"requests {r.get('requests')}, cpu {r['cpu']['load_pct']}%"
                        + (f"  ERROR {r['error']}" if r.get("error") else ""))
    finally:
        lock.release()

    summary = {}
    for name in names:
        for build in ("A", "B"):
            flag_noisy(runs[name][build], cpu_threshold)
        va = [r["ready_ms"] for r in runs[name]["A"] if r.get("ready_ms") is not None and not r.get("error")]
        vb = [r["ready_ms"] for r in runs[name]["B"] if r.get("ready_ms") is not None and not r.get("error")]
        s = {"median_a": median(va), "median_b": median(vb), "n_a": len(va), "n_b": len(vb),
             "spread_a_pct": spread_pct(va), "spread_b_pct": spread_pct(vb),
             "requests_a": median([r["requests"] for r in runs[name]["A"] if r.get("requests") is not None]),
             "requests_b": median([r["requests"] for r in runs[name]["B"] if r.get("requests") is not None]),
             "noisy_a": sum(1 for r in runs[name]["A"] if r["noisy"]),
             "noisy_b": sum(1 for r in runs[name]["B"] if r["noisy"])}
        if va and vb and s["median_a"]:
            s["delta_pct"] = 100.0 * (s["median_b"] - s["median_a"]) / s["median_a"]
            s["ci95_pct"] = bootstrap_delta_ci(va, vb) if len(va) >= 3 and len(vb) >= 3 else None
        paired = paired_deltas(runs[name]["A"], runs[name]["B"])
        if paired:
            s["paired_deltas_pct"] = [round(d, 2) for d in paired]
            s["paired_delta_pct"] = statistics.median(paired)
            s["paired_ci95_pct"] = bootstrap_median_ci(paired) if len(paired) >= 3 else None
        summary[name] = s
    out = {"label": label, "timestamp": stamp, "a": builds["A"], "b": builds["B"], "runs_per_build": args.runs,
           "summary": summary, "runs": runs}
    path = os.path.join(RESULTS, f"{label}-{stamp}.json")
    os.makedirs(RESULTS, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print()
    print_ab_table(summary)
    print(f"\nwrote {path}")


def print_ab_table(summary):
    """Medians and their delta with a bootstrap CI; then the same from per-round pairs (each round runs A
    and B back to back), which is the tighter number when the server's speed drifts during a batch."""
    print(f"{'scenario':<22}{'A ms':>8}{'B ms':>8}{'delta %':>9}{'95% CI %':>17}"
          f"{'paired %':>10}{'paired CI %':>17}{'req A/B':>10}{'noisy A/B':>11}")
    fmt = lambda v: "-" if v is None else f"{v:.0f}"  # noqa: E731
    ci = lambda c: "-" if not c else f"[{c[0]:+.1f}, {c[1]:+.1f}]"  # noqa: E731
    for name, s in summary.items():
        delta = "-" if s.get("delta_pct") is None else f"{s['delta_pct']:+.1f}"
        paired = "-" if s.get("paired_delta_pct") is None else f"{s['paired_delta_pct']:+.1f}"
        print(f"{name:<22}{fmt(s['median_a']):>8}{fmt(s['median_b']):>8}{delta:>9}{ci(s.get('ci95_pct')):>17}"
              f"{paired:>10}{ci(s.get('paired_ci95_pct')):>17}"
              f"{fmt(s['requests_a']) + '/' + fmt(s['requests_b']):>10}{str(s['noisy_a']) + '/' + str(s['noisy_b']):>11}")


def cmd_table(args):
    with open(args.results, encoding="utf-8") as f:
        data = json.load(f)
    if "a" in data:
        print_ab_table(data["summary"])
    else:
        for name, s in data["summary"].items():
            print(f"{name:<24}{s['median_ms']!s:>10}{s['spread_pct']!s:>24}{s['n']:>4}")


# ---------------------------------------------------------------- template / validate / discover

def cmd_profile_template(args):
    data, _ = load_scenarios()
    defaults = data.get("defaults", {})
    exe = os.path.abspath(args.exe)
    fix_engine(exe)
    work = os.path.join(PROFILES, "template-build")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    profile = os.path.join(work, "profile")
    steps = [
        {"action": "launch", "name": "login-screen", "expect_route": "LoginRoute", "measure": False},
        {"action": "login", "name": "login", "expect_route": "DashboardRoute", "measure": False},
        {"action": "set_up_profile", "name": "settings", "measure": False},
        {"action": "sleep", "ms": 1500},
    ]
    config = base_config(defaults, profile, os.path.join(work, "output.json"), "profile-template", steps)
    config["login"] = {"server": server_url(), "username": args.username, "password": args.password}
    config["exit_delay_ms"] = 2500
    lock = bench_lock("profile-template")
    try:
        out, info = launch_app(exe, config, os.path.join(work, "config.json"), 120,
                               (defaults.get("window", {}).get("x", 3000), defaults.get("window", {}).get("y", 100)))
    finally:
        lock.release()
        # The config holds the password; the output does not.
        try:
            os.remove(os.path.join(work, "config.json"))
        except OSError:
            pass
    if not out or not out.get("ok"):
        raise SystemExit(f"template run failed: {info} {json.dumps(out)[:2000] if out else ''}")
    prefs = os.path.join(profile, "support", "shared_preferences.json")
    if not os.path.exists(prefs):
        raise SystemExit("template run left no shared_preferences.json")
    # Credentials and settings only: no image cache, no database, no logs.
    shutil.rmtree(TEMPLATE, ignore_errors=True)
    os.makedirs(os.path.join(TEMPLATE, "support"))
    shutil.copyfile(prefs, os.path.join(TEMPLATE, "support", "shared_preferences.json"))
    shutil.rmtree(work, ignore_errors=True)
    log(f"template profile ready at {TEMPLATE}")


def cmd_validate(args):
    data, scenarios = load_scenarios()
    names = resolve_scenarios(args.scenarios, scenarios)
    exe = os.path.abspath(args.exe)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    root = os.path.join(RUNS, f"validate-{stamp}")
    shots = os.path.join(root, "shots")
    cpu_threshold = data.get("defaults", {}).get("cpu_quiet_pct", 20)
    lock = bench_lock("validate")
    report = []
    try:
        for name in names:
            r = one(exe, name, scenarios[name], data, root, name, cpu_threshold, screenshots=shots)
            with open(r["output_path"], encoding="utf-8") if r.get("output_path") else open(os.devnull) as f:
                out = json.load(f) if r.get("output_path") else {}
            for step in out.get("steps", []):
                if step.get("screenshot_ready") or step.get("screenshot_difference") is not None:
                    report.append({"scenario": name, "step": step["name"], "ready_ms": step.get("ready_ms"),
                                   "pixel_ready_ms": step.get("pixel_ready_ms"),
                                   "detected_ms": step.get("detected_ms"), "difference": step.get("screenshot_difference"),
                                   "ready": step.get("screenshot_ready"), "later": step.get("screenshot_later")})
                    log(f"{name}/{step['name']}: ready {step.get('ready_ms')} ms, last pixel change "
                        f"{step.get('pixel_ready_ms')} ms, ready vs +1500 ms difference {step.get('screenshot_difference')}")
            if r.get("error"):
                log(f"{name}: ERROR {r['error']}")
    finally:
        lock.release()
    with open(os.path.join(root, "validate.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)
    try:
        from PIL import Image, ImageDraw
        rows = [r for r in report if r.get("ready") and r.get("later")]
        if rows:
            w, h = Image.open(rows[0]["ready"]).size
            sheet = Image.new("RGB", (w * 2 + 10, (h + 24) * len(rows)), (40, 40, 40))
            d = ImageDraw.Draw(sheet)
            for i, r in enumerate(rows):
                y = i * (h + 24)
                d.text((4, y + 4), f"{r['scenario']}/{r['step']}  ready {r['ready_ms']} ms  last pixel change {r['pixel_ready_ms']} ms  diff {r['difference']:.4f}"
                       "   (left: at ready, right: ready + 1500 ms)", fill=(255, 255, 0))
                sheet.paste(Image.open(r["ready"]).convert("RGB"), (0, y + 24))
                sheet.paste(Image.open(r["later"]).convert("RGB"), (w + 10, y + 24))
            sheet_path = os.path.join(root, "contact-sheet.png")
            sheet.save(sheet_path)
            log(f"contact sheet {sheet_path}")
    except ImportError:
        pass
    log(f"wrote {os.path.join(root, 'validate.json')}")


def cmd_list(args):
    data, scenarios = load_scenarios()
    for name, s in scenarios.items():
        print(f"{name:<24}{s.get('profile', 'cold'):<6}{s.get('description', '')}")
    print("\nnot on the demo server:", ", ".join(data.get("missing_item_types", [])))


def cmd_discover(args):
    server = server_url()
    auth = 'MediaBrowser Client="Chudder perfbench", Device="perfbench", DeviceId="chudder-perfbench-discover", Version="1"'

    def req(path, data=None, token=None, **q):
        url = server + path + ("?" + urllib.parse.urlencode(q) if q else "")
        headers = {"Authorization": auth + (f', Token="{token}"' if token else ""), "Content-Type": "application/json"}
        body = json.dumps(data).encode() if data is not None else None
        with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers,
                                                           method="POST" if body else "GET"), timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}

    session = req("/Users/AuthenticateByName", {"Username": args.username, "Pw": args.password})
    token, user = session["AccessToken"], session["User"]["Id"]
    for view in req("/UserViews", token=token, userId=user)["Items"]:
        print(f"library   {view['Id']}  {view['Name']} ({view.get('CollectionType')})")
    for kind in ["Movie", "Series", "Season", "Episode", "Person", "BoxSet", "Playlist", "MusicAlbum", "MusicArtist",
                 "Audio", "Book", "AudioBook", "Photo", "PhotoAlbum", "Folder", "TvChannel", "MusicVideo", "Video",
                 "Trailer", "Studio", "Genre"]:
        r = req("/Items", token=token, userId=user, IncludeItemTypes=kind, Recursive="true", Limit="3")
        sample = ", ".join(f"{i['Id']} {i['Name']}" for i in r["Items"])
        print(f"{kind:<12}{r.get('TotalRecordCount', 0):>5}  {sample}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("build")
    p.add_argument("--worktree", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_build)
    p = sub.add_parser("profile-template")
    p.add_argument("--exe", required=True)
    p.add_argument("--username", default="demo")
    p.add_argument("--password", default="demo")
    p.set_defaults(func=cmd_profile_template)
    p = sub.add_parser("run")
    p.add_argument("--exe", required=True)
    p.add_argument("--scenarios", default="all")
    p.add_argument("--runs", type=int, default=5)
    p.add_argument("--label")
    p.add_argument("--output")
    p.add_argument("--window", help="x,y in physical pixels (default: off screen, from scenarios.json)")
    p.add_argument("--no-warmup", action="store_true")
    p.add_argument("--keep", action="store_true", help="keep each run's profile directory")
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("ab")
    p.add_argument("--a", required=True)
    p.add_argument("--b", required=True)
    p.add_argument("--scenarios", default="all")
    p.add_argument("--runs", type=int, default=8)
    p.add_argument("--label", required=True)
    p.set_defaults(func=cmd_ab)
    p = sub.add_parser("validate")
    p.add_argument("--exe", required=True)
    p.add_argument("--scenarios", default="all")
    p.set_defaults(func=cmd_validate)
    p = sub.add_parser("table", help="print the table of a results file again")
    p.add_argument("results")
    p.set_defaults(func=cmd_table)
    p = sub.add_parser("list")
    p.set_defaults(func=cmd_list)
    p = sub.add_parser("discover")
    p.add_argument("--username", default="demo")
    p.add_argument("--password", default="demo")
    p.set_defaults(func=cmd_discover)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
