# Casting — Key Findings & Architecture

Findings from building Chromecast + DLNA casting for Chudder (branch
`feat/chromecast-android`, June 2026). This documents how the implementation
works, the hard limits we ran into, how much control we actually have over the
remote player, and how casting interacts with everything else (SyncPlay,
sessions, networks).

---

## 1. Architecture overview

Casting hands the current playback off to a remote device by swapping the
active `BasePlayer` inside `MediaControlsWrapper` (`startCasting()` /
`stopCasting()` reuse the existing `_previousPlayer` swap mechanism). The rest
of the app — controls UI, progress reporting, playback model — keeps working
against the same `BasePlayer` interface and doesn't know it's remote.

There are **three remote player implementations**:

| Path | Player | Devices | How media gets there |
|---|---|---|---|
| Jellyfin Cast receiver (`F007D354`) | `JellyfinCastPlayer` | Chromecast 2nd-gen+, Google TV | Receiver fetches from the server itself (server-side PlaybackInfo + transcode) |
| Default Cast receiver (`CC1AD845`) | `CastPlayer` | Every Chromecast generation incl. 1st-gen | Phone asks Jellyfin for a progressive H.264/AAC MP4 transcode, re-serves it over plain HTTP via `LocalMediaProxy` |
| DLNA / UPnP | `DlnaPlayer` | webOS/Tizen TVs, Sonos, generic renderers | Same on-device proxy; AVTransport SOAP commands |

Key files:

- `lib/providers/cast_provider.dart` — discovery, connection, receiver
  selection, stream-URL/context building
- `lib/wrappers/players/jellyfin_cast_player.dart` — custom-receiver protocol
- `lib/wrappers/players/cast_player.dart` — default-receiver path
- `lib/wrappers/players/dlna_player.dart` + `dlna_discovery.dart` — DLNA
- `lib/wrappers/players/local_media_proxy.dart` — on-device HTTP proxy
- `lib/wrappers/players/jellyfin_cast_channel.dart` +
  `android/.../MainActivity.kt` — custom-namespace Cast messaging bridge
- `lib/profiles/chromecast_profile.dart` — default-receiver device profile

### Discovery

Two scans run in parallel from `CastNotifier.discover()`:

- **Chromecast**: native Cast SDK (mDNS) via `flutter_chrome_cast`. Requires a
  Wi-Fi **multicast lock** on Android (acquired over a small MethodChannel) or
  discovery silently finds nothing.
- **DLNA**: hand-rolled SSDP M-SEARCH. Must search **both**
  `urn:schemas-upnp-org:device:MediaRenderer:1` *and* `ssdp:all` — LG webOS TVs
  only answer `ssdp:all`. Devices without an AVTransport service are filtered
  out (a Chromecast also answers SSDP via its DIAL endpoint but is not a DLNA
  renderer).

---

## 2. How the Jellyfin-receiver path works (the active one)

This mirrors what the official Jellyfin web/Android apps do.

1. The Cast SDK is initialized with app id `F007D354`. Connecting to a device
   launches the Jellyfin Cast receiver (a web app) on the Chromecast.
2. All communication happens on the custom namespace
   **`urn:x-cast:com.connectsdk`** as JSON, sent through a MethodChannel
   (`nl.jknaapen.fladder/cast`) to native code, which uses
   `CastSession.sendMessage()` / `setMessageReceivedCallbacks()`. The
   `flutter_chrome_cast` plugin has **no custom-message API**, hence the bridge;
   both sides use the same `CastContext.getSharedInstance()` singleton so the
   session is shared.
3. Every message is a full envelope — the receiver is stateless about
   credentials and needs them **on every command**:

   ```json
   {
     "command": "PlayNow",
     "options": { "items": [<item stub>], "startPositionTicks": 0, "startIndex": 0 },
     "userId": "...", "deviceId": "...", "accessToken": "...",
     "serverAddress": "https://...", "serverId": "...",
     "serverVersion": "", "receiverName": "<device name>"
   }
   ```

   The item stub needs `{Id, ServerId, Name, Type, MediaType, IsFolder}` with
   **PascalCase `Type`** (`"Episode"`, not `"episode"` — use the swagger enum's
   `.value`, not `.name`). Wrong casing doesn't break playback (the receiver
   falls back to playing the stub by Id) but disables its next-episode logic.
