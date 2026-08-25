import AppKit
import ApplicationServices
import Foundation

/// Implements the helper side of the XPC contract.
///
/// All accessibility-sensitive calls originate here so that TCC trust is recorded against
/// this process's bundle ID, not the main app's.
final class HelperService: NSObject, OpenFlowHelperProtocol, @unchecked Sendable {
    private weak var connection: NSXPCConnection?

    // Guarded by always being touched on the main thread (tap callback + DispatchQueue.main).
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var currentKeyCode: Int64 = 0
    private var currentFlag: UInt64 = 0
    private var shouldConsumeEvent = false

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    // MARK: - Accessibility

    func checkAccessibility(reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    func promptAccessibilityIfNeeded(reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }

    // MARK: - Hotkey monitor

    func startHotkeyMonitor(
        keyCode: Int64,
        flagRawValue: UInt64,
        shouldConsume: Bool,
        reply: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { reply(false); return }
            self.stopTap()
            self.currentKeyCode = keyCode
            self.currentFlag = flagRawValue
            self.shouldConsumeEvent = shouldConsume

            let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            let refcon = Unmanaged.passUnretained(self).toOpaque()

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let svc = Unmanaged<HelperService>.fromOpaque(refcon).takeUnretainedValue()
                    let code = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    let consume = svc.handleTap(type: type, keyCode: code, flags: flags)
                    return consume ? nil : Unmanaged.passUnretained(event)
                },
                userInfo: refcon
            ) else {
                reply(false)
                return
            }

            self.tap = tap
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            reply(true)
        }
    }

    func stopHotkeyMonitor(reply: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.stopTap()
            reply()
        }
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
        isPressed = false
    }

    private func handleTap(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        guard type == .flagsChanged, keyCode == currentKeyCode else { return false }

        let nowPressed = flags.rawValue & currentFlag != 0
        guard nowPressed != isPressed else { return false }
        isPressed = nowPressed

        let proxy = connection?.remoteObjectProxy as? OpenFlowCallbackProtocol
        if nowPressed {
            proxy?.hotkeyDidPress()
        } else {
            proxy?.hotkeyDidRelease()
        }

        return shouldConsumeEvent
    }

    // MARK: - Text injection

    func insertText(_ text: String, reply: @escaping (Bool, String) -> Void) {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else {
            reply(false, "no focused element")
            return
        }

        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable
        ) == .success, settable.boolValue else {
            reply(false, "selected text not settable")
            return
        }

        guard let before = selectedRange(of: element) else {
            reply(false, "no readable selection range")
            return
        }

        guard AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString
        ) == .success else {
            reply(false, "set attribute failed")
            return
        }

        guard let after = selectedRange(of: element) else {
            reply(false, "selection range unreadable after write")
            return
        }

        let unchanged = after.location == before.location && after.length == before.length
        if unchanged {
            reply(false, "selection unmoved at \(before.location)")
        } else {
            reply(true, "")
        }
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
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
}
