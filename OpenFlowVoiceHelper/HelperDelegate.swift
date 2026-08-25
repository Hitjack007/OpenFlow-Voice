import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    // NSXPCListener.service() may or may not retain accepted connections depending on
    // the OS version. Keep a strong reference here so HelperService.connection (weak)
    // is guaranteed to stay non-nil for the lifetime of the connection.
    private var activeConnections: [NSXPCConnection] = []

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection conn: NSXPCConnection
    ) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: OpenFlowHelperProtocol.self)
        conn.exportedObject = HelperService(connection: conn)
        conn.remoteObjectInterface = NSXPCInterface(with: OpenFlowCallbackProtocol.self)
        conn.invalidationHandler = { [weak self, weak conn] in
            guard let self, let conn else { return }
            self.activeConnections.removeAll { $0 === conn }
        }
        conn.resume()
        activeConnections.append(conn)
        return true
    }
}
