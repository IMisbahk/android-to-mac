# MirrorCore Architecture

## Overview

MirrorCore is a production-grade system for mirroring and controlling an Android device from a macOS machine. It uses a custom binary framing protocol (**MCB1**) over ADB port forwarding (USB) or direct TCP (WiFi).

```
┌──────────────────┐                        ┌──────────────────┐
│  macOS Client    │                        │  Android Agent   │
│  (Swift/AppKit)  │◄──── MCB1/TCP ────────►│  (Kotlin/SDK)    │
│                  │                        │                  │
│  ┌────────────┐  │    Control:27183       │  ┌────────────┐  │
│  │ Metal      │  │◄───────────────────────│  │ MediaProj. │  │
│  │ Renderer   │  │    Video:27184        │  │ + H.264    │  │
│  │            │  │◄───────────────────────│  │ Encoder    │  │
│  └────────────┘  │    Audio:27185        │  └────────────┘  │
│  ┌────────────┐  │◄───────────────────────│  ┌────────────┐  │
│  │ VT H.264   │  │                        │  │ Audio      │  │
│  │ Decoder    │  │                        │  │ Capture    │  │
│  └────────────┘  │                        │  └────────────┘  │
│  ┌────────────┐  │                        │  ┌────────────┐  │
│  │ Input      │  │──── Touch/Key ────────►│  │ Accessib.  │  │
│  │ Mapper     │  │                        │  │ Service    │  │
│  └────────────┘  │                        │  └────────────┘  │
└──────────────────┘                        └──────────────────┘
        │                                           │
        └──── ADB USB / WiFi TCP (mDNS) ───────────┘
```

## Components

### 1. Android Agent (`mirrorcore-android-agent/`)

Runs on the device, no root required. Kotlin + Android SDK.

| Module | Purpose |
|---|---|
| `MainActivity` | Entry point, requests MediaProjection permission |
| `CaptureService` | Foreground service managing screen capture lifecycle |
| `ControlServer` | TCP server on :27183, MCB1 HELLO/PING, input dispatch, clipboard, file, shell |
| `VideoServer` | TCP server on :27184, streams H.264 NAL units via MCB1 |
| `AudioServer` | TCP server on :27185, captures system audio via AudioPlaybackCapture |
| `InputInjection` | AccessibilityService for touch/key injection + global actions |
| `WifiDiscovery` | mDNS/NSD broadcast for wireless mode |

### 2. macOS Client (`mirrorcore-macos/`)

Native Swift/AppKit application. No Electron, no web views.

| Module | Purpose |
|---|---|
| `Protocol/` | MCB1 framing codec (CRC32C, header, all payload types) |
| `Network/` | TCP connections, ADB bridge, Bonjour discovery |
| `Video/` | VideoToolbox H.264 decoder, Metal renderer |
| `Audio/` | CoreAudio PCM playback with ring buffer |
| `Input/` | Mouse→touch mapping, keyboard→Android keycodes, shortcuts |
| `Clipboard/` | Bi-directional NSPasteboard ↔ Android clipboard sync |
| `FileTransfer/` | Drag-and-drop chunked file transfer |
| `App/` | Window, app delegate, menu bar |

### 3. Connection Suite (`mirrorcore-connection-suite/`)

Rust CLI tool for headless operation and debugging.

```
mirrorcore-connection-suite mirror   # Stream H.264 to stdout (pipe to ffplay)
mirrorcore-connection-suite audio    # Play device audio
mirrorcore-connection-suite tap      # Send touch event
mirrorcore-connection-suite swipe    # Send swipe gesture
mirrorcore-connection-suite key      # Send Android keycode
mirrorcore-connection-suite back     # Send BACK
mirrorcore-connection-suite home     # Send HOME
mirrorcore-connection-suite recents  # Send RECENTS
```

### 4. Protocol Library (`mirrorcore-protocol/`)

Rust crate implementing MCB1 binary framing. See `PROTOCOL.md`.

### 5. Bridge Layer

- **USB**: ADB port forwarding (`adb forward tcp:PORT tcp:PORT`)
- **WiFi**: Direct TCP, device discovered via mDNS (`_mirrorcore._tcp.`)

## Data Flow

1. User connects phone via USB (or WiFi)
2. `mirrorcore-run.sh` installs APK, launches agent, sets up port forwards
3. macOS client connects to three TCP channels
4. MCB1 HELLO handshake establishes session
5. Video: Android MediaProjection → MediaCodec H.264 → VIDEO_FRAME → VideoToolbox → Metal
6. Audio: Android AudioPlaybackCapture → PCM_S16LE → AUDIO_FRAME → CoreAudio
7. Input: NSEvent → normalized coords → INPUT_EVENT → AccessibilityService
8. Clipboard: NSPasteboard poll → CLIPBOARD_SYNC → ClipboardManager (and reverse)
9. Files: Drag-and-drop → FILE_OFFER/CHUNK/END → Downloads directory

## Keyboard Shortcuts (macOS Client)

| Shortcut | Android Action |
|---|---|
| Escape | BACK |
| Cmd+← | BACK |
| Cmd+H | HOME |
| Cmd+R | RECENTS |
| Cmd+P | POWER (lock screen) |
| Cmd+↑ | VOLUME UP |
| Cmd+↓ | VOLUME DOWN |
| Cmd+M | NOTIFICATIONS |

## Requirements

- macOS 13+ (Ventura) with Xcode for native app build
- Android 10+ (API 29) for audio capture
- Android 14+ needs `MediaProjection` callback registration
- ADB + USB debugging enabled
- `ffplay` (from ffmpeg) for CLI fallback mode
