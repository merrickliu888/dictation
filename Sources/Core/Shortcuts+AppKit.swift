import AppKit

extension ShortcutModifiers {

    /// Only the four modifiers a shortcut can use: Caps Lock, fn and the
    /// numeric-pad flag never take part in matching.
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }

    /// The same four, read off a Quartz event from the tap.
    init(_ flags: CGEventFlags) {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        self = modifiers
    }
}

extension Shortcut {

    /// For a modifier key, the Quartz flag that is set while it is held;
    /// nil for ordinary keys. Pressing fn alone changes flags, not keys.
    var modifierKeyFlag: CGEventFlags? {
        switch keyCode {
        case 63: return .maskSecondaryFn
        case 58, 61: return .maskAlternate
        case 55, 54: return .maskCommand
        case 59, 62: return .maskControl
        case 56, 60: return .maskShift
        default: return nil
        }
    }

    /// The AppKit spelling of `modifierKeyFlag`, for the settings window's
    /// local event monitor.
    var modifierKeyEventFlag: NSEvent.ModifierFlags? {
        switch keyCode {
        case 63: return .function
        case 58, 61: return .option
        case 55, 54: return .command
        case 59, 62: return .control
        case 56, 60: return .shift
        default: return nil
        }
    }

    /// The modifiers held besides this key itself, so a bare right ⌥ reads
    /// as "no modifiers" rather than as holding option.
    func otherModifiers(in flags: CGEventFlags) -> ShortcutModifiers {
        strippingOwnModifier(ShortcutModifiers(flags))
    }

    func otherModifiers(in flags: NSEvent.ModifierFlags) -> ShortcutModifiers {
        strippingOwnModifier(ShortcutModifiers(flags))
    }

    private func strippingOwnModifier(_ modifiers: ShortcutModifiers) -> ShortcutModifiers {
        var result = modifiers
        switch keyCode {
        case 58, 61: result.remove(.option)
        case 55, 54: result.remove(.command)
        case 59, 62: result.remove(.control)
        case 56, 60: result.remove(.shift)
        default: break
        }
        return result
    }

    /// Whether a key press from the tap is this shortcut: same key code,
    /// exactly these modifiers.
    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == Int64(self.keyCode) && ShortcutModifiers(flags) == modifiers
    }
}
