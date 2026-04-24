#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTROL_PORT="27183"
VIDEO_PORT="27184"

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
  ANDROID_HOME="$ANDROID_HOME" ./gradlew :app:installDebug --no-daemon
)

echo "[3/5] Launching Agent (autostart)..."
adb -s "$SERIAL" shell am start -n dev.mirrorcore.agent/.MainActivity --ez autostart true >/dev/null || true
echo "On your phone: accept the screen-capture prompt when it appears."

echo "[4/5] Setting up port forwards..."
adb -s "$SERIAL" forward "tcp:${CONTROL_PORT}" "tcp:${CONTROL_PORT}" || true
adb -s "$SERIAL" forward "tcp:${VIDEO_PORT}" "tcp:${VIDEO_PORT}" || true

echo "[5/5] Starting mirror window (ffplay)..."
echo "Close ffplay to stop."

exec bash -lc \
  "cd \"$ROOT_DIR\" && \
   cargo run -q -p mirrorcore-connection-suite -- mirror --serial \"$SERIAL\" | \
   ffplay -loglevel warning -fflags nobuffer -flags low_delay -framedrop -probesize 32 -analyzeduration 0 -i -"
