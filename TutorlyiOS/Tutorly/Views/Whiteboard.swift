import SwiftUI
import PencilKit

// Each draw command has its own reveal time so new commands don't restart old animations.
struct DrawItem: Identifiable {
    let id = UUID()
    let command: DrawCommand
    let revealAt: Date
    static let animDuration: TimeInterval = 0.38
}

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

struct AIDrawingOverlay: View {
    let items: [DrawItem]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let sx = size.width  / CanvasSize.logicalWidth
                let sy = size.height / CanvasSize.logicalHeight
                let scale = min(sx, sy)

                for item in items {
                    let elapsed = timeline.date.timeIntervalSince(item.revealAt)
                    guard elapsed > 0 else { continue }
                    let progress = min(1.0, elapsed / DrawItem.animDuration)
                    draw(item.command, in: &ctx, sx: sx, sy: sy, scale: scale, progress: progress)
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
            let resolved = ctx.resolve(
                SwiftUI.Text(t.text)
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundColor(color(t.color))
            )
            ctx.opacity = progress
            ctx.draw(resolved, at: CGPoint(x: t.x * sx, y: t.y * sy), anchor: .bottomLeading)
            ctx.opacity = 1

        case .line(let l):
            var path = Path()
            path.move(to: CGPoint(x: l.x1 * sx, y: l.y1 * sy))
            path.addLine(to: CGPoint(
                x: l.x1 * sx + (l.x2 - l.x1) * sx * progress,
                y: l.y1 * sy + (l.y2 - l.y1) * sy * progress
            ))
            ctx.stroke(path, with: .color(color(l.color)),
                       style: StrokeStyle(lineWidth: l.width ?? 2, lineCap: .round))

        case .arrow(let a):
            let startP = CGPoint(x: a.x1 * sx, y: a.y1 * sy)
            let endP   = CGPoint(
                x: a.x1 * sx + (a.x2 - a.x1) * sx * progress,
                y: a.y1 * sy + (a.y2 - a.y1) * sy * progress
            )
            var path = Path()
            path.move(to: startP)
            path.addLine(to: endP)
            let col = color(a.color)
            ctx.stroke(path, with: .color(col),
                       style: StrokeStyle(lineWidth: a.width ?? 2, lineCap: .round))
            if progress >= 0.95 {
                let angle = atan2(endP.y - startP.y, endP.x - startP.x)
                let head: Double = 12
                var arrow = Path()
                arrow.move(to: endP)
                arrow.addLine(to: CGPoint(x: endP.x - head * cos(angle - .pi/6),
                                          y: endP.y - head * sin(angle - .pi/6)))
                arrow.addLine(to: CGPoint(x: endP.x - head * cos(angle + .pi/6),
                                          y: endP.y - head * sin(angle + .pi/6)))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(col))
            }

        case .circle(let c):
            let r = c.r * scale
            let col = color(c.color)
            if c.fill == true {
                let rect = CGRect(x: c.cx * sx - r, y: c.cy * sy - r, width: r*2, height: r*2)
                ctx.opacity = progress
                ctx.fill(Path(ellipseIn: rect), with: .color(col))
                ctx.opacity = 1
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
                ctx.opacity = progress
                ctx.fill(Path(rect), with: .color(col))
                ctx.opacity = 1
            } else {
                let p = progress * 4
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + min(1, p) * rect.width, y: rect.minY))
                if p > 1 { path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + min(1, p-1) * rect.height)) }
                if p > 2 { path.addLine(to: CGPoint(x: rect.maxX - min(1, p-2) * rect.width, y: rect.maxY)) }
                if p > 3 { path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - min(1, p-3) * rect.height)) }
                ctx.stroke(path, with: .color(col),
                           style: StrokeStyle(lineWidth: r.width ?? 2, lineCap: .round))
            }

        case .path(let p):
            guard p.points.count > 1 else { break }
            let total  = Double(p.points.count - 1)
            let reveal = total * progress
            var path = Path()
            path.move(to: CGPoint(x: p.points[0][0] * sx, y: p.points[0][1] * sy))
            for i in 1..<p.points.count {
                if Double(i) <= reveal {
                    path.addLine(to: CGPoint(x: p.points[i][0] * sx, y: p.points[i][1] * sy))
                } else {
                    let frac = reveal - Double(i - 1)
                    guard frac > 0 else { break }
                    let prev = p.points[i-1], curr = p.points[i]
                    path.addLine(to: CGPoint(x: (prev[0] + (curr[0]-prev[0]) * frac) * sx,
                                             y: (prev[1] + (curr[1]-prev[1]) * frac) * sy))
                    break
                }
            }
            ctx.stroke(path, with: .color(color(p.color)),
                       style: StrokeStyle(lineWidth: p.width ?? 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Whiteboard container

struct Whiteboard: View {
    @Environment(TutorSession.self) private var session
    @State private var canvas = PKCanvasView()
    @State private var tool: PKTool = PKInkingTool(.pen, color: .init(Theme.ink), width: 3)
    @State private var drawItems: [DrawItem] = []
    @State private var selectedColor: Color = Theme.ink
    @State private var isEraser = false
    @State private var brushSize: CGFloat = 3

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            boardArea
        }
        .onChange(of: session.drawTick) { _, _ in
            guard let block = session.pendingDrawBlock else { return }
            if block.clear == true {
                canvas.drawing = PKDrawing()
                drawItems = []
            }
            let now = Date()
            let newItems = block.commands.enumerated().map { i, cmd in
                DrawItem(command: cmd,
                         revealAt: now.addingTimeInterval(Double(i) * DrawItem.animDuration))
            }
            drawItems.append(contentsOf: newItems)
            session.pendingDrawBlock = nil
        }
        .onChange(of: session.clearBoardTrigger) { _, _ in
            canvas.drawing = PKDrawing()
            drawItems = []
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

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
                    .font(.mono(10, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var boardArea: some View {
        GeometryReader { _ in
            ZStack {
                Color(red: 1, green: 0.993, blue: 0.975)

                // Ruled grid
                Canvas { ctx, size in
                    let step: CGFloat = 32
                    let lineColor = Theme.line.opacity(0.45)
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
                    var margin = Path()
                    margin.move(to: CGPoint(x: 60, y: 0))
                    margin.addLine(to: CGPoint(x: 60, y: size.height))
                    ctx.stroke(margin, with: .color(Theme.teal.opacity(0.35)), lineWidth: 1)
                }

                PencilCanvas(canvas: $canvas, tool: $tool)

                AIDrawingOverlay(items: drawItems)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // Soft inner shadow gives depth without a harsh border
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            .overlay(AlwaysOnBorder(isActive: session.realtimeSession.isTutorSpeaking || session.isThinking))
        }
    }
}

// MARK: - Always-on animated gradient border
// Slow rotation at low opacity when idle; faster + brighter when the tutor is active.

struct AlwaysOnBorder: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { ctx in
            let t     = ctx.date.timeIntervalSinceReferenceDate
            let speed = isActive ? 3.0 : 14.0
            let angle = (t / speed).truncatingRemainder(dividingBy: 1.0) * 360

            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    AngularGradient(
                        colors: [Theme.navy, Theme.teal, Theme.amber, Theme.teal, Theme.navy],
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: isActive ? 2.5 : 1.5
                )
                .opacity(isActive ? 0.90 : 0.22)
        }
    }
}
