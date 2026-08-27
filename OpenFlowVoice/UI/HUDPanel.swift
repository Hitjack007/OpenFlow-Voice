import AppKit
import SwiftUI

/// The floating capsule that appears while you hold the key.
///
/// The single most important property here is that this panel **never becomes key**.
/// If it did, the user's text field would lose focus and `TextInjector` would have
/// nothing to insert into. Hence `.nonactivatingPanel` plus `canBecomeKey == false`.
@MainActor
final class HUDPanel: NSPanel {
    private static let pillSize     = NSSize(width: 96, height: 34)
    private static let expandedSize = NSSize(width: 300, height: 100)

    /// Pixels between the bottom of the HUD and the top of the Dock/menu-bar area.
    private static let dockGap: CGFloat = 20

    init(controller: DictationController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.pillSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        let rootView = HUDView(controller: controller)
        let hosting = NSHostingView(rootView: rootView)
        // Explicitly clear the hosting-view's layer so macOS doesn't render a
        // background rectangle behind the transparent SwiftUI capsule.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.layer?.isOpaque = false
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Parks the panel just above the Dock, horizontally centered on the active screen.
    ///
    /// Uses the visible frame's minimum Y (which sits exactly on top of the Dock) plus a
    /// small fixed gap — this keeps the pill close to the Dock on every display height.
    ///
    /// `NSScreen.main` is the screen with the *key window* — an accessory app with a
    /// non-activating panel never has one, so it can be nil. Falling back to `screens.first`
    /// keeps the HUD on-screen instead of stranding it at the origin.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.app.error("no screen available to position HUD")
            return
        }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + Self.dockGap
        ))
    }

    /// Resizes and configures the panel for the given controller state.
    /// Must be called before `present()` so the first reposition uses the right size.
    func updateForState(_ state: DictationController.State) {
        let isNoTarget: Bool
        if case .noTarget = state { isNoTarget = true } else { isNoTarget = false }

        ignoresMouseEvents = !isNoTarget
        let targetSize = isNoTarget ? Self.expandedSize : Self.pillSize
        guard frame.size != targetSize else { return }

        setContentSize(targetSize)
        reposition()
    }

    func present() {
        // Every active state change (starting → listening → finishing) calls this. Without
        // the early exit the panel would reset to alpha 0 and re-fade on each one, which
        // reads as a flicker mid-utterance.
        guard !isVisible || alphaValue < 1 else { return }

        reposition()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // AppKit always calls this on the main thread.
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}
