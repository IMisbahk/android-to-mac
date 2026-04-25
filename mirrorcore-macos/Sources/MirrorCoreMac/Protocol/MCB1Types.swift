import Foundation

// MARK: - Constants

enum MCB1Constants {
    static let magic: [UInt8] = [0x4D, 0x43, 0x42, 0x31] // "MCB1"
    static let headerLen: UInt16 = 32
    static let version: UInt8 = 1
    static let maxPayload: UInt32 = 16 * 1024 * 1024 // 16 MiB
    static let minHeaderLen: UInt16 = 32
    static let maxHeaderLen: UInt16 = 256
}

// MARK: - Message Types

enum MCB1MsgType: UInt8 {
    case hello        = 0x01
    case ping         = 0x02
    case pong         = 0x03
    case videoConfig  = 0x10
    case videoFrame   = 0x11
    case audioConfig  = 0x12
    case audioFrame   = 0x13
    case inputEvent   = 0x20
    case clipboardSync = 0x30
    case fileOffer    = 0x40
    case fileChunk    = 0x41
    case fileEnd      = 0x42
    case fileCancel   = 0x43
    case shellExec    = 0x50
    case shellOutput  = 0x51
}

// MARK: - Flags

struct MCB1Flags {
    static let ackReq: UInt16    = 0x0001
    static let ack: UInt16       = 0x0002
    static let keyframe: UInt16  = 0x0004
    static let compressed: UInt16 = 0x0008
}

// MARK: - Roles

enum MCB1Role: UInt8 {
    case android = 1
    case mac     = 2
}

// MARK: - Capabilities

struct MCB1Caps {
    static let video: UInt32     = 0x0000_0001
    static let input: UInt32     = 0x0000_0002
    static let clipboard: UInt32 = 0x0000_0004
    static let file: UInt32      = 0x0000_0008
}

// MARK: - Header

struct MCB1Header {
    let msgType: UInt8
    let flags: UInt16
    let headerLen: UInt16
    let payloadLen: UInt32
    let seq: UInt32
    let timestampUs: UInt64
    let crc32c: UInt32

    init(msgType: UInt8, flags: UInt16, seq: UInt32, timestampUs: UInt64, payloadLen: UInt32) {
        self.msgType = msgType
        self.flags = flags
        self.headerLen = MCB1Constants.headerLen
        self.payloadLen = payloadLen
        self.seq = seq
        self.timestampUs = timestampUs
        self.crc32c = 0 // Computed during serialization
    }

    init(msgType: UInt8, flags: UInt16, headerLen: UInt16, payloadLen: UInt32,
         seq: UInt32, timestampUs: UInt64, crc32c: UInt32) {
        self.msgType = msgType
        self.flags = flags
        self.headerLen = headerLen
        self.payloadLen = payloadLen
        self.seq = seq
        self.timestampUs = timestampUs
        self.crc32c = crc32c
    }

    /// Serialize header to bytes (32 bytes, CRC zeroed for CRC computation).
    func toBytes(withCRC crc: UInt32 = 0) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 32)
        // magic[4]
        buf[0] = MCB1Constants.magic[0]
        buf[1] = MCB1Constants.magic[1]
        buf[2] = MCB1Constants.magic[2]
        buf[3] = MCB1Constants.magic[3]
        // version:u8
        buf[4] = MCB1Constants.version
        // msg_type:u8
        buf[5] = msgType
        // flags:u16 LE
        buf[6] = UInt8(flags & 0xFF)
        buf[7] = UInt8(flags >> 8)
        // header_len:u16 LE
        buf[8] = UInt8(headerLen & 0xFF)
        buf[9] = UInt8(headerLen >> 8)
        // reserved:u16 LE
        buf[10] = 0
        buf[11] = 0
        // payload_len:u32 LE
        buf[12] = UInt8(payloadLen & 0xFF)
        buf[13] = UInt8((payloadLen >> 8) & 0xFF)
        buf[14] = UInt8((payloadLen >> 16) & 0xFF)
        buf[15] = UInt8((payloadLen >> 24) & 0xFF)
        // seq:u32 LE
        buf[16] = UInt8(seq & 0xFF)
        buf[17] = UInt8((seq >> 8) & 0xFF)
        buf[18] = UInt8((seq >> 16) & 0xFF)
        buf[19] = UInt8((seq >> 24) & 0xFF)
        // timestamp_us:u64 LE
        for i in 0..<8 {
            buf[20 + i] = UInt8((timestampUs >> (i * 8)) & 0xFF)
        }
        // crc32c:u32 LE
        buf[28] = UInt8(crc & 0xFF)
        buf[29] = UInt8((crc >> 8) & 0xFF)
        buf[30] = UInt8((crc >> 16) & 0xFF)
        buf[31] = UInt8((crc >> 24) & 0xFF)
        return buf
    }

    /// Parse header from exactly 32 bytes.
    static func parse(_ data: [UInt8]) -> MCB1Header? {
        guard data.count >= 32 else { return nil }
        // Validate magic
        guard data[0] == MCB1Constants.magic[0],
              data[1] == MCB1Constants.magic[1],
              data[2] == MCB1Constants.magic[2],
              data[3] == MCB1Constants.magic[3] else { return nil }

        let msgType = data[5]
        let flags = UInt16(data[6]) | (UInt16(data[7]) << 8)
        let headerLen = UInt16(data[8]) | (UInt16(data[9]) << 8)
        let payloadLen = UInt32(data[12]) | (UInt32(data[13]) << 8) | (UInt32(data[14]) << 16) | (UInt32(data[15]) << 24)
        let seq = UInt32(data[16]) | (UInt32(data[17]) << 8) | (UInt32(data[18]) << 16) | (UInt32(data[19]) << 24)
        var timestampUs: UInt64 = 0
        for i in 0..<8 {
            timestampUs |= UInt64(data[20 + i]) << (i * 8)
        }
        let crc = UInt32(data[28]) | (UInt32(data[29]) << 8) | (UInt32(data[30]) << 16) | (UInt32(data[31]) << 24)

        // Validate header_len bounds
        guard headerLen >= MCB1Constants.minHeaderLen, headerLen <= MCB1Constants.maxHeaderLen else { return nil }
        // Validate payload_len
        guard payloadLen <= MCB1Constants.maxPayload else { return nil }

        return MCB1Header(
            msgType: msgType,
            flags: flags,
            headerLen: headerLen,
            payloadLen: payloadLen,
            seq: seq,
            timestampUs: timestampUs,
            crc32c: crc
        )
    }
}
