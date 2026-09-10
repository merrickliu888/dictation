import AppKit
import CoreGraphics
import Foundation

/// Watches the dictation shortcuts system-wide through a Quartz event tap.
/// A tap — rather than Carbon's RegisterEventHotKey, which Minimal uses —
/// is what makes a bare modifier key like fn bindable, and it reports
/// releases, which hold-to-dictate depends on. Keyboard taps need
/// Accessibility trust; the app needs that anyway to insert text.
///
/// Ordinary key combos (⌃Space) are swallowed so the frontmost app doesn't
/// also act on them. Modifier keys pass through untouched: apps track those
/// flags themselves, and eating fn would break fn+arrow everywhere.
final class KeyMonitor {

    enum Phase { case down, up }

    var onEvent: ((Shortcut, Phase, TimeInterval) -> Void)?

    /// While true, everything passes through — the settings window is
    /// recording a new shortcut and must not start a dictation with it.
    var isSuspended = false

    private(set) var isRunning = false
    private var shortcuts: [Shortcut] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// The key combo currently held, so its repeats and release are ours.
    private var heldChord: Shortcut?

    /// Installs the tap for the shortcuts in `Shortcuts.config`. Fails, and
    /// says so, when the process isn't trusted for Accessibility.
    @discardableResult
    func start() -> Bool {
        stop()
        shortcuts = Array(Set(ShortcutAction.allCases.map { Shortcuts[$0].shortcut }))

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("KeyMonitor: could not create the event tap (is Accessibility granted?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    /// Re-read the bindings after config.toml is reloaded.
    @discardableResult
    func restart() -> Bool { start() }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        heldChord = nil
        isRunning = false
    }

    // MARK: - Tap callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system switches a slow or busy tap off; switch it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        default:
            break
        }
        guard !isSuspended else { return pass }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let time = ProcessInfo.processInfo.systemUptime

        switch type {
        case .flagsChanged:
            for shortcut in shortcuts where shortcut.isModifierKey && Int64(shortcut.keyCode) == keyCode {
                guard let flag = shortcut.modifierKeyFlag else { continue }
                let pressed = flags.contains(flag)
                // fn with ⌘ held is somebody else's shortcut. Releases are
                // always reported so a press never gets stuck.
                if pressed, shortcut.otherModifiers(in: flags) != shortcut.modifiers { continue }
                emit(shortcut, pressed ? .down : .up, at: time)
            }
            // Letting go of the modifier ends a ⌃Space hold as surely as
            // letting go of Space.
            if let chord = heldChord, !ShortcutModifiers(flags).isSuperset(of: chord.modifiers) {
                heldChord = nil
                emit(chord, .up, at: time)
            }
            return pass

        case .keyDown:
            if let chord = heldChord, Int64(chord.keyCode) == keyCode {
                return nil // auto-repeat of a held shortcut
            }
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return pass }
            if let shortcut = shortcuts.first(where: { !$0.isModifierKey && $0.matches(keyCode: keyCode, flags: flags) }) {
                heldChord = shortcut
                emit(shortcut, .down, at: time)
                return nil
            }
            return pass

        case .keyUp:
            if let chord = heldChord, Int64(chord.keyCode) == keyCode {
                heldChord = nil
                emit(chord, .up, at: time)
                return nil
            }
            return pass

        default:
            return pass
        }
    }

    /// Hand the event over off the tap's own call: starting the microphone
    /// takes long enough that doing it inline would get the tap disabled.
    private func emit(_ shortcut: Shortcut, _ phase: Phase, at time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(shortcut, phase, time)
        }
    }
}
