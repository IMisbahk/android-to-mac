# MirrorCore Debugging Guide

## Logging

### Android Agent Logs

```bash
# All MirrorCore logs
adb logcat -s MirrorCoreControl MirrorCoreCapture MirrorCoreInput MirrorCoreAudio MirrorCoreWifi

# Filter by component
adb logcat -s MirrorCoreControl   # Control channel (HELLO, input, clipboard, files, shell)
adb logcat -s MirrorCoreCapture   # Video capture and encoding
adb logcat -s MirrorCoreInput     # Touch/key injection
adb logcat -s MirrorCoreAudio     # Audio capture
```

### macOS Client Logs

The native macOS app prints timestamped logs to stdout:
```bash
./.build/release/MirrorCoreMac 2>&1 | tee mirrorcore.log
```

## Protocol Debugging

### Encode/Decode Frames

```bash
# Encode a HELLO frame
cargo run -p mirrorcore-protocol-cli -- encode hello --role mac --device-name "Debug" --caps video,input

# Decode from stdin
echo -n "..." | cargo run -p mirrorcore-protocol-cli -- decode

# Roundtrip test
cargo run -p mirrorcore-protocol-cli -- encode hello --role mac --device-name Test --caps video,input | \
  cargo run -p mirrorcore-protocol-cli -- decode
```

### Run Protocol Tests

```bash
cargo test -p mirrorcore-protocol
```

## Network Debugging

### Check Agent Ports

```bash
# Verify the agent is listening
adb shell ss -ltn | grep -E '27183|27184|27185'
```

### Port Forwarding

```bash
# Manual port forward setup
adb forward tcp:27183 tcp:27183
adb forward tcp:27184 tcp:27184
adb forward tcp:27185 tcp:27185

# Verify forwards
adb forward --list

# Remove all forwards
adb forward --remove-all
```

### Test Connection

```bash
# Test control channel handshake
cargo run -p mirrorcore-connection-suite -- tap --x 0.5 --y 0.5
# If this prints "sent tap", the control channel is working

# Test video stream
cargo run -p mirrorcore-connection-suite -- mirror | head -c 1024 | xxd | head
# If you see binary data, the video stream is working
```

## Video Debugging

### Check Encoder Output

```bash
# Watch encoder stats
adb logcat -s MirrorCoreCapture | grep -i "frame\|config\|sps\|pps"
```

### Dump Raw H.264

```bash
# Save raw H.264 to file
cargo run -p mirrorcore-connection-suite -- mirror > dump.h264

# Play the dump
ffplay -f h264 dump.h264
```

## Input Debugging

### Test Touch Injection

```bash
# Tap center of screen
cargo run -p mirrorcore-connection-suite -- tap --x 0.5 --y 0.5

# Swipe up (scroll down)
cargo run -p mirrorcore-connection-suite -- swipe --x0 0.5 --y0 0.8 --x1 0.5 --y1 0.2
```

### Test Key Injection

```bash
# Send BACK
cargo run -p mirrorcore-connection-suite -- back

# Send HOME
cargo run -p mirrorcore-connection-suite -- home

# Send ENTER
cargo run -p mirrorcore-connection-suite -- key --keycode 66

# Send Volume Down
cargo run -p mirrorcore-connection-suite -- key --keycode 25
```

### Check Accessibility Service

```bash
# Check if service is running
adb shell dumpsys accessibility | grep MirrorCore
```

## Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| Black screen | MediaProjection not granted | Accept the prompt on phone |
| No touch response | Accessibility service not enabled | Enable in Settings → Accessibility |
| No audio | Android < 10 or USAGE not media | Check API level, app must play media audio |
| High latency (>200ms) | WiFi congestion or encoder settings | Use USB, check encoder bitrate |
| CRC mismatch errors | Data corruption on wire | Check USB cable quality |
| Connection refused | Agent not running | Re-launch agent: `adb shell am start -n dev.mirrorcore.agent/.MainActivity` |
