import Foundation

/// The key-handling rules of dictation, kept free of AppKit so they can be
/// unit-tested: which press starts listening, whether a release inserts or
/// discards, and how a double tap locks hands-free mode.
///
/// Presses and releases arrive already matched to a `Shortcut`; the model
/// only decides what they mean given the two configured triggers.
struct DictationInteractionModel {

    enum Mode: Equatable {
        /// Listening while the hold shortcut is down; releasing it inserts.
        case hold
        /// Listening until the next press of either shortcut.
        case handsFree
    }

    enum Command: Equatable {
        case start(Mode)
        /// Stop listening and insert what was heard.
        case finish
        /// Stop listening and discard: the press was a tap, not a hold, so
        /// nothing was said.
        case cancel
    }

    /// What the press currently held down did when it landed.
    private enum PressRole {
        case startedHold
        case startedHandsFree
        case stopped
        case none
    }

    var hold: Trigger
    var toggle: Trigger
    /// A hold shorter than this is a tap. Nobody says a word in a quarter
    /// second, so a tap discards rather than inserting a stray fragment.
    var tapThreshold: TimeInterval = 0.3
    /// A press this soon after a tap of the same shortcut is a double tap.
    var doubleTapWindow: TimeInterval = 0.4

    private(set) var mode: Mode?
    private var press: (shortcut: Shortcut, at: TimeInterval, role: PressRole)?
    private var lastTap: (shortcut: Shortcut, at: TimeInterval)?

    init(hold: Trigger, toggle: Trigger) {
        self.hold = hold
        self.toggle = toggle
    }

    init(config: ShortcutConfig) {
        self.init(hold: config[.hold], toggle: config[.toggle])
    }

    var isListening: Bool { mode != nil }

    mutating func press(_ shortcut: Shortcut, at time: TimeInterval) -> [Command] {
        var commands: [Command] = []
        if let current = press {
            // A second key while one is down changes nothing. The same key
            // again means its release was missed (the tap was disabled for
            // a moment); settle that press first so nothing gets stuck.
            guard current.shortcut == shortcut else { return [] }
            commands += release(shortcut, at: time)
        }

        let isDoubleTap = lastTap.map { $0.shortcut == shortcut && time - $0.at <= doubleTapWindow } ?? false
        lastTap = nil

        var role = PressRole.none
        switch mode {
        case nil:
            if toggle.shortcut == shortcut && (!toggle.isDoubleTap || isDoubleTap) {
                mode = .handsFree
                role = .startedHandsFree
                commands.append(.start(.handsFree))
            } else if hold.shortcut == shortcut && !hold.isDoubleTap {
                mode = .hold
                role = .startedHold
                commands.append(.start(.hold))
            }
        case .handsFree:
            if shortcut == hold.shortcut || shortcut == toggle.shortcut {
                mode = nil
                role = .stopped
                commands.append(.finish)
            }
        case .hold:
            break
        }
        press = (shortcut, time, role)
        return commands
    }

    mutating func release(_ shortcut: Shortcut, at time: TimeInterval) -> [Command] {
        guard let press, press.shortcut == shortcut else { return [] }
        self.press = nil
        switch press.role {
        case .startedHold:
            mode = nil
            if time - press.at < tapThreshold {
                lastTap = (shortcut, time)
                return [.cancel]
            }
            return [.finish]
        case .none:
            // Did nothing on its own, but may be the first half of a double
            // tap on a toggle bound to a different key than the hold.
            lastTap = (shortcut, time)
            return []
        case .startedHandsFree, .stopped:
            return []
        }
    }

    /// Forget everything in flight, e.g. after the microphone failed.
    mutating func reset() {
        mode = nil
        press = nil
        lastTap = nil
    }
}
