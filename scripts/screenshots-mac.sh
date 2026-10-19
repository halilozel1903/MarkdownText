#!/usr/bin/env bash
# Captures the Mac README screenshots of the example app.
# Usage: scripts/screenshots-mac.sh <project> <Scheme> <scene> [<scene> ...]
# Writes docs/screenshots/mac-<scene>.png, for example mac-editor.png.
#
# Launched with `-screenshot <scene> -screenshot-marker <file>`, the app shows the scene and writes the marker
# once it is on screen.
#
# 1. Preferred: `screencapture -l <window id>` of the app's window, with the id looked up by
#    scripts/window-id.swift (CGWindowListCopyWindowInfo, filtered by the app's process id).
# 2. Fallback: `-render-screenshot <file>` makes the app draw its window into a PNG itself (NSView
#    cacheDisplay at 2x) after the same ready check, and quit. It needs no Screen Recording permission.
set -euo pipefail

PROJECT="$1"; SCHEME="$2"; shift 2
if [ $# -eq 0 ]; then
  echo "No scenes given" >&2
  exit 1
fi
OUT="docs/screenshots"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

xcrun swiftc -O scripts/check-screenshot.swift -o "$TMP/check-screenshot"
xcrun swiftc -O scripts/window-id.swift -o "$TMP/window-id"

xcodebuild build \
  -project "Example/$PROJECT.xcodeproj" \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -derivedDataPath build/mac \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= | tail -n 5

APP="$(find build/mac/Build/Products -maxdepth 2 -name "$SCHEME.app" | head -n 1)"
BIN="$APP/Contents/MacOS/$SCHEME"
if [ -z "$APP" ] || [ ! -x "$BIN" ]; then
  echo "Could not find $SCHEME.app in build/mac/Build/Products" >&2
  exit 1
fi

MIN_WIDTH=1100   # pixels; the window is 1180 points wide (2360 pixels on a Retina display)

# valid_capture <file> <previous capture or empty>
# Rejects missing, blank or narrow PNGs, and a capture identical to the previous scene.
valid_capture() {
  local file="$1" previous="$2" width
  [ -s "$file" ] || return 1
  "$TMP/check-screenshot" "$file" || return 1
  width="$(sips -g pixelWidth "$file" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  [ -n "$width" ] && [ "$width" -ge "$MIN_WIDTH" ] || return 1
  if [ -n "$previous" ] && cmp -s "$file" "$previous"; then
    return 1
  fi
  return 0
}

# wait_for_marker <pid> <marker> <seconds>: waits for the app's ready marker. Fails when the app quits or
# the time runs out.
wait_for_marker() {
  local pid="$1" marker="$2" limit="$3" waited=0
  while [ ! -f "$marker" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "The app quit before it was ready"
      return 1
    fi
    if [ "$waited" -ge "$limit" ]; then
      echo "The app was not ready after $limit seconds"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# wait_for_exit <pid> <seconds>: waits for the process to quit, kills it after the timeout.
# Returns the process's exit status, or 124 on a timeout.
wait_for_exit() {
  local pid="$1" limit="$2" waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# -ApplePersistenceIgnoreState keeps macOS from restoring windows of an earlier run.

# capture_window <scene> <file>: the preferred path, screencapture of the app's window by its id.
capture_window() {
  local scene="$1" file="$2" pid id marker="$TMP/ready-$scene" status=0
  rm -f "$marker"
  "$BIN" -screenshot "$scene" -screenshot-marker "$marker" -ApplePersistenceIgnoreState YES > "$TMP/$scene.log" 2>&1 &
  pid=$!
  wait_for_marker "$pid" "$marker" 180 || status=1
  if [ "$status" -eq 0 ]; then
    # Let the last transition finish.
    sleep 3
    id="$("$TMP/window-id" "$pid" 2>/dev/null || true)"
    if [ -n "$id" ]; then
      screencapture -x -o -l "$id" "$file" || true
    else
      echo "No window found for $scene"
    fi
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  tail -n 20 "$TMP/$scene.log"
  return "$status"
}

# render <scene> <file>: the fallback, the app renders its own window once ready.
render() {
  local scene="$1" file="$2" pid status=0
  "$BIN" -screenshot "$scene" -screenshot-marker "$TMP/render-ready-$scene" -render-screenshot "$file" \
    -ApplePersistenceIgnoreState YES > "$TMP/$scene-render.log" 2>&1 &
  pid=$!
  wait_for_exit "$pid" 240 || status=$?
  tail -n 20 "$TMP/$scene-render.log"
  return "$status"
}

previous=""
for scene in "$@"; do
  capture="$TMP/mac-$scene.png"
  ok=0
  for attempt in 1 2; do
    rm -f "$capture"
    if capture_window "$scene" "$capture" && valid_capture "$capture" "$previous"; then
      ok=1
      break
    fi
    echo "Window capture of mac-$scene failed (attempt $attempt)"
  done
  if [ "$ok" -ne 1 ]; then
    echo "Falling back to the app's own renderer for mac-$scene"
    rm -f "$capture"
    if render "$scene" "$capture" && valid_capture "$capture" "$previous"; then
      ok=1
    fi
  fi
  if [ "$ok" -ne 1 ]; then
    echo "Capture for mac-$scene failed; refusing to commit a broken screenshot." >&2
    exit 1
  fi
  mv "$capture" "$OUT/mac-$scene.png"
  previous="$OUT/mac-$scene.png"
  echo "Captured $previous ($(wc -c < "$previous" | tr -d ' ') bytes)"
done
