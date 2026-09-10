import AppKit
import Foundation

/// Puts text into whatever has keyboard focus. The text goes on the
/// pasteboard, ⌘V is synthesized, and the previous pasteboard contents come
/// back once the paste has landed. Pasting — rather than typing key by key
/// or setting the focused element's accessibility value — is what works
/// everywhere: terminals, Electron apps and web views included.
enum TextInserter {

    /// Delay before the pasteboard is restored. The target app reads the
    /// pasteboard when it handles the key event, which is immediate, but
    /// give it room under load.
    static let restoreDelay: TimeInterval = 0.4

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map(Snapshot.init) ?? []
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postCommandV()
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            restore(saved, to: pasteboard)
        }
    }

    // MARK: - Pasteboard

    /// Items read off a pasteboard belong to it and can't be written back
    /// after clearContents, so copy their data out first.
    private struct Snapshot {
        let representations: [(type: NSPasteboard.PasteboardType, data: Data)]

        init(_ item: NSPasteboardItem) {
            representations = item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }

        var item: NSPasteboardItem {
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
    }

    private static func restore(_ items: [Snapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map(\.item))
    }

    // MARK: - Key event

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
