import Foundation

/// Video channel — receives VIDEO_CONFIG and VIDEO_FRAME messages from the Android agent.
class VideoChannel {
    private let connection: TCPConnection
    private(set) var currentConfig: VideoConfigPayload?

    var onVideoConfig: ((VideoConfigPayload) -> Void)?
    var onVideoFrame: ((VideoFramePayload, VideoConfigPayload?) -> Void)?

    init(host: String, port: UInt16) throws {
        self.connection = try TCPConnection(host: host, port: port)
    }

    /// Blocking receive loop — call from a background thread.
    func runReceiveLoop() {
        guard let input = connection.getInputStream() else { return }
        do {
            while connection.isConnected {
                let frame = try MCB1Codec.readFrame(input)
                handleFrame(frame)
            }
        } catch {
            Log.warn("Video receive loop ended: \(error)")
        }
    }

    func close() {
        connection.close()
    }

    // MARK: - Private

    private func handleFrame(_ frame: MCB1Frame) {
        guard let msgType = MCB1MsgType(rawValue: frame.header.msgType) else {
            Log.warn("Unknown video msg_type: \(frame.header.msgType)")
            return
        }

        switch msgType {
        case .videoConfig:
            if let config = VideoConfigPayload.decode(frame.payload) {
                currentConfig = config
                onVideoConfig?(config)
            }
        case .videoFrame:
            if let vf = VideoFramePayload.decode(frame.payload) {
                onVideoFrame?(vf, currentConfig)
            }
        default:
            Log.warn("Unexpected msg on video channel: \(msgType)")
        }
    }
}