4. The receiver does its own `PlaybackInfo` + transcode negotiation against the
   server and plays the result. **We never see or choose the stream URL.**
5. **PlayNow must be retried.** The receiver's web app registers its message
   listener a beat after the Cast session reports connected; a PlayNow sent
   immediately (we measured 33 ms after connect) is silently dropped —
   `sendMessage` still returns success because delivery-to-device succeeded.
   We retry every 2 s (max 8) until the receiver sends *anything* back.
6. Receiver → sender status messages look like:

   ```json
   { "type": "playbackstart" | "playstatechange" | "playbackprogress",
     "data": {
       "PlayState": { "IsPaused": false, "PositionTicks": 149310000,
                      "CanSeek": true, "AudioStreamIndex": 1,
                      "SubtitleStreamIndex": -1, "VolumeLevel": 100,
                      "PlayMethod": "Transcode", "PlaySessionId": "..." },
       "NowPlayingItem": { "Id": "...", "RunTimeTicks": 13466790000,
                           "Chapters": [...], "MediaStreams": [...] }
     } }
   ```

   Everything is nested under `data.PlayState` / `data.NowPlayingItem` (ticks =
   100 ns units). Progress arrives only **every few seconds**, so the phone runs
   a 1 s local ticker between reports to keep the scrubber smooth, re-anchoring
   on each report.
7. **Replies are unicast, not broadcast.** The receiver replies to
   `window.senderId`, which it only learns *from a received message*. A
   receiver that never got a message is totally silent — silence does not
   distinguish "message never arrived" from "receiver chose not to reply"
   (e.g. `Identify` while idle is handled silently by design).

### Receiver protocol command set

`PlayNow / PlayNext / PlayLast / Pause / Unpause / PlayPause / Stop /
Seek {position: seconds} / SetAudioStreamIndex / SetSubtitleStreamIndex /
SetRepeatMode / NextTrack / PreviousTrack / Identify / DisplayContent /
Shuffle / InstantMix / Mute / Unmute / VolumeUp / VolumeDown / SetVolume`

