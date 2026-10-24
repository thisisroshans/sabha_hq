#!/usr/bin/env bash
# Runs integration_test/e2e_test.dart on an Android emulator/device against
# the LOCAL Firebase emulators with fresh mock data, and records the screen.
#
# Prerequisite, in another terminal (from the repo root):
#   npm --prefix functions run build
#   firebase emulators:start --only auth,firestore,functions --project sabha-hq
#
# Usage:  integration_test/run_e2e_android.sh [device-id]
# Output: build/e2e/sabha_hq_e2e.mp4 (+ test.log)
set -uo pipefail
cd "$(dirname "$0")/.."

# Git Bash on Windows rewrites arguments that start with "/" into Windows
# paths — which would mangle every /sdcard/... path passed to adb shell.
export MSYS_NO_PATHCONV=1

DEVICE="${1:-emulator-5554}"
PKG=com.example.sabha_hq
OUT=build/e2e
FIXTURE=integration_test/e2e_fixture.json

ADB="${ADB:-$(command -v adb || true)}"
if [ -z "$ADB" ]; then
  for candidate in "${ANDROID_HOME:-}/platform-tools/adb" "${LOCALAPPDATA:-}/Android/sdk/platform-tools/adb.exe"; do
    if [ -x "$candidate" ]; then ADB="$candidate"; break; fi
  done
fi
[ -n "$ADB" ] || { echo "adb not found (set ADB=/path/to/adb)"; exit 1; }
adb() { "$ADB" -s "$DEVICE" "$@"; }

mkdir -p "$OUT"
rm -f "$OUT"/*.mp4 "$OUT"/segments.txt

echo "== Seeding mock data into the local emulators"
(cd functions && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
  GCLOUD_PROJECT=sabha-hq node scripts/seed-e2e-emulator.js) || exit 1

echo "== Forwarding emulator ports to $DEVICE (the app connects to localhost)"
for port in 9099 8080 5001; do adb reverse "tcp:$port" "tcp:$port" >/dev/null || exit 1; done

adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard >/dev/null 2>&1
adb shell 'rm -f /sdcard/e2e_*.mp4 /sdcard/e2e_ui.xml'


# screenrecord stops by itself after 180s, so record back-to-back
# segments until told to stop, then stitch them together at the end.
record() {
  local i=0
  while [ -e "$OUT/.recording" ]; do
    i=$((i + 1))
    adb shell screenrecord --bit-rate 8000000 --time-limit 170 "/sdcard/e2e_$(printf %02d "$i").mp4"
  done
}

# Taps the check-in push notification in the shade, if one arrived.
open_push() {
  adb shell cmd statusbar expand-notifications
  sleep 2
  adb shell uiautomator dump /sdcard/e2e_ui.xml >/dev/null 2>&1
  local bounds
  bounds=$(adb shell cat /sdcard/e2e_ui.xml | tr '>' '\n' | grep -m1 'checked in"' \
    | grep -o 'bounds="[^"]*"' | grep -o '[0-9]\+' | tr '\n' ' ')
  if [ -n "$bounds" ]; then
    set -- $bounds
    echo "HOST: push notification found on screen — tapping it"
    adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
  else
    echo "HOST: no check-in push notification on screen — reopening the app instead"
    adb shell cmd statusbar collapse
    adb shell am start -n "$PKG/.MainActivity" >/dev/null
  fi
}

echo "== Building and running the test (this installs the app)"
flutter test integration_test/e2e_test.dart -d "$DEVICE" \
  --dart-define-from-file="$FIXTURE" > "$OUT/test.log" 2>&1 &
TEST_PID=$!

recording=0; went_home=0; opened_push=0
while kill -0 "$TEST_PID" 2>/dev/null; do
  # Pre-grant Android 13+'s notification permission so the system prompt
  # doesn't cover the recording (the app still asks; it's just already yes).
  adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
  # The test's print() output goes through the test runner to stdout
  # (test.log), not to logcat — so that's where the markers are.
  log=$(cat "$OUT/test.log" 2>/dev/null)
  if [ $recording = 0 ] && grep -q 'E2E-STEP: --- Admin login' <<<"$log"; then
    echo "== App is up — recording"
    touch "$OUT/.recording"; record & REC_PID=$!; recording=1
  fi
  if [ $went_home = 0 ] && grep -q 'E2E-STEP: go-home' <<<"$log"; then
    echo "HOST: pressing Home"; adb shell input keyevent KEYCODE_HOME; went_home=1
  fi
  if [ $opened_push = 0 ] && grep -q 'E2E-STEP: open-push' <<<"$log"; then
    open_push; opened_push=1
  fi
  sleep 1
done
wait "$TEST_PID"; TEST_EXIT=$?

sleep 2
rm -f "$OUT/.recording"
adb shell pkill -INT screenrecord >/dev/null 2>&1
[ $recording = 1 ] && wait "$REC_PID" 2>/dev/null
sleep 1

echo "== Collecting the recording"
for f in $(adb shell 'ls /sdcard/e2e_*.mp4 2>/dev/null' | tr -d '\r'); do
  adb pull "$f" "$OUT/" >/dev/null && echo "file '$(basename "$f")'" >> "$OUT/segments.txt"
done
if [ -s "$OUT/segments.txt" ]; then
  (cd "$OUT" && ffmpeg -loglevel error -y -f concat -safe 0 -i segments.txt -c copy sabha_hq_e2e.mp4) \
    && echo "Video: $OUT/sabha_hq_e2e.mp4"
fi

grep -E "E2E-RESULT|HOST:|All tests passed|Some tests failed|EXCEPTION|Expected:|Actual:" "$OUT/test.log" || true
echo "== Test exit code: $TEST_EXIT (full log: $OUT/test.log)"
exit "$TEST_EXIT"
