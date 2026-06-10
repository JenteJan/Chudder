# Casting — Verification Status

What has actually been confirmed working on real hardware, what is built but
untested, and what is known-broken or missing. Companion to
[CASTING.md](CASTING.md) (architecture & findings). Last updated: 2026-06-10,
branch `feat/chromecast-android`.

## Test environment

- Sender: Android phone (Pixel), debug builds
- Chromecast: 3rd-gen dongle (reports `modelName: Eureka Dongle` — see the
  correction note in CASTING.md §3; that string is not a generation indicator)
- DLNA: LG webOS TV (UP7700 series), Sonos Play:1
- Server: Jellyfin 10.11 in Docker, HTTPS-only behind a reverse proxy with an
  IP allowlist; split-horizon DNS on the LAN

## ✅ Confirmed working

### Chromecast — Jellyfin receiver path (`F007D354`, the active path)

| What | Notes |
|---|---|
| Device discovery | Native Cast SDK (mDNS) with Wi-Fi multicast lock |
| Session launch + receiver handshake | `PlayNow` retry-until-acknowledged is required and works (first send is dropped while the receiver JS boots) |
| Playback start | Receiver does its own PlaybackInfo/transcode against the server and plays |
| Phone ⇄ receiver state sync | Position (interpolated between `playbackprogress` reports), play/pause, duration all track correctly |
| Play / pause / seek from the phone | Confirmed against the receiver |
| **Subtitles** | Confirmed with **PGS (`pgssub`)** — the receiver's server-side transcode handles them (PGS requires burn-in, so this exercises the heaviest subtitle path; text formats should follow) |
| Single server session | While casting, the dashboard shows only the receiver's session; the phone's reporting is suppressed (`reportsOwnProgress`) |
| Resume-on-cast | TV starts at the phone's current position (`startPositionTicks`) |
| Resume-on-disconnect | Phone resumes where the TV got to (receiver-synced `lastState.position`) |
| Watched-state | Updates correctly via the receiver's own reporting; phone session is closed at handoff and re-registered on disconnect |

### DLNA path

| What | Notes |
|---|---|
| Discovery | webOS TVs require the `ssdp:all` search target (they don't answer `MediaRenderer:1`); Sonos answers both |
| Playback on webOS | Via the on-device HTTP proxy (`LocalMediaProxy`), zero server configuration |
| Seeking on webOS | Requires `DLNA.ORG_OP=01` + flags in DIDL `protocolInfo` **and** the `contentFeatures.dlna.org` response header, plus Range support; `REL_TIME` seek with zero-padded `hh:mm:ss` |
| Sonos | Discovered and resolved as a renderer (playback not explicitly exercised) |

### Root-cause findings (confirmed by fixing them)

- The original "receiver loads but never plays / never responds" failure was
  **network-level**: the Chromecast hardcodes Google DNS, resolved the public
  address, egressed via the router's VPN client, and was rejected by the
  reverse proxy's IP allowlist. Fixing the VPN/allowlist made both the
  **official Jellyfin app** and Fladder's receiver path work. It was never a
  sender-code or device-hardware problem.
- The default Cast receiver (`CC1AD845`) + a known-good public HLS stream
  plays fine on this device (isolation test) — useful to separate device/SDK
  problems from server/stream problems.

## 🟡 Built but not verified

| What | Status |
|---|---|
| Default-receiver fallback path (`CC1AD845` + progressive MP4 via proxy) | Fully implemented (`cast_player.dart`, `chromecast_profile.dart`, `_useJellyfinReceiver = false`) but never end-to-end tested — superseded by the custom receiver before testing. The open question is whether a modern receiver page may load plain-HTTP media (mixed content) |
| webOS **direct HTTPS** streaming (no proxy) | The original failure (error 716) may have been the same network block rather than TLS — retest pending; if it works, switch DLNA to direct-with-proxy-fallback |
| Audio track switching (`SetAudioStreamIndex`) | Wired, untested |
| Next-episode behaviour on the receiver | The PascalCase `Type` fix enables the receiver's episode-queue logic; not yet observed |
| Music/audio casting | Untested on all paths |

## ❌ Known issues / not implemented

- Receiver/device **volume control** not wired (the protocol's volume commands
  are receiver stubs; must use the Cast SDK's device volume — sender-side).
- **Playback rate** is impossible on the Jellyfin-receiver path (no protocol
  command).
- **SyncPlay × casting** mutual exclusion not enforced yet (see CASTING.md §5
  — the receiver has no SyncPlay support; the sane v1 is prompting to leave
  one when entering the other).
- First connect can fail with an active **Bluetooth audio route** (headphones);
  a retry connects.
- Receiver app id is **fixed per app process** — switching between the
  Jellyfin and default receiver is a compile-time constant and needs an app
  restart.
- **iOS** not implemented (Android-only MethodChannel bridge).
- Reconnecting to an already-running cast session (adopting receiver state via
  `Identify`) not implemented.
