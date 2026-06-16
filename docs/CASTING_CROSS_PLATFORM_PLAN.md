# Casting — Cross-Platform Expansion Plan (Windows / macOS / Web)

Design plan for extending casting beyond Android/iOS. Builds on the architecture
documented in [`CASTING.md`](./CASTING.md). Scope chosen with the maintainer:

1. **Pure-Dart Cast sender** — Chromecast on Windows/macOS/Linux
2. **Web Chromecast** — Cast Web Sender (Chromium browsers)
3. **macOS AirPlay picker**
4. **Desktop DLNA hardening**

Status: *plan only — no code yet.*

---

## 0. Why a refactor comes first

Today the cast stack is welded to `flutter_chrome_cast`, which declares **only
`android` + `ios`** platform implementations (verified in its `pubspec.yaml`):

- `lib/providers/cast_provider.dart` imports `flutter_chrome_cast` unconditionally
  and calls `GoogleCastContext` / `GoogleCastDiscoveryManager` directly.
- `lib/wrappers/players/remote_device.dart` holds a `GoogleCastDevice? cast`
  field — the device-picker model itself depends on the mobile package.
- `cast_player.dart` drives the default receiver through the plugin's
  `RemoteMediaClient`.
- The Jellyfin-receiver transport is a native MethodChannel bridge
  (`nl.jknaapen.fladder/cast`, see `jellyfin_cast_channel.dart`).

Desktop and web need *different* Chromecast backends but the **same** higher
layers (device picker, `BasePlayer` swap, Jellyfin receiver JSON protocol,
proxy). So step 0 is to introduce seams so the three backends can coexist.

### 0.1 New abstractions (`lib/wrappers/players/cast/`)

```dart
// A discovered "play to" target, backend-agnostic (replaces the
// GoogleCastDevice/DlnaRenderer fields on RemoteDevice).
class CastTarget {
  final String id;          // stable, backend-prefixed: "cast-native:..", "cast-dart:..", "cast-web:.."
  final String name;
  final CastBackendId backend;
  final Object handle;      // opaque, owned by the backend (GoogleCastDevice | mDNS result | JS device)
}

// Selects/launches the receiver and manages discovery for one platform.
abstract class CastBackend {
  bool get supported;
  Future<void> init(String appId);
  Future<List<CastTarget>> discover(Duration timeout);
  Future<CastSession> connect(CastTarget target);
  Future<void> disconnect();
}

// A live connection. Splits the two namespaces the app actually uses.
abstract class CastSession {
  CastMessageTransport get custom;   // urn:x-cast:com.connectsdk  (Jellyfin receiver)
  RemoteMediaControl?  get media;     // urn:x-cast:com.google.cast.media (default receiver)
  Future<void> setVolume(double level);
  Stream<CastConnectionStatus> get status;
}

// Custom-namespace messaging — the ONLY transport difference between backends.
abstract class CastMessageTransport {
  Future<void> registerNamespace(String namespace);
  Future<void> sendMessage(String namespace, String json);
  Stream<String> messages(String namespace);
}

// Default-receiver media control (LOAD/PLAY/PAUSE/SEEK + status stream).
abstract class RemoteMediaControl {
  Future<void> load(CastMediaRequest req);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<RemoteMediaStatus> get status;
}
```

### 0.2 Backend selection (conditional import)

```dart
// cast_backend.dart
export 'cast_backend_stub.dart'
  if (dart.library.io) 'cast_backend_io.dart'
  if (dart.library.js_interop) 'cast_backend_web.dart';
```

- `cast_backend_io.dart` is the **only** file that imports `flutter_chrome_cast`.
  At runtime it returns `NativeCastBackend` on `Platform.isAndroid || isIOS`,
  else `DartCastBackend` (workstream 1). This keeps the mobile plugin out of the
  web compilation unit entirely.
- `cast_backend_web.dart` returns `WebCastBackend` (workstream 2); never imports
  `flutter_chrome_cast`.
