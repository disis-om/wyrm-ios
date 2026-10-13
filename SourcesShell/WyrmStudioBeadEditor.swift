import SwiftUI
import UIKit

/*
 * The bead editor (OM, 2026-10-12; iOS 2026-10-13). Android twin:
 * ui/StudioBeadEditor.kt. The bead as big as the screen allows, to paint on
 * with a brush, an eraser, a fill and a colour picker, with mirror or radial
 * symmetry and undo; and its look: a finish, colour, hue, saturation,
 * brightness, opacity, smoothness and detail. A strip of the bead along a
 * snake shows the finished bead as the arena will draw it. Nothing is kept
 * until Done; the X throws the changes away.
 */

private enum BrushTool { case brush, eraser, fill, picker }

private enum Symmetry: CaseIterable {
    case off, mirror, quad, radial
    var label: String {
        switch self {
        case .off: return "Off"
        case .mirror: return "Mirror"
        case .quad: return "4 way"
        case .radial: return "6 way"
        }
    }
}

/// The painting's resolution: the bead's disc square.
private let paintSize = 256

/// The working painting and its history: a private copy until Done.
private final class StudioPaintWork {
    let paint: StudioCanvas
    var undo: [StudioCanvas] = []
    var redo: [StudioCanvas] = []
    var changed = false
    /// The stroke under the finger.
    var last: CGPoint = .zero
    var mid: CGPoint = .zero
    var stroking = false
    /// Pictures that cost a little to draw, kept while their inputs stay the same.
    var baseKey = ""
    var base: CGImage?
    var finishesKey = ""
    var finishes: [CGImage?] = []
    var finishedKey = ""
    var finished: CGImage?

    init(beadID: String, painted: Bool) {
        paint = StudioCanvas(width: paintSize, height: paintSize)!
        if painted, let picture = WyrmStudioPaints.shared.image(beadID) {
            paint.draw(picture, in: CGRect(x: 0, y: 0, width: paintSize, height: paintSize))
        }
    }

    func snapshot() {
        if let copy = paint.copy() { undo.append(copy) }
        if undo.count > 25 { undo.removeFirst() }
        redo.removeAll()
    }
}

struct StudioBeadEditor: View {
    let beadID: String
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let onDone: (_ saved: Bool) -> Void

    private let start: WyrmStudioBead
    @State private var draft: WyrmStudioBead
    @State private var work: StudioPaintWork
    @State private var paintTick = 0
    /// Bumped when a stroke ends (or a fill, clear, undo): the finished bead redraws then.
    @State private var strokeDone = 0
    @State private var tool = BrushTool.brush
    @State private var symmetry = Symmetry.off
    @State private var brushColor: UInt32 = 0xFFFF_FFFF
    @State private var brushSize: Float = 18
    @State private var brushSoft: Float = 0.2
    @State private var panel = 0

    init(beadID: String, textures: WyrmSkinTextureLibrary, onDone: @escaping (_ saved: Bool) -> Void) {
        self.beadID = beadID
        self.textures = textures
        self.onDone = onDone
        let bead = WyrmStudio.shared.bead(beadID) ?? WyrmStudioBead(id: beadID)
        start = bead
        _draft = State(initialValue: bead)
        _work = State(initialValue: StudioPaintWork(beadID: beadID, painted: bead.painted))
    }

