import SwiftUI
import PencilKit

// MARK: - PencilKit wrapper

struct PencilCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    @Binding var tool: PKTool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = tool
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = tool
    }
}

// MARK: - AI drawing overlay
// Animates commands on, keyed by a simple step counter per DrawBlock.

struct AIDrawingOverlay: View {
    let commands: [DrawCommand]
    let startTime: Date
    let logicalSize: CGSize

    private let stepDuration: Double = 0.35 // seconds per command reveal

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                let sx = size.width  / logicalSize.width
                let sy = size.height / logicalSize.height
                let scale = min(sx, sy)

                for (i, cmd) in commands.enumerated() {
                    let appearAt = Double(i) * stepDuration
                    let localT = elapsed - appearAt
                    guard localT > 0 else { continue }
                    let progress = min(1, localT / stepDuration)
                    draw(cmd, in: &ctx, sx: sx, sy: sy, scale: scale, progress: progress)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func color(_ hex: String?) -> Color {
        if let h = hex { return Color(hex: h) }
        return Theme.ink
    }

    private func draw(_ cmd: DrawCommand, in ctx: inout GraphicsContext,
                      sx: Double, sy: Double, scale: Double, progress: Double) {
        switch cmd {
        case .text(let t):
            let fontSize = (t.size ?? 28) * scale
            let text = SwiftUI.Text(t.text)
                .font(.system(size: fontSize, weight: .medium, design: .serif))
                .foregroundColor(color(t.color))
            ctx.opacity = progress
            ctx.draw(
                text,
                at: CGPoint(x: t.x * sx, y: t.y * sy),
                anchor: .bottomLeading
            )
            ctx.opacity = 1

        case .line(let l):
            var path = Path()
            path.move(to: CGPoint(x: l.x1 * sx, y: l.y1 * sy))
            let end = CGPoint(
                x: l.x1 * sx + (l.x2 - l.x1) * sx * progress,
                y: l.y1 * sy + (l.y2 - l.y1) * sy * progress
            )
            path.addLine(to: end)
            ctx.stroke(path, with: .color(color(l.color)),
                       style: StrokeStyle(lineWidth: (l.width ?? 2), lineCap: .round))

        case .arrow(let a):
            var path = Path()
            let startP = CGPoint(x: a.x1 * sx, y: a.y1 * sy)
            let endP = CGPoint(
                x: a.x1 * sx + (a.x2 - a.x1) * sx * progress,
                y: a.y1 * sy + (a.y2 - a.y1) * sy * progress
            )
            path.move(to: startP)
            path.addLine(to: endP)
            let col = color(a.color)
            ctx.stroke(path, with: .color(col),
                       style: StrokeStyle(lineWidth: (a.width ?? 2), lineCap: .round))

            // Draw arrowhead when fully extended
            if progress >= 0.95 {
                let angle = atan2(endP.y - startP.y, endP.x - startP.x)
                let head: Double = 12
                var arrow = Path()
                arrow.move(to: endP)
                arrow.addLine(to: CGPoint(
                    x: endP.x - head * cos(angle - .pi / 6),
                    y: endP.y - head * sin(angle - .pi / 6)
                ))
                arrow.addLine(to: CGPoint(
                    x: endP.x - head * cos(angle + .pi / 6),
                    y: endP.y - head * sin(angle + .pi / 6)
                ))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(col))
            }

        case .circle(let c):
            let r = c.r * scale
            let rect = CGRect(
                x: c.cx * sx - r, y: c.cy * sy - r,
                width: r * 2, height: r * 2
            )
            let path = Path(ellipseIn: rect)
            let col = color(c.color)
            // Draw partial arc based on progress
            let angle = Angle.degrees(360 * progress)
            var arcPath = Path()
            arcPath.addArc(
                center: CGPoint(x: c.cx * sx, y: c.cy * sy),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90) + angle,
                clockwise: false
            )
            if c.fill == true {
                ctx.opacity = progress
                ctx.fill(path, with: .color(col))
                ctx.opacity = 1
            } else {
                ctx.stroke(arcPath, with: .color(col),
                           style: StrokeStyle(lineWidth: (c.width ?? 2), lineCap: .round))
            }

        case .rect(let r):
            let rect = CGRect(x: r.x * sx, y: r.y * sy, width: r.w * sx, height: r.h * sy)
            let col = color(r.color)
            if r.fill == true {
                ctx.opacity = progress
                ctx.fill(Path(rect), with: .color(col))
                ctx.opacity = 1
            } else {
                // Animate: top edge, right edge, bottom edge, left edge
                let p = progress * 4
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(
                    x: rect.minX + min(1, p) * rect.width, y: rect.minY))
                if p > 1 {
                    path.addLine(to: CGPoint(
                        x: rect.maxX,
                        y: rect.minY + min(1, p - 1) * rect.height))
                }
                if p > 2 {
                    path.addLine(to: CGPoint(
                        x: rect.maxX - min(1, p - 2) * rect.width,
                        y: rect.maxY))
                }
                if p > 3 {
                    path.addLine(to: CGPoint(
                        x: rect.minX,
                        y: rect.maxY - min(1, p - 3) * rect.height))
                }
                ctx.stroke(path, with: .color(col),
                           style: StrokeStyle(lineWidth: (r.width ?? 2), lineCap: .round))
            }

