import AppKit

/// MirrorCore macOS application delegate.
/// Orchestrates the connection manager, video decoder, audio player,
/// clipboard sync, file transfer, and the mirror window.
class MirrorCoreApp: NSObject, NSApplicationDelegate {
    private let window = MirrorWindow()
    private let connectionManager = ConnectionManager()
    private let h264Decoder = H264Decoder()
    private let audioPlayer = AudioPlayer()
    private let clipboardSync = ClipboardSync()
    private let fileTransfer = FileTransferManager()
    private let inputMapper = InputMapper()
    private let shellPanel = ShellPanel()

    private var fpsTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        wireUpComponents()
        window.makeKeyAndOrderFront(nil)
        window.center()

        // Auto-connect via USB
        connectionManager.connect(mode: .usb(serial: nil))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        connectionManager.disconnect()
        h264Decoder.stop()
        audioPlayer.stop()
        clipboardSync.stop()
    }

    // MARK: - Setup

    private func wireUpComponents() {
        // Connection state
        connectionManager.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .disconnected:
                self.window.updateStatus(state: "Disconnected")
            case .connecting:
                self.window.updateStatus(state: "Connecting...")
            case .connected(let name):
                self.window.updateStatus(state: "Connected: \(name)")
                self.clipboardSync.start()
            case .error(let msg):
                self.window.updateStatus(state: "Error: \(msg)")
            }
        }

        // Video pipeline
        connectionManager.onVideoFrame = { [weak self] frame, config in
            guard let self else { return }
            if let config = config {
                // Configure decoder if not already done or dimensions changed
                self.h264Decoder.configure(
                    sps: config.sps,
                    pps: config.pps,
                    width: Int(config.width),
                    height: Int(config.height)
                )
                self.window.videoRenderer.configure(width: Int(config.width), height: Int(config.height))
                self.inputMapper.configure(videoWidth: Int(config.width), videoHeight: Int(config.height))
            }
            self.h264Decoder.decode(annexBData: frame.data, pts: frame.ptsUs)
        }

        h264Decoder.onDecodedFrame = { [weak self] pixelBuffer, pts in
            self?.window.videoRenderer.displayFrame(pixelBuffer)
        }

        // Audio pipeline
        connectionManager.onAudioConfig = { [weak self] config in
            self?.audioPlayer.configure(sampleRate: config.sampleRate, channels: config.channels)
            self?.audioPlayer.start()
        }

        connectionManager.onAudioFrame = { [weak self] frame in
            self?.audioPlayer.feedPCM(frame.data)
        }

        // Input mapping
        inputMapper.onTouchEvent = { [weak self] event in
            self?.connectionManager.sendTouchEvent(event)
        }
        inputMapper.onKeyEvent = { [weak self] event in
            self?.connectionManager.sendKeyEvent(event)
        }
        window.inputMapper.onTouchEvent = inputMapper.onTouchEvent
        window.inputMapper.onKeyEvent = inputMapper.onKeyEvent

        // Clipboard sync
        clipboardSync.onClipboardChanged = { [weak self] payload in
            self?.connectionManager.sendClipboard(payload)
        }
        connectionManager.onClipboardReceived = { [weak self] payload in
            self?.clipboardSync.receiveFromAndroid(payload)
        }

        // File transfer
        window.onFilesDropped = { [weak self] urls in
            self?.fileTransfer.sendFiles(urls: urls)
        }
        fileTransfer.sendOffer = { [weak self] payload in
            self?.connectionManager.sendFileOffer(payload)
        }
        fileTransfer.sendChunk = { [weak self] payload in
            self?.connectionManager.sendFileChunk(payload)
        }
        fileTransfer.sendEnd = { [weak self] payload in
            self?.connectionManager.sendFileEnd(payload)
        }

        // Shell panel
        shellPanel.onCommand = { [weak self] command in
            let payload = ShellExecPayload(command: command)
            self?.connectionManager.sendShellExec(payload)
        }

        // FPS timer
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let fps = self.window.videoRenderer.currentFPS
            if case .connected(let name) = self.connectionManager.state {
                self.window.updateStatus(state: "Connected: \(name)", fps: fps)
            }
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MirrorCore", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MirrorCore", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Device menu
        let deviceMenu = NSMenu(title: "Device")
        deviceMenu.addItem(withTitle: "Connect USB", action: #selector(connectUSB), keyEquivalent: "u")
        deviceMenu.addItem(withTitle: "Disconnect", action: #selector(disconnect), keyEquivalent: "d")
        deviceMenu.addItem(.separator())
        deviceMenu.addItem(withTitle: "Back", action: #selector(sendBack), keyEquivalent: "\u{1b}") // Escape
        deviceMenu.addItem(withTitle: "Home", action: #selector(sendHome), keyEquivalent: "")
        deviceMenu.addItem(withTitle: "Recents", action: #selector(sendRecents), keyEquivalent: "")
        deviceMenu.addItem(.separator())
        deviceMenu.addItem(withTitle: "Shell Panel", action: #selector(toggleShell), keyEquivalent: "t")
        let deviceMenuItem = NSMenuItem()
        deviceMenuItem.submenu = deviceMenu
        mainMenu.addItem(deviceMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func connectUSB() {
        connectionManager.connect(mode: .usb(serial: nil))
    }

    @objc private func disconnect() {
        connectionManager.disconnect()
    }

    @objc private func sendBack() {
        connectionManager.sendKeyEvent(KeyEventPayload(action: .down, androidKeycode: KeycodeMap.AKEYCODE_BACK, metaState: 0))
    }

    @objc private func sendHome() {
        connectionManager.sendKeyEvent(KeyEventPayload(action: .down, androidKeycode: KeycodeMap.AKEYCODE_HOME, metaState: 0))
    }

    @objc private func sendRecents() {
        connectionManager.sendKeyEvent(KeyEventPayload(action: .down, androidKeycode: KeycodeMap.AKEYCODE_APP_SWITCH, metaState: 0))
    }

    @objc private func toggleShell() {
        if shellPanel.isVisible {
            shellPanel.orderOut(nil)
        } else {
            shellPanel.makeKeyAndOrderFront(nil)
        }
    }
}
