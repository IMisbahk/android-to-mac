# MirrorCore Android Agent

Android app that captures screen using MediaProjection and streams H.264 over MirrorCore's MCB1 protocol.

## Build

From repo root:

```sh
cd mirrorcore-android-agent
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew :app:assembleDebug
```
