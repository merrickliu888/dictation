import SwiftUI

/// Bottom-center pill shown while dictating: recording dot, live waveform,
/// the tail of what has been heard so far, and how to finish.
struct DictationPillView: View {
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var transcriber: Transcriber

    private var isFinishing: Bool {
        if case .finishing = controller.phase { return true }
        return false
    }

    var body: some View {
        VStack {
            Spacer()
            pill
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pill: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isFinishing ? Color.secondary : Color.red)
                .frame(width: 8, height: 8)
                .opacity(0.9)
                .modifier(PulseEffect())

            WaveformView(level: isFinishing ? 0 : transcriber.audioLevel)
                .frame(width: 88, height: 24)

            status
                .font(.system(size: 14))
                .frame(maxWidth: 320, alignment: .leading)

            if isFinishing {
                ProgressView().controlSize(.small)
            } else if let hint = controller.hint {
                KeyHint(symbol: hint.symbol, label: hint.label)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlayCard(cornerRadius: Theme.pillRadius)
        .fixedSize()
    }

    @ViewBuilder
    private var status: some View {
        if let error = transcriber.lastError {
            Text(error)
                .foregroundStyle(Theme.failure)
                .lineLimit(2)
        } else if !transcriber.partialText.isEmpty {
            // The newest words matter most; drop the start, not the end.
            Text(transcriber.partialText)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
        } else if isFinishing {
            Text("Finishing…").foregroundStyle(Theme.textSecondary)
        } else if !transcriber.isActive {
            Text("Starting microphone…").foregroundStyle(Theme.textSecondary)
        } else {
            Text("Listening…").foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Symmetric center-weighted level bars.
struct WaveformView: View {
    var level: Float
    private let weights: [CGFloat] = [0.35, 0.55, 0.78, 0.95, 1.0, 0.95, 0.78, 0.55, 0.35]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(weights.indices, id: \.self) { i in
                    let travel = 0.5 + 0.5 * sin(time * 6.2 - Double(i) * 0.78)
                    let base = CGFloat(level) * weights[i]
                    let liveliness = (1 - base) * CGFloat(0.06 + travel * 0.16)
                    let height = max(3, (base + liveliness) * 24)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.accent)
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 24)
        }
    }
}

struct PulseEffect: ViewModifier {
    @State private var pulsing = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.25 : 0.9)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
