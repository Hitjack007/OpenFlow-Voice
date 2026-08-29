import AppKit
import Carbon.HIToolbox
import Foundation

/// Installs a CGEventTap in the main app process for push-to-talk.
///
/// The tap must live in the main app — `CGEvent.tapCreate` checks the calling process's TCC
/// Accessibility entry, and TCC trust is per-process. Running it in an XPC helper would require
/// a separate, user-invisible Accessibility grant for the helper bundle.
final class HotkeyMonitor: @unchecked Sendable {
    static let shared = HotkeyMonitor()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var currentFlag: UInt64 = 0
    private var shouldConsumeEvent = false
    private var lastPressAt: Date?
    private var lastReleaseAt: Date?

    /// Installs the event tap for `key`. Returns `true` on success; `false` means Accessibility
    /// has not been granted to this process yet.
    @discardableResult
    func start(key: PushToTalkKey) -> Bool {
        stopTap()
        currentFlag = key.flagRawValue
        shouldConsumeEvent = key.shouldConsumeEvent

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let flags = event.flags
                let consume = monitor.handleTap(type: type, flags: flags)
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        stopTap()
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
        isPressed = false
        lastPressAt = nil
        lastReleaseAt = nil
    }

    // Runs on the main thread (tap is registered on CFRunLoopGetMain).
    private func handleTap(type: CGEventType, flags: CGEventFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        guard type == .flagsChanged else { return false }

        // Pass the event through untouched if the frontmost app is excluded.
        if let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            let excluded = MainActor.assumeIsolated { Settings.shared.excludedBundleIDs }
            if excluded.contains(frontID) { return false }
        }

        let nowPressed = flags.rawValue & currentFlag != 0
        guard nowPressed != isPressed else { return false }
        isPressed = nowPressed

        let now = Date()
        if nowPressed {
            let isDoubleTap: Bool
            if let lastPressAt, let lastReleaseAt {
                let prevHoldDuration = lastReleaseAt.timeIntervalSince(lastPressAt)
                let interTapGap = now.timeIntervalSince(lastReleaseAt)
                isDoubleTap = prevHoldDuration < 0.25 && interTapGap < 0.35
            } else {
                isDoubleTap = false
            }
            lastPressAt = now
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if isDoubleTap { self.onDoubleTap?() } else { self.onPress?() }
            }
        } else {
            lastReleaseAt = now
            DispatchQueue.main.async { [weak self] in
                self?.onRelease?()
            }
        }

        return shouldConsumeEvent
    }
}

/// Which modifier key holds the mic open.
enum PushToTalkKey: String, CaseIterable, Sendable {
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand
    case fn

    var keyCode: Int64 {
        switch self {
        case .leftOption: Int64(kVK_Option)             // 58
        case .rightOption: Int64(kVK_RightOption)       // 61
        case .leftCommand: Int64(kVK_Command)           // 55
        case .rightCommand: Int64(kVK_RightCommand)     // 54
        case .fn: Int64(kVK_Function)                   // 63
        }
    }

    /// Device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — it's set whenever *either* Option
    /// key is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible
    /// (the union bit is still set by the left key), so `onRelease` never fires. The mic
    /// stays open, the HUD stays up, and the next press is swallowed too.
    ///
    /// These raw values are the NX_DEVICE* masks from IOKit's event system; they carry the
    /// left/right distinction that the public `CGEventFlags` constants discard.
    var flagRawValue: UInt64 {
        switch self {
        case .leftOption: 0x20     // NX_DEVICELALTKEYMASK
        case .rightOption: 0x40   // NX_DEVICERALTKEYMASK
        case .leftCommand: 0x08   // NX_DEVICELCMDKEYMASK
        case .rightCommand: 0x10  // NX_DEVICERCMDKEYMASK
        case .fn: CGEventFlags.maskSecondaryFn.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .leftOption: "Left ⌥"
        case .rightOption: "Right ⌥"
        case .leftCommand: "Left ⌘"
        case .rightCommand: "Right ⌘"
        case .fn: "fn"
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so we let it
    /// through. Dedicated right-hand modifiers are safe to consume.
    var shouldConsumeEvent: Bool { self != .fn }
}