    var body: some View {
        let white = textures.beads[40]
        let _ = paintTick
        let finished = finishedBead(white: white)
        return VStack(spacing: 0) {
            topBar
            // The bead along a snake, as the arena draws it.
            Canvas { context, size in
                guard let finished else { return }
                let bead = size.height * 0.8
                let step = bead * studioBeadStep
                let count = max(Int(size.width / step), 2)
                let picture = context.resolve(Image(decorative: finished, scale: 1))
                for i in stride(from: count - 1, through: 0, by: -1) {
                    let x = size.width - bead / 2 - CGFloat(i) * step
                    let y = size.height / 2 + sin(CGFloat(i) * 0.5) * bead * 0.08
                    context.draw(picture, in: CGRect(x: x - bead / 2, y: y - bead / 2, width: bead, height: bead))
                }
            }
            .frame(height: 54)
            .padding(.horizontal, 16)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, 360)
                        paintCanvas(side: side, white: white)
                            .frame(width: side, height: side)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: min(UIScreen.main.bounds.width - 48, 360))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    Text("The front half (right) is what shows along the body.").font(.androidWyrm(11)).foregroundColor(ATheme.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                    Spacer().frame(height: 12)
                    WSSegmented(options: ["Paint", "Look"], selected: panel) { panel = $0 }.padding(.horizontal, 16)
                    Spacer().frame(height: 12)
                    VStack(alignment: .leading, spacing: 10) {
                        if panel == 0 { paintPanel } else { lookPanel(white: white) }
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    Spacer().frame(height: 60)
                }
            }
        }
        .background(ATheme.paper.ignoresSafeArea())
    }

    /// The finished bead as the arena draws it (painting, edge and all): redrawn
    /// when a stroke ends or the look changes, not on every move.
    private func finishedBead(white: CGImage?) -> CGImage? {
        let key = "\(strokeDone)|\(draft)|\(white != nil)"
        if work.finishedKey != key {
            work.finishedKey = key
            var full = draft
            full.painted = true
            work.finished = WyrmStudioArt.renderBead(full, paint: work.paint.image(), size: 160, white: white)
        }
        return work.finished
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            // The working painting is a copy: closing simply drops it.
            StudioRoundButton(icon: "xmark", size: 38) { onDone(false) }
            VStack(alignment: .leading, spacing: 1) {
                Text("BEAD").font(.androidWyrm(9.5, .bold)).tracking(1.2).foregroundColor(ATheme.quiet)
                Text(WyrmStudioArt.finishes[safeIndex: draft.finish] ?? "Bead").font(.androidWyrm(22, .bold))
                    .foregroundColor(ATheme.ink).lineLimit(1)
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            StudioRoundButton(icon: "arrow.uturn.backward", enabled: !work.undo.isEmpty, size: 38) {
                guard let last = work.undo.popLast() else { return }
                if let now = work.paint.copy() { work.redo.append(now) }
                restore(last)
            }
            Spacer().frame(width: 8)
            StudioRoundButton(icon: "arrow.uturn.forward", enabled: !work.redo.isEmpty, size: 38) {
                guard let next = work.redo.popLast() else { return }
                if let now = work.paint.copy() { work.undo.append(now) }
                restore(next)
            }
            Spacer().frame(width: 10)
            StudioCapsule(label: "Done", icon: "checkmark") {
                var saved = draft
                saved.painted = start.painted
                WyrmStudio.shared.updateBead(saved)
                if work.changed {
                    WyrmStudio.shared.savePaint(beadID, work.paint.isEmpty ? nil : work.paint.image())
                }
                onDone(true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func restore(_ from: StudioCanvas) {
        work.paint.load(from: from)
        work.changed = true
        paintTick += 1
        strokeDone += 1
    }

    // MARK: the canvas

    private func paintCanvas(side s: CGFloat, white: CGImage?) -> some View {
        let rd = s / 2 * WyrmStudioArt.disc
        let left = s / 2 - rd
        let shown = composite(white: white)
        let mode = symmetry
        return Canvas { context, size in
            // A checkerboard shows through where the bead is see-through.
            let cell = s / 16
            for yy in 0..<16 {
                for xx in 0..<16 {
                    context.fill(Path(CGRect(x: CGFloat(xx) * cell, y: CGFloat(yy) * cell, width: cell, height: cell)),
                                 with: .color((xx + yy) % 2 == 0 ? ATheme.card : ATheme.rule.opacity(0.5)))
                }
            }
            let disc = Path(ellipseIn: CGRect(x: left, y: left, width: 2 * rd, height: 2 * rd))
            if let shown {
                var inside = context
                inside.clip(to: disc)
                inside.draw(Image(decorative: shown, scale: 1), in: CGRect(x: 0, y: 0, width: s, height: s))
            }
            // The part a body shows: the front (+x) half; the back is under the next bead.
            var back = Path()
            back.addArc(center: CGPoint(x: s / 2, y: s / 2), radius: rd, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            context.stroke(back, with: .color(ATheme.ink.opacity(0.18)), style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
            context.stroke(disc, with: .color(ATheme.rule), lineWidth: 1.5)
            if mode != .off {
                let guide = GraphicsContext.Shading.color(ATheme.link.opacity(0.35))
                var line = Path()
                line.move(to: CGPoint(x: left, y: s / 2)); line.addLine(to: CGPoint(x: left + 2 * rd, y: s / 2))
                if mode != .mirror {
                    line.move(to: CGPoint(x: s / 2, y: left)); line.addLine(to: CGPoint(x: s / 2, y: left + 2 * rd))
                }
                context.stroke(line, with: guide, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let point = CGPoint(x: (drag.location.x - left) / (2 * rd) * CGFloat(paintSize),
                                    y: (drag.location.y - left) / (2 * rd) * CGFloat(paintSize))
                if !work.stroking { begin(at: point) } else { move(to: point) }
            }
            .onEnded { _ in
                if work.stroking {
                    work.stroking = false
                    strokeDone += 1
                }
            })
    }

    /// What the canvas shows: the finish (unadjusted, full square) and the
    /// painting over its disc, with this bead's colour adjustment and opacity.
    private func composite(white: CGImage?) -> CGImage? {
        let key = "\(draft.finish):\(draft.color):\(draft.detail):\(white != nil)"
        if work.baseKey != key {
            work.baseKey = key
            work.base = WyrmStudioArt.renderBase(draft, size: 512, white: white)
        }
        guard let canvas = StudioCanvas(width: paintSize, height: paintSize) else { return nil }
        let full = CGFloat(paintSize)
        if let base = work.base { canvas.draw(base, in: CGRect(x: 0, y: 0, width: full, height: full)) }
        let rd = full / 2 * WyrmStudioArt.disc
        let left = full / 2 - rd
        if let painting = work.paint.image() {
            canvas.draw(painting, in: CGRect(x: left, y: left, width: 2 * rd, height: 2 * rd))
        }
        WyrmStudioArt.adjust(canvas, matrix: WyrmStudioArt.adjustMatrix(hue: draft.hue, saturation: draft.saturation,
                                                                         brightness: draft.brightness),
                             alpha: Double(draft.opacity))
        return canvas.image()
    }

    /// Every place a point lands with the symmetry on.
    private func mirrored(_ p: CGPoint) -> [CGPoint] {
        let n = CGFloat(paintSize)
        let h = n / 2
        switch symmetry {
        case .off: return [p]
        case .mirror: return [p, CGPoint(x: p.x, y: n - p.y)]
        case .quad: return [p, CGPoint(x: n - p.x, y: p.y), CGPoint(x: p.x, y: n - p.y), CGPoint(x: n - p.x, y: n - p.y)]
        case .radial:
            return (0..<6).map { k in
                let a = CGFloat(k) * .pi / 3
                let dx = p.x - h, dy = p.y - h
                return CGPoint(x: h + dx * cos(a) - dy * sin(a), y: h + dx * sin(a) + dy * cos(a))
            }
        }
    }

    private func begin(at first: CGPoint) {
        switch tool {
        case .picker:
            let painted = work.paint.pixel(Int(first.x.rounded()), Int(first.y.rounded()))
            brushColor = (painted >> 24) > 40 ? painted | 0xFF00_0000 : draft.color
            tool = .brush
        case .fill:
            work.snapshot()
            let c = work.paint.context
            c.saveGState()
            c.setFillColor(WyrmStudioArt.cg(brushColor))
            c.fill(CGRect(x: 0, y: 0, width: paintSize, height: paintSize))
            c.restoreGState()
            work.changed = true
            paintTick += 1
            strokeDone += 1
        case .brush, .eraser:
            work.snapshot()
            work.stroking = true
            work.last = first
            work.mid = first
            // A dot for a tap.
            for p in mirrored(first) {
                let dot = CGMutablePath()
                dot.move(to: p)
                dot.addLine(to: CGPoint(x: p.x + 0.01, y: p.y))
                stroke(dot)
            }
            work.changed = true
            paintTick += 1
        }
    }

    private func move(to now: CGPoint) {
        guard now != work.last else { return }
        let nextMid = CGPoint(x: (work.last.x + now.x) / 2, y: (work.last.y + now.y) / 2)
        // Quadratic through the midpoints: a smooth line from a jittery finger.
        let lastSet = mirrored(work.last), fromSet = mirrored(work.mid), toSet = mirrored(nextMid)
        for k in lastSet.indices {
            let path = CGMutablePath()
            path.move(to: fromSet[k])
            path.addQuadCurve(to: toSet[k], control: lastSet[k])
            stroke(path)
        }
        work.mid = nextMid
        work.last = now
        paintTick += 1
    }

    private func stroke(_ path: CGPath) {
        let erase = tool == .eraser
        let width = CGFloat(brushSize)
        if brushSoft > 0.02 {
            WyrmStudioArt.softStroke(work.paint, path: path, width: width, color: brushColor,
                                     blur: width * CGFloat(brushSoft) * 0.6 + 0.5, cap: .round, join: .round, erase: erase)
        } else {
            let c = work.paint.context
            c.saveGState()
            c.setBlendMode(erase ? .clear : .normal)
            c.setStrokeColor(WyrmStudioArt.cg(brushColor))
            c.setLineWidth(width)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.addPath(path)
            c.strokePath()
            c.restoreGState()
        }
    }

    // MARK: panels

    @ViewBuilder private var paintPanel: some View {
        HStack(spacing: 10) {
            StudioRoundButton(icon: "paintbrush.pointed", active: tool == .brush) { tool = .brush }
            StudioRoundButton(icon: studioSymbol("eraser", "scribble"), active: tool == .eraser) { tool = .eraser }
            StudioRoundButton(icon: "drop.fill", active: tool == .fill) { tool = .fill }
            StudioRoundButton(icon: "eyedropper", active: tool == .picker) { tool = .picker }
            Spacer()
            StudioRoundButton(icon: "trash") {
                work.snapshot()
                work.paint.clear()
                work.changed = true
                paintTick += 1
                strokeDone += 1
            }
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Symmetry.allCases, id: \.self) { mode in
                    StudioCapsule(label: mode.label, icon: mode == .off ? nil : "arrow.left.and.right.righttriangle.left.righttriangle.right",
                                  filled: symmetry == mode) { symmetry = mode }
                }
            }
        }
        StudioColorPicker(color: brushColor) { next in
            brushColor = next
            if tool == .eraser || tool == .picker { tool = .brush }
        }
        StudioValueSlider(title: "Brush size", value: brushSize, range: 2...80, shown: { "\(Int($0.rounded()))" }) { brushSize = $0 }
        StudioValueSlider(title: "Brush softness", value: brushSoft, range: 0...1, shown: studioPercent) { brushSoft = $0 }
    }

    @ViewBuilder private func lookPanel(white: CGImage?) -> some View {
        Text("Finish").font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.ink)
        finishGrid(white: white)
        Text("Colour").font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.ink)
        StudioColorPicker(color: draft.color) { draft.color = $0 }
        StudioValueSlider(title: "Hue", value: draft.hue, range: -180...180, shown: { "\(Int($0.rounded()))°" }) { draft.hue = $0 }
        StudioValueSlider(title: "Saturation", value: draft.saturation, range: 0...2, shown: studioPercent) { draft.saturation = $0 }
        StudioValueSlider(title: "Brightness", value: draft.brightness, range: 0...2, shown: studioPercent) { draft.brightness = $0 }
        StudioValueSlider(title: "Opacity", value: draft.opacity, range: 0.15...1, shown: studioPercent) { draft.opacity = $0 }
        StudioValueSlider(title: "Smoothness", value: draft.smoothness, range: 0...1, shown: studioPercent) { draft.smoothness = $0 }
        StudioValueSlider(title: "Detail", value: draft.detail, range: 0...1, shown: studioPercent) { draft.detail = $0 }
        HStack {
            StudioCapsule(label: "Reset look", icon: "arrow.counterclockwise", filled: false) {
                draft.hue = 0; draft.saturation = 1; draft.brightness = 1
                draft.opacity = 1; draft.smoothness = 0; draft.detail = 0.7
            }
            Spacer()
        }
    }

    /// Every finish, drawn in this bead's own colour.
    private func finishGrid(white: CGImage?) -> some View {
        let key = "\(draft.color):\(draft.detail):\(white != nil)"
        if work.finishesKey != key {
            work.finishesKey = key
            work.finishes = WyrmStudioArt.finishes.indices.map { finish in
                var bead = draft
                bead.finish = finish
                return WyrmStudioArt.renderBase(bead, size: 96, white: white)
            }
        }
        let previews = work.finishes
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(previews.indices, id: \.self) { index in
                let chosen = draft.finish == index
                VStack(spacing: 3) {
                    StudioPicture(image: previews[index])
                        .padding(4)
                        .frame(width: 58, height: 58)
                        .overlay(Circle().stroke(chosen ? ATheme.ink : ATheme.rule, lineWidth: chosen ? 2.5 : 1))
                        .contentShape(Circle())
                        .onTapGesture { draft.finish = index }
                    Text(WyrmStudioArt.finishes[index]).font(.androidWyrm(9.5, .semibold))
                        .foregroundColor(chosen ? ATheme.ink : ATheme.quiet)
                }
            }
        }
    }
}
