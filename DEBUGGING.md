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

