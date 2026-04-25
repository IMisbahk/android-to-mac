# MirrorCore

> Mirror and control your Android phone from your Mac — low-latency, native, no root required.

## Features

- **Screen mirroring** — H.264 video decoded via VideoToolbox, rendered with Metal
- **Audio forwarding** — System audio captured and played on Mac via CoreAudio
- **Touch control** — Click/drag on the mirror window to interact with your phone
- **Keyboard input** — Type on your Mac keyboard, input goes to Android
- **Navigation shortcuts** — Cmd+← (Back), Cmd+H (Home), Cmd+R (Recents)
- **Clipboard sync** — Copy on Mac, paste on Android (and vice versa)
- **File transfer** — Drag-and-drop files onto the mirror window
- **Shell commands** — Execute commands on the device remotely
- **USB & WiFi** — Works over ADB or direct TCP with mDNS discovery

## Quick Start

### Prerequisites

- macOS 13+ (Ventura or later)
- Xcode (for building native macOS app)
- Android SDK with ADB
- Android phone with USB debugging enabled
- `ffmpeg` (for `ffplay` fallback mode): `brew install ffmpeg`
- Rust toolchain: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

### Run

```bash
# One command to rule them all:
./scripts/mirrorcore-run.sh

# Or specify a device serial:
./scripts/mirrorcore-run.sh SERIAL
```

This will:
1. Build and install the Android agent APK
2. Launch the agent and request screen capture permission
3. Set up ADB port forwarding
4. Start the mirror window (native app or ffplay fallback)

### Build Native macOS App

```bash
cd mirrorcore-macos
swift build -c release
```

### CLI Commands

```bash
# Mirror (pipe to ffplay)
cargo run -p mirrorcore-connection-suite -- mirror

# Touch input
cargo run -p mirrorcore-connection-suite -- tap --x 0.5 --y 0.5
cargo run -p mirrorcore-connection-suite -- swipe --x0 0.5 --y0 0.8 --x1 0.5 --y1 0.2

# Navigation
cargo run -p mirrorcore-connection-suite -- back
cargo run -p mirrorcore-connection-suite -- home
cargo run -p mirrorcore-connection-suite -- recents

# Key events
cargo run -p mirrorcore-connection-suite -- key --keycode 66  # Enter
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design.

## Protocol

MirrorCore uses **MCB1** (MirrorCore Binary v1), a custom framing protocol with:
- 32-byte headers with CRC32C integrity
- Little-endian byte ordering
- Message types for video, audio, input, clipboard, files, and shell

See [PROTOCOL.md](PROTOCOL.md) for the wire format specification.

## Repository Structure

```
mirrorcore-protocol/          # Rust: MCB1 binary protocol library
mirrorcore-protocol-cli/      # Rust: CLI for encoding/decoding frames
mirrorcore-connection-suite/   # Rust: Host CLI (mirror, audio, input, etc.)
mirrorcore-android-agent/      # Kotlin: Android agent app
mirrorcore-macos/              # Swift: Native macOS client
scripts/                       # Launch scripts
```

## License

Private.
