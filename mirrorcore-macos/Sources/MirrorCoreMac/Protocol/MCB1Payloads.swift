import Foundation

// MARK: - Payload Helpers

enum PayloadReader {
    static func readU8(_ data: inout Data) -> UInt8? {
        guard !data.isEmpty else { return nil }
        let v = data[data.startIndex]
        data = data.dropFirst()
        return v
    }

    static func readU16LE(_ data: inout Data) -> UInt16? {
        guard data.count >= 2 else { return nil }
        let v = UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
        data = data.dropFirst(2)
        return v
    }

    static func readU32LE(_ data: inout Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        let s = data.startIndex
        let v = UInt32(data[s]) | (UInt32(data[s+1]) << 8) | (UInt32(data[s+2]) << 16) | (UInt32(data[s+3]) << 24)
        data = data.dropFirst(4)
        return v
    }

    static func readU64LE(_ data: inout Data) -> UInt64? {
        guard data.count >= 8 else { return nil }
        let s = data.startIndex
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(data[s + i]) << (i * 8)
        }
        data = data.dropFirst(8)
        return v
    }

    static func readF32LE(_ data: inout Data) -> Float? {
        guard let bits = readU32LE(&data) else { return nil }
        return Float(bitPattern: bits)
    }

    static func readI32LE(_ data: inout Data) -> Int32? {
        guard let bits = readU32LE(&data) else { return nil }
        return Int32(bitPattern: bits)
    }

    static func readStrU16(_ data: inout Data) -> String? {
        guard let len = readU16LE(&data) else { return nil }
        guard data.count >= Int(len) else { return nil }
        let strData = data.prefix(Int(len))
        data = data.dropFirst(Int(len))
        return String(data: strData, encoding: .utf8)
    }

    static func readBytesU32(_ data: inout Data) -> Data? {
        guard let len = readU32LE(&data) else { return nil }
        guard data.count >= Int(len) else { return nil }
        let bytes = data.prefix(Int(len))
        data = data.dropFirst(Int(len))
        return Data(bytes)
    }
}

enum PayloadWriter {
    static func writeU8(_ out: inout Data, _ v: UInt8) {
        out.append(v)
    }

    static func writeU16LE(_ out: inout Data, _ v: UInt16) {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8(v >> 8))
    }

    static func writeU32LE(_ out: inout Data, _ v: UInt32) {
        out.append(UInt8(v & 0xFF))
        out.append(UInt8((v >> 8) & 0xFF))
        out.append(UInt8((v >> 16) & 0xFF))
        out.append(UInt8((v >> 24) & 0xFF))
    }

    static func writeU64LE(_ out: inout Data, _ v: UInt64) {
        for i in 0..<8 {
            out.append(UInt8((v >> (i * 8)) & 0xFF))
        }
    }

    static func writeF32LE(_ out: inout Data, _ v: Float) {
        writeU32LE(&out, v.bitPattern)
    }

    static func writeI32LE(_ out: inout Data, _ v: Int32) {
        writeU32LE(&out, UInt32(bitPattern: v))
    }

    static func writeStrU16(_ out: inout Data, _ s: String) {
        let utf8 = Data(s.utf8)
        writeU16LE(&out, UInt16(utf8.count))
        out.append(utf8)
    }

    static func writeBytesU32(_ out: inout Data, _ bytes: Data) {
        writeU32LE(&out, UInt32(bytes.count))
        out.append(bytes)
    }
}

// MARK: - Payload Types

struct HelloPayload {
    let role: MCB1Role
    let caps: UInt32
    let deviceName: String
    let sessionNonce: UInt64

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU8(&out, role.rawValue)
        PayloadWriter.writeU32LE(&out, caps)
        PayloadWriter.writeStrU16(&out, deviceName)
        PayloadWriter.writeU64LE(&out, sessionNonce)
        return out
    }

    static func decode(_ data: Data) -> HelloPayload? {
        var buf = data
        guard let roleRaw = PayloadReader.readU8(&buf),
              let role = MCB1Role(rawValue: roleRaw),
              let caps = PayloadReader.readU32LE(&buf),
              let name = PayloadReader.readStrU16(&buf),
              let nonce = PayloadReader.readU64LE(&buf) else { return nil }
        return HelloPayload(role: role, caps: caps, deviceName: name, sessionNonce: nonce)
    }
}

struct PingPayload {
    let echoTimestampUs: UInt64

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU64LE(&out, echoTimestampUs)
        return out
    }

    static func decode(_ data: Data) -> PingPayload? {
        var buf = data
        guard let ts = PayloadReader.readU64LE(&buf) else { return nil }
        return PingPayload(echoTimestampUs: ts)
    }
}

struct VideoConfigPayload {
    let codec: UInt8
    let width: UInt16
    let height: UInt16
    let fpsX1000: UInt32
    let sps: Data
    let pps: Data

    static func decode(_ data: Data) -> VideoConfigPayload? {
        var buf = data
        guard let codec = PayloadReader.readU8(&buf),
              let w = PayloadReader.readU16LE(&buf),
              let h = PayloadReader.readU16LE(&buf),
              let fps = PayloadReader.readU32LE(&buf),
              let sps = PayloadReader.readBytesU32(&buf),
              let pps = PayloadReader.readBytesU32(&buf) else { return nil }
        return VideoConfigPayload(codec: codec, width: w, height: h, fpsX1000: fps, sps: sps, pps: pps)
    }
}

