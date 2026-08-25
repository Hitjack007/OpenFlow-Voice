import AppKit
import SwiftUI

struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var section: Section = .transcriptions

    enum Section: String, CaseIterable, Identifiable {
        case transcriptions, dictionary
        var id: String { rawValue }
        var title: String { self == .transcriptions ? "Transcriptions" : "Dictionary" }
    }

    var body: some View {
        VStack(spacing: 0) {
            RecordControl(controller: controller)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Picker("", selection: $section) {
                ForEach(Section.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch section {
                case .transcriptions: TranscriptionList()
                case .dictionary: DictionaryPanel()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}

// MARK: - Record Control

private struct RecordControl: View {
    @Bindable var controller: DictationController
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?
    @State private var settings = Settings.shared
    @Environment(\.openSettings) private var openSettings

    private var isRecording: Bool { controller.state.isActive }

    var body: some View {
        HStack(spacing: 20) {
            Button {
                if isRecording {
                    controller.stopButtonRecording()
                } else {
                    controller.startButtonRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red : Color.accentColor)
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: isRecording)

            VStack(alignment: .leading, spacing: 3) {
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(counterText)
                    .font(.system(.subheadline, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            LevelBars(level: controller.level, isActive: isRecording)

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .padding(8)
                    .glassEffect(in: .circle)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 18))
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
        case .idle: "Hold \(settings.pushToTalkKey.displayName) or tap to record"
        case .starting: "Starting…"
        case .listening: "Recording"
        case .finishing: "Processing…"
        case .error(let msg): msg
        }
    }

    private var counterText: String {
        guard isRecording else { return "—" }
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Level Bars

private struct LevelBars: View {
    let level: Float
    var isActive: Bool
    private let count = 20

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                let normalized = Float(i + 1) / Float(count)
                let isLit = isActive && normalized <= level
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLit ? barColor(normalized) : Color.secondary.opacity(0.12))
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .animation(.linear(duration: 0.04), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let center = Float(count - 1) / 2.0
        let dist = abs(Float(index) - center) / center
        return 6 + CGFloat(1.0 - dist) * 24
    }

    private func barColor(_ normalized: Float) -> Color {
        normalized > 0.85 ? .red : normalized > 0.65 ? .yellow : .green
    }
}

// MARK: - Transcriptions

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
