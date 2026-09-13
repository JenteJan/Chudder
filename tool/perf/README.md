# Load-time benchmark

Measures how long Chudder's Windows release build takes to show what a person asked for - the home
dashboard after launch, a film's page after its card is pressed, search results, playback - and
compares two builds of it. Built to prove small (5 %) improvements while several agents work on the
same PC, and while someone uses that PC.

The app measures itself. Started with `--perf-bench=<config.json>` it runs a scripted scenario from
the inside (`lib/perf_bench`), decides when each step is visually complete, writes a JSON file and
exits. `tool/perf/perfbench.py` builds, prepares profiles, launches one run at a time and does the
statistics. Nothing is recorded from the screen and no input goes into Windows, so runs can happen
off-screen while the PC is in use. (The older `tool/marketing/bench/bench.py` compares Chudder with
Jellyfin Web from screen recordings; it cannot run alongside anything else.)

Everything shared lives in `C:\Users\jente\Development\FladderFork\perf-artifacts`:

| path | what |
| --- | --- |
| `baseline\Release` | the shared build A: perf/base with the harness. Do not change it. |
| `results\baseline.json` | every scenario on the baseline |
| `results\<label>-<time>.json` | results of `run` and `ab` |
| `runs\<label>-<time>\` | each run's own output (request lists, frame counts), and screenshots of `validate` |
| `profiles\template-demo` | signed-in profile the runs start from (credentials and settings only) |
| `locks\` | build slots and the bench lock |
| `builds\` | a good place for your own `build --out` |

The demo server's address comes from `tool/marketing/local.json` or `tool/perf/local.json`
(`{"server": "https://..."}`, both gitignored). It never goes into anything committed.

## Commands

Python 3, standard library only (Pillow, when installed, makes the `validate` contact sheet).
Flutter is always `C:\Users\jente\fvm\versions\3.44.9\bin\flutter`.

```
# Build a worktree and copy the Release folder out of it (takes a build slot; at most 2 builds at once)
python tool/perf/perfbench.py build --worktree C:\...\my-worktree --out C:\...\perf-artifacts\builds\my-change

# Compare against the baseline: interleaved ABBA, one discarded warm-up round, holds the bench lock
python tool/perf/perfbench.py ab --a C:\...\perf-artifacts\baseline\Release --b C:\...\perf-artifacts\builds\my-change ^
    --scenarios open-movie,open-series --runs 10 --label my-change

# One build on its own
python tool/perf/perfbench.py run --exe C:\...\perf-artifacts\builds\my-change --scenarios start-cold --runs 10

# Check the readiness detector by eye: a picture at the detected ready moment and 1500 ms later
python tool/perf/perfbench.py validate --exe C:\...\builds\my-change --scenarios open-movie

