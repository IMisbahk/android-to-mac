import Foundation

/// TCP wrapper that provides InputStream/OutputStream for MCB1 communication.
class TCPConnection {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let host: String
    private let port: UInt16
    private(set) var isConnected = false

    init(host: String, port: UInt16) throws {
        self.host = host
        self.port = port

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)

        guard let input = readStream?.takeRetainedValue() as InputStream?,
              let output = writeStream?.takeRetainedValue() as OutputStream? else {
            throw MCB1Error.ioError("failed to create streams to \(host):\(port)")
        }

        self.inputStream = input
        self.outputStream = output

        // Set TCP_NODELAY
        input.setProperty(true, forKey: Stream.PropertyKey(rawValue: "kCFStreamPropertyShouldCloseNativeSocket"))
        output.setProperty(true, forKey: Stream.PropertyKey(rawValue: "kCFStreamPropertyShouldCloseNativeSocket"))

        input.open()
        output.open()

        // Wait for connection (with timeout)
        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline {
            if output.streamStatus == .open { break }
            if output.streamStatus == .error {
                throw MCB1Error.ioError("connection failed: \(output.streamError?.localizedDescription ?? "unknown")")
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if output.streamStatus != .open {
            throw MCB1Error.ioError("connection timeout to \(host):\(port)")
        }

        isConnected = true
    }

    func getInputStream() -> InputStream? { inputStream }
    func getOutputStream() -> OutputStream? { outputStream }

    func writeData(_ data: Data) throws {
        guard let output = outputStream else { throw MCB1Error.streamClosed }
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let written = output.write(bytes, maxLength: bytes.count - offset)
            if written < 0 {
                throw MCB1Error.ioError(output.streamError?.localizedDescription ?? "write failed")
            }
            if written == 0 {
                throw MCB1Error.streamClosed
            }
            offset += written
        }
    }

    func close() {
        isConnected = false
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
    }
}