⚠️ The volume/mute handlers are **stubs in the receiver** ("implemented on the
sender") — volume must go through the Cast SDK's device volume, not the
protocol.

---

## 3. Hard limits

### One receiver app id per process

`CastContext` reads the receiver app id **once**, when the singleton is first
created (during discovery init). Re-setting options later is a no-op. So we
cannot pick custom-vs-default receiver per device at connect time — it's a
compile-time choice (`_useJellyfinReceiver` in `cast_provider.dart`, currently
`true`). Changing it requires an app restart to take effect even in dev.

### Receiver hardware floor

The Jellyfin receiver is a modern JS bundle (Vite/ES2020 + Shaka); upstream
documents it as unsupported on **1st-gen Chromecasts (2013)** — the splash can
render while the JS never initializes, so messages are silently dropped. The
default receiver (`CC1AD845`) is a tiny native player and runs on everything;
that's the reason the fallback path exists.

⚠️ **Correction from testing:** don't identify the generation via
`device-desc.xml` / `eureka_info` `modelName` — a confirmed-working **3rd-gen**
device also reports `"Eureka Dongle"`, so that string is not a generation
indicator. During development this misled us into blaming hardware when the
actual cause was network-level blocking (next section). If the receiver loads
but never responds, **rule out server reachability from the TV before blaming
the device** — the two failures look identical.

### The receiver fetches the server directly — network reachability is on the TV

With the custom receiver, the **Chromecast itself** must be able to resolve and
reach `serverAddress`. Failures here look identical to a dead receiver: logo
shows, nothing plays, no error anywhere. Found in practice (and these broke the
*official* Jellyfin app too):

- **Chromecasts hardcode Google DNS (8.8.8.8)** and ignore DHCP/router DNS.
  A split-horizon DNS setup (a local resolver like AdGuard/Pi-hole mapping the
  domain to a LAN IP) does not apply to the Chromecast — it resolves the
  public IP.
- Routed through a **VPN client on the router**, the Chromecast exits from the
  VPN's IP; combined with a **reverse-proxy IP allowlist**, the receiver's
  requests were rejected.
- A useful probe: the receiver calls `POST /Sessions/Capabilities/Full` on the
  first valid message — **if no new device appears in the Jellyfin dashboard,
  the receiver never reached the server** (or never got the message).
- Typical consumer routers cannot DNAT port 53, so the DNS bypass can't be
  fixed on that hardware; it needs a real firewall or accepting the public
  path (allowlist the LAN/VPN egress).

The default-receiver + proxy path sidesteps all of this: the TV only talks to
the phone over the LAN; the phone (which demonstrably reaches the server) does
the HTTPS fetch. Old devices also have stale CA stores / TLS stacks — plain
HTTP from the phone avoids that class of failure too.

### Transcode-start latency

Casting spins up a fresh server-side transcode; first frames can take 15–30 s.
Watchdogs/timeouts must allow for this (we use 45 s before declaring failure).

### Misc

- `setResumeSavedSession(true)` + reconnection service are baked into the
  plugin's CastOptions; a previous session can be silently rejoined.
- An active Bluetooth audio route (headphones) can make the *first* connect
  attempt flaky (`Skip setBluetoothA2dpOn`); retrying connects fine.
- Cast SDK is wired on **Android and iOS**. iOS uses the same custom-namespace
  bridge pattern (Swift `AppDelegate.swift` mirrors Kotlin `MainActivity.kt`),
  `IOSGoogleCastOptions` with `initWithApplicationID` for the receiver, and
  `GCKCastChannel` subclassing for incoming messages. macOS, Windows and Linux
  have no Google-provided SDK; on those the picker shows DLNA targets only.
- **iOS prerequisites** wired in this branch: bumped `IPHONEOS_DEPLOYMENT_TARGET`
  to 15 (Cast SDK requirement), added `NSLocalNetworkUsageDescription` + the
  `_googlecast._tcp` (and receiver-specific `_F007D354._googlecast._tcp`,
  `_CC1AD845._googlecast._tcp`) Bonjour services to `Info.plist`, and added the
  `com.apple.developer.networking.multicast` entitlement (also required for
  DLNA SSDP). Apple gates the multicast entitlement: works immediately for
  dev/TestFlight, requires their request form for App Store.
- **iOS AirPlay** is surfaced via `AVRoutePickerView` wrapped in a Flutter
  `UiKitView` (`lib/screens/video_player/components/airplay_route_button.dart`).
  Audio routes through the OS once the user picks a target — but we don't get
  video AirPlay because media-kit/mpv isn't `AVPlayer` (would require either
  switching iOS playback to AVPlayer or implementing the AirPlay video
  protocol).

  ⚠️ **Confirmed on device (2026-06-14):** with mpv as the player, the audio
  route picker connects the Apple TV as an audio device and routes **neither
  audio nor video** — mpv drives CoreAudio directly and does not follow the
  system AirPlay route. The plain audio-picker affordance is therefore a dead
  end and is being superseded by the video-AirPlay path below.

### Video AirPlay (via `AVPlayer`)

Real AirPlay *video* only works through `AVPlayer`, so it's implemented as a
swapped-in remote `BasePlayer` — same pattern as Chromecast/DLNA — backed by the
existing `video_player` dependency (AVFoundation on iOS/macOS). Playback is
*local*: the phone's `AVPlayer` fetches a Jellyfin **HLS** transcode and the OS
routes it out to the Apple TV when a route is selected.

- `lib/wrappers/players/airplay_video_player.dart` — `AirPlayVideoPlayer`
  (`VideoPlayerController`), phone-side progress (`reportsOwnProgress = false`).
- `lib/profiles/airplay_profile.dart` — HLS / H.264 / AAC profile (AVPlayer's
  native path); higher bitrate ceiling than Chromecast (≤ 20 Mbps, up to 4K).
