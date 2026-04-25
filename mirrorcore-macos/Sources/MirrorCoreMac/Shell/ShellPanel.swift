import AppKit

/// Terminal-like panel for executing shell commands on the connected Android device.
/// Commands are sent as SHELL_EXEC messages and output is displayed as SHELL_OUTPUT responses.
class ShellPanel: NSPanel {
    private let outputView = NSTextView()
    private let inputField = NSTextField()
    private var commandHistory: [String] = []
    private var historyIndex = -1

    var onCommand: ((String) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 300, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        title = "MirrorCore Shell"
        minSize = NSSize(width: 300, height: 200)
        isReleasedWhenClosed = false

        setupUI()
    }

    private func setupUI() {
        let container = NSView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.05, alpha: 1).cgColor

        // Output scroll view
        let scrollView = NSScrollView(frame: NSRect(
            x: 0, y: 30,
            width: container.bounds.width,
            height: container.bounds.height - 30
        ))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        outputView.isEditable = false
        outputView.isSelectable = true
        outputView.backgroundColor = NSColor(white: 0.05, alpha: 1)
        outputView.textColor = NSColor(white: 0.85, alpha: 1)
        outputView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        outputView.autoresizingMask = [.width]
        outputView.isVerticallyResizable = true
        outputView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        outputView.textContainer?.widthTracksTextView = true

        scrollView.documentView = outputView
        container.addSubview(scrollView)

        // Input field
        inputField.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: 30)
        inputField.autoresizingMask = [.width, .maxYMargin]
        inputField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        inputField.backgroundColor = NSColor(white: 0.1, alpha: 1)
        inputField.textColor = .systemGreen
        inputField.placeholderString = "$ enter command..."
        inputField.isBezeled = true
        inputField.bezelStyle = .squareBezel
        inputField.focusRingType = .none
        inputField.target = self
        inputField.action = #selector(submitCommand)
        container.addSubview(inputField)

        contentView = container

        appendOutput("MirrorCore Shell — connected to device\nType a command and press Enter.\n\n", color: .systemCyan)
    }

    @objc private func submitCommand() {
        let cmd = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        commandHistory.append(cmd)
        historyIndex = commandHistory.count

        appendOutput("$ \(cmd)\n", color: .systemGreen)
        inputField.stringValue = ""

        onCommand?(cmd)
    }

    func appendOutput(_ text: String, color: NSColor = NSColor(white: 0.85, alpha: 1)) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: color,
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            self.outputView.textStorage?.append(attrStr)
            self.outputView.scrollToEndOfDocument(nil)
        }
    }

    func displayShellOutput(exitCode: Int32, stdout: String, stderr: String) {
        if !stdout.isEmpty {
            appendOutput(stdout, color: NSColor(white: 0.85, alpha: 1))
        }
        if !stderr.isEmpty {
            appendOutput(stderr, color: .systemRed)
        }
        if exitCode != 0 {
            appendOutput("exit code: \(exitCode)\n", color: .systemYellow)
        }
        appendOutput("\n")
    }
}