- `cast_backend_stub.dart` returns an unsupported backend (DLNA-only fallback).

### 0.3 What the existing players become

- `JellyfinCastPlayer` and `CastPlayer` stop importing `flutter_chrome_cast`;
  they take a `CastSession` and use `session.custom` / `session.media`. **The
  Jellyfin envelope-building + retry logic moves unchanged** — only the bytes'
  transport changes. This is the big reuse win: all three Chromecast backends
  share one receiver protocol implementation.
- `RemoteDevice` swaps its `GoogleCastDevice? cast` / `DlnaRenderer? dlna` fields
  for `CastTarget? cast` + `DlnaRenderer? dlna` (DLNA stays as-is; it's already
  cross-platform pure Dart).
- `cast_provider.dart` talks to `CastBackend` instead of `GoogleCast*` directly.

**Effort:** ~1–2 days, mechanical but touches several files. Net behavior on
mobile must be identical (regression-test Android/iOS casting after).

---

## 1. Pure-Dart Cast sender (desktop) — *REMOVED (2026-06-14)*

> **Status: removed.** A pure-Dart CASTV2 sender (mDNS discovery + protocol
> client + `DartCastPlayer`) was built and compiled on macOS, then deleted. It
> could only drive the *default* receiver, whose plain-HTTP proxy stream is
> liable to mixed-content blocking on modern receivers (CASTING.md §6), and the
> *custom Jellyfin receiver* (the path that works on mobile/web) can't be driven
> over a raw CASTV2 transport without significant extra work. Desktop ships
> **AirPlay (macOS) + DLNA** instead. If revived, the approach would be to drive
> the Jellyfin receiver over a CASTV2 custom-namespace channel — see git history
> (`feat(cast): pure-Dart Chromecast sender for desktop`) for the deleted code.

Original goal (not pursued): Chromecast discovery + control on
Windows/macOS/Linux with no Google SDK.

### 1.1 Discovery — `multicast_dns` (add dependency)

Query `_googlecast._tcp.local`, resolve each:
- **SRV** → host + port (almost always `8009`)
- **TXT** → `fn` (friendly name), `id` (device id), `md` (model), `ca`, `rs`

Map to `CastTarget(backend: dartCast)`. Pure Dart, works on all desktop OSes.
Same multi-NIC caveat as DLNA (§4).

### 1.2 CASTV2 protocol (the client)

TLS socket to `host:8009` (`SecureSocket.connect`, `onBadCertificate: => true`
— receivers use self-signed certs). Wire format: **4-byte big-endian length
prefix + protobuf `CastMessage`** (`cast_channel.proto`). `protobuf` 3.1.0 is
already in the lockfile; generate the one message with `protoc` or hand-encode
(it has ~7 fields).

Connection sequence:
1. `CONNECT` on `…tp.connection` (`sender-0` → `receiver-0`).
2. `PING`/`PONG` on `…tp.heartbeat` every ~5 s (receiver drops idle channels).
3. `LAUNCH {appId}` on `…receiver` → `RECEIVER_STATUS` returns the app's
   `transportId`.
4. `CONNECT` a virtual connection to that `transportId`.
5. Then per receiver:
   - **Jellyfin (`F007D354`)**: send the existing JSON envelopes on
     `urn:x-cast:com.connectsdk` to `transportId`; receive on the same
     namespace. → implements `CastMessageTransport`. The PlayNow-retry and
     status-parsing already in `JellyfinCastPlayer` work verbatim.
   - **Default (`CC1AD845`)**: `LOAD/PLAY/PAUSE/SEEK/GET_STATUS` on
     `urn:x-cast:com.google.cast.media`; parse `MEDIA_STATUS` for position. →
     implements `RemoteMediaControl`. Feed it the existing `LocalMediaProxy`
     URL + `chromecastProfile` transcode (proxy already runs on desktop).
