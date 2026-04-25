import Foundation

/// Manages the overall connection lifecycle: ADB port forwarding, TCP connections
/// to the three channels (control, video, audio), and reconnection logic.
class ConnectionManager {
    enum ConnectionMode {
        case usb(serial: String?)
        case wifi(host: String)
    }

    enum ConnectionState {
        case disconnected
        case connecting
        case connected(deviceName: String)
        case error(String)
    }

    static let controlPort: UInt16 = 27183
    static let videoPort: UInt16 = 27184
    static let audioPort: UInt16 = 27185

    private(set) var state: ConnectionState = .disconnected
    private var mode: ConnectionMode = .usb(serial: nil)
    private var running = false

    private var controlChannel: ControlChannel?
    private var videoChannel: VideoChannel?
    private var audioChannel: AudioChannel?

    var onStateChange: ((ConnectionState) -> Void)?
    var onVideoFrame: ((VideoFramePayload, VideoConfigPayload?) -> Void)?
    var onAudioFrame: ((AudioFramePayload) -> Void)?
    var onAudioConfig: ((AudioConfigPayload) -> Void)?
    var onClipboardReceived: ((ClipboardSyncPayload) -> Void)?

    func connect(mode: ConnectionMode) {
        self.mode = mode
        running = true
        setState(.connecting)

        // Set up ADB forwarding if USB
        if case .usb(let serial) = mode {
            ADBBridge.forward(serial: serial, hostPort: Self.controlPort, devicePort: Self.controlPort)
            ADBBridge.forward(serial: serial, hostPort: Self.videoPort, devicePort: Self.videoPort)
            ADBBridge.forward(serial: serial, hostPort: Self.audioPort, devicePort: Self.audioPort)
        }

        let host: String
        switch mode {
        case .usb: host = "127.0.0.1"
        case .wifi(let h): host = h
        }

        // Connect control channel
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.connectControl(host: host)
        }

        // Connect video channel
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.connectVideo(host: host)
        }

        // Connect audio channel
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.connectAudio(host: host)
        }
    }

    func disconnect() {
        running = false
        controlChannel?.close()
        videoChannel?.close()
        audioChannel?.close()
        controlChannel = nil
        videoChannel = nil
        audioChannel = nil
        setState(.disconnected)
    }

    // MARK: - Input

    func sendTouchEvent(_ event: TouchEventPayload) {
        controlChannel?.sendInput(event.encode())
    }

    func sendKeyEvent(_ event: KeyEventPayload) {
        controlChannel?.sendInput(event.encode())
    }

    func sendClipboard(_ payload: ClipboardSyncPayload) {
        controlChannel?.sendClipboard(payload)
    }

    func sendFileOffer(_ payload: FileOfferPayload) {
        controlChannel?.sendFileOffer(payload)
    }

    func sendFileChunk(_ payload: FileChunkPayload) {
        controlChannel?.sendFileChunk(payload)
    }

    func sendFileEnd(_ payload: FileEndPayload) {
        controlChannel?.sendFileEnd(payload)
    }

    func sendShellExec(_ payload: ShellExecPayload) {
        controlChannel?.sendShellExec(payload)
    }

    // MARK: - Private

    private func setState(_ newState: ConnectionState) {
        state = newState
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStateChange?(newState)
        }
    }

    private func connectControl(host: String) {
        var backoff: TimeInterval = 0.2
        while running {
            do {
                let channel = try ControlChannel(host: host, port: Self.controlPort)
                controlChannel = channel
                channel.onClipboardReceived = { [weak self] payload in
                    self?.onClipboardReceived?(payload)
                }
                let hello = try channel.performHello(
                    deviceName: Host.current().localizedName ?? "Mac",
                    sessionNonce: UInt64.random(in: 0...UInt64.max)
                )
                setState(.connected(deviceName: hello.deviceName))
                Log.info("Control connected: device=\(hello.deviceName)")
                channel.runReceiveLoop()
                // If we get here, connection was lost
                Log.info("Control channel disconnected")
                backoff = 0.2
            } catch {
                Log.error("Control connect failed: \(error)")
            }
            guard running else { break }
            Thread.sleep(forTimeInterval: backoff)
            backoff = min(backoff * 2, 2.0)
        }
    }

    private func connectVideo(host: String) {
        var backoff: TimeInterval = 0.2
        while running {
            do {
                let channel = try VideoChannel(host: host, port: Self.videoPort)
                videoChannel = channel
                channel.onVideoConfig = { [weak self] config in
                    Log.info("VIDEO_CONFIG \(config.width)x\(config.height)")
                    // Config is stored internally in the channel
                }
                channel.onVideoFrame = { [weak self] frame, config in
                    self?.onVideoFrame?(frame, config)
                }
                channel.runReceiveLoop()
                Log.info("Video channel disconnected")
                backoff = 0.2
            } catch {
                Log.error("Video connect failed: \(error)")
            }
            guard running else { break }
            Thread.sleep(forTimeInterval: backoff)
            backoff = min(backoff * 2, 2.0)
        }
    }

    private func connectAudio(host: String) {
        var backoff: TimeInterval = 0.2
        while running {
            do {
                let channel = try AudioChannel(host: host, port: Self.audioPort)
                audioChannel = channel
                channel.onAudioConfig = { [weak self] config in
                    Log.info("AUDIO_CONFIG rate=\(config.sampleRate) ch=\(config.channels)")
                    self?.onAudioConfig?(config)
                }
                channel.onAudioFrame = { [weak self] frame in
                    self?.onAudioFrame?(frame)
                }
                channel.runReceiveLoop()
                Log.info("Audio channel disconnected")
                backoff = 0.2
            } catch {
                Log.error("Audio connect failed: \(error)")
            }
            guard running else { break }
            Thread.sleep(forTimeInterval: backoff)
            backoff = min(backoff * 2, 2.0)
        }
    }
}
