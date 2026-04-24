# MirrorCore Architecture (High Level)

MirrorCore is composed of three major components:

1. **Android Agent** (runs on device, no root)
   - Captures screen via MediaProjection
   - Encodes H.264 via MediaCodec
   - Streams video to macOS
   - Receives and injects input events (Accessibility / InputManager where permitted)
   - Syncs clipboard and handles file transfer

2. **macOS Client**
   - Receives H.264 stream
   - Decodes via VideoToolbox
   - Renders low-latency window
   - Captures mouse/keyboard and sends control events
   - Syncs clipboard and supports drag-and-drop file transfer

3. **Bridge Layer**
   - ADB port forwarding (USB) and optional direct TCP (WiFi)
   - Lightweight, inspectable protocol (MCB1)

See `PROTOCOL.md` for the Phase 1 protocol specification.

