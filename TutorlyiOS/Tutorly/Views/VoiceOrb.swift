import SwiftUI

struct VoiceOrb: View {
    let state: VoiceState
    var size: CGFloat = 88

    @State private var breathe: CGFloat = 1.0
    @State private var barHeights: [CGFloat] = [12, 20, 8]
    @State private var wavePhase: CGFloat = 0

    var body: some View {
        ZStack {
            if state != .idle {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: size * 1.1, height: size * 1.1)
                    .blur(radius: 4)
            }
            if state == .speaking {
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: size, height: size)
                    .blur(radius: 8)
            }
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.accentDeep, Theme.accent, Theme.accentDeep],
                    center: .center, startRadius: 0, endRadius: size / 2))
                .frame(width: size * 0.77, height: size * 0.77)
                .overlay(
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [Color.white.opacity(0.8), Color.white.opacity(0)],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0, endRadius: size * 0.2))
                        .frame(width: size * 0.4, height: size * 0.27)
                        .offset(x: -size * 0.1, y: -size * 0.12)
                )
                .scaleEffect(breathe)

            Group {
                switch state {
                case .speaking:
                    WavePath(phase: wavePhase)
                        .stroke(Color.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: size * 0.45, height: size * 0.18)
                case .listening:
                    HStack(spacing: size * 0.04) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white)
                                .frame(width: 3, height: barHeights[i])
                        }
                    }
                case .idle:
                    Circle().fill(Color.white.opacity(0.9)).frame(width: 6, height: 6)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animate() }
        .onChange(of: state) { _, _ in animate() }
    }

    private func animate() {
        switch state {
        case .speaking:
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = 1.04
            }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
        case .listening:
            breathe = 1.0
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                barHeights = [20, 12, 18]
            }
        case .idle:
            breathe = 1.0
            barHeights = [12, 20, 8]
            wavePhase = 0
        }
    }
}

struct WavePath: Shape {
    var phase: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 40
        p.move(to: CGPoint(x: 0, y: rect.midY))
        for i in 1...steps {
            let x = CGFloat(i) / CGFloat(steps) * rect.width
            let y = rect.midY + sin(CGFloat(i) / CGFloat(steps) * .pi * 4 + phase) * rect.height * 0.3
            p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }
}