- Surfaced as a fixed **"AirPlay"** entry in the cast picker (iOS only for now);
  selecting it swaps in the AVPlayer path. Wired in `cast_provider.dart`
  (`_airplayStreamUrl` + the `RemoteDeviceKind.airplay` branch).

**Limitations (by design / v1):**
- **Two-step interaction.** There's no public API to open the system AirPlay
  picker programmatically, so the user selects "AirPlay" (swaps to AVPlayer),
  then picks the actual Apple TV via the route button / Control Center. Until a
  route is active, the HLS stream plays *locally* through AVPlayer.
- **Transcode-only / format limits.** AVPlayer is pickier than mpv — content is
  served as HLS H.264/AAC. No mpv niceties (advanced subtitle rendering, broad
  codec/container direct play, audio passthrough) on this path.
- **No mid-play track switching.** Changing audio/subtitle track needs a fresh
  transcode URL; not wired in v1 (the baked-in track plays). `setAudioTrack`/
  `setSubtitleTrack` are no-ops returning the requested index, mirroring DLNA.
- **No screenshots; playback rate** works on AVPlayer but some receivers ignore
  it.
- **macOS** now has the AppKit route picker (`macos/Runner/AirPlayRouteView.swift`
  + `AppKitView`), so the same `AirPlayVideoPlayer` path is offered there. ⚠️
  Bigger unknown than iOS: macOS has no app-wide audio session, so the picker may
  need to be bound to the specific `AVPlayer` to route it — if route selection
  doesn't hand video to the TV, the picker must be wired to `video_player`'s
  `AVPlayer`. Needs on-device validation.
- **Needs on-device validation** that `video_player`'s AVPlayer keeps
  `allowsExternalPlayback` enabled (the default) so route selection actually
  hands off video — if not, a small native shim to set it is required.

---

## 4. How much control do we have over the player?

With the **Jellyfin receiver**, the receiver is the player; we are a remote
control. Mapping of `BasePlayer` operations:

| Operation | Mechanism | Fidelity |
|---|---|---|
| load | `PlayNow` (+ retry) | Good; receiver picks stream/quality itself |
| play/pause | `Unpause`/`Pause`, optimistic local state, confirmed by `playstatechange` | Good |
| seek | `Seek {seconds}` | Good (server-side transcode seek) |
| position | `playbackprogress` every few seconds + 1 s local interpolation | ~±2 s accuracy |
| duration | `NowPlayingItem.RunTimeTicks` | Exact |
| audio/sub tracks | `SetAudioStreamIndex` / `SetSubtitleStreamIndex` | Receiver re-negotiates stream |
| volume | **Not via protocol** (receiver stubs) — must use Cast SDK device volume | Not wired up yet |
| playback rate | **No protocol command** — not possible on this path | None |
| screenshots/subtitle overlay | n/a remotely | None |

What we *cannot* control on the custom-receiver path: the stream selection
(bitrate/codec decisions happen receiver-side via its own device profile),
playback rate, and frame-accurate position.

With the **default receiver**, control inverts: we own the stream URL (and thus
quality, via `chromecastProfile` — H.264 ≤ L4.1, ≤ 1080p, ≤ 8 Mbps, AAC stereo,
progressive MP4 over the proxy), and the Cast SDK's `RemoteMediaClient` gives
play/pause/seek/rate and a media status stream. But we lose server-side track
switching (audio/subtitle changes require building a new transcode URL and
reloading) and the receiver reports against *our* URL, not a Jellyfin play
session.

### Session identity (matters for everything server-side)

- **Custom receiver**: the Chromecast registers **its own session** with the
  server (own capabilities, own progress reporting, own `PlaySessionId`). The
  server sees playback happening on "Chromecast", not on the phone. The phone's
  own progress reports should be suppressed while casting or the server sees
  two contradictory sessions for the same item.
- **Default receiver/DLNA**: the server only sees a transcode being pulled; the
  *phone* must keep reporting progress for watched-state to update.

---

## 5. SyncPlay implications

SyncPlay group membership is **per server session**, and precise sync needs
tight control of position/rate. Consequences:

