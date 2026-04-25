# MirrorCore Setup Guide

## macOS Requirements

### Required Software

1. **Xcode** (for native macOS app)
   ```bash
   xcode-select --install
   # Or install Xcode from the App Store
   ```

2. **Rust toolchain**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

3. **Android SDK + ADB**
   ```bash
   # Via Homebrew
   brew install --cask android-platform-tools

   # Or set ANDROID_HOME to your SDK path
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   ```

4. **ffmpeg** (for ffplay fallback)
   ```bash
   brew install ffmpeg
   ```

## Android Requirements

1. **Android 10+** (API 29) — required for audio capture
2. **USB Debugging** enabled:
   - Settings → About Phone → tap Build Number 7 times
   - Settings → Developer Options → USB Debugging → ON
3. **Accessibility Service** enabled for MirrorCore:
   - Settings → Accessibility → MirrorCore → ON
   - This enables touch and key injection

## USB Setup

1. Connect phone via USB cable
2. Authorize USB debugging on the phone prompt
3. Verify connection:
   ```bash
   adb devices
   ```
4. Run MirrorCore:
   ```bash
   ./scripts/mirrorcore-run.sh
   ```

## WiFi Setup

1. Ensure both devices are on the same WiFi network
2. Enable WiFi mode on the Android agent (toggle in app UI)
3. The device will broadcast via mDNS (`_mirrorcore._tcp.`)
4. The macOS client will auto-discover it
5. No ADB forwarding needed in WiFi mode

## Troubleshooting

### "No ADB devices found"

- Ensure USB cable supports data (not charge-only)
- Check USB debugging is enabled on the phone
- Try different USB port
- Run `adb kill-server && adb start-server`

### Screen capture prompt doesn't appear

- Force stop MirrorCore agent: Settings → Apps → MirrorCore → Force Stop
- Re-launch via `adb shell am start -n dev.mirrorcore.agent/.MainActivity`

### Touch input doesn't work

- Verify MirrorCore Accessibility Service is enabled
- Settings → Accessibility → Installed Services → MirrorCore → ON

### Audio not working

- Audio capture requires Android 10+ (API 29)
- Some OEMs restrict AudioPlaybackCapture; check logcat for errors
- Audio only captures media/game audio (not phone calls)

### Video latency is high

- Use USB instead of WiFi for lowest latency
- Check encoder logs: `adb logcat -s MirrorCoreCapture`
- The native macOS app has lower latency than the ffplay fallback

### Build fails

```bash
# Clean Rust build
cargo clean && cargo build

# Clean Android build
cd mirrorcore-android-agent && ./gradlew clean

# Clean Swift build
cd mirrorcore-macos && swift package clean
```
