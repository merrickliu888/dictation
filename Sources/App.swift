import SwiftUI

@main
struct DictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            // Pass the delegate directly: NSApp.delegate is SwiftUI's own
            // proxy under NSApplicationDelegateAdaptor, so casting it to
            // AppDelegate fails silently.
            MenuBarView(appDelegate: appDelegate)
                .environmentObject(appDelegate.controller)
                .environmentObject(appDelegate.permissions)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Image(systemName: controller.isListening ? "mic.fill" : "mic")
    }
}

struct MenuBarView: View {
    let appDelegate: AppDelegate
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var permissions: PermissionsManager

    var body: some View {
        Group {
            Text(statusLine)
            Divider()
            Button("Reload Config") {
                appDelegate.reloadConfig()
            }
            Button("Settings…") {
                appDelegate.showSettingsWindow()
            }
            Button("Quit Dictation") {
                NSApp.terminate(nil)
            }
        }
    }

    private var statusLine: String {
        if !permissions.allGranted { return "Setup needed — open Settings" }
        switch controller.phase {
        case .idle: return "Hold \(Shortcuts[.hold].display) to dictate"
        case .listening: return "Listening…"
        case .finishing: return "Inserting…"
        }
    }
}
