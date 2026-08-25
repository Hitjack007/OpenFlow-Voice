import Foundation

@objc protocol OpenFlowHelperProtocol: NSObjectProtocol {
    func checkAccessibility(reply: @escaping (Bool) -> Void)
    func promptAccessibilityIfNeeded(reply: @escaping (Bool) -> Void)
    func startHotkeyMonitor(
        keyCode: Int64,
        flagRawValue: UInt64,
        shouldConsume: Bool,
        reply: @escaping (Bool) -> Void
    )
    func stopHotkeyMonitor(reply: @escaping () -> Void)
    func insertText(_ text: String, reply: @escaping (Bool, String) -> Void)
}

@objc protocol OpenFlowCallbackProtocol: NSObjectProtocol {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}
