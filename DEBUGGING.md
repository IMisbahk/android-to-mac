# Debugging (Phase 1)

Phase 1 debugging is focused on the protocol framing layer.

## Protocol CLI

After building, the CLI can:

- Decode frames from stdin or a file
- Encode sample frames for smoke testing

Examples (once `mirrorcore-protocol-cli` is implemented):

```sh
# Encode a HELLO then decode it back
cargo run -p mirrorcore-protocol-cli -- encode hello --role android --device-name Pixel --caps video,input | \
  cargo run -p mirrorcore-protocol-cli -- decode
```

Decode with payload preview:

```sh
cargo run -p mirrorcore-protocol-cli -- decode --payload-hex-bytes 32 < frames.bin
```

## Connection suite (host)

The host-side connection suite automates ADB forwarding, control handshake, and raw H.264 capture:

```sh
cargo run -p mirrorcore-connection-suite -- devices
cargo run -p mirrorcore-connection-suite -- forward --serial <SERIAL>
cargo run -p mirrorcore-connection-suite -- hello --serial <SERIAL>
cargo run -p mirrorcore-connection-suite -- capture --serial <SERIAL> --seconds 10 --out capture.h264
```