6. Volume: `SET_VOLUME {volume:{level}}` on `…receiver`.

**Build vs. buy:** evaluate the `cast` / `dart_chromecast` pub packages as a
shortcut for steps 1–4 before hand-rolling; both are thin and may be stale, but
the framing + protobuf are the tedious part. Recommendation: spike with a
vendored minimal client (we only need ~6 message types) to avoid an unmaintained
dependency in the hot path.

### 1.3 Integration

`DartCastBackend.connect()` returns a `CastSession` exposing both `custom` and
`media`; the rest (player swap, UI) is unchanged from mobile. The
one-receiver-per-process constraint (`_useJellyfinReceiver`) is a non-issue here
(we control the LAUNCH per connect) — a latent improvement we *could* expose,
but keep parity with mobile for v1.

**Effort:** several days + real-device testing across generations. Biggest risk
is protocol/cert drift and heartbeat timing.

---

## 2. Web Chromecast — Cast Web Sender — *medium*

Goal: `WebCastBackend` using Google's Cast Web Sender framework via JS interop
(`web` / `dart:js_interop`, both available).

- Load `https://www.gstatic.com/cv/js/sender/v1/cast_sender.js?loadCastFramework=1`
  (script tag in `web/index.html`); gate on the `__onGCastApiAvailable`
  callback. Absent in Firefox/Safari → backend reports `supported = false`.
- Bind `cast.framework.CastContext`:
  `setOptions({receiverApplicationId: F007D354, autoJoinPolicy})`,
  `requestSession()` (must be user-gesture-initiated — the cast button tap),
  `getCurrentSession()`.
- **Jellyfin path**: `session.sendMessage(ns, msg)` +
  `session.addMessageListener(ns, cb)` → `CastMessageTransport` directly. Reuses
  the envelope code.
- **Default path** (optional): `session.loadMedia(...)` +
  `session.getMediaSession()` → `RemoteMediaControl`. No proxy on web, so it
  would need a **direct HTTPS Jellyfin transcode URL** (modern receiver can
  fetch it). Recommend shipping web as **Jellyfin-receiver only**.

Constraints to surface in the UI:
- **Chromium only** (Chrome/Edge/Brave). Hide the cast button when
  `cast.framework` is unavailable.
- Page must be **HTTPS** (or `localhost`).
- All the receiver→server network caveats from `CASTING.md §3` apply (the TV,
  not the browser, fetches the media).
- DLNA stays disabled on web (no UDP/`ServerSocket`) — unchanged.

**Effort:** medium; mostly JS-interop plumbing + availability/UX gating.

---

## 3. Video AirPlay via AVPlayer — *new direction (replaces the audio picker)*

**Decision (2026-06-14, validated on device):** the audio `AVRoutePickerView`
approach is abandoned. On real hardware it connects the Apple TV as an *audio
route* and, because the player is media-kit/mpv (not `AVPlayer`), routes **no
audio and no video**. The iOS AirPlay button should be **hidden** in its current
form, and the macOS audio-picker workstream is **cancelled** (mpv on macOS would
fail identically).

Instead, do real **video** AirPlay through `AVPlayer` — the only API that
AirPlays video. Same architecture as casting: a dedicated `BasePlayer` swapped in
for the AirPlay session, leaving mpv out of that session.

- **Reuse the existing `video_player` dependency** (2.10.1 +
  `video_player_avfoundation`), which is `AVPlayer`-backed on iOS/macOS. AVPlayer
  does AirPlay video natively (`allowsExternalPlayback` defaults true), so this
  likely needs **little/no new native code**.
- New `AirPlayVideoPlayer : BasePlayer` wrapping a `VideoPlayerController`,
  loading a Jellyfin **HLS** transcode URL. Swap it in when an AirPlay route is
  selected; progress reporting stays phone-side (like DLNA — `reportsOwnProgress
  = false`).
