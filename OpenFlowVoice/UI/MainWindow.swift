import AppKit
import SwiftUI

// MARK: - Sidebar Width Pin

private struct SidebarWidthPin: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { pin(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { pin(from: nsView) }
    }

    private func pin(from view: NSView) {
        guard let splitVC = findSplitViewController(from: view),
              let sidebarItem = splitVC.splitViewItems.first else { return }
        sidebarItem.minimumThickness = width
        sidebarItem.maximumThickness = width
        splitVC.splitView.setPosition(width, ofDividerAt: 0)
    }

    private func findSplitViewController(from view: NSView) -> NSSplitViewController? {
        var responder: NSResponder? = view
        while let r = responder {
            if let vc = r as? NSSplitViewController { return vc }
            responder = r.nextResponder
        }
        var v: NSView? = view
        while let current = v {
            if let contentVC = current.window?.contentViewController as? NSSplitViewController {
                return contentVC
            }
            v = current.superview
        }
        return nil
    }
}

// MARK: - Section Enum

enum MainSection: String, Identifiable {
    case transcriptions, dictionary
    case general, model, cleanup, audio, permissions
    var id: String { rawValue }
}

// MARK: - Main Window

struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var selection: MainSection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Dictation") {
                    Label("General", systemImage: "keyboard")
                        .tag(MainSection.general)
                    Label("Audio", systemImage: "speaker.wave.2.fill")
                        .tag(MainSection.audio)
                }
                Section("Processing") {
                    Label("Model", systemImage: "brain")
                        .tag(MainSection.model)
                    Label("Cleanup & Enhancement", systemImage: "wand.and.sparkles")
                        .tag(MainSection.cleanup)
                }
                Section("Privacy") {
                    Label("Permissions", systemImage: "lock.shield.fill")
                        .tag(MainSection.permissions)
                }
                Section("History") {
                    Label("Transcriptions", systemImage: "text.bubble")
                        .tag(MainSection.transcriptions)
                    Label("Dictionary", systemImage: "character.book.closed")
                        .tag(MainSection.dictionary)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
            .toolbar(removing: .sidebarToggle)
            .background(SidebarWidthPin(width: 200))
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 700)
        .toolbar {
            Button("Quit app") { NSApp.terminate(nil) }
                .controlSize(.extraLarge)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .general {
        case .transcriptions: TranscriptionList()
        case .dictionary:     DictionaryPanel()
        case .general:        InlineGeneralSettings(controller: controller)
        case .model:          InlineModelSettings()
        case .cleanup:        InlineCleanupSettings()
        case .audio:          InlineAudioSettings()
        case .permissions:    InlinePermissionsSettings()
        }
    }
}

private struct SidebarLevelBars: View {
    let level: Float
    var isActive: Bool
    private let count = 10

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let normalized = Float(i + 1) / Float(count)
                let isLit = isActive && normalized <= level
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isLit ? barColor(normalized) : Color.secondary.opacity(0.15))
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .animation(.linear(duration: 0.04), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let center = Float(count - 1) / 2.0
        let dist = abs(Float(index) - center) / center
        return 4 + CGFloat(1.0 - dist) * 18
    }

    private func barColor(_ normalized: Float) -> Color {
        normalized > 0.85 ? .red : normalized > 0.65 ? .yellow : .green
    }
}

// MARK: - Transcriptions Detail

private struct TranscriptionList: View {
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var runs: [DictationRun] {
        let all = store.runs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, placeholder: "Search transcriptions")

