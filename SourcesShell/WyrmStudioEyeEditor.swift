import SwiftUI
import UIKit

/*
 * The eye editor (OM, 2026-10-12; iOS 2026-10-13). Android twin:
 * ui/StudioEyeEditor.kt. The head, big, with its eyes. Drag an eye anywhere;
 * tap one to style it; hold one for Delete this eye / Delete every eye /
 * Duplicate / Mirror. Each eye has its own white (the Sclera: shape and
 * colour), its own pupil (16 shapes, any colour), sizes and how far it
 * looks. "Pair" moves and styles an eye's mirror twin with it. Nothing is
 * kept until Done.
 */

/// The finger on the head: which eye, and whether it moved or is being held.
private final class EyeTouch {
    var active = false
    var hit = -1
    var start: CGPoint = .zero
    var last: CGPoint = .zero
    var dragging = false
    var held = false
    var generation = 0
}

struct StudioEyeEditor: View {
    let skin: WyrmStudioSkin
    let image: (String) -> CGImage?
    let onDone: () -> Void

    @State private var eyes: [WyrmStudioEye]
    @State private var selected: Int
    @State private var paired = true
    @State private var menuFor = -1
    @State private var clock = StudioClock()
    @State private var touch = EyeTouch()

    init(skin: WyrmStudioSkin, image: @escaping (String) -> CGImage?, onDone: @escaping () -> Void) {
        self.skin = skin
        self.image = image
        self.onDone = onDone
        _eyes = State(initialValue: skin.eyes)
        _selected = State(initialValue: skin.eyes.isEmpty ? -1 : 0)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                head
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let eye = eyes[safeIndex: selected] {
                            styling(eye)
                        } else {
                            Spacer().frame(height: 18)
                            Text(eyes.isEmpty ? "No eyes. Add one, or keep the snake blind." : "Tap an eye to style it.")
                                .font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
                        }
                        Spacer().frame(height: 60)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background(ATheme.paper.ignoresSafeArea())

            if let menuEye = eyes[safeIndex: menuFor] {
                let target = menuFor
                StudioActionSheet(title: "Eye \(target + 1)", actions: menuActions(menuEye, target)) { menuFor = -1 }
                    .zIndex(5)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            StudioRoundButton(icon: "xmark", size: 38) { onDone() }
            VStack(alignment: .leading, spacing: 1) {
                Text("EYES · \(eyes.count) / \(WyrmStudio.maxEyes)").font(.androidWyrm(9.5, .bold)).tracking(1.2).foregroundColor(ATheme.quiet)
                Text(skin.name).font(.androidWyrm(22, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
            StudioCapsule(label: "Done", icon: "checkmark") {
                WyrmStudio.shared.setEyes(skin.id, eyes)
                onDone()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: the head

    private var head: some View {
        let skin = self.skin
        let picture = self.image
        let clock = self.clock
        let shownEyes = eyes
        let ringed = eyes[safeIndex: selected]
        return GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let time = clock.advance(to: timeline.date)
                        let bead = size.height * 0.62
                        let unit = bead / 29
                        let headPoint = CGPoint(x: size.width * 0.58, y: size.height * 0.5)
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                            Gradient(colors: [ATheme.ink.opacity(0.05), .clear]), center: headPoint,
                            startRadius: 0, endRadius: size.width * 0.6))
                        let look = CGPoint(x: 1.2 + 0.8 * cos(time * 0.8), y: 1.6 * sin(time * 0.6))
                        drawStudioSnake(context, skin: skin, count: 16, bead: bead,
                                        place: { i in CGPoint(x: headPoint.x - CGFloat(i) * bead * studioBeadStep, y: headPoint.y) },
                                        image: picture, look: look, eyes: shownEyes, shadow: false)
                        // The chosen eye, ringed.
                        if let e = ringed {
                            let c = CGPoint(x: headPoint.x + CGFloat(e.fwd) * unit, y: headPoint.y + CGFloat(e.side) * unit)
                            let r = CGFloat(max(e.white, e.pupil)) * unit + 6
                            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                           with: .color(ATheme.link), lineWidth: 3)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in onTouch(drag.location, size: size) }
                    .onEnded { _ in touch.active = false; touch.generation += 1 })

                Text("Drag an eye to move it. Touch and hold an eye to delete, copy or mirror it.")
                    .font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14).padding(.top, 12).padding(.trailing, 120)
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    StudioCapsule(label: "Add eye", icon: "plus", enabled: eyes.count < WyrmStudio.maxEyes) { addEye() }
                    StudioCapsule(label: "Pair", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                                  filled: paired) { paired.toggle() }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: 290)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ATheme.card))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func onTouch(_ location: CGPoint, size: CGSize) {
        let bead = size.height * 0.62
        let unit = bead / 29
        let headPoint = CGPoint(x: size.width * 0.58, y: size.height * 0.5)
        if !touch.active {
            touch.active = true
            touch.dragging = false
            touch.held = false
            touch.start = location
            touch.last = location
            touch.generation += 1
            func centre(_ e: WyrmStudioEye) -> CGPoint {
                CGPoint(x: headPoint.x + CGFloat(e.fwd) * unit, y: headPoint.y + CGFloat(e.side) * unit)
            }
            func distance(_ i: Int) -> CGFloat { hypot(centre(eyes[i]).x - location.x, centre(eyes[i]).y - location.y) }
            let nearest = eyes.indices.min { distance($0) < distance($1) }
            guard let hit = nearest, distance(hit) <= max(CGFloat(eyes[hit].white) * unit, 22) else {
                touch.hit = -1
                selected = -1
                return
            }
            touch.hit = hit
            selected = hit
            // Held still for 450 ms: the eye's menu.
            let mine = touch.generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard touch.active, touch.generation == mine, !touch.dragging, touch.hit == hit else { return }
                touch.held = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                menuFor = hit
            }
            return
        }
        guard touch.hit >= 0, !touch.held else { return }
        if !touch.dragging {
            guard hypot(location.x - touch.start.x, location.y - touch.start.y) > 8 else { return }
            touch.dragging = true
        }
        let delta = CGPoint(x: location.x - touch.last.x, y: location.y - touch.last.y)
        touch.last = location
        edit(touch.hit) { e in
            var next = e
            next.fwd = min(max(e.fwd + Float(delta.x / unit), -20), 20)
            next.side = min(max(e.side + Float(delta.y / unit), -20), 20)
            return next
        }
    }

    private func addEye() {
        let style = eyes[safeIndex: selected] ?? eyes.last ?? WyrmStudioEye()
        let spots: [Float] = [0, 9, -9, 4.5, -4.5, 13, -13, 2]
        let spot = spots.first { s in !eyes.contains { abs($0.side - s) < 2 && abs($0.fwd - 6) < 2 } } ?? 0
        var next = style
        next.fwd = 6
        next.side = spot
        eyes.append(next)
        selected = eyes.count - 1
    }

    /// The eye mirrored from [index] across the head, if there is one.
    private func twin(_ list: [WyrmStudioEye], _ index: Int) -> Int {
        guard let e = list[safeIndex: index], abs(e.side) >= 0.6 else { return -1 }
        var best = -1
        var bestD: Float = 2.2
        for (i, o) in list.enumerated() where i != index {
            let d = hypot(o.fwd - e.fwd, o.side + e.side)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    /// Changes eye [index] (and its twin, mirrored, when paired).
    private func edit(_ index: Int, _ change: (WyrmStudioEye) -> WyrmStudioEye) {
        var list = eyes
        guard let e = list[safeIndex: index] else { return }
        let t = paired ? twin(list, index) : -1
        let next = change(e)
        list[index] = next
        if t >= 0 {
            let other = list[t]
            var mirrored = next
            mirrored.side = -next.side
            // Position mirrors; the twin keeps nothing of its own but its side.
            if next.fwd == e.fwd && next.side == e.side {
                mirrored.fwd = other.fwd
                mirrored.side = other.side
            }
            list[t] = mirrored
        }
        eyes = list
    }

    private func styleAll(_ from: WyrmStudioEye) {
        eyes = eyes.map { e in
            var next = e
            next.white = from.white; next.pupil = from.pupil; next.look = from.look
            next.whiteColor = from.whiteColor; next.pupilColor = from.pupilColor
            next.whiteShape = from.whiteShape; next.pupilShape = from.pupilShape
            return next
        }
    }

    private func menuActions(_ menuEye: WyrmStudioEye, _ target: Int) -> [StudioAction] {
        var actions = [StudioAction(title: "Delete this eye", icon: "trash", destructive: true) {
            eyes.remove(at: target)
            selected = -1
        }]
        if eyes.count > 1 {
            actions.append(StudioAction(title: "Delete every eye", icon: "eye.slash", destructive: true) {
                eyes = []
                selected = -1
            })
        }
        if eyes.count < WyrmStudio.maxEyes {
            actions.append(StudioAction(title: "Duplicate", icon: "doc.on.doc") {
                var copy = menuEye
                copy.fwd = min(max(menuEye.fwd - 3, -20), 20)
                eyes.append(copy)
                selected = eyes.count - 1
            })
        }
        if eyes.count < WyrmStudio.maxEyes && abs(menuEye.side) > 0.6 && twin(eyes, target) < 0 {
            actions.append(StudioAction(title: "Mirror to the other side",
                                        icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                var copy = menuEye
                copy.side = -menuEye.side
                eyes.append(copy)
                selected = eyes.count - 1
            })
        }
        return actions
    }

    // MARK: styling

    @ViewBuilder private func styling(_ eye: WyrmStudioEye) -> some View {
        Spacer().frame(height: 16)
        sectionTitle("Pupil")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WyrmStudioArt.pupilShapes.indices, id: \.self) { index in
                    let chosen = eye.pupilShape == index
                    VStack(spacing: 3) {
                        StudioPicture(image: WyrmStudioArt.pupilImage(Self.withPupil(eye, index)))
                            .padding(9)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color(studio: eye.whiteColor)))
                            .overlay(Circle().stroke(chosen ? ATheme.ink : ATheme.rule, lineWidth: chosen ? 2.5 : 1))
                            .contentShape(Circle())
                            .onTapGesture { edit(selected) { var e = $0; e.pupilShape = index; return e } }
                        Text(WyrmStudioArt.pupilShapes[index]).font(.androidWyrm(9.5, .semibold))
                            .foregroundColor(chosen ? ATheme.ink : ATheme.quiet)
                    }
                }
            }
        }
        Spacer().frame(height: 10)
        StudioColorPicker(color: eye.pupilColor) { c in edit(selected) { var e = $0; e.pupilColor = c; return e } }
        StudioValueSlider(title: "Pupil size", value: eye.pupil, range: 0...12, shown: { String(format: "%.1f", $0) }) { v in
            edit(selected) { var e = $0; e.pupil = v; return e }
        }
        StudioValueSlider(title: "Looks around", value: eye.look, range: 0...3, shown: studioPercent) { v in
            edit(selected) { var e = $0; e.look = v; return e }
        }
        Spacer().frame(height: 16)
        sectionTitle("Sclera")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WyrmStudioArt.whiteShapes.indices, id: \.self) { index in
                    StudioCapsule(label: WyrmStudioArt.whiteShapes[index], filled: eye.whiteShape == index) {
                        edit(selected) { var e = $0; e.whiteShape = index; return e }
                    }
                }
            }
        }
        Spacer().frame(height: 10)
        StudioColorPicker(color: eye.whiteColor) { c in edit(selected) { var e = $0; e.whiteColor = c; return e } }
        StudioValueSlider(title: "Sclera size", value: eye.white, range: 0...14, shown: { String(format: "%.1f", $0) }) { v in
            edit(selected) { var e = $0; e.white = v; return e }
        }
        Spacer().frame(height: 14)
        HStack {
            StudioCapsule(label: "Style every eye like this", icon: "wand.and.stars", filled: false) { styleAll(eye) }
            Spacer()
        }
    }

    private static func withPupil(_ eye: WyrmStudioEye, _ shape: Int) -> WyrmStudioEye {
        var next = eye
        next.pupilShape = shape
        return next
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.androidWyrm(10.5, .bold)).tracking(1.1).foregroundColor(ATheme.quiet)
            .padding(.bottom, 8)
    }
}
