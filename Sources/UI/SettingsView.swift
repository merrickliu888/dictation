import Foundation
import SwiftUI

/// Conventional onboarding/settings window: the three macOS permissions and
/// the two shortcuts. Everything else happens in the pill.
struct SettingsView: View {
    @EnvironmentObject var permissions: PermissionsManager
    @ObservedObject var recorder: ShortcutRecorder
    @State private var scratch = ""

    var body: some View {
        let config = Shortcuts.config
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictation Setup")
                    .font(.title2.weight(.semibold))
                Text(
                    "Grant the permissions below, then hold \(config[.hold].display) in any text field, speak, and let go to insert what you said."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            GroupBox("Permissions — all required") {
                VStack(spacing: 10) {
                    permissionRow(
                        title: "Microphone",
                        detail: "Hears what you say",
                        status: permissions.microphone,
                        grant: { permissions.requestMicrophone() },
                        openSettings: { permissions.openSettingsPane("Privacy_Microphone") }
                    )
                    permissionRow(
                        title: "Speech Recognition",
                        detail: "Turns your voice into text, on device",
                        status: permissions.speech,
                        grant: { permissions.requestSpeech() },
                        openSettings: { permissions.openSettingsPane("Privacy_SpeechRecognition") }
                    )
                    permissionRow(
                        title: "Accessibility",
                        detail: "Watches for the shortcut and pastes the text",
                        status: permissions.accessibility,
                        grant: { permissions.requestAccessibility() },
                        openSettings: { permissions.requestAccessibility() }
                    )
                }
                .padding(.vertical, 4)
            }

            GroupBox("Shortcuts") {
                VStack(alignment: .leading, spacing: 10) {
                    shortcutRow(
                        .hold,
                        title: "Hold to dictate",
                        detail: "Speak while it's down; release to insert",
                        trigger: config[.hold]
                    )
                    Divider().opacity(0.4)
                    shortcutRow(
                        .toggle,
                        title: "Toggle dictation",
                        detail: "Hands-free until you press \(config[.toggle].shortcut.display) again",
                        trigger: config[.toggle]
                    )
                    if let message = recorder.message {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.failure)
                    }
                    if usesFn(config) {
                        Divider().opacity(0.4)
                        fnNote
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Try it") {
                TextField(
                    "Click here, hold \(config[.hold].display), say something, and let go…",
                    text: $scratch, axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(2...4)
                .padding(.vertical, 4)
            }

            HStack {
                if permissions.allGranted {
                    Label(
                        "Ready — hold \(config[.hold].display) in any app to dictate.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Dictation needs all three permissions.",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            shortcutsNote(config)
        }
        .padding(22)
        .frame(width: 540, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear {
            permissions.stopPolling()
            recorder.cancel()
        }
    }

    // MARK: - Shortcuts

    @ViewBuilder
    private func shortcutRow(
        _ action: ShortcutAction, title: String, detail: String, trigger: Trigger
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if recorder.recording == action {
                Text(recorder.prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                Button("Cancel") { recorder.cancel() }
                    .controlSize(.small)
            } else {
                keyCap(trigger)
                Button("Change") { recorder.begin(action) }
                    .controlSize(.small)
                    .disabled(recorder.recording != nil)
            }
        }
    }

    private func keyCap(_ trigger: Trigger) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<trigger.taps, id: \.self) { _ in
                Text(trigger.shortcut.display)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            if trigger.isDoubleTap {
                Text("double-tap")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usesFn(_ config: ShortcutConfig) -> Bool {
        ShortcutAction.allCases.contains { config[$0].shortcut.keyCode == 63 }
    }

    /// macOS gives the 🌐 key a job of its own (the emoji picker, by
    /// default) that fires on exactly the tap the toggle uses.
    private var fnNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "macOS also acts on the fn (🌐) key by itself — usually by opening the emoji picker. In Keyboard settings, set “Press 🌐 key to” to “Do Nothing” so it only dictates."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Open Keyboard Settings") { permissions.openKeyboardSettings() }
                    .controlSize(.small)
            }
        }
    }

    /// Where the shortcuts came from, plus anything that went wrong reading
    /// the config file — the only place those warnings are visible in the UI.
    @ViewBuilder
    private func shortcutsNote(_ config: ShortcutConfig) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(shortcutsSummary(config))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ForEach(Array(config.warnings.enumerated()), id: \.offset) { warning in
                Text(warning.element)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.failure)
            }
        }
    }

    private func shortcutsSummary(_ config: ShortcutConfig) -> String {
        guard let source = config.source else {
            return "Shortcuts: defaults — Change writes \(abbreviated(ShortcutConfig.userConfigPath()))."
        }
        return "Shortcuts: \(abbreviated(source)) — Change edits it, or edit by hand and Reload Config."
    }

    private func abbreviated(_ url: URL) -> String {
        let home = NSHomeDirectory()
        guard url.path.hasPrefix(home) else { return url.path }
        return "~" + String(url.path.dropFirst(home.count))
    }

    // MARK: - Permissions

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        status: PermissionsManager.Status,
        grant: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status == .granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if status != .granted {
                if status == .denied {
                    Button("Open Settings") { openSettings() }
                        .controlSize(.small)
                } else {
                    Button("Grant") { grant() }
                        .controlSize(.small)
                }
            }
        }
    }
}
