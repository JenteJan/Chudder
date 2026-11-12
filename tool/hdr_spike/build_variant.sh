#!/usr/bin/env bash
# build_variant.sh <entry.dart> <name> [local]
# Builds the worktree's Windows release with the given entry point, on the
# stock engine or (with "local") on C:\src\flutter's out\host_release, and
# copies the result to tool/hdr_spike/builds/<name>.
set -e
cd "$(dirname "$0")/../.."
F=/c/Users/jente/fvm/versions/3.44.9/bin/flutter
ARGS=(build windows --release -t "$1")
if [ "$3" = "local" ]; then
  ARGS+=(--local-engine-src-path='C:\src\flutter\engine\src' --local-engine=host_release --local-engine-host=host_release)
fi
rm -f build/windows/x64/runner/Release/data/app.so
"$F" "${ARGS[@]}" > "/tmp/build_$2.log" 2>&1 || { grep -E "error|Error|failed|Exception" "/tmp/build_$2.log" | head -15; echo "BUILD FAILED: $2"; exit 1; }
grep -E "Built" "/tmp/build_$2.log"
rm -rf "tool/hdr_spike/builds/$2"
mkdir -p tool/hdr_spike/builds
cp -r build/windows/x64/runner/Release "tool/hdr_spike/builds/$2"
md5sum "tool/hdr_spike/builds/$2/flutter_windows.dll"
