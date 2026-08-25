import AppKit
import SwiftUI

struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        Form {
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
                Text("Hold this key anywhere to dictate. The window's Record button works regardless of what's focused.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Push to Talk")
            }

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
                Text("Model")
            }

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
                Toggle("Sound effects", isOn: $settings.soundEnabled)
            } header: {
                Text("Audio")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 440)
    }
}

// MARK: - Shortcut Recorder

private struct ShortcutRecorder: View {
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
