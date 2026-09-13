# Marketing captures

Scripts for the README screenshots and the showcase video. Everything they
produce - raw takes, frames, renders - lands in `out/`, which is gitignored.
Only finished assets are copied into `assets/marketing/`.

Shot on a demo Jellyfin server stocked with the Blender Studio open movies
(CC BY) and public-domain classics. Its address goes in `local.json` here,
which is gitignored too:

```json
{ "server": "https://your-demo-server" }
```

Keep real server addresses out of everything committed, captured or published.
The release build must be signed in to the demo account before shooting.

## Scripts

| Script | What it does |
| --- | --- |
| `drive.ps1 -Keys "..."` | Brings the Chudder window forward and plays a sequence: SendKeys tokens (`{DOWN}`, `{ENTER}`), `click:x,y`, `move:x,y`, `wheel:x,y,steps`, `type:text`, `paste:text`, `space`, `waitMS`. Coordinates are physical pixels. Logs `T <seconds> <step>` per step. |
| `window.ps1 -W -H [-X -Y]` | Moves and sizes the window (physical pixels, border included) and prints the client size. `-Maximize` restores it afterwards. |
| `grab.sh <name> [WxH]` | One frame of the window by handle into `out/shots/`, optionally Lanczos-scaled. |
| `take.sh <name> <s> "<keys>"` | Records the window for `s` seconds while `drive.ps1` plays the keys; frames go to `out/fr/<name>/`. |
| `tvlaunch.ps1` | Starts the release build with `--htpc`, full screen on the primary monitor. |
| `taskbar.ps1 -Show 0/1` | Hides or shows the taskbar, so clicks near the bottom of the screen don't open Windows search. |
| `web.py <command>` | Drives the web build (`build/web`, served on :8765) in headless Chrome: `start`, `size W H [touch]`, `click`, `type`, `key`, `wheel`, `eval`, `wait-images`, `shot <name> [WxH]`, `stop`. Renders at 2x. Its Chrome profile in `out/chrome` keeps the login. |
| `open_details.py <id> [backdrop]` | Opens an item's page in the web build, retrying until it picks the wanted backdrop (the app picks one at random). |
| `hold_viewport.py W H` | Keeps a phone-sized viewport while it runs; headless Chrome won't size a window below about 500 px. |
| `demo.py <path> [k=v ...]` | Small client for the demo server (`set_position()` leaves a film part-watched so it offers Resume). |

## Screenshots

`assets/marketing/screenshots/<Device>/<name>.png`. Desktop, tablet and phone
come from the web build in headless Chrome (no window buttons, and nobody's
mouse); the television from the release build with `--htpc`, shot at 2560x1440
on the primary monitor and scaled down.

| Device | Size | How | Shots |
| --- | --- | --- | --- |
| Desktop | 1600x1000 | `web.py size 1600 1000` | dashboard, show (Bonanza), film (Charge, backdrop 1), search ("Metropolus"), library (Movies), settings ("cache") |
| Tablet | 1194x834 | `web.py size 1194 834 touch` | dashboard, show, film |
| Mobile | 424x918 | `hold_viewport.py 424 918` in the background | dashboard, show, film |
| Television | 1920x1080 | `tvlaunch.ps1`, `drive.ps1` arrow keys, `grab.sh <name> 1920x1080` | dashboard, show, film |

Layout follows the logical window width: phone below 600, tablet 600-1919,
desktop 1920-2560.

## Gotchas

- Grab by window handle, never by title (titles carry non-ASCII separators) or
  screen region (that shows whatever window is on top).
- Hide the mouse in grabs (`-draw_mouse 0`); nudge it mid-take when the player
  controls need to stay up, since they hide about 5 s after the last move.
- On a television, focus rings only show in d-pad mode: press an arrow key after
  any mouse use. Enter on a hero card or Continue Watching poster plays the item;
  the library grid opens its page. Escape stops playback.
- A detail page keeps the progress it fetched; open it fresh after
  `demo.py`'s `set_position()` or it will not offer Resume.
- Park the web pointer on an empty spot (`web.py move 20 760`) before a shot, or a
  hover tooltip or highlight ends up in it. A key press puts the app in d-pad
  mode and draws focus rings; reload the page to clear that.
- After a new `flutter build web`, clear the browser cache and service worker,
  or Chrome keeps serving the previous bundle.
- Don't run a second Chudder instance next to someone's own: they share a device
  id, and the server's pushes go to only one of them.