        case .path(let p):
            guard p.points.count > 1 else { break }
            var path = Path()
            let total = Double(p.points.count - 1)
            let reveal = total * progress
            path.move(to: CGPoint(x: p.points[0][0] * sx, y: p.points[0][1] * sy))
            for i in 1..<p.points.count {
                let t = Double(i)
                if t <= reveal {
                    path.addLine(to: CGPoint(
                        x: p.points[i][0] * sx,
                        y: p.points[i][1] * sy
                    ))
                } else {
                    // Partial segment
                    let prev = p.points[i - 1]
                    let curr = p.points[i]
                    let frac = reveal - Double(i - 1)
                    if frac > 0 {
                        path.addLine(to: CGPoint(
                            x: (prev[0] + (curr[0] - prev[0]) * frac) * sx,
                            y: (prev[1] + (curr[1] - prev[1]) * frac) * sy
                        ))
                    }
                    break
                }
            }
            ctx.stroke(path, with: .color(color(p.color)),
                       style: StrokeStyle(lineWidth: (p.width ?? 2),
                                          lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Whiteboard container

struct Whiteboard: View {
    @Environment(TutorSession.self) private var session
    @State private var canvas = PKCanvasView()
    @State private var tool: PKTool = PKInkingTool(.pen, color: .init(Theme.ink), width: 3)
    @State private var activeCommands: [DrawCommand] = []
    @State private var animationStart: Date = .distantPast
    @State private var selectedColor: Color = Theme.ink
    @State private var isEraser = false
    @State private var brushSize: CGFloat = 3

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            boardArea
        }
        .onChange(of: session.drawTick) { _, _ in
            guard let block = session.pendingDrawBlock else { return }
            if block.clear == true {
                canvas.drawing = PKDrawing()
                activeCommands = []
            }
            activeCommands.append(contentsOf: block.commands)
            animationStart = Date()
            session.pendingDrawBlock = nil
        }
        .onChange(of: session.clearBoardTrigger) { _, _ in
            canvas.drawing = PKDrawing()
            activeCommands = []
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Pen / eraser
            HStack(spacing: 2) {
                toolButton(systemImage: "pencil.tip", active: !isEraser) {
                    isEraser = false
                    tool = PKInkingTool(.pen, color: .init(selectedColor), width: brushSize)
                }
                toolButton(systemImage: "eraser", active: isEraser) {
                    isEraser = true
                    tool = PKEraserTool(.vector)
                }
            }
            .padding(4)
            .background(Theme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Colors
            HStack(spacing: 6) {
                ForEach(Theme.drawColors, id: \.name) { c in
                    Button {
                        selectedColor = c.color
                        isEraser = false
                        tool = PKInkingTool(.pen, color: .init(c.color), width: brushSize)
                    } label: {
                        Circle()
                            .fill(c.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        selectedColor == c.color && !isEraser ? Theme.ink : Color.clear,
                                        lineWidth: 2
                                    )
                                    .padding(-3)
                            )
                    }
                }
            }

            Spacer()

            Button { session.clearBoard() } label: {
                Text("CLEAR")
                    .font(.mono(11, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            }
        }
    }

    private func toolButton(systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? Theme.paper : Theme.ink)
                .frame(width: 36, height: 36)
                .background(active ? Theme.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var boardArea: some View {
        GeometryReader { geo in
            ZStack {
                // Paper background
                Color(red: 1, green: 0.992, blue: 0.973)

                // Ruled grid
                Canvas { ctx, size in
                    let step: CGFloat = 32
                    let lineColor = Theme.line.opacity(0.5)
                    var x: CGFloat = 0
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(p, with: .color(lineColor), lineWidth: 0.5)
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(lineColor), lineWidth: 0.5)
                        y += step
                    }
                    // Margin line
                    var margin = Path()
                    margin.move(to: CGPoint(x: 64, y: 0))
                    margin.addLine(to: CGPoint(x: 64, y: size.height))
                    ctx.stroke(margin, with: .color(Theme.teal.opacity(0.4)), lineWidth: 1)
                }

                // PencilKit — user's drawing
                PencilCanvas(canvas: $canvas, tool: $tool)

                // AI drawing layer
                AIDrawingOverlay(
                    commands: activeCommands,
                    startTime: animationStart,
                    logicalSize: CGSize(width: CanvasSize.logicalWidth, height: CanvasSize.logicalHeight)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                AnimatedBorder(isActive: session.isThinking)
            )
        }
    }
}

// MARK: - Animated shimmer border (discrete, only visible when AI is working)

struct AnimatedBorder: View {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(
                isActive
                ? AnyShapeStyle(AngularGradient(
                    colors: [Theme.navy, Theme.teal, Theme.amber, Theme.navy],
                    center: .center,
                    angle: .degrees(Double(phase) * 360)
                ))
                : AnyShapeStyle(Theme.line),
                lineWidth: isActive ? 2 : 1
            )
            .animation(
                isActive
                ? .linear(duration: 2.5).repeatForever(autoreverses: false)
                : .default,
                value: phase
            )
            .onChange(of: isActive) { _, active in
                phase = active ? 1 : 0
            }
    }
}