- **Custom receiver path**: the Chromecast is its own session, so *the phone's*
  SyncPlay membership doesn't make the TV synced. The Jellyfin receiver app has
  **no SyncPlay support** — it ignores group play-state. Conceptually the group
  would have to enroll the *receiver's* session and the receiver would need to
  implement SyncPlay's clock/seek discipline; that's an upstream
  jellyfin-chromecast feature, not something a sender can bolt on.
- **Sender-driven approximation**: the phone could stay in the SyncPlay group
  and translate group commands into `Pause`/`Unpause`/`Seek` toward the
  receiver. Workable for casual "watch together", but the control loop is
  coarse: position reports every few seconds, seek granularity of 1 s,
  transcode restart latency on every corrective seek. Sub-second sync is not
  achievable; expect ±2–5 s drift.
- **Mutual exclusion is the sane v1**: entering a SyncPlay group while casting
  (or casting while in a group) should prompt to leave one. The
  `MediaControlsWrapper` player-swap is the natural enforcement point.
- DLNA is strictly worse (some renderers ignore seek entirely, position polling
  is SOAP `GetPositionInfo`) — never try to sync a DLNA renderer.

---

## 6. Other notable findings

- **`sendMessage success=true` ≠ delivered to the app.** Cast SDK success means
  the frame reached the *device*. If no listener is registered for the
  namespace (receiver still loading, receiver JS dead, wrong receiver), it
  vanishes without error. Design every send-side flow around acknowledgement,
  not send success.
- **Debugging a published receiver is blind.** No console access to Jellyfin's
  hosted receiver. The observable side-channels, in order of usefulness:
  device appearing in the Jellyfin dashboard (`postFullCapabilities`), receiver
  status messages, server access logs, and `eureka_info` for hardware identity.
- **Isolation test pattern that paid off**: cast a known-good public HLS URL
  (Apple's bipbop) through the default receiver. It separates
  device/SDK/network problems from server/stream problems in one move.
  Kept available via `_castDiagnosticMode` in `cast_player.dart`.
- **DLNA specifics** (webOS verified working): renderers commonly can't fetch
  HTTPS (no/old TLS stacks) → the proxy is the safe default. *Caveat:* our
  webOS "can't fetch HTTPS" diagnosis (error 716 on the direct URL) predates
  discovering the network-level blocking — the TV may have been rejected by
  the reverse proxy, not by TLS. Retest direct HTTPS before treating the proxy
  as mandatory for webOS; if direct works, prefer direct-with-proxy-fallback
  (frees the phone from the data path). Seeking
  requires advertising `DLNA.ORG_OP=01` + flags in both the DIDL `protocolInfo`
  and the `contentFeatures.dlna.org` response header, plus honoring Range.
  webOS needs `REL_TIME` seek with zero-padded `hh:mm:ss` (falls back to
  `ABS_TIME`).
- **The proxy** binds an ephemeral port on `anyIPv4`, picks the phone's private
  LAN IP, forwards Range/HEAD, and adds DLNA + CORS headers. It serves exactly
  one upstream at a time (`?t=` token busts renderer caches). HLS is *not*
  proxyable as-is (playlists carry absolute server URLs — would need rewriting);
  that's why the default-receiver path requests a **progressive MP4** transcode.
- **Mixed content caveat (untested)**: a modern receiver page is HTTPS; whether
  it may load plain-HTTP media from the proxy was never confirmed on real
  hardware (the 3rd-gen ended up on the custom-receiver path instead). If the
  default-receiver+proxy path is ever needed on a modern device, verify this
  first — a 2013 device predates strict mixed-content blocking, newer firmware
  may not.

## 7. Open follow-ups

- Resume-on-cast: pass the local position as `startPositionTicks` in `PlayNow`
  (currently starts where `loadVideo` is told to; verify end-to-end).
- Suppress the phone's own progress reporting while the custom receiver path is
  active (avoid duplicate sessions).
- Device volume control via the Cast SDK (protocol stubs make this sender-side).
- Next-episode handoff (receiver supports queueing via `PlayNext`/`PlayLast`).
- iOS support; Identify-based reconnect to an already-playing receiver.
- SyncPlay × casting mutual exclusion in the UI.
