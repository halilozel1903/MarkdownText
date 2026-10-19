#!/usr/bin/env bash
# Captures the iPhone README screenshots of the example app on a simulator.
# Usage: scripts/screenshots.sh <project> <Scheme> <bundle id> <scene> [<scene> ...]
# Writes docs/screenshots/iphone-<scene>.png, for example iphone-document.png.
#
# MarkdownText is a UI library: the scenes render the example app's bundled demo documents (see
# Example/Shared/Screenshots.swift). The app writes tmp/screenshot-ready into its container only once the scene's
# state is on screen; the script waits for that marker and exits with an error instead of keeping a blank, stale
# or home-screen capture.
set -euo pipefail

PROJECT="$1"; SCHEME="$2"; BUNDLE="$3"; shift 3
SCENES=("$@")
if [ ${#SCENES[@]} -eq 0 ]; then
  echo "No scenes given" >&2
  exit 1
fi
OUT="docs/screenshots"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

# Checks a capture's size and colour variety, so a blank or launching frame is rejected.
xcrun swiftc -O scripts/check-screenshot.swift -o "$TMP/check-screenshot"

newest_runtime() {
  xcrun simctl list runtimes available -j | jq -r --arg platform "$1" '
    [.runtimes[] | select(.identifier | test($platform))]
    | sort_by(.version | split(".") | map(tonumber)) | last | .identifier // empty'
}

# pick_iphone: an iPhone Pro on the newest iOS runtime, then any iPhone. Creates one when none exists.
pick_iphone() {
  local devices udid pattern type runtime
  devices=$(xcrun simctl list devices available -j | jq -c '
    [.devices | to_entries | sort_by(.key) | reverse | .[]
     | select(.key | test("iOS")) | .value[] | select(.name | test("^iPhone"))]')
  for pattern in "^iPhone [0-9]+ Pro$" "Pro$" "^iPhone [0-9]+$"; do
    udid=$(jq -r --arg pattern "$pattern" 'map(select(.name | test($pattern))) | .[0].udid // empty' <<< "$devices")
    if [ -n "$udid" ]; then echo "$udid"; return; fi
  done
  udid=$(jq -r '.[0].udid // empty' <<< "$devices")
  if [ -z "$udid" ]; then
    runtime=$(newest_runtime iOS)
    type=$(xcrun simctl list devicetypes -j | jq -r '
      [.devicetypes[] | select(.name | test("^iPhone"))] | last | .identifier // empty')
    if [ -z "$type" ] || [ -z "$runtime" ]; then
      echo "No iPhone simulator, device type or iOS runtime available" >&2
      exit 1
    fi
    udid=$(xcrun simctl create "Screenshots iPhone" "$type" "$runtime")
  fi
  echo "$udid"
}

# build <scheme> <udid>: builds the scheme for the simulator and prints the app's path.
build() {
  local scheme="$1" udid="$2" app
  xcodebuild build \
    -project "Example/$PROJECT.xcodeproj" \
    -scheme "$scheme" \
    -destination "id=$udid" \
    -derivedDataPath "build/$scheme" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= | tail -n 5 >&2
  app=$(find "build/$scheme/Build/Products" -maxdepth 2 -name "$scheme.app" | head -n 1)
  if [ -z "$app" ]; then
    echo "Build product $scheme.app not found" >&2
    exit 1
  fi
  echo "$app"
}

# valid_capture <file> <home capture> <previous capture or empty>
# Rejects blank or launching frames (the checker), a capture identical to the home screen (the app never
# came to the front) and one identical to the previous scene (the app never switched).
valid_capture() {
  local file="$1" home="$2" previous="$3"
  [ -s "$file" ] || return 1
  "$TMP/check-screenshot" "$file" || return 1
  if cmp -s "$file" "$home"; then
    return 1
  fi
  if [ -n "$previous" ] && cmp -s "$file" "$previous"; then
    return 1
  fi
  return 0
}

UDID=$(pick_iphone)
echo "Using iPhone simulator $UDID"
APP=$(build "$SCHEME" "$UDID")

xcrun simctl shutdown all > /dev/null 2>&1 || true
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)

# System banners (such as "Ready for Apple Intelligence") appear shortly after a first boot. Launch the
# app once and let them come and go before capturing anything.
xcrun simctl launch "$UDID" "$BUNDLE" > /dev/null 2>&1 || true
sleep 45
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
# Give the home screen time to settle, then keep a capture of it so a frame where the app never came to
# the front is rejected.
sleep 15
HOME_CAPTURE="$TMP/home.png"
xcrun simctl io "$UDID" screenshot "$HOME_CAPTURE"

previous=""
for scene in "${SCENES[@]}"; do
  file="$OUT/iphone-$scene.png"
  capture="$TMP/iphone-$scene.png"
  ok=""
  for attempt in 1 2 3; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    sleep 1
    rm -f "$CONTAINER/tmp/screenshot-ready"
    if ! xcrun simctl launch "$UDID" "$BUNDLE" -screenshot "$scene"; then
      echo "Could not launch the app for iphone-$scene (attempt $attempt), retrying"
      continue
    fi
    # The app writes this marker once the scene's state is on screen.
    waited=0
    while [ ! -f "$CONTAINER/tmp/screenshot-ready" ] && [ "$waited" -lt 180 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if [ ! -f "$CONTAINER/tmp/screenshot-ready" ]; then
      echo "The app did not report $scene as ready (attempt $attempt), retrying"
      continue
    fi
    # Let the transitions finish.
    sleep $((3 + attempt * 2))
    rm -f "$capture"
    xcrun simctl io "$UDID" screenshot "$capture"
    if valid_capture "$capture" "$HOME_CAPTURE" "$previous"; then
      ok=1
      break
    fi
    echo "Blank, stale or home screen capture for iphone-$scene (attempt $attempt), retrying"
  done
  if [ -z "$ok" ]; then
    echo "Capture for iphone-$scene failed; refusing to commit a broken screenshot." >&2
    exit 1
  fi
  mv "$capture" "$file"
  previous="$file"
  echo "Captured $file ($(wc -c < "$file" | tr -d ' ') bytes)"
done

xcrun simctl shutdown "$UDID" || true
