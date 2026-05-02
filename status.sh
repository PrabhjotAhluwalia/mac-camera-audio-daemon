#!/bin/zsh
set -euo pipefail

LABEL="com.prabhjot.camera-audio-daemon"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECORDING_DIR="$SCRIPT_DIR/Voice recordings"

launchctl print "gui/$(id -u)/$LABEL" | sed -n '1,40p'

echo
echo "Daemon processes:"
pgrep -fl camera-audio-daemon || true

echo
echo "Camera hardware state:"
ioreg -r -l -c AppleH16CamIn | grep 'FrontCameraActive' || true

echo
echo "Latest recordings:"
ls -lt "$RECORDING_DIR" 2>/dev/null | head -n 8 || true
