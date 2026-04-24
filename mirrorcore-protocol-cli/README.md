# mirrorcore-protocol-cli

Small debugging CLI for MirrorCore MCB1 framing.

## Decode frames

```sh
cargo run -p mirrorcore-protocol-cli -- decode < frames.bin
```

Preview payload bytes (hex):

```sh
cargo run -p mirrorcore-protocol-cli -- decode --payload-hex-bytes 32 < frames.bin
```

## Encode sample frames

```sh
cargo run -p mirrorcore-protocol-cli -- encode hello --role android --device-name Pixel --caps video,input
```

