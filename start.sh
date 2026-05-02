#!/bin/zsh
set -euo pipefail

LABEL="com.prabhjot.camera-audio-daemon"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "Started: $LABEL"
