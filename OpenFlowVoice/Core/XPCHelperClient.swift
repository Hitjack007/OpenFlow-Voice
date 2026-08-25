import Foundation
import Observation

/// Main-app side of the XPC connection to `OpenFlowVoiceHelper`.
///
/// Lazily opens the connection on first use and rebuilds it automatically after an
/// interruption (helper crash) or invalidation (helper process exited).
@MainActor
@Observable
final class XPCHelperClient: NSObject, OpenFlowCallbackProtocol {
    static let shared = XPCHelperClient()

    // Must match CFBundleIdentifier in the built helper. Check with:
    //   defaults read "$BUILT_PRODUCTS_DIR/OpenFlowVoice.app/Contents/XPCServices/OpenFlowVoiceHelper.xpc/Contents/Info" CFBundleIdentifier
    private static let serviceName = "com.Hitjack007.OpenFlow-Voice.Helper.OpenFlowVoiceHelper"

    /// Reflects the last known accessibility state of the helper process.
    /// Updated once at launch and whenever `checkAndUpdateAccessibility()` is called.
    private(set) var isAccessibilityGranted: Bool = false

    var onHotkeyPress: (() -> Void)?
    var onHotkeyRelease: (() -> Void)?

    private var connection: NSXPCConnection?

    private func openConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(serviceName: Self.serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: OpenFlowHelperProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: OpenFlowCallbackProtocol.self)
        conn.exportedObject = self
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        conn.resume()
        return conn
    }

    /// Returns a proxy that calls the error handler (and fails fast) if the connection
    /// drops rather than letting callers hang indefinitely.
    private func proxy(onError: @escaping @Sendable (Error) -> Void) -> any OpenFlowHelperProtocol {
        if connection == nil { connection = openConnection() }
        return connection!.remoteObjectProxyWithErrorHandler(onError) as! any OpenFlowHelperProtocol
    }

    // MARK: - Accessibility

    func checkAndUpdateAccessibility() async -> Bool {
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            proxy { _ in c.resume(returning: false) }
                .checkAccessibility { c.resume(returning: $0) }
        }
        isAccessibilityGranted = granted
        return granted
    }

    func promptAccessibilityIfNeeded() async -> Bool {
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            proxy { _ in c.resume(returning: false) }
                .promptAccessibilityIfNeeded { c.resume(returning: $0) }
        }
        isAccessibilityGranted = granted
        return granted
    }

    // MARK: - Hotkey monitor

    func startHotkeyMonitor(keyCode: Int64, flagRawValue: UInt64, shouldConsume: Bool) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            proxy { _ in c.resume(returning: false) }
                .startHotkeyMonitor(keyCode: keyCode, flagRawValue: flagRawValue, shouldConsume: shouldConsume) {
                    c.resume(returning: $0)
                }
        }
    }

    func stopHotkeyMonitor() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            proxy { _ in c.resume() }
                .stopHotkeyMonitor { c.resume() }
        }
    }

    // MARK: - Text injection

    /// Returns `(true, "")` on verified AX insert, or `(false, reason)` if unverified.
    /// Never hangs — a broken XPC connection returns `(false, "XPC error")` immediately.
    func insertText(_ text: String) async -> (Bool, String) {
        await withCheckedContinuation { (c: CheckedContinuation<(Bool, String), Never>) in
            proxy { _ in c.resume(returning: (false, "XPC error")) }
                .insertText(text) { ok, reason in c.resume(returning: (ok, reason)) }
        }
    }

    // MARK: - OpenFlowCallbackProtocol

    nonisolated func hotkeyDidPress() {
        Task { @MainActor in self.onHotkeyPress?() }
    }

    nonisolated func hotkeyDidRelease() {
        Task { @MainActor in self.onHotkeyRelease?() }
    }
}
