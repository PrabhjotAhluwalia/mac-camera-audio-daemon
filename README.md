# Camera Audio Daemon (macOS)

This utility runs in the background on macOS and:

1. Detects when any camera is actively in use by another app.
2. Starts microphone recording automatically when camera turns on.
3. Stops recording automatically when camera turns off.
4. Creates a separate file for each on/off camera session.

Use only where recording is legal and everyone who needs to consent has consented.

Output folder:

- `./Voice recordings`

Output format:

- `camera-session-YYYY-MM-DD_HH-mm-ss.m4a`

## Install and run

```bash
cd mac-camera-audio-daemon
chmod +x install.sh start.sh stop.sh status.sh
./install.sh
```

The first time, macOS should ask for microphone access. Allow it.

## Control

Start:

```bash
./start.sh
```

Stop:

```bash
./stop.sh
```

Status:

```bash
./status.sh
```

## Notes

- This records **microphone audio**, not remote-party system audio.
- It works for browser and non-browser apps as long as camera usage is detected by macOS AVFoundation.
- If microphone permission is denied, no recording files will be produced.
- Recordings are ignored by git so private audio is not committed accidentally.