- iOS first; macOS likely free via the same AVFoundation path.
- **Independent of the §0 backend refactor** — can be built in parallel.

Open questions to settle during build: building the right HLS/MP4 transcode URL
from Jellyfin; audio/subtitle track switching (more limited via `video_player`
than mpv); clean player-swap on route selection vs. deselection.

**Effort:** medium — a new player path + Jellyfin HLS URL building; no CASTV2/
protocol work.

---

## 4. Desktop DLNA hardening — *testing + multi-NIC*

The DLNA path (`dlna_discovery.dart`, `dlna_player.dart`, `LocalMediaProxy`) is
already pure Dart and runs on desktop today (the Android multicast-lock channel
degrades to a caught `MissingPluginException`). Open work is verification + the
desktop network surface:

- **Multi-NIC discovery (likely real bug):** `RawDatagramSocket.bind(anyIPv4, 0)`
  on a desktop with Ethernet + Wi-Fi + VPN virtual adapters may emit M-SEARCH on
  the wrong interface and miss responses. Enumerate `NetworkInterface.list()`,
  send M-SEARCH per interface, and `joinMulticast(group, interface)`.
- **Proxy LAN-IP selection:** `LocalMediaProxy` picks "the private LAN IP" —
  on multi-NIC desktop it must pick the one on the renderer's subnet.
- **Windows Firewall:** first run prompts for inbound on the proxy's ephemeral
  port; document it / consider a fixed port + manifest hint.
- **Test matrix:** {Windows, macOS} build × {webOS TV, generic UPnP renderer,
  Sonos (audio-only filter)} — confirm discovery, playback, seek, and the
  audio-only filtering.

**Effort:** small-to-medium; the multi-NIC fix is the main code change.

---

## 5. Sequencing & dependencies

```
[0] Backend refactor (seams)  ──┬──> [1] Dart sender (desktop)
                                └──> [2] Web sender
[3] macOS AirPlay   — independent (spike first)
[4] DLNA hardening  — independent (can start immediately)
```

- **0 blocks 1 and 2.** Do it first; ship it as a no-behavior-change refactor
  verified against mobile.
- **4 and 3 are independent** of the refactor — good parallel/early work. Start
  4 immediately (highest value-per-effort: real Chromecast-less desktop users
  get DLNA today). Spike 3's audio routing before investing.
- **1 then 2:** the Dart sender forces the cleanest `CastSession`/transport
  design; web then reuses those interfaces with minimal new surface.

Suggested order: **4 (quick win) → 0 → 1 → 2 → 3 (if spike passes).**

---

## 6. Risks & unknowns

| Risk | Workstream | Mitigation |
|---|---|---|
| `flutter_chrome_cast` leaking into web build | 0 | Conditional import; verify `flutter build web` post-refactor |
| CASTV2 cert/heartbeat/protocol drift | 1 | Vendor minimal client; test multiple device generations |
| Unmaintained `cast` pub packages | 1 | Prefer vendored ~6-message client over a stale dep |
| Web sender Chromium-only / HTTPS-only | 2 | Feature-detect; hide button otherwise |
| mpv audio won't follow macOS AirPlay route | 3 | **Spike before building**; drop if it fails |
| Multi-NIC misses DLNA devices on desktop | 4 | Per-interface M-SEARCH + joinMulticast |
| One-receiver-per-process (`_useJellyfinReceiver`) | 1,2 | Keep mobile parity v1; revisit per-connect launch later |

## 7. Testing

- **Regression (gate for 0):** Android + iOS casting unchanged (discovery,
  Jellyfin receiver PlayNow/retry, default-receiver proxy, volume).
- **1:** macOS + Windows builds against ≥2 Chromecast generations; both receiver
  paths; volume; reconnect.
- **2:** Chrome + Edge over HTTPS; Jellyfin receiver path; graceful hide on
  Firefox/Safari.
- **3:** macOS audio actually routes to an AirPlay speaker.
- **4:** the §4 device matrix.
