import AppKit
import SwiftUI

struct SettingsWindow: View {
    let controller: DictationController
    @State private var selection: SettingsSection? = .general
    @State private var accentColorUpdateTrigger = UUID()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Dictation") {
                    Label(SettingsSection.general.title, systemImage: SettingsSection.general.icon)
                        .tag(SettingsSection.general)
                    Label(SettingsSection.audio.title, systemImage: SettingsSection.audio.icon)
                        .tag(SettingsSection.audio)
                }
                Section("Processing") {
                    Label(SettingsSection.model.title, systemImage: SettingsSection.model.icon)
                        .tag(SettingsSection.model)
                    Label(SettingsSection.cleanup.title, systemImage: SettingsSection.cleanup.icon)
                        .tag(SettingsSection.cleanup)
                }
                Section("Privacy") {
                    Label(SettingsSection.permissions.title, systemImage: SettingsSection.permissions.icon)
                        .tag(SettingsSection.permissions)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(200)
            .scrollBounceBehavior(.basedOnSize)
            .tint(.accentColor)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("").frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.accentColor)
        .id(accentColorUpdateTrigger)
        .frame(width: 700, height: 600)
        .background(SettingsWindowChrome())
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .general {
        case .general:     GeneralSectionView(controller: controller)
        case .model:       ModelSectionView()
        case .cleanup:     CleanupSectionView()
        case .audio:       AudioSectionView()
        case .permissions: PermissionsSectionView()
        }
    }
}

// MARK: - Window Chrome

private struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowAccessorView { .init() }
    func updateNSView(_ nsView: SettingsWindowAccessorView, context: Context) {}
}

private class SettingsWindowAccessorView: NSView {
    private var observations: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observations.forEach { NotificationCenter.default.removeObserver($0) }
        observations = []
        guard let window else { return }

        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("OpenFlowVoiceSettingsWindow")
        window.title = "OpenFlow Voice"
        if window.toolbar == nil {
            window.toolbar = NSToolbar(identifier: "OpenFlowVoiceSettings")
        }

        NSApp.setActivationPolicy(.regular)

        observations = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in DispatchQueue.main.async { NSApp.setActivationPolicy(.regular) } }
        ]
    }
}

// MARK: - Section Definition

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, model, cleanup, audio, permissions
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     "General"
        case .model:       "Model"
        case .cleanup:     "Cleanup"
        case .audio:       "Audio"
        case .permissions: "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general:     "keyboard"
        case .model:       "brain"
        case .cleanup:     "wand.and.sparkles"
        case .audio:       "speaker.wave.2.fill"
        case .permissions: "lock.shield.fill"
        }
    }
}

// MARK: - Shared UI Helpers

@ViewBuilder
private func customBadge(text: String) -> some View {
    Text(text)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(NSColor.secondarySystemFill), in: Capsule())
}

// MARK: - General

private struct GeneralSectionView: View {
    let controller: DictationController
    @State private var settings = Settings.shared
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var isRecording: Bool { controller.state.isActive }

    var body: some View {
        Form {
            Section("Dictation") {
                HStack(spacing: 12) {
                    Button {
                        if isRecording { controller.stopButtonRecording() }
                        else { controller.startButtonRecording() }
                    } label: {
                        ZStack {
                            Circle().fill(isRecording ? Color.red : Color.accentColor)
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isRecording)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusText)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(isRecording ? String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) : "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(key: Binding(
                        get: { settings.pushToTalkKey },
                        set: { key in
                            settings.pushToTalkKey = key
                            controller.reloadHotkey()
                        }
                    ))
                }
            } header: {
                Text("Push to Talk")
            } footer: {
                Text("Hold this key anywhere to dictate.")
            }

        }
        .navigationTitle("General")
        .accentColor(.accentColor)
        .toolbar {
            Button("Quit app") { NSApp.terminate(nil) }
                .controlSize(.extraLarge)
        }
        .onChange(of: isRecording) { _, active in
            startedAt = active ? Date() : nil
            if !active { elapsed = 0 }
        }
        .task(id: startedAt) {
            guard let startedAt else { return }
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var statusText: String {
        switch controller.state {
        case .idle:           "Hold \(settings.pushToTalkKey.displayName) or tap"
        case .starting:       "Starting…"
        case .listening:      "Recording"
        case .finishing:      "Processing…"
        case .noTarget:       "Hold \(settings.pushToTalkKey.displayName) or tap"
        case .error(let msg): msg
        }
    }
}

