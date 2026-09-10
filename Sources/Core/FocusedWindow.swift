import AppKit
import ApplicationServices

/// Where the text being dictated into is on screen, via Accessibility.
enum FocusedWindow {

    /// Frame of the frontmost app's focused window in AppKit screen
    /// coordinates, or nil when there is no such window (or no trust).
    static func frame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let window = focused as! AXUIElement

        guard let origin = point(of: kAXPositionAttribute, in: window),
              let size = size(of: kAXSizeAttribute, in: window)
        else { return nil }

        // Accessibility measures from the top-left of the primary display;
        // AppKit from its bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: origin.x, y: primaryHeight - origin.y - size.height,
            width: size.width, height: size.height
        )
    }

    private static func point(of attribute: String, in element: AXUIElement) -> CGPoint? {
        guard let value = axValue(of: attribute, in: element) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(of attribute: String, in element: AXUIElement) -> CGSize? {
        guard let value = axValue(of: attribute, in: element) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func axValue(of attribute: String, in element: AXUIElement) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        return (raw as! AXValue)
    }
}
