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
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(run.engine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1), in: .capsule)

                Text(String(format: "%.1fs", run.processSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Spacer()

                if isHovering {
                    HStack(spacing: 4) {
                        inlineActionPill(didCopy ? "Copied" : "Copy",
                                        icon: didCopy ? "checkmark" : "doc.on.doc") { copyText() }
                        inlineActionPill("Delete", icon: "trash") { onDelete() }
                            .foregroundStyle(Color.red.opacity(0.75))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
                }

                Text(run.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Text(run.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, run.corrections?.isEmpty == false ? 8 : 12)

            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            Divider()
        }
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private func inlineActionPill(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopy = false
        }
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
        case .awaitingNetworkFallback: "No network connection"
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

// MARK: - Card Components

private struct OptionCard<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    private let label: Label

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.isSelected = isSelected
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct CardContent: View {
    let title: String
    let subtitle: String
    var pros: [String] = []
    var cons: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !pros.isEmpty || !cons.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(pros, id: \.self) { CardBullet(text: $0, isPositive: true) }
                    ForEach(cons, id: \.self) { CardBullet(text: $0, isPositive: false) }
                }
            }
        }
    }
}

private struct CardBullet: View {
    let text: String
    let isPositive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isPositive ? "checkmark" : "minus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isPositive ? Color.green : Color.secondary)
                .frame(width: 12, height: 12, alignment: .center)
                .padding(.top, 1.5)
            Text(text)
                .font(.caption)
                .foregroundStyle(isPositive ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Inline Settings: Model

private struct InlineModelSettings: View {
    @State private var settings = Settings.shared
    @State private var isPreloading = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Speech Engine")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                HStack(alignment: .top, spacing: 12) {
                    OptionCard(isSelected: settings.engine == .apple, action: { settings.engine = .apple }) {
                        CardContent(
                            title: "Apple Speech",
                            subtitle: "Streams text as you speak",
                            pros: ["Live text while dictating", "No download required", "Instant start"],
                            cons: ["Lower accuracy on technical content"]
                        )
                    }
                    OptionCard(isSelected: settings.engine == .parakeet, action: { settings.engine = .parakeet }) {
                        CardContent(
                            title: "Parakeet",
                            subtitle: "Neural Engine batch model",
                            pros: ["Higher accuracy", "Resolves full phrase at once", "Neural Engine optimized"],
                            cons: ["~470 MB download required", "Resolves on key release only"]
                        )
                    }
                }
                .padding(.horizontal, 16)

                if settings.engine == .parakeet {
                    Divider()
                        .padding(.horizontal, 16)

                    HStack(spacing: 14) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Parakeet Model")
                                .font(.subheadline.weight(.medium))
                            Text("NVIDIA Parakeet TDT CTC 110M · ~470 MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if parakeetOnDisk {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        } else {
                            Button(isPreloading ? "Downloading…" : "Download") {
                                downloadParakeet()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isPreloading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .padding(.bottom, 20)
        }
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
        ScrollView {
            VStack(spacing: 0) {
                Text("Enhancement")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                VStack(spacing: 10) {
                    enhancementCard(
                        mode: .off,
                        icon: "circle.slash",
                        title: "Off",
                        subtitle: "Raw transcription only.",
                        bullets: ["No AI processing", "Fastest, zero extra latency", "Dictionary corrections still apply"]
                    )
                    enhancementCard(
                        mode: .local,
                        icon: "cpu",
                        title: "On-device AI",
                        subtitle: "Apple Intelligence improves grammar and clarity.",
                        bullets: ["Completely private — nothing leaves your Mac", "No API key required"],
                        isAvailable: FoundationModelFormatter.isAvailable,
                        unavailableReason: FoundationModelFormatter.unavailableReason
                    )
                    enhancementCard(
                        mode: .cloud,
                        icon: "cloud",
                        title: "Cloud AI",
                        subtitle: "Sends text to an AI provider for enhancement.",
                        bullets: ["Most powerful rewriting", "Sensitive data auto-redacted before sending", "Requires an API key"]
                    )
                }
                .padding(.horizontal, 16)

                if settings.enhancementMode == .cloud {
                    cloudConfigSection
                        .padding(.top, 12)
                }

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Text("Cleanup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                Toggle(isOn: $settings.cleanupEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean up transcripts")
                            .font(.subheadline.weight(.medium))
                        Text("Strips filler words, fixes spacing and punctuation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if settings.cleanupEnabled {
                    Divider().padding(.leading, 20)
                    Toggle(isOn: $settings.smartCleanup) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart cleanup")
                                .font(.subheadline.weight(.medium))
                            Text("Uses on-device AI to clean up rather than fixed rules.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!FoundationModelFormatter.isAvailable)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    if let reason = FoundationModelFormatter.unavailableReason, !FoundationModelFormatter.isAvailable {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            apiKey = KeychainStore.load(forKey: settings.cloudProvider.keychainKey) ?? ""
        }
        .onChange(of: settings.cloudProvider) { _, _ in
            apiKey = KeychainStore.load(forKey: settings.cloudProvider.keychainKey) ?? ""
        }
        .task(id: settings.cloudProvider.rawValue + apiKey) {
            guard !apiKey.isEmpty else {
                geminiModelLabel = ""
                return
            }
            switch settings.cloudProvider {
            case .gemini:
                isResolvingGeminiModel = true
                let model = await CloudEnhancer.resolveGeminiModel(apiKey: apiKey)
                isResolvingGeminiModel = false
                geminiModelLabel = model
            case .claude:
                geminiModelLabel = ""
                await CloudEnhancer.resolveClaudeModel(apiKey: apiKey)
            case .openai:
                geminiModelLabel = ""
                await CloudEnhancer.resolveOpenAIModel(apiKey: apiKey)
            case .groq:
                geminiModelLabel = ""
                await CloudEnhancer.resolveGroqModel(apiKey: apiKey)
            }
        }
    }

    @ViewBuilder
    private var cloudConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Provider")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Provider", selection: $settings.cloudProvider) {
                    ForEach(CloudProviderChoice.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            ApiKeyField(provider: settings.cloudProvider, text: apiKeyBinding)

            if settings.cloudProvider == .gemini && !apiKey.isEmpty {
                HStack(spacing: 6) {
                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isResolvingGeminiModel {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Detecting…").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if !geminiModelLabel.isEmpty {
                        Text(geminiModelLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "network")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                Text("Text is sent to \(settings.cloudProvider.displayName). Sensitive data is redacted before sending; you'll confirm before anything leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func enhancementCard(
        mode: EnhancementMode,
        icon: String,
        title: String,
        subtitle: String,
        bullets: [String],
        isAvailable: Bool = true,
        unavailableReason: String? = nil
    ) -> some View {
        let isSelected = settings.enhancementMode == mode

        Button {
            guard isAvailable else { return }
            settings.enhancementMode = mode
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if !isAvailable {
                            Text("Unavailable")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.15), in: .capsule)
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.35))
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let reason = unavailableReason, !isAvailable {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(bullets, id: \.self) { CardBullet(text: $0, isPositive: true) }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
        )
        .opacity(isAvailable ? 1 : 0.6)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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

struct ApiKeyField: View {
    let provider: CloudProviderChoice
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !text.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Spacer()
                Link("Get key →", destination: provider.apiKeyURL)
                    .font(.caption)
            }

            HStack(spacing: 4) {
                Group {
                    if isRevealed {
                        TextField(provider.keyPlaceholder, text: $text)
                    } else {
                        SecureField(provider.keyPlaceholder, text: $text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: provider) { _, _ in isRevealed = false }
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
