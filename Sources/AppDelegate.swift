import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let permissions = PermissionsManager()
    let transcriber = Transcriber()
    let recorder = ShortcutRecorder()
    lazy var controller = DictationController(transcriber: transcriber)

    private let keys = KeyMonitor()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A fresh install gets a config.toml documenting every action and the
        // format. Seeding happens here and not in reloadConfig() — that is
        // also the menu action, which must not resurrect a file the user
        // deleted on purpose.
        ShortcutConfig.seedUserConfigIfMissing()
        Shortcuts.reload()
        controller.reloadShortcuts()
        applyAppearance()

        controller.canDictate = { [weak self] in
            self?.permissions.allGranted ?? false
        }
        controller.onRequestSettings = { [weak self] in
            self?.showSettingsWindow()
        }
        keys.onEvent = { [weak self] shortcut, phase, time in
            self?.controller.handleKey(shortcut, phase, at: time)
        }
        recorder.onRecordingChange = { [weak self] recording in
            self?.keys.isSuspended = recording
        }
        recorder.onCapture = { [weak self] action, trigger in
            self?.rebind(action, to: trigger)
        }

        // The event tap can only be installed once the process is trusted
        // for Accessibility, which usually happens during setup; follow the
        // permission rather than assuming it at launch.
        permissions.$accessibility
            .sink { [weak self] status in
                guard let self else { return }
                if status == .granted {
                    if !self.keys.isRunning { self.keys.start() }
                } else if self.keys.isRunning {
                    self.keys.stop()
                }
            }
            .store(in: &cancellables)

        permissions.refresh()
        if !permissions.allGranted {
            showSettingsWindow()
        }
        permissions.startPolling()
    }

    /// Re-read config.toml (menu bar → Reload Config) so a shortcut edit
    /// takes effect without restarting the app.
    func reloadConfig() {
        Shortcuts.reload()
        controller.reloadShortcuts()
        applyAppearance()
        if keys.isRunning { keys.restart() }
        recorder.noteConfigChanged()
    }

    /// Every window — settings, pill, menu — takes the configured theme.
    private func applyAppearance() {
        NSApp.appearance = Shortcuts.config.appearance.nsAppearance
    }

    private func setAppearance(_ appearance: Appearance) {
        do {
            try ShortcutConfig.setAppearance(appearance)
        } catch {
            NSLog("Appearance: could not save theme (%@)", String(describing: error))
        }
        reloadConfig()
    }

    private func rebind(_ action: ShortcutAction, to trigger: Trigger) {
        do {
            try ShortcutConfig.rebind(action, to: trigger)
        } catch {
            NSLog("Shortcuts: could not save %@ (%@)", action.rawValue, String(describing: error))
        }
        reloadConfig()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.cancel()
        keys.stop()
    }

    // MARK: - Settings window

    func showSettingsWindow() {
        if settingsWindow == nil {
            let view = SettingsView(recorder: recorder) { [weak self] appearance in
                self?.setAppearance(appearance)
            }
            .environmentObject(permissions)
            let hosting = NSHostingController(rootView: view)
            // Don't let SwiftUI size the window via constraints: the content
            // height changes as checks complete, and the resulting layout
            // feedback loop trips AppKit's constraint-pass limit (crash).
            hosting.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 710),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 540, height: 710))
            window.title = "Dictation"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.recorder.cancel()
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        // LSUIElement app: give the settings window a real presence.
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
