import AppKit

/// Maps macOS mouse/trackpad events to MCB1 touch events with normalized coordinates.
class InputMapper {
    private var videoWidth: CGFloat = 1
    private var videoHeight: CGFloat = 1
    private var viewWidth: CGFloat = 1
    private var viewHeight: CGFloat = 1
    private var isMouseDown = false

    var onTouchEvent: ((TouchEventPayload) -> Void)?
    var onKeyEvent: ((KeyEventPayload) -> Void)?

    func configure(videoWidth: Int, videoHeight: Int) {
        self.videoWidth = CGFloat(videoWidth)
        self.videoHeight = CGFloat(videoHeight)
    }

    func updateViewSize(width: CGFloat, height: CGFloat) {
        self.viewWidth = width
        self.viewHeight = height
    }

    /// Convert view-local point to normalized (0..1) coordinates
    /// accounting for aspect ratio letterboxing.
    private func normalize(point: NSPoint) -> (x: Float, y: Float)? {
        let viewAspect = viewWidth / viewHeight
        let videoAspect = videoWidth / videoHeight

        var renderWidth: CGFloat
        var renderHeight: CGFloat
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if videoAspect > viewAspect {
            // Video wider than view — letterbox top/bottom
            renderWidth = viewWidth
            renderHeight = viewWidth / videoAspect
            offsetY = (viewHeight - renderHeight) / 2
        } else {
            // Video taller than view — pillarbox left/right
            renderHeight = viewHeight
            renderWidth = viewHeight * videoAspect
            offsetX = (viewWidth - renderWidth) / 2
        }

        let localX = point.x - offsetX
        let localY = point.y - offsetY

        // Check bounds
        guard localX >= 0, localX <= renderWidth, localY >= 0, localY <= renderHeight else {
            return nil
        }

        let normX = Float(localX / renderWidth)
        // NSView origin is bottom-left, Android is top-left
        let normY = Float(1.0 - (localY / renderHeight))

        return (normX.clamped(to: 0...1), normY.clamped(to: 0...1))
    }

    // MARK: - Mouse Events

    func handleMouseDown(at point: NSPoint) {
        guard let (x, y) = normalize(point: point) else { return }
        isMouseDown = true
        let event = TouchEventPayload(
            action: .down,
            pointerId: 0,
            xNorm: x,
            yNorm: y,
            pressure: 1.0,
            buttons: 0
        )
        onTouchEvent?(event)
    }

    func handleMouseDragged(at point: NSPoint) {
        guard isMouseDown, let (x, y) = normalize(point: point) else { return }
        let event = TouchEventPayload(
            action: .move,
            pointerId: 0,
            xNorm: x,
            yNorm: y,
            pressure: 1.0,
            buttons: 0
        )
        onTouchEvent?(event)
    }

    func handleMouseUp(at point: NSPoint) {
        guard let (x, y) = normalize(point: point) else {
            isMouseDown = false
            return
        }
        isMouseDown = false
        let event = TouchEventPayload(
            action: .up,
            pointerId: 0,
            xNorm: x,
            yNorm: y,
            pressure: 0.0,
            buttons: 0
        )
        onTouchEvent?(event)
    }

    // MARK: - Keyboard Events

    func handleKeyDown(event: NSEvent) {
        // Check for shortcuts first
        if let shortcut = ShortcutManager.handleKeyEvent(event) {
            onKeyEvent?(shortcut)
            return
        }

        // Map macOS keycode to Android keycode
        guard let androidCode = KeycodeMap.macToAndroid(keyCode: event.keyCode) else { return }

        let metaState = androidMetaState(from: event.modifierFlags)
        let keyEvent = KeyEventPayload(
            action: .down,
            androidKeycode: androidCode,
            metaState: metaState
        )
        onKeyEvent?(keyEvent)
    }

    func handleKeyUp(event: NSEvent) {
        guard let androidCode = KeycodeMap.macToAndroid(keyCode: event.keyCode) else { return }
        let metaState = androidMetaState(from: event.modifierFlags)
        let keyEvent = KeyEventPayload(
            action: .up,
            androidKeycode: androidCode,
            metaState: metaState
        )
        onKeyEvent?(keyEvent)
    }

    private func androidMetaState(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var meta: UInt32 = 0
        if flags.contains(.shift) { meta |= 0x01 }     // META_SHIFT_ON
        if flags.contains(.control) { meta |= 0x1000 }  // META_CTRL_ON
        if flags.contains(.option) { meta |= 0x02 }     // META_ALT_ON
        if flags.contains(.command) { meta |= 0x10000 }  // META_META_ON
        return meta
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
