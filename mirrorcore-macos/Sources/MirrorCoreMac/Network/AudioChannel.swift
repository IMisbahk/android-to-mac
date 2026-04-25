import Foundation

/// Audio channel — receives AUDIO_CONFIG and AUDIO_FRAME messages from the Android agent.
class AudioChannel {
    private let connection: TCPConnection

    var onAudioConfig: ((AudioConfigPayload) -> Void)?
    var onAudioFrame: ((AudioFramePayload) -> Void)?

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
            Log.warn("Audio receive loop ended: \(error)")
        }
    }

    func close() {
        connection.close()
    }

    // MARK: - Private

    private func handleFrame(_ frame: MCB1Frame) {
        guard let msgType = MCB1MsgType(rawValue: frame.header.msgType) else { return }

        switch msgType {
        case .audioConfig:
            if let config = AudioConfigPayload.decode(frame.payload) {
                onAudioConfig?(config)
            }
        case .audioFrame:
            if let af = AudioFramePayload.decode(frame.payload) {
                onAudioFrame?(af)
            }
        default:
            break
        }
    }
}