// MARK: - Model

private struct ModelSectionView: View {
    @State private var settings = Settings.shared
    @State private var isPreloading = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Compare mode", isOn: $settings.compareMode)
            } header: {
                Text("Engine")
            } footer: {
                Text(settings.engine == .parakeet
                    ? "Parakeet runs on the Neural Engine. Resolves on release; ~470 MB model download."
                    : "Apple's on-device transcriber. Streams text while you speak; no download required.")
            }

            if settings.engine == .parakeet || settings.compareMode {
                Section {
                    LabeledContent("Parakeet models") {
                        if parakeetOnDisk {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.footnote)
                        } else {
                            Button(isPreloading ? "Downloading…" : "Download (~470 MB)") {
                                downloadParakeet()
                            }
                            .disabled(isPreloading)
                        }
                    }
                } header: {
                    Text("Downloads")
                }
            }
        }
        .navigationTitle("Model")
        .accentColor(.accentColor)
    }

    private func downloadParakeet() {
        guard !isPreloading else { return }
        isPreloading = true
        Task {
            _ = try? await ParakeetModels.shared.manager()
            parakeetOnDisk = ParakeetModels.isDownloaded
            isPreloading = false
        }
    }
}

// MARK: - Cleanup

private struct CleanupSectionView: View {
    @State private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Clean up transcripts", isOn: $settings.cleanupEnabled)
            } header: {
                Text("Text Processing")
            } footer: {
                Text("Strips fillers, fixes spacing and punctuation. Dictionary corrections run either way.")
            }

            Section {
                Toggle("Smart cleanup (on-device AI)", isOn: $settings.smartCleanup)
                    .disabled(!FoundationModelFormatter.isAvailable)
                if let reason = FoundationModelFormatter.unavailableReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("AI Enhancement")
            }
            .disabled(!settings.cleanupEnabled)
        }
        .navigationTitle("Cleanup")
        .accentColor(.accentColor)
    }
}

// MARK: - Audio

private struct AudioSectionView: View {
    @State private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Sound effects", isOn: $settings.soundEnabled)
            } header: {
                Text("Feedback")
            } footer: {
                Text("Plays a short tick when recording starts and stops.")
            }
        }
        .navigationTitle("Audio")
        .accentColor(.accentColor)
    }
}

// MARK: - Permissions

private struct PermissionsSectionView: View {
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasMicrophone = Permissions.hasMicrophone

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    if hasAccessibility {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    } else {
                        Button("Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            } header: {
                Text("System")
            } footer: {
                Text("Required to monitor the push-to-talk key and type text into other apps.")
            }

            Section {
                LabeledContent("Microphone") {
                    if hasMicrophone {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    } else {
                        Button("Grant Access…") {
                            Permissions.openMicrophoneSettings()
                        }
                    }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Required to capture audio for speech recognition.")
            }
        }
        .navigationTitle("Permissions")
        .accentColor(.accentColor)
        .task {
            hasAccessibility = Permissions.hasAccessibility
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                hasAccessibility = Permissions.hasAccessibility
            }
        }
        .task {
            hasMicrophone = Permissions.hasMicrophone
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                hasMicrophone = Permissions.hasMicrophone
            }
        }
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorder: View {
    @Binding var key: PushToTalkKey
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Text(isRecording ? "Press a modifier key…" : key.displayName)
                .font(.body.monospacedDigit())
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 90, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.background.secondary, in: .rect(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Button(isRecording ? "Cancel" : "Record") {
                if isRecording { stopRecording() } else { startRecording() }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let code = Int64(event.keyCode)
            guard let matched = PushToTalkKey.allCases.first(where: { $0.keyCode == code }) else {
                return event
            }
            Task { @MainActor in
                self.key = matched
                self.stopRecording()
            }
            return event
        }
        eventMonitor = monitor
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
