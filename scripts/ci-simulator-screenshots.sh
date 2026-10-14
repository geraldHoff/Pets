#!/usr/bin/env bash
# Builds the app for the iOS Simulator, launches it once per mood, and saves
# screenshots plus a short video of the animation to build/screenshots.
# Also zips the simulator .app (build/ScreenPet-simulator.zip) for Appetize.io.
# Runs on macOS only (GitHub Actions macOS runner, or a Mac if you ever get one).
set -euo pipefail

SCHEME=ScreenPet
OUT=build/screenshots
DERIVED=build/DerivedData
MOODS=(happy content sleepy sad) # must match PetCore.Mood raw values

mkdir -p "$OUT"

# Newest iOS runtime; prefer a "Pro" iPhone (Dynamic Island), else any iPhone.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
runtimes = json.load(sys.stdin)["devices"]
def version(key):
    return [int(n) for n in re.findall(r"\d+", key.split("iOS")[-1])]
for key in sorted((k for k in runtimes if "iOS" in k), key=version, reverse=True):
    phones = [d for d in runtimes[key] if d["name"].startswith("iPhone")]
    if not phones:
        continue
    pro = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
    pick = (pro or phones)[0]
    print(pick["udid"])
    print("Using " + pick["name"] + " (" + key + ")", file=sys.stderr)
    break
')
if [[ -z "$UDID" ]]; then
  echo "No iPhone simulator available" >&2
  xcrun simctl list devices available >&2
  exit 1
fi

xcodebuild \
  -project ScreenPet.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")

ditto -c -k --sequesterRsrc --keepParent "$APP" "build/$SCHEME-simulator.zip"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override \
  --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"

for mood in "${MOODS[@]}"; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMood "$mood"
  sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/$mood.png"
  echo "Saved $OUT/$mood.png"
done

# A few seconds of video per mood, to check the frame animation.
for mood in "${MOODS[@]}"; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMood "$mood"
  sleep 2
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$mood.mp4" &
  recorder=$!
  sleep 4
  kill -INT "$recorder"
  wait "$recorder" || true
  echo "Saved $OUT/$mood.mp4"
done

xcrun simctl shutdown "$UDID" || true
