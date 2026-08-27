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
        Waveform(level: controller.level, isActive: controller.state == .listening)
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
    }
}

/// Level-reactive bars — fixed phase offsets keep bars from pumping in unison.
private struct Waveform: View {
    let level: Float
    let isActive: Bool

    private static let barCount = 10
    private static let phases: [Double] = (0..<barCount).map { index in
        (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: height(for: index, at: t))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let floorHeight: CGFloat = 3
        guard isActive else { return floorHeight }

        let phase = Self.phases[index]
        let wave = sin(time * 6.0 + phase * .pi * 2)
        let amplitude = CGFloat(max(0.04, level))
        let scaled = amplitude * (0.55 + 0.45 * CGFloat(wave))
        return floorHeight + max(0, scaled) * 11
    }
}
