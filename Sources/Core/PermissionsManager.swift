import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Foundation
import Speech

/// Tracks and requests the macOS permissions the app cannot function
/// without: microphone, speech recognition, and Accessibility (which both
/// the key tap and text insertion depend on).
@MainActor
final class PermissionsManager: ObservableObject {

    enum Status: Equatable {
        case unknown
        case granted
        case denied
        case notDetermined
    }

    @Published private(set) var microphone: Status = .unknown
    @Published private(set) var speech: Status = .unknown
    @Published private(set) var accessibility: Status = .unknown

    var allGranted: Bool {
        microphone == .granted && speech == .granted && accessibility == .granted
    }

    private var pollTimer: Timer?

    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphone = .granted
        case .notDetermined: microphone = .notDetermined
        default: microphone = .denied
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = .granted
        case .notDetermined: speech = .notDetermined
        default: speech = .denied
        }
        // Accessibility has no "not yet asked" state to read back.
        accessibility = AXIsProcessTrusted() ? .granted : .denied
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    /// Lists the app in System Settings → Privacy & Security → Accessibility
    /// and shows the system prompt; flipping the switch is the user's.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettingsPane("Privacy_Accessibility")
    }

    func openSettingsPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// System Settings → Keyboard, where "Press 🌐 key to" lives.
    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS sends no notification when the user grants a permission in
    /// System Settings, so poll until everything is in place.
    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.refresh()
                if self.allGranted { self.stopPolling() }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
