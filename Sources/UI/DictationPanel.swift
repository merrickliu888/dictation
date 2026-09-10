import AppKit
import SwiftUI

/// Borderless overlay for the pill. Unlike Minimal's panel it never becomes
/// key and ignores the mouse: the whole point is that focus stays in the
/// text field being dictated into.
final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    func setRootView<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    func present(frame: NSRect) {
        setFrame(frame, display: true)
        alphaValue = 1
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
        // orderOut alone leaves the SwiftUI hierarchy mounted and animating;
        // unmount so repeat-forever animations stop flushing Core Animation.
        contentView = NSView()
    }
}
