# MirrorCore Connection Suite

Host-side tooling to connect to the Android Agent over ADB-forwarded loopback ports.

## Commands

List devices:

```sh
cargo run -p mirrorcore-connection-suite -- devices
```

Set up forwards (control `27183`, video `27184`):

```sh
cargo run -p mirrorcore-connection-suite -- forward --serial <SERIAL>
```

Remove forwards:

```sh
cargo run -p mirrorcore-connection-suite -- unforward --serial <SERIAL>
```

HELLO handshake:

```sh
cargo run -p mirrorcore-connection-suite -- hello --serial <SERIAL>
```

PING/PONG:

```sh
cargo run -p mirrorcore-connection-suite -- ping --serial <SERIAL> --echo-us 4242
```

Capture raw H.264 AnnexB stream to `capture.h264`:

```sh
cargo run -p mirrorcore-connection-suite -- capture --serial <SERIAL> --seconds 10 --out capture.h264
```

Play (requires ffmpeg tools):

```sh
ffplay -fflags nobuffer -flags low_delay -framedrop capture.h264
```
