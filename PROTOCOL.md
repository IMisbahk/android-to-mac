# MirrorCore Protocol (MCB1)

MCB1 is a language-agnostic binary framing protocol used by MirrorCore to carry:

- Video (H.264) from Android → macOS
- Control (input events), clipboard sync, and file transfer (bi-directional)

MCB1 is designed to be inspectable, modular, and low-latency.

## Transport

MirrorCore uses **two TCP ports**:

- **Control channel** (bi-directional): `HELLO`, `PING/PONG`, `INPUT_EVENT`, `CLIPBOARD_SYNC`, `FILE_*`
- **Video channel** (Android → macOS): `VIDEO_CONFIG`, `VIDEO_FRAME`
- **Audio channel** (Android → macOS): `AUDIO_CONFIG`, `AUDIO_FRAME`

Initially, both ports are expected to run over **ADB port forwarding** (USB). The protocol is also compatible with direct TCP for WiFi mode.

## Framing

Each message is:

```
HEADER (fixed 32 bytes) + PAYLOAD (payload_len bytes)
```

All integer fields are **little-endian**.

### Header layout (32 bytes)

- `magic[4]`: ASCII `MCB1`
- `version:u8`: `1`
- `msg_type:u8`: message type enum
- `flags:u16`: bitset
- `header_len:u16`: `32` (forward-compat)
- `reserved:u16`: `0`
- `payload_len:u32`: `0..=MAX_PAYLOAD`
- `seq:u32`: per-sender monotonic (wrap allowed)
- `timestamp_us:u64`: sender monotonic microseconds since its start
- `crc32c:u32`: CRC32C over `(header with crc32c field zeroed) + payload`

### Flags

- `0x0001` `ACK_REQ` (control; reserved)
- `0x0002` `ACK` (control; reserved)
- `0x0004` `KEYFRAME` (video frames)
- `0x0008` `COMPRESSED` (reserved)

### Safety limits

- `MAX_PAYLOAD = 16 MiB` (Phase 1)
- `header_len` must be `32..=256` (Phase 1)

## Message types

Values are stable and shared across platforms.

### Control channel messages

#### `0x01 HELLO`

Payload:

- `role:u8` (1=ANDROID, 2=MAC)
- `caps:u32` bitset (VIDEO, INPUT, CLIPBOARD, FILE)
- `device_name:str` (u16 length + UTF-8)
- `session_nonce:u64`

#### `0x02 PING` / `0x03 PONG`

Payload:

- `echo_timestamp_us:u64`

#### `0x20 INPUT_EVENT`

Payload:

- `kind:u8` (1=TOUCH, 2=KEY)

TOUCH:

- `action:u8` (0=DOWN,1=MOVE,2=UP,3=CANCEL)
- `pointer_id:u8`
- `x_norm:f32` (0..1)
- `y_norm:f32` (0..1)
- `pressure:f32` (0..1)
- `buttons:u16`
- `reserved:u16`

KEY:

- `action:u8` (0=DOWN,1=UP)
- `android_keycode:u32`
- `meta_state:u32`

#### `0x30 CLIPBOARD_SYNC`

Payload:

- `origin:u8` (1=ANDROID,2=MAC)
- `clip_id:u64` (monotonic per-origin)
- `mime:str` (u16 len + UTF-8), initially `text/plain`
- `data:bytes` (u32 len + bytes)

#### `0x40 FILE_OFFER`

Payload:

- `transfer_id:u64`
- `name:str` (u16 len + UTF-8)
- `size:u64`

#### `0x41 FILE_CHUNK`

Payload:

- `transfer_id:u64`
- `offset:u64`
- `data:bytes` (u32 len + bytes) (chunk target: 256 KiB)

#### `0x42 FILE_END`

Payload:

- `transfer_id:u64`
- `sha256[32]` (reserved for Phase 2+; optional in Phase 1)

#### `0x43 FILE_CANCEL`

Payload:

- `transfer_id:u64`

### Video channel messages

#### `0x10 VIDEO_CONFIG`

Payload:

- `codec:u8` (1=H264)
- `width:u16`, `height:u16`
- `fps_times_1000:u32`
- `sps:bytes` (u32 len + bytes, raw NAL without startcode)
- `pps:bytes` (u32 len + bytes, raw NAL without startcode)

#### `0x11 VIDEO_FRAME`

Payload:

- `pts_us:u64`
- `data:bytes` (u32 len + bytes), AnnexB access unit (start codes allowed)

### Audio channel messages

#### `0x12 AUDIO_CONFIG`

Payload:

- `codec:u8` (1=PCM_S16LE)
- `sample_rate:u32` (e.g. 48000)
- `channels:u8` (1 or 2)
- `frame_samples:u16` (samples per channel per frame; e.g. 960 for 20ms @48k)
- `reserved:u16` (0)

#### `0x13 AUDIO_FRAME`

Payload:

- `pts_us:u64`
- `data:bytes` (u32 len + bytes), interleaved PCM_S16LE

## Forward compatibility rules

- Unknown `msg_type` is not fatal: decoders should surface a generic frame with raw payload.
- Future versions may set `header_len > 32`. Phase 1 implementations **must reject** `header_len < 32` and reject `header_len > 256`.