struct VideoFramePayload {
    let ptsUs: UInt64
    let data: Data

    static func decode(_ raw: Data) -> VideoFramePayload? {
        var buf = raw
        guard let pts = PayloadReader.readU64LE(&buf),
              let frameData = PayloadReader.readBytesU32(&buf) else { return nil }
        return VideoFramePayload(ptsUs: pts, data: frameData)
    }
}

struct AudioConfigPayload {
    let codec: UInt8
    let sampleRate: UInt32
    let channels: UInt8
    let frameSamples: UInt16

    static func decode(_ data: Data) -> AudioConfigPayload? {
        var buf = data
        guard let codec = PayloadReader.readU8(&buf),
              let rate = PayloadReader.readU32LE(&buf),
              let ch = PayloadReader.readU8(&buf),
              let fs = PayloadReader.readU16LE(&buf) else { return nil }
        // Skip reserved u16
        _ = PayloadReader.readU16LE(&buf)
        return AudioConfigPayload(codec: codec, sampleRate: rate, channels: ch, frameSamples: fs)
    }
}

struct AudioFramePayload {
    let ptsUs: UInt64
    let data: Data

    static func decode(_ raw: Data) -> AudioFramePayload? {
        var buf = raw
        guard let pts = PayloadReader.readU64LE(&buf),
              let pcm = PayloadReader.readBytesU32(&buf) else { return nil }
        return AudioFramePayload(ptsUs: pts, data: pcm)
    }
}

// MARK: - Input Events

enum TouchAction: UInt8 {
    case down   = 0
    case move   = 1
    case up     = 2
    case cancel = 3
}

enum KeyAction: UInt8 {
    case down = 0
    case up   = 1
}

struct TouchEventPayload {
    let action: TouchAction
    let pointerId: UInt8
    let xNorm: Float
    let yNorm: Float
    let pressure: Float
    let buttons: UInt16

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU8(&out, 1) // kind = TOUCH
        PayloadWriter.writeU8(&out, action.rawValue)
        PayloadWriter.writeU8(&out, pointerId)
        PayloadWriter.writeF32LE(&out, xNorm)
        PayloadWriter.writeF32LE(&out, yNorm)
        PayloadWriter.writeF32LE(&out, pressure)
        PayloadWriter.writeU16LE(&out, buttons)
        PayloadWriter.writeU16LE(&out, 0) // reserved
        return out
    }
}

struct KeyEventPayload {
    let action: KeyAction
    let androidKeycode: UInt32
    let metaState: UInt32

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU8(&out, 2) // kind = KEY
        PayloadWriter.writeU8(&out, action.rawValue)
        PayloadWriter.writeU32LE(&out, androidKeycode)
        PayloadWriter.writeU32LE(&out, metaState)
        return out
    }
}

// MARK: - Clipboard

struct ClipboardSyncPayload {
    let origin: MCB1Role
    let clipId: UInt64
    let mime: String
    let data: Data

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU8(&out, origin.rawValue)
        PayloadWriter.writeU64LE(&out, clipId)
        PayloadWriter.writeStrU16(&out, mime)
        PayloadWriter.writeBytesU32(&out, data)
        return out
    }

    static func decode(_ raw: Data) -> ClipboardSyncPayload? {
        var buf = raw
        guard let roleRaw = PayloadReader.readU8(&buf),
              let role = MCB1Role(rawValue: roleRaw),
              let clipId = PayloadReader.readU64LE(&buf),
              let mime = PayloadReader.readStrU16(&buf),
              let data = PayloadReader.readBytesU32(&buf) else { return nil }
        return ClipboardSyncPayload(origin: role, clipId: clipId, mime: mime, data: data)
    }
}

// MARK: - File Transfer

struct FileOfferPayload {
    let transferId: UInt64
    let name: String
    let size: UInt64

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU64LE(&out, transferId)
        PayloadWriter.writeStrU16(&out, name)
        PayloadWriter.writeU64LE(&out, size)
        return out
    }

    static func decode(_ raw: Data) -> FileOfferPayload? {
        var buf = raw
        guard let tid = PayloadReader.readU64LE(&buf),
              let name = PayloadReader.readStrU16(&buf),
              let size = PayloadReader.readU64LE(&buf) else { return nil }
        return FileOfferPayload(transferId: tid, name: name, size: size)
    }
}

struct FileChunkPayload {
    let transferId: UInt64
    let offset: UInt64
    let data: Data

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU64LE(&out, transferId)
        PayloadWriter.writeU64LE(&out, offset)
        PayloadWriter.writeBytesU32(&out, data)
        return out
    }
}

struct FileEndPayload {
    let transferId: UInt64

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU64LE(&out, transferId)
        return out
    }
}

struct FileCancelPayload {
    let transferId: UInt64

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeU64LE(&out, transferId)
        return out
    }
}

// MARK: - Shell

struct ShellExecPayload {
    let command: String

    func encode() -> Data {
        var out = Data()
        PayloadWriter.writeStrU16(&out, command)
        return out
    }
}

struct ShellOutputPayload {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data

    static func decode(_ raw: Data) -> ShellOutputPayload? {
        var buf = raw
        guard let code = PayloadReader.readI32LE(&buf),
              let out = PayloadReader.readBytesU32(&buf),
              let err = PayloadReader.readBytesU32(&buf) else { return nil }
        return ShellOutputPayload(exitCode: code, stdout: out, stderr: err)
    }
}
