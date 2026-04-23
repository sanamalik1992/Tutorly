import SwiftUI

struct Whiteboard: View {
    @Environment(TutorSession.self) private var session
    @State private var drawItems: [DrawItem] = []

    struct DrawItem: Identifiable {
        let id = UUID()
        let command: DrawCommand
        let revealAt: Date
        static let animDuration: TimeInterval = 0.35
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )

            GeometryReader { _ in
                Canvas { ctx, size in
                    let dotSpacing: CGFloat = 20
                    let dotColor = Color.white.opacity(0.09)
                    var y: CGFloat = 10
                    while y < size.height {
                        var x: CGFloat = 10
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8)),
                                     with: .color(dotColor))
                            x += dotSpacing
                        }
                        y += dotSpacing
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))

            GeometryReader { geo in
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        let sx = size.width / CanvasSize.width
                        let sy = size.height / CanvasSize.height
                        let scale = min(sx, sy)
                        let now = timeline.date
                        for item in drawItems {
                            let elapsed = now.timeIntervalSince(item.revealAt)
                            guard elapsed > 0 else { continue }
                            let progress = min(1, elapsed / DrawItem.animDuration)
                            drawCommand(item.command, ctx: &ctx, sx: sx, sy: sy, scale: scale, progress: progress)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .onChange(of: session.realtime.drawTick) { _, _ in
            guard let block = session.realtime.pendingDrawBlock else { return }
            print("[View] applying \(block.commands.count) commands to canvas")
            if block.clear == true { drawItems.removeAll() }
            let now = Date()
            for (i, cmd) in block.commands.enumerated() {
                drawItems.append(DrawItem(
                    command: cmd,
                    revealAt: now.addingTimeInterval(Double(i) * DrawItem.animDuration)
                ))
            }
            session.realtime.pendingDrawBlock = nil
        }
    }

    private func color(_ hex: String?) -> Color {
        guard let hex else { return Theme.accent }
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }

    private func drawCommand(_ cmd: DrawCommand, ctx: inout GraphicsContext,
                              sx: Double, sy: Double, scale: Double, progress: Double) {
        ctx.opacity = progress
        switch cmd {
        case .text(let t):
            let fontSize = (t.size ?? 24) * scale
            ctx.draw(
                Text(t.text)
                    .font(.system(size: fontSize, weight: .medium, design: .serif))
                    .foregroundColor(color(t.color)),
                at: CGPoint(x: t.x * sx, y: t.y * sy),
                anchor: .bottomLeading
            )

        case .line(let l):
            var path = Path()
            path.move(to: CGPoint(x: l.x1 * sx, y: l.y1 * sy))
            let ex = l.x1 * sx + (l.x2 - l.x1) * sx * progress
            let ey = l.y1 * sy + (l.y2 - l.y1) * sy * progress
            path.addLine(to: CGPoint(x: ex, y: ey))
            ctx.stroke(path, with: .color(color(l.color)),
                       style: StrokeStyle(lineWidth: l.width ?? 2.5, lineCap: .round))

        case .arrow(let a):
            let x1 = a.x1 * sx, y1 = a.y1 * sy
            let ex = x1 + (a.x2 - a.x1) * sx * progress
            let ey = y1 + (a.y2 - a.y1) * sy * progress
            var path = Path()
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: ex, y: ey))
            let col = color(a.color)
            ctx.stroke(path, with: .color(col),
                       style: StrokeStyle(lineWidth: a.width ?? 2.5, lineCap: .round))
            if progress >= 0.95 {
                let angle = atan2(ey - y1, ex - x1)
                let head: Double = 12
                var arrow = Path()
                arrow.move(to: CGPoint(x: ex, y: ey))
                arrow.addLine(to: CGPoint(x: ex - head * cos(angle - .pi / 6),
                                          y: ey - head * sin(angle - .pi / 6)))
                arrow.addLine(to: CGPoint(x: ex - head * cos(angle + .pi / 6),
                                          y: ey - head * sin(angle + .pi / 6)))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(col))
            }

        case .circle(let c):
            let r = c.r * scale
            let col = color(c.color)
            if c.fill == true {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.cx * sx - r, y: c.cy * sy - r,
                                          width: r * 2, height: r * 2)),
                    with: .color(col)
                )
            } else {
                var arc = Path()
                arc.addArc(center: CGPoint(x: c.cx * sx, y: c.cy * sy),
                           radius: r,
                           startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * progress),
                           clockwise: false)
                ctx.stroke(arc, with: .color(col),
                           style: StrokeStyle(lineWidth: c.width ?? 2, lineCap: .round))
            }

        case .rect(let r):
            let rect = CGRect(x: r.x * sx, y: r.y * sy, width: r.w * sx, height: r.h * sy)
            let col = color(r.color)
            if r.fill == true {
                ctx.fill(Path(rect), with: .color(col))
            } else {
                ctx.stroke(Path(rect), with: .color(col),
                           style: StrokeStyle(lineWidth: r.width ?? 2))
            }
        }
        ctx.opacity = 1
    }
}
