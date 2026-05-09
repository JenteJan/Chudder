# ReleaseManager (Dart CLI) — design

**Status:** Design — pending implementation plan
**Date:** 2026-05-09
**Branch:** `maktep-syncplay`
**Targets:** Maktep fork release pipeline (Android APK + Windows installer → AList via WebDAV)

## Goal

Provide a small, repo-local Dart CLI that orchestrates a private release for
the Maktep fork: build Android + Windows artifacts, hash them, upload to an
AList instance over WebDAV, and update `manifest.json` so the in-app AList
updater picks up the new version on its next poll.

## Non-goals

- Linux / macOS / iOS / web releases.
- Code signing for the Windows installer (only the existing Android keystore
  is used).
- Multiple release channels (single `manifest.json`).
- Git tagging or pushing — orthogonal; the user runs those themselves.
- CI integration. The tool is invoked locally from a developer machine.
- Steam / FTP / netsparkle appcast — patterns borrowed from
  `Blastr.ReleaseManager` are limited to `ProcessRunner.Run` and the
  GET-modify-PUT manifest flow.

## Constraints

- Single-file Dart script in `tools/release_manager.dart`. Uses only deps
  already in `pubspec.yaml` (`http`, `yaml`, `args`, `crypto`) — no new
  dependencies, no nested package.
- Run from repo root: `dart run tools/release_manager.dart [options]`.
- Inno Setup `iscc.exe` and the Flutter SDK must already be on `PATH` (or
  `iscc` configured via the local config file).
- The user's `android/app/key.properties` is required for signed Android
  release builds. The script does not provision keystores.
- AList endpoint is reachable via HTTP Basic auth on its WebDAV path.

## Architecture

### Form factor

A single Dart file at `tools/release_manager.dart`. The `tools/` folder is
ignored by the analyzer for `lib/` rules but `flutter analyze` still lints
it; the script must pass `flutter analyze` clean.

If the file ever exceeds ~600 lines or grows multiple subsystems, it splits
into a `tools/release_manager/` package. v1 is intentionally one file.

### Configuration

Two files in `tools/`:

```
tools/release_manager.config.example.json    # committed scaffold
tools/release_manager.config.local.json      # GITIGNORED real values
```

Schema (both files):

```jsonc
{
  "alistDavUrl":      "https://alist.example/dav/fladder",
  "alistDownloadUrl": "https://alist.example/d/fladder",
  "alistUser":        "uploader",
  "alistPass":        "...",
  "innoSetupPath":    "C:\\Program Files (x86)\\Inno Setup 6\\iscc.exe",
  "maxReleases":      10,
  "manifestPath":     "/manifest.json"
}
```

Field rules:

- `alistDavUrl` (required): WebDAV root for uploads. Files PUT to
  `{alistDavUrl}/{version}/{filename}` and `{alistDavUrl}{manifestPath}`.
- `alistDownloadUrl` (required): public download root used in the manifest
  entries — typically `https://.../d/...` rather than `/dav/...`.
- `alistUser` / `alistPass` (required): HTTP Basic credentials for WebDAV.
- `innoSetupPath` (optional): full path to `iscc.exe`. If empty/missing,
  the script tries to find `iscc` on `PATH`.
- `maxReleases` (optional, default 10): manifest history is trimmed to this
  many entries after a release.
- `manifestPath` (optional, default `/manifest.json`): path to the manifest
  on AList, relative to `alistDavUrl`.

The tool reads only `release_manager.config.local.json`. The `.example.json`
exists for documentation. Missing local file → exit with a message
pointing at the example.

### CLI surface

```
dart run tools/release_manager.dart [options]
  --bump major|minor|patch|build   Rewrite pubspec.yaml version before building
  --version X.Y.Z                  Override version (test-only; bypasses pubspec)
  --platforms android,windows      Comma-separated; default both
  --dry-run                        Build + hash; skip uploads + manifest PUT
  --skip-build                     Skip build; reuse existing artifacts
  --config <path>                  Alternate config path
  -h, --help                       Show help
```

### Pipeline

