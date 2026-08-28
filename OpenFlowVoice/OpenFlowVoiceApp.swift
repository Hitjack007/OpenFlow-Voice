import AppKit
import SwiftUI

@main
struct OpenFlowVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Status and the hotkey while you're working in another app.
        // Only MenuBarExtra — no SwiftUI Window/WindowGroup scenes.
        // All windows are managed manually via NSWindowController so we
        // own the activation-policy lifecycle without SwiftUI interference.
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: delegate.controller.state.isActive ? "waveform.circle.fill" : "waveform")
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reveal Dictionary File") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
        }
    }
}

// MARK: - Main Window Controller

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static var shared: MainWindowController?
    private weak var appDelegate: AppDelegate?
    private var activationObserver: NSObjectProtocol?

    init(controller: DictationController, appDelegate: AppDelegate) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.title = "OpenFlow Voice"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .participatesInCycle, .moveToActiveSpace]
        window.minSize = NSSize(width: 700, height: 520)
        window.setFrameAutosaveName("OpenFlowVoiceMain")
        window.center()

        let toolbar = NSToolbar(identifier: "OpenFlowVoiceMain")
        window.toolbar = toolbar

        self.appDelegate = appDelegate
        super.init(window: window)

        window.contentViewController = NSHostingController(
            rootView: MainWindow(controller: controller)
        )
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func showAndActivate() {
        guard let win = window else { return }
        NSApp.setActivationPolicy(.regular)
        win.orderFrontRegardless()
        NSApp.activate()
        if NSApp.isActive {
            win.makeKeyAndOrderFront(nil)
            win.makeKey()
            win.makeMain()
        } else {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.window?.makeKeyAndOrderFront(nil)
                    self?.window?.makeKey()
                    self?.window?.makeMain()
                    if let obs = self?.activationObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self?.activationObserver = nil
                    }
                }
            }
        }
    }

    private func relinquishFocus() {
        window?.orderOut(nil)
        appDelegate?.windowBecameHidden()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        relinquishFocus()
        return false
    }
}

// MARK: - Comparison Window Controller

@MainActor
final class ComparisonWindowController: NSWindowController, NSWindowDelegate {
    static var shared: ComparisonWindowController?
    private weak var appDelegate: AppDelegate?
    private var activationObserver: NSObjectProtocol?

    init(controller: DictationController, appDelegate: AppDelegate) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Engine comparison"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .participatesInCycle, .moveToActiveSpace]
        window.setFrameAutosaveName("OpenFlowVoiceComparison")
        window.center()

        self.appDelegate = appDelegate
        super.init(window: window)

        window.contentView = NSHostingView(rootView: ComparisonWindow(controller: controller))
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func showAndActivate() {
        guard let win = window else { return }
        NSApp.setActivationPolicy(.regular)
        win.orderFrontRegardless()
        NSApp.activate()
        if NSApp.isActive {
            win.makeKeyAndOrderFront(nil)
            win.makeKey()
            win.makeMain()
        } else {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.window?.makeKeyAndOrderFront(nil)
                    self?.window?.makeKey()
                    self?.window?.makeMain()
                    if let obs = self?.activationObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self?.activationObserver = nil
                    }
                }
            }
        }
    }

    private func relinquishFocus() {
        window?.orderOut(nil)
        appDelegate?.windowBecameHidden()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        relinquishFocus()
        return false
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private(set) var mainWindowController: MainWindowController?
    private var comparisonWindowController: ComparisonWindowController?
    private var hud: HUDPanel?

    // MARK: - Activation policy

    func windowBecameHidden() {
        let mainVisible = mainWindowController?.window?.isVisible == true
        let compVisible = comparisonWindowController?.window?.isVisible == true
        if !mainVisible && !compVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            MainWindowController.shared?.showAndActivate()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        mainWindowController = MainWindowController(controller: controller, appDelegate: self)
        MainWindowController.shared = mainWindowController

        comparisonWindowController = ComparisonWindowController(controller: controller, appDelegate: self)
        ComparisonWindowController.shared = comparisonWindowController

        hud = HUDPanel(controller: controller)

        controller.activate()
        Permissions.promptAccessibilityIfNeeded()
        retryActivation()
        RunLog.regenerate()

        let willUseParakeet = Settings.shared.compareMode || Settings.shared.engine == .parakeet
        if willUseParakeet, ParakeetModels.isDownloaded {
            Task.detached(priority: .utility) {
                _ = try? await ParakeetModels.shared.manager()
            }
        }

        if UserDefaults.standard.bool(forKey: "comparisonWindowOpen") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Self.showComparisonWindow()
            }
        }

        observeState()
        monitorAccessibility()
        Log.app.info("OpenFlow Voice ready — hold \(Settings.shared.pushToTalkKey.displayName) to dictate")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "openflowvoice" {
            switch url.host {
            case "clear":
                RunLog.clear()
                RunStore.shared.reload()
            case "show":
                Self.showComparisonWindow()
            default:
                break
            }
        }
    }

    static func showComparisonWindow() {
        RunStore.shared.reload()
        ComparisonWindowController.shared?.showAndActivate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let isOpen = comparisonWindowController?.window?.isVisible == true
        UserDefaults.standard.set(isOpen, forKey: "comparisonWindowOpen")
        controller.deactivate()
    }

    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let state = self.controller.state
                if state.showsHUD {
                    self.hud?.updateForState(state)
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    private func retryActivation() {
        Task { @MainActor in
            while true {
                if HotkeyMonitor.shared.start(key: Settings.shared.pushToTalkKey) {
                    Log.app.info("Accessibility granted — hotkey armed")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func monitorAccessibility() {
        Task { @MainActor in
            var lastTrusted = Permissions.hasAccessibility
            while true {
                try? await Task.sleep(for: .seconds(3))
                let trusted = Permissions.hasAccessibility
                if trusted && !lastTrusted {
                    let ok = HotkeyMonitor.shared.start(key: Settings.shared.pushToTalkKey)
                    if ok { Log.app.info("Accessibility re-granted — hotkey re-armed") }
                } else if !trusted && lastTrusted {
                    HotkeyMonitor.shared.stop()
                    Log.app.warning("Accessibility revoked — hotkey disarmed")
                    Permissions.promptAccessibilityIfNeeded()
                }
                lastTrusted = trusted
            }
        }
    }
}

// MARK: - Menu Bar Content

private struct MenuContent: View {
    @State private var settings = Settings.shared

    var body: some View {
        Text("Hold \(settings.pushToTalkKey.displayName) to dictate")

        Divider()

        Button("Open OpenFlow Voice") {
            MainWindowController.shared?.showAndActivate()
        }

        Divider()

        Button("Quit OpenFlow Voice") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
