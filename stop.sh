#!/bin/zsh
set -euo pipefail

LABEL="com.prabhjot.camera-audio-daemon"
BIN_PATH="$HOME/Library/Application Support/CameraAudioDaemon/camera-audio-daemon"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
pkill -f "$BIN_PATH" >/dev/null 2>&1 || true
echo "Stopped: $LABEL"
