import AppKit
import Combine
import Foundation

/// Captures a new binding from the keyboard while the settings window is
/// key: the next key or modifier pressed, and — for the toggle — whether it
/// was pressed twice in quick succession.
@MainActor
final class ShortcutRecorder: ObservableObject {

    @Published private(set) var recording: ShortcutAction?
    /// Why the last press was refused, shown next to the field.
    @Published private(set) var message: String?
    /// Bumped whenever the bindings change, so views re-read `Shortcuts`.
    @Published private(set) var version = 0

    var onCapture: ((ShortcutAction, Trigger) -> Void)?
    /// True while recording, so the global tap can stand aside.
    var onRecordingChange: ((Bool) -> Void)?

    private var monitor: Any?
    private var pending: (shortcut: Shortcut, at: TimeInterval)?
    private var settle: DispatchWorkItem?
    private let doubleTapWindow: TimeInterval = 0.4

    var prompt: String {
        recording?.allowsDoubleTap == true
            ? "Press a key or shortcut — twice for a double tap"
            : "Press a key or shortcut"
    }

    func begin(_ action: ShortcutAction) {
        cancel()
        recording = action
        message = nil
        onRecordingChange?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settle?.cancel()
        settle = nil
        pending = nil
        if recording != nil {
            recording = nil
            onRecordingChange?(false)
        }
    }

    func noteConfigChanged() {
        version += 1
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let action = recording else { return false }

        let shortcut: Shortcut
        switch event.type {
        case .flagsChanged:
            let candidate = Shortcut(event.keyCode)
            guard let flag = candidate.modifierKeyEventFlag else { return true }
            // Only the press; the release of a modifier is not a shortcut.
            guard event.modifierFlags.contains(flag) else { return true }
            shortcut = Shortcut(event.keyCode, candidate.otherModifiers(in: event.modifierFlags))
        case .keyDown:
            guard !event.isARepeat else { return true }
            if event.keyCode == 53 { // escape
                cancel()
                return true
            }
            shortcut = Shortcut(event.keyCode, ShortcutModifiers(event.modifierFlags))
        default:
            return false
        }

        guard shortcut.isBindable else {
            message = "\(shortcut.display) alone would swallow typing — add ⌘, ⌥ or ⌃."
            return true
        }
        message = nil

        let now = event.timestamp
        if action.allowsDoubleTap, let pending, pending.shortcut == shortcut,
           now - pending.at <= doubleTapWindow {
            commit(action, Trigger(shortcut, taps: 2))
            return true
        }
        pending = (shortcut, now)
        settle?.cancel()
        guard action.allowsDoubleTap else {
            commit(action, Trigger(shortcut))
            return true
        }
        // Give a second press the chance to make it a double tap.
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.commit(action, Trigger(shortcut)) }
        }
        settle = item
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: item)
        return true
    }

    private func commit(_ action: ShortcutAction, _ trigger: Trigger) {
        cancel()
        onCapture?(action, trigger)
        version += 1
    }
}
