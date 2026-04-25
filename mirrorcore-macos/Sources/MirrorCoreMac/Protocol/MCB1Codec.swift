import Foundation

// MARK: - MCB1 Frame

struct MCB1Frame {
    let header: MCB1Header
    let payload: Data
}

// MARK: - MCB1 Codec Error

enum MCB1Error: Error, CustomStringConvertible {
    case badMagic
    case badHeaderLen(UInt16)
    case payloadTooLarge(UInt32)
    case crcMismatch(expected: UInt32, actual: UInt32)
    case streamClosed
    case ioError(String)

    var description: String {
        switch self {
        case .badMagic: return "bad MCB1 magic"
        case .badHeaderLen(let len): return "bad header_len: \(len)"
        case .payloadTooLarge(let len): return "payload too large: \(len)"
        case .crcMismatch(let expected, let actual):
            return "CRC32C mismatch: expected 0x\(String(expected, radix: 16)) got 0x\(String(actual, radix: 16))"
        case .streamClosed: return "stream closed"
        case .ioError(let msg): return "I/O error: \(msg)"
        }
    }
}

// MARK: - MCB1 Codec

/// Thread-safe MCB1 framing codec. Encodes and decodes MCB1 frames over a byte stream.
class MCB1Codec {
    private let lock = NSLock()
    private var seqCounter: UInt32 = 1

    func nextSeq() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        let s = seqCounter
        seqCounter &+= 1
        return s
    }

    static func nowUs() -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = mach_absolute_time() * UInt64(info.numer) / UInt64(info.denom)
        return nanos / 1000
    }

    // MARK: - Encode

    /// Encode a frame into wire bytes (header + payload with CRC32C).
    func encodeFrame(msgType: UInt8, flags: UInt16, payload: Data) -> Data {
        let seq = nextSeq()
        let ts = MCB1Codec.nowUs()
        let header = MCB1Header(
            msgType: msgType,
            flags: flags,
            seq: seq,
            timestampUs: ts,
            payloadLen: UInt32(payload.count)
        )
        return encodeFrame(header: header, payload: payload)
    }

    /// Encode a frame with a given header.
    func encodeFrame(header: MCB1Header, payload: Data) -> Data {
        // Serialize header with CRC zeroed
        let headerBytes = header.toBytes(withCRC: 0)

        // Compute CRC over (header_with_crc_zeroed + payload)
        var crcInput = Data(headerBytes)
        crcInput.append(payload)
        let crc = CRC32C.compute(crcInput)

        // Re-serialize header with the real CRC
        let finalHeaderBytes = header.toBytes(withCRC: crc)

        var frame = Data(finalHeaderBytes)
        frame.append(payload)
        return frame
    }

    // MARK: - Decode

    /// Read exactly `count` bytes from an InputStream. Blocks until all bytes are available.
    static func readExact(_ stream: InputStream, count: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        var totalRead = 0
        while totalRead < count {
            let n = stream.read(&buffer[totalRead], maxLength: count - totalRead)
            if n < 0 {
                throw MCB1Error.ioError(stream.streamError?.localizedDescription ?? "read failed")
            }
            if n == 0 {
                throw MCB1Error.streamClosed
            }
            totalRead += n
        }
        return Data(buffer)
    }

    /// Read one MCB1 frame from the stream. Blocks until a complete frame is available.
    static func readFrame(_ stream: InputStream) throws -> MCB1Frame {
        // Read 32-byte header
        let headerData = try readExact(stream, count: 32)
        let headerBytes = [UInt8](headerData)

        guard let header = MCB1Header.parse(headerBytes) else {
            // Determine specific error
            if headerBytes[0] != MCB1Constants.magic[0] ||
               headerBytes[1] != MCB1Constants.magic[1] ||
               headerBytes[2] != MCB1Constants.magic[2] ||
               headerBytes[3] != MCB1Constants.magic[3] {
                throw MCB1Error.badMagic
            }
            let hLen = UInt16(headerBytes[8]) | (UInt16(headerBytes[9]) << 8)
            if hLen < MCB1Constants.minHeaderLen || hLen > MCB1Constants.maxHeaderLen {
                throw MCB1Error.badHeaderLen(hLen)
            }
            let pLen = UInt32(headerBytes[12]) | (UInt32(headerBytes[13]) << 8) |
                       (UInt32(headerBytes[14]) << 16) | (UInt32(headerBytes[15]) << 24)
            if pLen > MCB1Constants.maxPayload {
                throw MCB1Error.payloadTooLarge(pLen)
            }
            throw MCB1Error.ioError("failed to parse header")
        }

        // Skip extra header bytes if header_len > 32
        if header.headerLen > 32 {
            let extra = Int(header.headerLen) - 32
            _ = try readExact(stream, count: extra)
        }

        // Read payload
        let payload: Data
        if header.payloadLen > 0 {
            payload = try readExact(stream, count: Int(header.payloadLen))
        } else {
            payload = Data()
        }

        // Verify CRC32C
        var crcHeaderBytes = headerBytes
        // Zero the CRC field (bytes 28..31)
        crcHeaderBytes[28] = 0
        crcHeaderBytes[29] = 0
        crcHeaderBytes[30] = 0
        crcHeaderBytes[31] = 0
        var crcInput = Data(crcHeaderBytes)
        crcInput.append(payload)
        let computedCRC = CRC32C.compute(crcInput)
        if computedCRC != header.crc32c {
            throw MCB1Error.crcMismatch(expected: header.crc32c, actual: computedCRC)
        }

        return MCB1Frame(header: header, payload: payload)
    }
}
