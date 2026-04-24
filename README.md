# MirrorCore

MirrorCore is a production-grade, low-latency bridge for mirroring and controlling an Android device from macOS.

## Phases

### Phase 1 — Protocol (MCB1)

This repository begins with a language-agnostic binary framing protocol plus a Rust reference implementation:

- `mirrorcore-protocol/`: framing + CRC32C + typed message payload codecs
- `mirrorcore-protocol-cli/`: small CLI to encode/decode frames for debugging

## Status

Phase 1 in progress: protocol + reference implementation + tests.