            if runs.isEmpty {
                EmptyPanel(
                    label: store.runs.isEmpty ? "No recordings yet" : "No matches",
                    detail: store.runs.isEmpty
                        ? "Hold your push-to-talk key or tap the mic button."
                        : "Try a different search."
                )
            } else {
                List {
                    ForEach(runs) { run in
                        TranscriptionRow(run: run) {
                            withAnimation { RunLog.delete(run) }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                footer
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(store.runs.count) recording\(store.runs.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Delete All") { isConfirmingClear = true }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .confirmationDialog(
            "Delete all \(store.runs.count) recordings?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { RunLog.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct TranscriptionRow: View {
    let run: DictationRun
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(run.engine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2fs", run.processSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(run.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                copyButton
                if isHovering { deleteButton }
            }

            Text(run.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .onHover { isHovering = $0 }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(run.text, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                didCopy = false
            }
        } label: {
            Text(didCopy ? "Copied" : "Copy")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassEffect(in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .glassEffect(in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Delete this transcription")
    }
}

private struct CorrectionBadges: View {
    let corrections: [AppliedCorrection]

    var body: some View {
        HStack(spacing: 6) {
            Text("Corrected")
                .font(.caption2)
                .foregroundStyle(.orange)
            ForEach(corrections, id: \.self) { correction in
                HStack(spacing: 4) {
                    Text(correction.from)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(correction.to)
                    if correction.count > 1 {
                        Text("×\(correction.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.1), in: .capsule)
            }
            Spacer()
        }
    }
}

// MARK: - Inline Settings: General

private struct InlineGeneralSettings: View {
    let controller: DictationController
    @State private var settings = Settings.shared
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?
    @State private var isAddingApp = false

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

                    Spacer()

                    SidebarLevelBars(level: controller.levels.max() ?? 0, isActive: isRecording)
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

            Section {
                if settings.excludedBundleIDs.isEmpty {
                    Text("No apps excluded")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(appDisplayName(for: bundleID))
                            Spacer()
                            Button {
                                settings.excludedBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Add App…") { isAddingApp = true }
                    .font(.footnote)
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("The push-to-talk key is ignored when these apps are frontmost, so their native modifier-key shortcuts still work.")
            }

        }
        .sheet(isPresented: $isAddingApp) {
            AppPickerSheet { bundleID in
                if !settings.excludedBundleIDs.contains(bundleID) {
                    settings.excludedBundleIDs.append(bundleID)
                }
                isAddingApp = false
            } onCancel: {
                isAddingApp = false
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .idle:                  "Hold \(settings.pushToTalkKey.displayName) or tap"
        case .starting:              "Starting…"
        case .listening:             "Recording"
        case .finishing:             "Processing…"
        case .awaitingEnhancement:   "Confirm enhancement…"
        case .enhancing:             "Enhancing…"
        case .awaitingRetry:         "Enhancement failed"
        case .noTarget:              "Hold \(settings.pushToTalkKey.displayName) or tap"
        case .error(let msg):        msg
        }
    }

    private func appDisplayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return bundleID }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
    }
}

// MARK: - Inline Settings: Model

private struct InlineModelSettings: View {
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
                Toggle("Compare mode (both engines)", isOn: $settings.compareMode)
                Text(settings.engine == .parakeet
                    ? "Parakeet on the Neural Engine. Resolves on release; ~470 MB model download."
                    : "Apple's on-device transcriber. Streams text while you speak; no download required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Engine")
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
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Inline Settings: Cleanup & Enhancement

private struct InlineCleanupSettings: View {
    @State private var settings = Settings.shared
    @State private var apiKey: String = ""
    @State private var geminiModelLabel: String = ""
    @State private var isResolvingGeminiModel = false

    var body: some View {
        Form {
            Section {
                Toggle("Clean up transcripts", isOn: $settings.cleanupEnabled)
                if settings.cleanupEnabled {
                    Toggle("Smart cleanup (on-device AI)", isOn: $settings.smartCleanup)
                        .disabled(!FoundationModelFormatter.isAvailable)
                    if let reason = FoundationModelFormatter.unavailableReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Strips fillers, fixes spacing and punctuation. Dictionary corrections run either way.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cleanup")
            }

            Section {
                Picker("Mode", selection: $settings.enhancementMode) {
                    ForEach(EnhancementMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch settings.enhancementMode {
                case .off:
                    Text("No enhancement — only cleanup and dictionary corrections apply.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                case .local:
                    Text("Uses Apple Intelligence to improve grammar, structure, and clarity. Runs entirely on-device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !FoundationModelFormatter.isAvailable, let reason = FoundationModelFormatter.unavailableReason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                case .cloud:
                    Picker("Provider", selection: $settings.cloudProvider) {
                        ForEach(CloudProviderChoice.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    SecureField("API Key", text: apiKeyBinding)
                        .textFieldStyle(.roundedBorder)
                    if settings.cloudProvider == .gemini && !apiKey.isEmpty {
                        LabeledContent("Model") {
                            if isResolvingGeminiModel {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("Detecting…").foregroundStyle(.secondary)
                                }
                            } else if !geminiModelLabel.isEmpty {
                                Text(geminiModelLabel).foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                    }
                    Label(
                        "Your transcribed text is sent to \(settings.cloudProvider.displayName). Sensitive data is detected and redacted before sending; you'll confirm before any redacted text leaves this Mac.",
                        systemImage: "network"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Enhancement")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            apiKey = KeychainStore.load(forKey: settings.cloudProvider.keychainKey) ?? ""
        }
        .onChange(of: settings.cloudProvider) { _, _ in
            apiKey = KeychainStore.load(forKey: settings.cloudProvider.keychainKey) ?? ""
        }
        .task(id: settings.cloudProvider.rawValue + apiKey) {
            guard settings.cloudProvider == .gemini, !apiKey.isEmpty else {
                geminiModelLabel = ""
                return
            }
            isResolvingGeminiModel = true
            let model = await CloudEnhancer.resolveGeminiModel(apiKey: apiKey)
            isResolvingGeminiModel = false
            geminiModelLabel = model
        }
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKey },
            set: { newValue in
                apiKey = newValue
                if newValue.isEmpty {
                    KeychainStore.delete(forKey: settings.cloudProvider.keychainKey)
                } else {
                    KeychainStore.save(newValue, forKey: settings.cloudProvider.keychainKey)
                }
            }
        )
    }
}

// MARK: - Inline Settings: Audio

private struct InlineAudioSettings: View {
    @State private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Sound effects", isOn: $settings.soundEnabled)
                Text("Plays a short tick when recording starts and stops.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Feedback")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inline Settings: Permissions

private struct InlinePermissionsSettings: View {
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
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    }
                }
                Text("Required to monitor the push-to-talk key and type text into other apps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("System")
            }

            Section {
                LabeledContent("Microphone") {
                    if hasMicrophone {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    } else {
                        Button("Grant Access…") { Permissions.openMicrophoneSettings() }
                    }
                }
                Text("Required to capture audio for speech recognition.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - App Picker

private struct AppEntry: Identifiable {
    let id: String  // bundle ID
    let name: String
    let icon: NSImage
}

private struct AppPickerSheet: View {
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var apps: [AppEntry] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filtered: [AppEntry] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select App to Exclude")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            if isLoading {
                VStack {
                    ProgressView("Scanning applications…")
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    Button {
                        onSelect(app.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .fontWeight(.medium)
                                Text(app.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $searchText, prompt: "Search by name or bundle ID")
            }
        }
        .frame(width: 420, height: 520)
        .task { await loadApps() }
    }

    @MainActor
    private func loadApps() async {
        let appData = await Task.detached(priority: .userInitiated) {
            scanApps()
        }.value
        apps = appData.map { AppEntry(id: $0.bundleID, name: $0.name, icon: NSWorkspace.shared.icon(forFile: $0.path)) }
        isLoading = false
    }

    nonisolated private func scanApps() -> [(name: String, bundleID: String, path: String)] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [(name: String, bundleID: String, path: String)] = []

        let dirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for dir in dirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                seen.insert(bundleID)
                result.append((name: name, bundleID: bundleID, path: url.path))
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Shared

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.background.secondary)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct EmptyPanel: View {
    let label: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

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
