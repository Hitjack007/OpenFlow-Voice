import AppKit
import ApplicationServices
import Foundation

/// Puts text into whatever field currently has keyboard focus.
///
/// Two strategies, in order:
/// 1. **Accessibility** — sets `kAXSelectedTextAttribute` on the focused element directly in the
///    main app process (which holds the TCC Accessibility grant). Clean, instant, pasteboard untouched.
/// 2. **Pasteboard + ⌘V** — works in Electron apps and anything else with a half-hearted AX
///    implementation. The previous pasteboard contents are restored afterwards.
///
/// The HUD is a non-activating panel, so focus never leaves the user's target app.
@MainActor
enum TextInjector {
    static func insert(_ text: String) async {
        guard !text.isEmpty else { return }

        let (ok, reason) = insertViaAX(text)
        if ok {
            Log.inject.info("inserted via AX (\(text.count) chars)")
        } else {
            Log.inject.info("AX insert not verified (\(reason, privacy: .public)) — pasting")
            insertViaPasteboard(text)
        }
    }

    // MARK: - Accessibility

    private static func insertViaAX(_ text: String) -> (Bool, String) {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else {
            return (false, "no focused element")
        }

        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable
        ) == .success, settable.boolValue else {
            return (false, "selected text not settable")
        }

        guard let before = selectedRange(of: element) else {
            return (false, "no readable selection range")
        }

        guard AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        ) == .success else {
            return (false, "set attribute failed")
        }

        guard let after = selectedRange(of: element) else {
            return (false, "selection range unreadable after write")
        }

        let unchanged = after.location == before.location && after.length == before.length
        return unchanged ? (false, "selection unmoved at \(before.location)") : (true, "")
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value
        ) == .success, let value else { return nil }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    // MARK: - Pasteboard + ⌘V

    private static func insertViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Task { @MainActor in
            // Give the target app a moment to observe the new pasteboard generation before
            // ⌘V arrives, or a fast paste can grab the *previous* contents.
            try? await Task.sleep(for: .milliseconds(40))
            postCommandV()
            Log.inject.info("pasted (\(text.count) chars)")

            // The paste is asynchronous in the target app; restore only once it's had time
            // to read the pasteboard.
            try? await Task.sleep(for: .milliseconds(500))
            restore(saved, to: pasteboard)
        }
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let vKey: CGKeyCode = 9 // kVK_ANSI_V

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func restore(
        _ saved: [[NSPasteboard.PasteboardType: Data]]?,
        to pasteboard: NSPasteboard
    ) {
        guard let saved, !saved.isEmpty else { return }
        pasteboard.clearContents()
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