```
0. Parse args; load config; resolve iscc path.
1. Read pubspec.yaml; if --bump, rewrite version; capture (version, buildNumber).
2. Verify tools/changelogs/<version>.md exists; read it.
3. flutter pub get.
4. If "android" in platforms:
     flutter build apk --release --flavor=production --build-number=N \
       --dart-define=UPDATE_SOURCE=alist \
       --dart-define=ALIST_BASE_URL=<alistDownloadUrl>
     -> build/app/outputs/flutter-apk/app-production-release.apk
5. If "windows" in platforms:
     flutter build windows --release --build-number=N \
       --dart-define=UPDATE_SOURCE=alist \
       --dart-define=ALIST_BASE_URL=<alistDownloadUrl>
     -> build/windows/x64/runner/Release/...
     iscc /DFLADDER_VERSION=X.Y.Z windows\windows_setup.iss
     -> windows/Output/cinemaktep_setup.exe
6. SHA-256 each artifact (chunked through package:crypto).
7. For each artifact:
     PUT to <alistDavUrl>/<version>/<filename>
8. GET <alistDavUrl><manifestPath>; if 404 use { schema:1, latest:"", releases:[] }.
9. Build new release entry:
     {
       version, publishedAt: now ISO-8601, changelog,
       downloads: { android: <downloadUrl>/<version>/Fladder-Android.apk,
                    windows_installer: <downloadUrl>/<version>/Fladder-Windows-Setup.exe },
       sha256:    { android: ..., windows_installer: ... }
     }
   Only include keys for platforms that were actually built this run.
10. Replace any existing entry with the same `version`; insert new at top;
    sort by version desc; trim to `maxReleases`; set `latest` to the new
    version (whichever is highest by semver compare).
11. PUT updated manifest.json back to AList.
12. Print summary: hashes + final download URLs.
```

