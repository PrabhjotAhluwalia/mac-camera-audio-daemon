#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.prabhjot.camera-audio-daemon"
APP_DIR="$HOME/Library/Application Support/CameraAudioDaemon"
BIN_PATH="$APP_DIR/camera-audio-daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/CameraAudioDaemon"
RECORDING_DIR="$SCRIPT_DIR/Voice recordings"

mkdir -p "$APP_DIR" "$LOG_DIR" "$RECORDING_DIR" "$HOME/Library/LaunchAgents"

swiftc "$SCRIPT_DIR/camera_audio_daemon.swift" -framework AVFoundation -o "$BIN_PATH"
chmod +x "$BIN_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CAMERA_AUDIO_RECORDING_DIR</key>
    <string>$RECORDING_DIR</string>
  </dict>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
pkill -f "$BIN_PATH" >/dev/null 2>&1 || true
sleep 1
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed and started: $LABEL"
echo "Binary: $BIN_PATH"
echo "Plist:  $PLIST_PATH"
