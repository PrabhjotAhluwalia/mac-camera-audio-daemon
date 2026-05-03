#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_PATH="$(mktemp /tmp/camera-audio-daemon-test.XXXXXX)"
TEST_DIR="$(mktemp -d /tmp/camera-audio-duration-test.XXXXXX)"
LOCK_PATH="$TEST_DIR/daemon.lock"
SHORT_SECONDS="${SHORT_SECONDS:-5}"
LONG_SECONDS="${LONG_SECONDS:-65}"

cleanup() {
  rm -f "$BIN_PATH"
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

swiftc "$SCRIPT_DIR/camera_audio_daemon.swift" -framework AVFoundation -o "$BIN_PATH"

run_session() {
  local seconds="$1"
  local log_file="$2"

  CAMERA_AUDIO_DAEMON_FORCE_RECORD=1 \
  CAMERA_AUDIO_DAEMON_LOCK_PATH="$LOCK_PATH" \
  CAMERA_AUDIO_RECORDING_DIR="$TEST_DIR" \
    "$BIN_PATH" >"$log_file" 2>&1 &

  local pid="$!"
  sleep "$seconds"
  kill -TERM "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

echo "Testing short session (${SHORT_SECONDS}s) is discarded..."
run_session "$SHORT_SECONDS" "$TEST_DIR/short.log"

short_count="$(find "$TEST_DIR" -maxdepth 1 -name 'camera-session-*.m4a' | wc -l | tr -d ' ')"
if [[ "$short_count" != "0" ]]; then
  echo "Expected 0 recordings after short session, found $short_count"
  cat "$TEST_DIR/short.log"
  exit 1
fi

if ! grep -q "Discarded short camera session" "$TEST_DIR/short.log"; then
  echo "Short-session discard log was not found."
  cat "$TEST_DIR/short.log"
  exit 1
fi

echo "Testing long session (${LONG_SECONDS}s) is kept..."
run_session "$LONG_SECONDS" "$TEST_DIR/long.log"

long_files=("${(@f)$(find "$TEST_DIR" -maxdepth 1 -name 'camera-session-*.m4a' -print)}")
if [[ "${#long_files[@]}" -ne 1 ]]; then
  echo "Expected 1 recording after long session, found ${#long_files[@]}"
  cat "$TEST_DIR/long.log"
  exit 1
fi

if [[ ! -s "${long_files[1]}" ]]; then
  echo "Long-session recording exists but is empty: ${long_files[1]}"
  cat "$TEST_DIR/long.log"
  exit 1
fi

echo "Duration filter test passed."
echo "Kept long recording: ${long_files[1]}"
