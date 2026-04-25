import AppKit

/// Handles keyboard shortcuts that map to Android navigation actions.
/// - Cmd+← or Escape → BACK
/// - Cmd+H → HOME (intercepted before macOS hides window)
/// - Cmd+R → RECENTS (app switcher)
/// - Cmd+P → POWER
/// - Cmd+Up → VOLUME_UP
/// - Cmd+Down → VOLUME_DOWN
enum ShortcutManager {

    /// Returns a KeyEventPayload if the event matches a shortcut, nil otherwise.
    static func handleKeyEvent(_ event: NSEvent) -> KeyEventPayload? {
        let cmd = event.modifierFlags.contains(.command)

        // Escape → BACK (no modifier needed)
        if event.keyCode == 0x35 { // Escape
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_BACK,
                metaState: 0
            )
        }

        guard cmd else { return nil }

        switch event.keyCode {
        case 0x7B: // Cmd+Left Arrow → BACK
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_BACK,
                metaState: 0
            )
        case 0x04: // Cmd+H → HOME
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_HOME,
                metaState: 0
            )
        case 0x0F: // Cmd+R → APP_SWITCH (recents)
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_APP_SWITCH,
                metaState: 0
            )
        case 0x23: // Cmd+P → POWER
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_POWER,
                metaState: 0
            )
        case 0x7E: // Cmd+Up → VOLUME_UP
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_VOLUME_UP,
                metaState: 0
            )
        case 0x7D: // Cmd+Down → VOLUME_DOWN
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_VOLUME_DOWN,
                metaState: 0
            )
        case 0x2E: // Cmd+M → MENU
            return KeyEventPayload(
                action: .down,
                androidKeycode: KeycodeMap.AKEYCODE_MENU,
                metaState: 0
            )
        default:
            return nil
        }
    }
}
