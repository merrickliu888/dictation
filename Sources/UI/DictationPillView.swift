import SwiftUI

/// Bottom-center pill shown while dictating: just the live waveform.
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
        WaveformView(level: isFinishing ? 0 : transcriber.audioLevel)
            .frame(width: 56, height: 14)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlayCard(cornerRadius: 14)
            .fixedSize()
    }
}

/// Symmetric center-weighted level bars.
struct WaveformView: View {
    var level: Float
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2.5
    var maxHeight: CGFloat = 14
    private let weights: [CGFloat] = [0.35, 0.55, 0.78, 0.95, 1.0, 0.95, 0.78, 0.55, 0.35]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(weights.indices, id: \.self) { i in
                    let travel = 0.5 + 0.5 * sin(time * 6.2 - Double(i) * 0.78)
                    let base = CGFloat(level) * weights[i]
                    let liveliness = (1 - base) * CGFloat(0.06 + travel * 0.16)
                    let height = max(barWidth, (base + liveliness) * maxHeight)
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(Theme.accent)
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(height: maxHeight)
        }
    }
}