python tool/perf/perfbench.py list                         # scenarios, and item types the server lacks
python tool/perf/perfbench.py discover                     # item ids per type on the demo server
python tool/perf/perfbench.py profile-template --exe ...   # re-create the signed-in template profile
```

`--scenarios` takes names, `all`, or a prefix with `*` (`open-*`).

`ab` prints, per scenario: median A, median B, the delta in %, a bootstrap 95 % confidence interval
of that delta, median request counts, and how many runs were flagged noisy (an error, the CPU busy
before the run, the window taking focus, or an outlier beyond 4 MADs). A change is real when the
whole interval is on one side of zero. Every run's raw output is kept under `runs\`: open two of
them to see which requests changed.

Before each run the driver waits (up to 10 minutes) until the whole machine's CPU has stayed under
20 % for three seconds - other agents may be compiling - and records the load it started at.

## Locks

Both kinds are directories created with `os.mkdir` (atomic), holding an `owner.json` with pid, host,
worktree/label and start time that the holder rewrites every 30 s.

* `locks\build-slot-1`, `locks\build-slot-2`: one per running release build. Stale after 45 minutes
  without a heartbeat, or when the owner's process is gone.
* `locks\bench`: held for a whole `run`, `ab`, `validate` or `profile-template` batch, so only one
  benchmark runs at a time. Stale after 30 minutes without a heartbeat, or when the owner is gone.

A waiting command retries with backoff and prints who holds the lock once a minute. Do not delete a
lock by hand unless its owner is really gone.

Builds are fine during someone else's benchmark (the CPU wait absorbs them); a benchmark during
someone's build waits for the CPU.

## What a run is

1. A fresh copy of `profiles\template-demo` (its own `shared_preferences.json`: the demo login with
   a device id of its own, update checks off, player volume 0). Warm scenarios first run the
   scenario once in that profile, unmeasured, to fill its disk caches, then measure a second process.
2. `chudder.exe --perf-bench=config.json --perf-launch-us=<QPC µs> --perf-window=3000,100
   --skipNotifications`, with `TEMP`/`TMP` pointed into the profile. The launch time is
   QueryPerformanceCounter read just before the process is created; Dart's monotonic clock reads the
   same counter (checked: the wall-clock difference agrees within 1 ms).
3. The app runs the steps, writes `output.json`, and exits. The driver kills it (by handle) after
   `run_timeout_s`.

### Isolation (what bench mode changes, all in `lib/perf_bench` unless noted)

* **Every directory** path_provider hands out - documents, support, cache, temp, downloads - is under
  the profile (`bench_paths.dart`), and so is shared_preferences, which keeps a
  `PathProviderWindows` of its own and is handed the bench one. That covers the drift database, the
  image disk cache (`flutter_cache_manager`), crash and cast logs, background_downloader's store and
  `Directory.systemTemp`. An `IOOverrides` audit lists every `File`/`Directory` the app creates
  outside the profile and its own install folder in `outside_profile_paths` (in practice only
  `/system/fonts/VivoFont.ttf`, an existence check by chinese_font_library). Checked by hand: the
  real `AppData\Local|Roaming\JenteJan\chudder` never receives the bench device id.
* **Window** (`windows/runner/main.cpp`, `win32_window.cpp`, `lib/util/window_helper.dart`): created
  with `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW` at physical (3000, 100) - right of every monitor on
  this PC - shown with `SW_SHOWNOACTIVATE`, never `show()`n or `focus()`ed by window_manager, not on
  the taskbar, client area sized to exactly 1400 x 900 logical pixels (device pixel ratio 1.25 there,
  from the nearest monitor). The driver watches the foreground window during every run and flags a
  run whose window took it; none has.
* **Media session** (`lib/wrappers/media_control_wrapper.dart`): no SMTC session, so a play scenario
  cannot take the media keys or the Windows media overlay from what the person at the PC plays.
* **Notifications**: `--skipNotifications` (existing flag).
* **Update checks**: off in the template profile (they call GitHub, which rate-limits per IP).
* **Playback reports** (`POST /Sessions/Playing*`) are sent to `POST /System/Ping` instead - a real
  round trip of the same size that changes nothing - so play scenarios do not move the demo
  account's resume points. Configurable as `rewrite_requests` in `scenarios.json`.
* **Text cursor**: stays lit instead of blinking (`EditableText.debugDeterministicCursor`). A blink
  is a repaint every 500 ms that nothing else asked for, and would keep a search step from settling.
* Not needed: there is no single-instance guard, no protocol registration at runtime, no local
  server until you cast (cast/DLNA discovery only runs from the cast picker). Server pushes go by
  device id, and each profile has its own.

Without `--perf-bench` none of this exists: `PerfBench.startIfRequested` returns at once, `wrap`
returns the app unchanged, the stock binding is used, and the runner creates the window exactly as
before.

### Window strategy

Off-screen, not minimised: a minimised or hidden window changes the app lifecycle and stops frames.
Tested against a visible window at (700, 250) on the 239 Hz primary monitor, alternating
off/on/off/on with 3 runs each:

| scenario | off-screen median | visible median | frame gap p50 off / on |
| --- | --- | --- | --- |
| start-cold | 1527, 1658 ms | 1555, 1511 ms | 4.4-4.5 ms / 4.5-4.7 ms |
| open-movie | 1126, 1118 ms | 1116, 1126 ms | 4.1-4.2 ms / 4.1-4.2 ms |
| tab-search | 960, 951 ms | 945, 957 ms | 4.3-4.5 ms / 4.2-4.5 ms |

Frames come at the primary monitor's refresh rate either way and the numbers are the same within
noise. Every output has `frame_pacing` (frame gap and build-to-raster percentiles) to spot a
throttled window.

## Readiness: when a step is done

A step is **ready** at the raster-finish time (from the engine's `FrameTiming`) of the **last content
frame**, detected once all of these have held together for `quiet_ms` (450 ms):

* no content frame and no animation starting or stopping;
* no HTTP request in flight or finishing - every `dart:io` `HttpClient` is wrapped through
  `HttpOverrides`, which covers `package:http`'s IOClient, chopper, flutter_cache_manager,
  extended_image and `WebSocket.connect` (a websocket counts until its upgrade). A response whose
  body nobody starts reading within 300 ms counts as done (the image cache drops 404 bodies). The
  players fetch media natively and are not seen;
* no image the image cache is still loading or decoding (`ImageCache.putIfAbsent` is wrapped);
* the step's own condition, e.g. `expect_route` (the top route's name);
* no animation running - unless the running animations have not changed for 2 s, which is taken to
  mean they never end (a spinner, a shimmer);

and then an element-tree walk finds no **visible loading indicator**: an indeterminate
`ProgressIndicator`, or a widget named in `loading_widgets` (`Shimmer`, `ShimmerPosterRow`,
`ShimmerBox`), that is laid out, painted by every ancestor (`paintsChild`), not in an `Offstage`,
hidden `Visibility` or muted `TickerMode`, and on screen. A step whose spinner never goes away
times out (`step_timeout_ms`, 30 s) and says what it was waiting on.

A **content frame** is a frame something other than a running animation asked for. The bench
binding (`bench_binding.dart`) marks a frame content when `scheduleFrame` was called between frames
(a setState from a response, an image arriving, a scroll, a navigation, a timer) rather than by a
ticker during the frame, or when an animation ended on it (fewer transient callbacks after the frame
than before: the last frame of a fade or a page transition). Frames that only move an animation
along are not content, so an endless spinner never holds a step open by itself, and a finite fade
(FadeInImage's 1 s on the details backdrop) holds it until its last frame.

Each step also reports `first_frame_ms` (the first frame after the action), `detected_ms`,
`requests`, `response_bytes`, `images_loaded`, and `request_list` (method, path without host or
ApiKey/token, status, start/end ms, bytes). Startup reports `main_ms` and `first_frame_ms` from the
launch; the launch step's `ready_ms` is home ready from the launch.

Play steps use the player instead: ready is the first player state that is playing with the position
advancing at the pace of the clock (a seek to the resume point is a jump, not movement);
`advanced_1s_ms` is when a second has played.

### Validation

`validate` runs scenarios with screenshots (a layer capture of the whole app at 0.5x): the frame of
the last content frame (the ready moment) and a capture 1500 ms after it, a pixel difference (share
of pixels that moved more than 8 in a channel), and a contact sheet
(`runs\validate-<time>\contact-sheet.png`). It also checks the detector from the other side: every
content frame is captured and compared with the capture before it, and `pixel_ready_ms` is the last
one that changed any pixels. `ready_ms` earlier than `pixel_ready_ms` would be a false early (never
seen); later means the last content frame(s) changed nothing visible at 0.5x - the end of an eased
fade, or a rebuild to the same picture. All scenarios were checked by eye; every pair is identical
(difference 0.0), and `pixel_ready_ms` equals `ready_ms` except start-cold/start-warm (190-240 ms
earlier: the dashboard's image fades ending), search-few (70 ms) and back-home/tab-library (< 15 ms).
What validation found and fixed:

* False early on every details page: the backdrop's `FadeInImage` fades for a second after its image
  has loaded, entirely on a ticker. Fixed by treating a running animation as activity until it ends
  or has run unchanged for 2 s.
* Search and the Search tab kept settling late and at random: the focused field's blinking cursor.
  Fixed with the steady cursor.
* A request that never ended: the image cache does not read the body of the demo user's missing
  avatar (404). Fixed with the 300 ms unread-body rule.
* Hidden tabs' spinners counted as visible: `IndexedStack` hides children through `Visibility`,
  whose render object does not implement `paintsChild`. Fixed at the widget level
  (`test/perf_bench_test.dart`).

Screenshot runs capture on every content frame, which costs time: their numbers are not comparable.

## Noise

To be measured on the baseline.

## Scenarios

Run `perfbench.py list`. Ids are in `scenarios.json` under `items` (with names under `item_notes`);
`$movie` in a step means that item.

On the demo server there are no: playlist, photo, photo album, live TV channel or programme, music
video, audiobook, trailer, home video. Genres open an empty page and are not a scenario.

## Adding a scenario

Add an entry to `scenarios.json`:

```json
"open-something": {
  "description": "home ready -> something's page ready",
  "profile": "cold",
  "metric": "open",
  "steps": [
    {"action": "launch", "name": "home", "expect_route": "DashboardRoute", "measure": false},
    {"action": "open_item", "name": "open", "id": "$something", "expect_route": "DetailsRoute"}
  ]
}
```

* `profile`: `cold` (fresh template copy) or `warm` (an unmeasured run of `prime` - or of the same
  steps - in the same profile first).
* `metric`: the step whose `ready_ms` is the scenario's number.
* Every step after the first starts from a quiet app (the detector is run once, unmeasured).
* `"measure": false` still waits for the step to be ready; `"wait": false` too does not.

Actions (`lib/perf_bench/bench_steps.dart`):

| action | fields | does |
| --- | --- | --- |
| `launch` | `expect_route` | timed from process launch |
| `wait_ready` | `expect_route` | waits for readiness from now |
| `sleep` | `ms` | |
| `open_item` | `id` | fetches the item (untimed), then `item.navigateTo` on the top stack: a card tap, prefetch included |
| `push` | `route` (`DetailsRoute`, `LibrarySearchRoute`), `args` | pushes on the top stack |
| `tab` | `tab` (`dashboard`, `library`, `favorites`, `search`, ...) | `showHomeTab` |
| `back` | | `maybePopTop` |
| `type` | `text`, `char_delay_ms` (90), `submit` (true), `measure_from` (`submit` or `first_key`) | types into the focused field through `EditableTextState.updateEditingValue`, a character at a time, then `performAction` |
| `scroll` | `to` (`end` or pixels) | jumps the largest visible vertical scrollable |
| `tap` | `widget` (type name), `index`, `ready: "player"` | a synthetic mouse click in the widget's centre through `GestureBinding` |
| `login` | | the template's sign-in through `authProvider` |
| `set_up_profile` | | the template's settings |

A new action is a `case` in `BenchStepRunner.prepare`: do the untimed setup there, return the timed
part as a closure that returns `Performed` (optionally a `condition` the detector must also see
hold). Keep app hooks outside `lib/perf_bench` to a minimum.

Check a new scenario with `validate` before trusting it, and run it a few times with `run` to see
its spread.

## Known gaps

To be written after the baseline runs.
