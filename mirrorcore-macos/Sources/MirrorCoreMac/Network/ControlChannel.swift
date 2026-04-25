import Foundation

/// Control channel — handles HELLO handshake, PING/PONG, and sending input events.
class ControlChannel {
    private let connection: TCPConnection
    private let codec = MCB1Codec()
    private let writeLock = NSLock()

    var onClipboardReceived: ((ClipboardSyncPayload) -> Void)?
    var onShellOutput: ((ShellOutputPayload) -> Void)?

    init(host: String, port: UInt16) throws {
        self.connection = try TCPConnection(host: host, port: port)
    }

    func performHello(deviceName: String, sessionNonce: UInt64) throws -> HelloPayload {
        let hello = HelloPayload(
            role: .mac,
            caps: MCB1Caps.video | MCB1Caps.input | MCB1Caps.clipboard | MCB1Caps.file,
            deviceName: deviceName,
            sessionNonce: sessionNonce
        )
        let payload = hello.encode()
        let frameData = codec.encodeFrame(
            msgType: MCB1MsgType.hello.rawValue,
            flags: 0,
            payload: payload
        )
        try sendRaw(frameData)

        // Read response
        guard let input = connection.getInputStream() else {
            throw MCB1Error.streamClosed
        }
        let response = try MCB1Codec.readFrame(input)
        guard response.header.msgType == MCB1MsgType.hello.rawValue else {
            throw MCB1Error.ioError("expected HELLO response, got \(response.header.msgType)")
        }
        guard let helloResp = HelloPayload.decode(response.payload) else {
            throw MCB1Error.ioError("failed to decode HELLO response")
        }
        return helloResp
    }

    func sendInput(_ payload: Data) {
        let frameData = codec.encodeFrame(
            msgType: MCB1MsgType.inputEvent.rawValue,
            flags: 0,
            payload: payload
        )
        try? sendRaw(frameData)
    }

    func sendClipboard(_ payload: ClipboardSyncPayload) {
        let frameData = codec.encodeFrame(
            msgType: MCB1MsgType.clipboardSync.rawValue,
            flags: 0,
            payload: payload.encode()
        )
        try? sendRaw(frameData)
    }

    func sendFileOffer(_ payload: FileOfferPayload) {
        let frameData = codec.encodeFrame(
            msgType: MCB1MsgType.fileOffer.rawValue,
            flags: 0,
            payload: payload.encode()
        )
        try? sendRaw(frameData)
    }

    func sendFileChunk(_ payload: FileChunkPayload) {
        let frameData = codec.encodeFrame(
            msgType: MCB1MsgType.fileChunk.rawValue,
            flags: 0,
            payload: payload.encode()
        )
        try? sendRaw(frameData)
    }

    func sendFileEnd(_ payload: FileEndPayload) {
        let frameData = codec.encodeFrame(
            msgType: MCB1MsgType.fileEnd.rawValue,
            flags: 0,
            payload: payload.encode()
        )
        try? sendRaw(frameData)
    }

    func sendShellExec(_ payload: ShellExecPayload) {
        let frameData = codec.encodeFrame(
            msgType: MCB1MsgType.shellExec.rawValue,
            flags: 0,
            payload: payload.encode()
        )
        try? sendRaw(frameData)
    }

    /// Receive loop — processes incoming control messages.
    func runReceiveLoop() {
        guard let input = connection.getInputStream() else { return }
        do {
            while connection.isConnected {
                let frame = try MCB1Codec.readFrame(input)
                handleFrame(frame)
            }
        } catch {
            Log.warn("Control receive loop ended: \(error)")
        }
    }

    func close() {
        connection.close()
    }

    // MARK: - Private

    private func handleFrame(_ frame: MCB1Frame) {
        guard let msgType = MCB1MsgType(rawValue: frame.header.msgType) else {
            Log.warn("Unknown control msg_type: \(frame.header.msgType)")
            return
        }

        switch msgType {
        case .clipboardSync:
            if let payload = ClipboardSyncPayload.decode(frame.payload) {
                onClipboardReceived?(payload)
            }
        case .shellOutput:
            if let payload = ShellOutputPayload.decode(frame.payload) {
                onShellOutput?(payload)
            }
        case .pong:
            if let ping = PingPayload.decode(frame.payload) {
                Log.info("PONG echo=\(ping.echoTimestampUs)")
            }
        default:
            break
        }
    }

    private func sendRaw(_ data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try connection.writeData(data)
    }
}
