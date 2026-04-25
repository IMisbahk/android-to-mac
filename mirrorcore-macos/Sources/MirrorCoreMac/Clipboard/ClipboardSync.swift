import AppKit
import Foundation

/// Bi-directional clipboard synchronization between macOS and Android.
/// Monitors NSPasteboard for changes and sends CLIPBOARD_SYNC messages.
/// Receives CLIPBOARD_SYNC from Android and updates NSPasteboard.
class ClipboardSync {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var clipIdCounter: UInt64 = 1
    private var ignoreNextChange = false

    var onClipboardChanged: ((ClipboardSyncPayload) -> Void)?

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        // Poll pasteboard every 500ms (NSPasteboard has no change notification API)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when clipboard data is received from Android.
    func receiveFromAndroid(_ payload: ClipboardSyncPayload) {
        guard payload.origin == .android else { return }

        if payload.mime == "text/plain" {
            let text = String(data: payload.data, encoding: .utf8) ?? ""
            ignoreNextChange = true
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            lastChangeCount = pb.changeCount
            Log.info("Clipboard ← Android: \(text.prefix(50))")
        }
    }

    // MARK: - Private

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        // Read text from pasteboard
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        let data = Data(text.utf8)

        let payload = ClipboardSyncPayload(
            origin: .mac,
            clipId: clipIdCounter,
            mime: "text/plain",
            data: data
        )
        clipIdCounter += 1
        onClipboardChanged?(payload)
        Log.info("Clipboard → Android: \(text.prefix(50))")
    }
}