If `--dry-run`: steps 7, 8, 11 are replaced with logged "would PUT" entries.
If `--skip-build`: steps 3, 4, 5 are skipped; step 6 still runs against the
existing artifacts (errors clearly if they're missing).

## Components

### `runProcess`

```dart
Future<int> runProcess(String executable, List<String> args, {String? cwd});
```

Spawns the process inheriting stdout/stderr; throws on non-zero exit unless
the caller chooses to inspect the return code. Mirrors Blastr's
`ProcessRunner.Run`. Logs the full command before running.

### `sha256OfFile`

```dart
Future<String> sha256OfFile(File f);
```

Streams the file through `package:crypto`'s `sha256` and returns the hex
digest, lower-case.

### WebDAV helpers

```dart
class _WebDavAuth { final String user; final String pass; ... }

Future<http.Response> webdavGet(Uri url, _WebDavAuth auth);
Future<void> webdavPutFile(Uri url, File file, _WebDavAuth auth);
Future<void> webdavPutJson(Uri url, Object json, _WebDavAuth auth);
```

- All requests carry `Authorization: Basic <base64(user:pass)>`.
- `webdavPutFile` streams the file into the request body with
  `Content-Type: application/octet-stream`.
- `webdavPutJson` serializes with 2-space indent and
  `Content-Type: application/json; charset=utf-8`.
- All helpers throw on non-2xx with the status + response body.
- `webdavGet` returns the raw response so the caller can branch on 404.

### Pubspec utilities

```dart
({String version, int buildNumber}) parsePubspecVersion(String yamlText);
String bumpPubspecVersion(String yamlText, String level); // major|minor|patch|build
```

Parsing uses `package:yaml`. Rewriting uses a regex on the literal
`version: X.Y.Z+N` line so it preserves comments and surrounding formatting
(yaml round-tripping in `package:yaml` is lossy).

### Manifest model

A small record-style class holding the parsed manifest. Forward-compatible:
unknown fields on releases are preserved (`Map<String, dynamic>` shape;
known fields read explicitly, the rest passed through on serialize).

## Data flow

```
Local repo                         AList
+---------------------+            +-------------------------+
| pubspec.yaml        |            |                         |
| tools/changelogs/X  |            |  /<version>/...apk      |
|        |            |            |  /<version>/...exe      |
|        v            |            |  /manifest.json         |
| ReleaseManager.dart | <--HTTP--> |                         |
| - flutter build apk |            |                         |
| - flutter build win |            |                         |
| - iscc              |            |                         |
| - sha256            |            |                         |
+---------------------+            +-------------------------+
```

## Error handling

- Missing config file → exit 2, print path to copy from.
- Missing `tools/changelogs/<version>.md` → exit 3.
- `iscc` not found → exit 4.
- Build process non-zero → exit code propagated, stderr already on terminal.
- WebDAV GET fails (other than 404) → exit 5, dump status + body.
- WebDAV PUT fails → exit 6, dump status + body.
- Final manifest validation: re-GET after PUT and compare schema field —
  exit 7 on mismatch.

All exit codes are documented in `--help`.

## Idempotency

Re-running for the same `version` replaces the matching entry in
`releases[]` rather than duplicating. Re-uploads overwrite any prior
binaries at `/<version>/...`. Safe to re-run after a partial failure.

## Testing

Unit tests live alongside other tests in `test/tools/`. Pure-function
coverage only — no live HTTP / process invocation in tests:

- `test/tools/release_manager_pubspec_test.dart`
  - `parsePubspecVersion` returns `(version, buildNumber)` for valid input.
  - `bumpPubspecVersion` increments correctly for major / minor / patch /
    build, resets lower components, preserves the `+N` suffix shape.
  - Round-trip preserves comments and surrounding lines.
- `test/tools/release_manager_manifest_test.dart`
  - Fresh manifest builder produces correct shape.
  - Inserting a new release replaces the same-version entry.
  - Trim respects `maxReleases`.
  - `latest` points at highest semver.

The full pipeline (`flutter build`, `iscc`, WebDAV) is verified manually by
running the tool with `--dry-run` and inspecting the printed plan, then a
real run against a test path on AList.

## File layout

```
tools/release_manager.dart                    # the tool
tools/release_manager.config.example.json     # committed scaffold
tools/release_manager.config.local.json       # GITIGNORED, never committed
tools/changelogs/README.md                    # documents the format
tools/changelogs/.gitkeep
.gitignore                                    # adds tools/release_manager.config.local.json
test/tools/release_manager_pubspec_test.dart
test/tools/release_manager_manifest_test.dart
docs/superpowers/specs/2026-05-09-release-manager-design.md   # this file
```

## Resolved decisions

- **Language:** Dart (not PowerShell). Easier to extend, integrates with
  the project's existing tooling.
- **Single file vs package:** Single file `tools/release_manager.dart` for
  v1. Splits later if it grows beyond ~600 lines.
- **Config:** JSON, two-file split (`example` committed, `local` gitignored).
  Mirrors the `appsettings.json` pattern from the Blastr reference.
- **Changelog source:** Per-version files in `tools/changelogs/<version>.md`.
  Missing file is a hard error.
- **Version bump:** Optional `--bump` flag rather than interactive prompt.
  Keeps the tool fully scriptable.
- **WebDAV auth:** HTTP Basic via `Authorization` header. AList supports it
  natively.
- **Two URLs (DAV + Download):** AList exposes WebDAV at `/dav/...` and
  public downloads at `/d/...`. Both paths are explicit in the config.

## Risks & mitigations

- **AList path conventions vary by deploy.** Two URLs (DAV + download) make
  the deployment-specific bits explicit; users adapt the config file, not
  the script.
- **Inno Setup not on PATH.** Config has an explicit `innoSetupPath`
  override. Resolution order: config → `PATH` → fail.
- **Long-lived AList tokens leaking.** The config file is gitignored. The
  tool warns if it detects placeholder values like `PUT-IN-LOCAL-FILE`.
- **Partial uploads.** Each PUT is independent; the manifest update is the
  last step, so a binary upload failure leaves the previous manifest
  intact. Re-running with `--skip-build` resumes cleanly.
- **Multi-line `version:` in pubspec.** The regex assumes the canonical
  `version: X.Y.Z+N` line. The tool fails clearly if it can't find that
  pattern rather than corrupting the file.

## Out of scope (explicit)

- Cross-platform builds (Linux/macOS/iOS).
- macOS code-signing / notarization.
- Multi-channel manifests.
- Auto-publishing release notes anywhere.
- Generating screenshots / store listings.
- Update rollback (just publish a new release).
