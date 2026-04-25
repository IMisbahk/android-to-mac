import AppKit

/// The main mirror window that displays the Android screen and captures input.
class MirrorWindow: NSWindow {
    let videoRenderer: VideoRenderer
    let inputMapper = InputMapper()
    private let statusBar = StatusBarView()

    init() {
        videoRenderer = VideoRenderer(frame: NSRect(x: 0, y: 0, width: 400, height: 800))

        super.init(
            contentRect: NSRect(x: 200, y: 200, width: 400, height: 860),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "MirrorCore"
        minSize = NSSize(width: 200, height: 400)
        isReleasedWhenClosed = false
        backgroundColor = .black

        // Layout: status bar on top, video below
        let container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        statusBar.frame = NSRect(x: 0, y: container.bounds.height - 30, width: container.bounds.width, height: 30)
        statusBar.autoresizingMask = [.width, .minYMargin]
        container.addSubview(statusBar)

        videoRenderer.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: container.bounds.height - 30)
        videoRenderer.autoresizingMask = [.width, .height]
        container.addSubview(videoRenderer)

        contentView = container

        // Register for drag-and-drop
        registerForDraggedTypes([.fileURL])

        // Accept first responder for key events
        makeFirstResponder(videoRenderer)
    }

    func updateStatus(state: String, fps: Double = 0) {
        statusBar.update(state: state, fps: fps)
    }

    // MARK: - Drag and Drop

    var onFilesDropped: (([URL]) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        let fileURLs = items.filter { $0.isFileURL }
        if !fileURLs.isEmpty {
            onFilesDropped?(fileURLs)
        }
        return true
    }
}

// MARK: - Mirror View (for mouse/keyboard events)

class MirrorView: VideoRenderer {
    var inputMapper: InputMapper?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputMapper?.handleMouseDown(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputMapper?.handleMouseDragged(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        inputMapper?.handleMouseUp(at: point)
    }

    override func keyDown(with event: NSEvent) {
        inputMapper?.handleKeyDown(event: event)
    }

    override func keyUp(with event: NSEvent) {
        inputMapper?.handleKeyUp(event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        // Handle modifier keys
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        inputMapper?.updateViewSize(width: bounds.width, height: bounds.height)
    }
}

// MARK: - Status Bar

class StatusBarView: NSView {
    private let stateLabel = NSTextField(labelWithString: "Disconnected")
    private let fpsLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.9).cgColor

        stateLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        stateLabel.textColor = .lightGray
        stateLabel.frame = NSRect(x: 8, y: 5, width: 200, height: 20)
        stateLabel.autoresizingMask = [.maxXMargin]
        addSubview(stateLabel)

        fpsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        fpsLabel.textColor = .systemGreen
        fpsLabel.alignment = .right
        fpsLabel.frame = NSRect(x: bounds.width - 150, y: 5, width: 140, height: 20)
        fpsLabel.autoresizingMask = [.minXMargin]
        addSubview(fpsLabel)
    }

    func update(state: String, fps: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.stateLabel.stringValue = state
            if fps > 0 {
                self?.fpsLabel.stringValue = String(format: "%.1f fps", fps)
                self?.fpsLabel.textColor = fps > 25 ? .systemGreen : (fps > 15 ? .systemYellow : .systemRed)
            } else {
                self?.fpsLabel.stringValue = ""
            }
        }
    }
}
