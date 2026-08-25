import Foundation

/// Commands the main app sends to the helper process.
///
/// All accessibility-sensitive work (CGEventTap, AXUIElement*) runs in the helper so that TCC
/// trust is keyed on the helper's bundle ID rather than the main app's. The helper's entry in
/// System Settings > Privacy > Accessibility persists across main-app rebuilds/re-signs.
@objc protocol OpenFlowHelperProtocol: NSObjectProtocol {
    func checkAccessibility(reply: @escaping (Bool) -> Void)
    func promptAccessibilityIfNeeded(reply: @escaping (Bool) -> Void)

    /// Installs a CGEventTap for the given key. The helper calls back via
    /// `OpenFlowCallbackProtocol` on the connection's exported object.
    func startHotkeyMonitor(
        keyCode: Int64,
        flagRawValue: UInt64,
        shouldConsume: Bool,
        reply: @escaping (Bool) -> Void
    )
    func stopHotkeyMonitor(reply: @escaping () -> Void)

    /// Attempts AX text injection into the focused element.
    /// Returns (true, "") on success or (false, reason) when the AX write wasn't verified.
    func insertText(_ text: String, reply: @escaping (Bool, String) -> Void)
}

/// Callbacks the helper sends back to the main app when a hotkey event fires.
@objc protocol OpenFlowCallbackProtocol: NSObjectProtocol {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}
