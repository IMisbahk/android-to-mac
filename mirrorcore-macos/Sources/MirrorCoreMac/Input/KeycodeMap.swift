import Foundation

/// Maps macOS key codes (from NSEvent.keyCode) to Android key codes (AKEYCODE_*).
/// Reference: https://developer.android.com/reference/android/view/KeyEvent
enum KeycodeMap {
    // Android AKEYCODE constants
    static let AKEYCODE_BACK: UInt32 = 4
    static let AKEYCODE_HOME: UInt32 = 3
    static let AKEYCODE_APP_SWITCH: UInt32 = 187
    static let AKEYCODE_POWER: UInt32 = 26
    static let AKEYCODE_VOLUME_UP: UInt32 = 24
    static let AKEYCODE_VOLUME_DOWN: UInt32 = 25
    static let AKEYCODE_DPAD_UP: UInt32 = 19
    static let AKEYCODE_DPAD_DOWN: UInt32 = 20
    static let AKEYCODE_DPAD_LEFT: UInt32 = 21
    static let AKEYCODE_DPAD_RIGHT: UInt32 = 22
    static let AKEYCODE_ENTER: UInt32 = 66
    static let AKEYCODE_DEL: UInt32 = 67      // Backspace
    static let AKEYCODE_FORWARD_DEL: UInt32 = 112
    static let AKEYCODE_TAB: UInt32 = 61
    static let AKEYCODE_SPACE: UInt32 = 62
    static let AKEYCODE_ESCAPE: UInt32 = 111
    static let AKEYCODE_MENU: UInt32 = 82

    /// macOS keyCode → Android keyCode
    private static let mapping: [UInt16: UInt32] = [
        // Letters A-Z (macOS keyCodes)
        0x00: 29,   // A
        0x0B: 30,   // B
        0x08: 31,   // C
        0x02: 32,   // D
        0x0E: 33,   // E
        0x03: 34,   // F
        0x05: 35,   // G
        0x04: 36,   // H
        0x22: 37,   // I
        0x26: 38,   // J
        0x28: 39,   // K
        0x25: 40,   // L
        0x2E: 41,   // M
        0x2D: 42,   // N
        0x1F: 43,   // O
        0x23: 44,   // P
        0x0C: 45,   // Q
        0x0F: 46,   // R
        0x01: 47,   // S
        0x11: 48,   // T
        0x20: 49,   // U
        0x09: 50,   // V
        0x0D: 51,   // W
        0x07: 52,   // X
        0x10: 53,   // Y
        0x06: 54,   // Z

        // Numbers 0-9
        0x1D: 7,    // 0
        0x12: 8,    // 1
        0x13: 9,    // 2
        0x14: 10,   // 3
        0x15: 11,   // 4
        0x17: 12,   // 5
        0x16: 13,   // 6
        0x1A: 14,   // 7
        0x1C: 15,   // 8
        0x19: 16,   // 9

        // Special keys
        0x24: 66,   // Return → ENTER
        0x30: 61,   // Tab → TAB
        0x31: 62,   // Space → SPACE
        0x33: 67,   // Backspace → DEL
        0x75: 112,  // Forward Delete → FORWARD_DEL
        0x35: 111,  // Escape → ESCAPE

        // Arrow keys
        0x7E: 19,   // Up → DPAD_UP
        0x7D: 20,   // Down → DPAD_DOWN
        0x7B: 21,   // Left → DPAD_LEFT
        0x7C: 22,   // Right → DPAD_RIGHT

        // Punctuation
        0x2B: 55,   // , → COMMA
        0x2F: 56,   // . → PERIOD
        0x2C: 76,   // / → SLASH
        0x29: 74,   // ; → SEMICOLON
        0x27: 75,   // ' → APOSTROPHE
        0x21: 71,   // [ → LEFT_BRACKET
        0x1E: 72,   // ] → RIGHT_BRACKET
        0x2A: 73,   // \ → BACKSLASH
        0x18: 70,   // = → EQUALS
        0x1B: 69,   // - → MINUS
        0x32: 68,   // ` → GRAVE

        // Function keys
        0x7A: 131,  // F1
        0x78: 132,  // F2
        0x63: 133,  // F3
        0x76: 134,  // F4
        0x60: 135,  // F5
        0x61: 136,  // F6
        0x62: 137,  // F7
        0x64: 138,  // F8
        0x65: 139,  // F9
        0x6D: 140,  // F10
        0x67: 141,  // F11
        0x6F: 142,  // F12
    ]

    static func macToAndroid(keyCode: UInt16) -> UInt32? {
        return mapping[keyCode]
    }
}
