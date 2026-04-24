#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTROL_PORT="27183"
VIDEO_PORT="27184"
AUDIO_PORT="27185"

ANDROID_HOME_DEFAULT="${HOME}/Library/Android/sdk"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_HOME_DEFAULT}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing dependency: $1" >&2
    exit 1
  fi
}

need adb
need cargo
need rg

if ! command -v ffplay >/dev/null 2>&1; then
  echo "missing dependency: ffplay (ffmpeg). Install via Homebrew: brew install ffmpeg" >&2
  exit 1
fi

if [ ! -d "$ANDROID_HOME" ]; then
  echo "ANDROID_HOME not found at: $ANDROID_HOME" >&2
  echo "Set ANDROID_HOME to your Android SDK path." >&2
  exit 1
fi

cd "$ROOT_DIR"

echo "[1/5] Checking adb device..."
DEV_COUNT="$(adb devices | awk 'NR>1 && $2=="device" {c++} END {print c+0}')"
if [ "$DEV_COUNT" -eq 0 ]; then
  echo "No adb devices. Connect phone and enable USB debugging." >&2
  exit 1
fi

SERIAL="${1:-}"
if [ -z "$SERIAL" ]; then
  if [ "$DEV_COUNT" -gt 1 ]; then
    echo "Multiple devices detected. Re-run with serial:" >&2
    adb devices -l >&2
    exit 1
  fi
  SERIAL="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi
echo "Using device: $SERIAL"

echo "[2/5] Installing Android Agent..."
(
  cd "$ROOT_DIR/mirrorcore-android-agent"
  ANDROID_HOME="$ANDROID_HOME" ./gradlew :app:assembleDebug --no-daemon
)

APK="$ROOT_DIR/mirrorcore-android-agent/app/build/outputs/apk/debug/app-debug.apk"
if [ ! -f "$APK" ]; then
  echo "ERROR: APK not found at $APK" >&2
  exit 1
fi
adb -s "$SERIAL" install -r "$APK" >/dev/null

echo "[3/5] Launching Agent (autostart)..."
adb -s "$SERIAL" shell am start -n dev.mirrorcore.agent/.MainActivity --ez autostart true >/dev/null || true
echo "On your phone: accept the screen-capture prompt when it appears."

echo "[4/5] Setting up port forwards..."
adb -s "$SERIAL" forward "tcp:${CONTROL_PORT}" "tcp:${CONTROL_PORT}" || true
adb -s "$SERIAL" forward "tcp:${VIDEO_PORT}" "tcp:${VIDEO_PORT}" || true
adb -s "$SERIAL" forward "tcp:${AUDIO_PORT}" "tcp:${AUDIO_PORT}" || true

echo "[4.5/5] Waiting for agent ports to come up..."
DEADLINE=$((SECONDS + 45))
READY="0"
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  if adb -s "$SERIAL" shell ss -ltn 2>/dev/null | rg -q ":${CONTROL_PORT}"; then
    if adb -s "$SERIAL" shell ss -ltn 2>/dev/null | rg -q ":${VIDEO_PORT}"; then
      if adb -s "$SERIAL" shell ss -ltn 2>/dev/null | rg -q ":${AUDIO_PORT}"; then
        echo "Agent ports are listening."
        READY="1"
        break
      fi
    fi
  fi
  echo "Waiting... (accept the prompt on the phone)"
  sleep 1
done
if [ "$READY" != "1" ]; then
  echo "ERROR: Agent ports did not come up within 45s." >&2
  echo "Make sure you tapped Allow on the screen-capture prompt and the MirrorCore notification is visible." >&2
  echo "Debug: adb -s $SERIAL logcat -d | rg -n \"MirrorCore\" | tail -n 200" >&2
  exit 1
fi

echo "[5/5] Starting mirror window (ffplay)..."
echo "Close ffplay to stop."

trap 'pkill -P $$ || true' EXIT

(
  cd "$ROOT_DIR"
  cargo run -q -p mirrorcore-connection-suite -- audio --serial "$SERIAL" >/dev/null
) &

exec bash -lc \
  "cd \"$ROOT_DIR\" && \
   cargo run -q -p mirrorcore-connection-suite -- mirror --serial \"$SERIAL\" | \
   ffplay -loglevel warning -fflags nobuffer -flags low_delay -framedrop -probesize 32 -analyzeduration 0 -i -"
