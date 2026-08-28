import AppKit
import SwiftUI

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
                Label("General", systemImage: "keyboard")
                    .tag(MainSection.general)
                Label("Model", systemImage: "brain")
                    .tag(MainSection.model)
                Label("Cleanup", systemImage: "wand.and.sparkles")
                    .tag(MainSection.cleanup)
                Label("Audio", systemImage: "speaker.wave.2.fill")
                    .tag(MainSection.audio)
                Label("Permissions", systemImage: "lock.shield.fill")
                    .tag(MainSection.permissions)

                Section("History") {
                    Label("Transcriptions", systemImage: "text.bubble")
                        .tag(MainSection.transcriptions)
                    Label("Dictionary", systemImage: "character.book.closed")
                        .tag(MainSection.dictionary)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailView
        }
        .frame(minWidth: 760, minHeight: 520)
        .toolbar {
            if selection == .general || selection == nil {
                Button("Quit app") { NSApp.terminate(nil) }
                    .controlSize(.extraLarge)
            }
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

                    SidebarLevelBars(level: controller.level, isActive: isRecording)
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
        case .idle:           "Hold \(settings.pushToTalkKey.displayName) or tap"
        case .starting:       "Starting…"
        case .listening:      "Recording"
        case .finishing:      "Processing…"
        case .noTarget:       "Hold \(settings.pushToTalkKey.displayName) or tap"
        case .error(let msg): msg
        }
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

// MARK: - Inline Settings: Cleanup

private struct InlineCleanupSettings: View {
    @State private var settings = Settings.shared

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
                Text("Text Processing")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
