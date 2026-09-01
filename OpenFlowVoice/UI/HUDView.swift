import AppKit
import SwiftUI

enum Brand {
    static let accent = Color(red: 0.42, green: 0.55, blue: 1.0)
    static let accentWarm = Color(red: 0.76, green: 0.47, blue: 1.0)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentWarm],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct HUDView: View {
    @Bindable var controller: DictationController

    var body: some View {
        Group {
            if case .noTarget(let text) = controller.state {
                NoTargetView(text: text, controller: controller)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else if case .awaitingEnhancement(let text, let flagged) = controller.state {
                AwaitingEnhancementView(text: text, flagged: flagged, controller: controller)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else if controller.state == .enhancing {
                EnhancingView()
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else if case .awaitingRetry(let text) = controller.state {
                AwaitingRetryView(text: text, controller: controller)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else if case .awaitingNetworkFallback(let text) = controller.state {
                AwaitingNetworkFallbackView(text: text, controller: controller)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                RecordingPill(controller: controller)
            }
        }
        .background(Color.clear)
    }
}

private struct RecordingPill: View {
    @Bindable var controller: DictationController

    var body: some View {
        Waveform(levels: controller.levels, isActive: controller.state == .listening)
            .frame(width: 64, height: 16)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                Capsule()
                    .fill(Color(white: 0.06))
            }
    }
}

private struct NoTargetView: View {
    let text: String
    let controller: DictationController
    @State private var copied = false
    @State private var timeLeft: Int = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center) {
                Text("Select a text field first")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                Text("\(timeLeft)s")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.22))
                    .monospacedDigit()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        controller.dismissNoTarget()
                    }
                } label: {
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copied ? Color(red: 0.3, green: 0.9, blue: 0.5) : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .animation(.easeOut(duration: 0.15), value: copied)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.06))
        }
        .task {
            while timeLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                timeLeft -= 1
            }
            controller.dismissNoTarget()
        }
    }
}

private struct AwaitingEnhancementView: View {
    let text: String
    let flagged: [SensitiveMatch]
    let controller: DictationController

    /// Unique kinds in declaration order — avoids showing the same category twice.
    private var kinds: [SensitiveMatch.Kind] {
        SensitiveMatch.Kind.allCases.filter { kind in flagged.contains { $0.kind == kind } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sensitive information detected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(kinds, id: \.self) { kind in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow.opacity(0.9))
                        Text(kind.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }

            Text("Send to \(Settings.shared.cloudProvider.displayName) for enhancement?")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 8) {
                Button("No, use local AI") {
                    controller.resolveEnhancement(sendToCloud: false)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)

                Spacer()

                Button("Yes, send redacted") {
                    controller.resolveEnhancement(sendToCloud: true)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Brand.accent.opacity(0.15), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.06))
        }
    }
}

private struct EnhancingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .colorScheme(.dark)
            Text("Enhancing…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.06))
        }
    }
}

private struct AwaitingRetryView: View {
    let text: String
    let controller: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enhancement failed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text("Cloud unavailable. Try on-device AI?")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 8) {
                Button("Skip") {
                    controller.resolveRetry(useLocal: false)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)

                Spacer()

                Button("Try local AI") {
                    controller.resolveRetry(useLocal: true)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Brand.accent.opacity(0.15), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.06))
        }
    }
}

private struct AwaitingNetworkFallbackView: View {
    let text: String
    let controller: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No network connection")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow.opacity(0.9))
                Text("Cloud enhancement unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Text("Use on-device AI or skip enhancement?")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 8) {
                Button("Skip") {
                    controller.resolveRetry(useLocal: false)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)

                Spacer()

                Button("Use local AI") {
                    controller.resolveRetry(useLocal: true)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Brand.accent.opacity(0.15), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.06))
        }
    }
}

/// Spectrum bars driven by real per-band mel levels from the microphone FFT pipeline.
private struct Waveform: View {
    let levels: [Float]
    let isActive: Bool

    private static let barCount = 10

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { _ in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: height(for: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int) -> CGFloat {
        let floorHeight: CGFloat = 3
        guard isActive, index < levels.count else { return floorHeight }
        return floorHeight + CGFloat(min(1.0, max(0.02, levels[index] * 4))) * 13
    }
}
