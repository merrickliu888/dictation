import AppKit
import Combine
import SwiftUI

/// Runs a dictation from key press to inserted text: feeds key events to
/// the interaction model, drives the transcriber, shows the pill, and pastes
/// the result into whatever had focus.
@MainActor
final class DictationController: ObservableObject {

    typealias Mode = DictationInteractionModel.Mode

    enum Phase: Equatable {
        case idle
        case listening(Mode)
        /// Audio has stopped; waiting for the recognizer's final pass.
        case finishing(Mode)
    }

    @Published private(set) var phase: Phase = .idle

    /// Checked before listening starts; false sends the user to setup.
    var canDictate: () -> Bool = { true }
    var onRequestSettings: (() -> Void)?

    let transcriber: Transcriber
    private var model: DictationInteractionModel
    private var panel: DictationPanel?
    /// After a tap (a press too short to be a hold) the microphone stays
    /// open for the double-tap window, so a second tap carries straight on
    /// into hands-free mode with no gap and no flicker.
    private var graceCancel: DispatchWorkItem?
    private var errorDismiss: DispatchWorkItem?

    init(transcriber: Transcriber) {
        self.transcriber = transcriber
        model = DictationInteractionModel(config: Shortcuts.config)
    }

    var isListening: Bool { phase != .idle }

    /// Key-cap hint for the pill: what ends the dictation.
    var hint: (symbol: String, label: String)? {
        switch phase {
        case .listening(.hold): return (Shortcuts[.hold].shortcut.display, "release to insert")
        case .listening(.handsFree): return (Shortcuts[.toggle].shortcut.display, "stop")
        case .idle, .finishing: return nil
        }
    }

    /// Pick up rebound shortcuts after config.toml is reloaded.
    func reloadShortcuts() {
        model = DictationInteractionModel(config: Shortcuts.config)
        objectWillChange.send()
    }

    // MARK: - Keys

    func handleKey(_ shortcut: Shortcut, _ phase: KeyMonitor.Phase, at time: TimeInterval) {
        let commands = phase == .down
            ? model.press(shortcut, at: time)
            : model.release(shortcut, at: time)
        for command in commands { perform(command) }
    }

    private func perform(_ command: DictationInteractionModel.Command) {
        switch command {
        case .start(let mode): start(mode)
        case .finish: finish()
        case .cancel: cancelAfterGrace()
        }
    }

    // MARK: - Session

    private func start(_ mode: Mode) {
        guard canDictate() else {
            model.reset()
            onRequestSettings?()
            return
        }
        errorDismiss?.cancel()
        errorDismiss = nil
        if let pending = graceCancel {
            pending.cancel()
            graceCancel = nil
            if transcriber.isActive {
                phase = .listening(mode)
                return
            }
        }
        transcriber.start()
        phase = .listening(mode)
        presentPanel()
        if !transcriber.isActive {
            // The microphone or recognizer refused; leave the reason up
            // briefly, then get out of the way.
            model.reset()
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.cancel() }
            }
            errorDismiss = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
        }
    }

    private func finish() {
        guard case .listening(let mode) = phase else { return }
        graceCancel?.cancel()
        graceCancel = nil
        phase = .finishing(mode)
        transcriber.finish { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // A trailing space so back-to-back dictations don't run
                // together.
                TextInserter.insert(trimmed + " ")
            }
            // A new session may already have started while the final pass
            // ran; leave its pill alone.
            if case .finishing = self.phase {
                self.phase = .idle
                self.dismissPanel()
            }
        }
    }

    private func cancelAfterGrace() {
        graceCancel?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.cancel() }
        }
        graceCancel = item
        DispatchQueue.main.asyncAfter(deadline: .now() + model.doubleTapWindow, execute: item)
    }

    /// Stop listening and discard whatever was heard.
    func cancel() {
        graceCancel?.cancel()
        graceCancel = nil
        errorDismiss?.cancel()
        errorDismiss = nil
        transcriber.cancel()
        model.reset()
        phase = .idle
        dismissPanel()
    }

    // MARK: - Panel

    private func presentPanel() {
        let size = NSSize(width: 640, height: 96)
        let panel = self.panel ?? DictationPanel(size: size)
        self.panel = panel
        if panel.isVisible { return }
        panel.setRootView(
            DictationPillView()
                .environmentObject(self)
                .environmentObject(transcriber)
        )
        let screen = Self.targetScreen()
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 12,
            width: size.width, height: size.height
        )
        panel.present(frame: frame)
    }

    private func dismissPanel() {
        panel?.dismiss()
    }

    /// The screen holding the window being dictated into: the frontmost
    /// app's focused window, or failing that the pointer's screen.
    static func targetScreen() -> NSScreen {
        if NSApp.isActive, let screen = NSApp.keyWindow?.screen { return screen }
        if let frame = FocusedWindow.frame() {
            let center = NSPoint(x: frame.midX, y: frame.midY)
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
                return screen
            }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
