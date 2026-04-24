# Setup (Phase 1)

Phase 1 only requires Rust.

## Requirements

- Rust toolchain (`rustc`, `cargo`)
- Android SDK (for Phase 2+)

## Build & test

From repository root:

```sh
cargo test
```

Build the CLI:

```sh
cargo build -p mirrorcore-protocol-cli
```

## Phase 2: Android Agent

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
cd mirrorcore-android-agent
./gradlew testDebugUnitTest
./gradlew :app:assembleDebug
```
