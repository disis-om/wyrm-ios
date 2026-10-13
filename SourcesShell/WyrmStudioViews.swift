import SwiftUI
import UIKit

/*
 * Skin Studio's shared pieces (OM, 2026-10-12/13; iOS 2026-10-13). Android
 * twins: ui/StudioWidgets.kt (capsules, sliders, the snake drawing) and
 * ui/StudioChrome.kt (the colour picker, the action sheet, the centred dialog
 * and the touch-and-hold captions), in the app's own style.
 */

/// An SF Symbol, or [fallback] on a system that does not have it.
func studioSymbol(_ name: String, _ fallback: String) -> String {
    UIImage(systemName: name) != nil ? name : fallback
}

/// An ink capsule (filled) or a paper one (outline) with an optional icon.
struct StudioCapsule: View {
    let label: String
    var icon: String? = nil
    var filled = true
    var enabled = true
    let action: () -> Void

    var body: some View {
        let fg = filled ? ATheme.onInk : ATheme.ink
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(label).font(.androidWyrm(12.5, .bold))
            }
            .foregroundColor(fg)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(filled ? ATheme.ink.opacity(enabled ? 1 : 0.35) : ATheme.card))
            .overlay(Capsule().stroke(filled ? Color.clear : ATheme.rule, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(WSPressStyle())
        .disabled(!enabled)
        .opacity(!filled && !enabled ? 0.45 : 1)
    }
}

/// A round icon button; [active] fills it with ink.
struct StudioRoundButton: View {
    let icon: String
    var active = false
    var enabled = true
    var size: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor((active ? ATheme.onInk : ATheme.ink).opacity(enabled ? 1 : 0.35))
                .frame(width: size, height: size)
                .background(Circle().fill(active ? ATheme.ink : ATheme.card))
                .overlay(Circle().stroke(active ? ATheme.ink : ATheme.rule, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(WSPressStyle())
        .disabled(!enabled)
    }
}

/// A label, its value, and the slider under them.
struct StudioValueSlider: View {
    let title: String
    let value: Float
    let range: ClosedRange<Float>
    let shown: (Float) -> String
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.ink)
                Spacer()
                Text(shown(value)).font(.androidWyrm(11.5, .bold)).foregroundColor(ATheme.quiet).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                                  set: { onChange(Float($0)) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .tint(ATheme.ink)
        }
        .padding(.vertical, 4)
    }
}

func studioPercent(_ value: Float) -> String { "\(Int((value * 100).rounded()))%" }

/// Colours a player reaches for first.
let studioSwatches: [UInt32] = [
    0xFFFF_FFFF, 0xFF11_1111, 0xFF3F_EE96, 0xFF0F_6B46, 0xFF22_E3FF, 0xFF2F_5BFF,
    0xFF8B_5CFF, 0xFFFF_4F9A, 0xFFFF_3B30, 0xFFFF_8A1F, 0xFFF2_B33D, 0xFFFF_F27A,
]

extension Color {
    /// 0x(AA)RRGGBB, opaque.
    init(studio rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }
}

private func hsvColor(_ h: Double, _ s: Double, _ v: Double) -> Color {
    Color(studio: WyrmStudioArt.fromHSV(h, s, v))
}

/// The colour picker: the chosen colour as a swatch with its hex, a row of
/// swatches, then three labelled tracks — Hue, Strength (saturation) and
/// Brightness — each a slim pill of its own range under a knob that wears the
/// colour it gives.
struct StudioColorPicker: View {
    let color: UInt32
    let onChange: (UInt32) -> Void

    var body: some View {
        let hsv = WyrmStudioArt.toHSV(color)
        let opaque = Color(studio: color)
        func emit(h: Double? = nil, s: Double? = nil, v: Double? = nil) {
            onChange(WyrmStudioArt.fromHSV(h ?? hsv.h, s ?? hsv.s, v ?? hsv.v))
        }
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(opaque).frame(width: 38, height: 38).overlay(Circle().stroke(ATheme.rule, lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    Text("COLOUR").font(.androidWyrm(9.5, .bold)).tracking(1.1).foregroundColor(ATheme.quiet)
                    Text(String(format: "#%06X", color & 0xFF_FFFF)).font(.androidWyrm(15, .bold)).foregroundColor(ATheme.ink)
                }
                Spacer()
            }
            HStack(spacing: 0) {
                ForEach(studioSwatches.indices, id: \.self) { index in
                    let swatch = studioSwatches[index]
                    let selected = (swatch & 0xFF_FFFF) == (color & 0xFF_FFFF)
                    Circle().fill(Color(studio: swatch))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2.5 : 1))
                        .contentShape(Circle())
                        .onTapGesture { onChange(swatch) }
                    if index < studioSwatches.count - 1 { Spacer(minLength: 0) }
                }
            }
            StudioColorTrack(title: "Hue", value: "\(Int(hsv.h.rounded()))°", fraction: hsv.h / 360,
                             colors: (0...6).map { hsvColor(Double($0) * 60, 1, 1) }, knob: hsvColor(hsv.h, 1, 1)) {
                emit(h: min(max($0 * 360, 0), 359.9))
            }
            StudioColorTrack(title: "Strength", value: studioPercent(Float(hsv.s)), fraction: hsv.s,
                             colors: [hsvColor(hsv.h, 0, max(hsv.v, 0.12)), hsvColor(hsv.h, 1, max(hsv.v, 0.12))],
                             knob: opaque) { emit(s: $0) }
            StudioColorTrack(title: "Brightness", value: studioPercent(Float(hsv.v)), fraction: hsv.v,
                             colors: [.black, hsvColor(hsv.h, hsv.s, 1)], knob: opaque) { emit(v: $0) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
    }
}

/// One colour track: its name and value above a slim pill; tap it, or slide sideways.
struct StudioColorTrack: View {
    let title: String
    let value: String
    let fraction: Double
    let colors: [Color]
    let knob: Color
    let onPick: (Double) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.ink)
                Spacer()
                Text(value).font(.androidWyrm(11, .bold)).foregroundColor(ATheme.quiet)
            }
            GeometryReader { proxy in
                let knobSize: CGFloat = 26
                let run = max(proxy.size.width - knobSize, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().stroke(ATheme.rule, lineWidth: 1))
                        .frame(height: 12)
                        .padding(.horizontal, 9)
                    Circle().fill(Color.white)
                        .frame(width: knobSize, height: knobSize)
                        .overlay(Circle().fill(knob).padding(4))
                        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                        .offset(x: run * CGFloat(min(max(fraction, 0), 1)))
                }
                .frame(height: knobSize)
                .contentShape(Rectangle())
                // A tap, or a slide sideways: a scroll that starts on a track still scrolls the page.
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let dx = abs(drag.translation.width), dy = abs(drag.translation.height)
                        guard dx > 3, dx >= dy else { return }
                        onPick(Double(min(max((drag.location.x - knobSize / 2) / run, 0), 1)))
                    }
                    .onEnded { drag in
                        guard abs(drag.translation.width) < 4, abs(drag.translation.height) < 4 else { return }
                        onPick(Double(min(max((drag.location.x - knobSize / 2) / run, 0), 1)))
                    })
            }
            .frame(height: 26)
        }
    }
}

/// A small quiet line: what a touch and hold does here.
struct StudioCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 2)
    }
}

/// One action in a `StudioActionSheet`.
struct StudioAction {
    let title: String
    let icon: String
    var destructive = false
    let action: () -> Void
}

/// The Studio's action sheet: a paper card that rises with a spring over a
/// dimmed screen — a grabber, the title, one row per action with its icon in
/// a round well (the destructive one in red) — and Cancel apart, as a capsule.
/// Placed last in a full-size ZStack.
struct StudioActionSheet: View {
    let title: String
    var subtitle = ""
    let actions: [StudioAction]
    let onDismiss: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.42 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Capsule().fill(ATheme.rule).frame(width: 40, height: 5)
                        .frame(maxWidth: .infinity).padding(.top, 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.androidWyrm(22, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                        }
                    }
                    .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 10)
                    ForEach(actions.indices, id: \.self) { index in
                        let item = actions[index]
                        let tint = item.destructive ? ATheme.badge : ATheme.ink
                        Button { close(then: item.action) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.icon).font(.system(size: 16, weight: .semibold)).foregroundColor(tint)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(item.destructive ? ATheme.badge.opacity(0.12) : ATheme.card))
                                    .overlay(Circle().stroke(ATheme.rule, lineWidth: 1))
                                Text(item.title).font(.androidWyrm(15.5, .semibold)).foregroundColor(tint)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(WSPressStyle())
                    }
                }
                .padding(.bottom, 8)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ATheme.paper))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
                Button { close() } label: {
                    Text("Cancel").font(.androidWyrm(16, .bold)).foregroundColor(ATheme.ink)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(Capsule().fill(ATheme.paper))
                        .overlay(Capsule().stroke(ATheme.rule, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(WSPressStyle())
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 12).padding(.bottom, 12)
            .offset(y: shown ? 0 : 520)
            .opacity(shown ? 1 : 0.3)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { shown = true }
        }
    }

    private func close(then: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.26, dampingFraction: 1)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onDismiss()
            then?()
        }
    }
}

/// A centred dialog over a dimmed page; SwiftUI keeps it above the keyboard.
/// Placed last in a full-size ZStack.
struct StudioDialog<Content: View>: View {
    let title: String
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.42 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.androidWyrm(22, .bold)).foregroundColor(ATheme.ink)
                content()
            }
            .padding(22)
            .frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(ATheme.paper))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 6)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
            .padding(24)
        }
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { shown = true } }
    }
}

/// "Name this snake": a one-line field with Cancel and Save; the keyboard comes up at once.
struct StudioRenameDialog: View {
    let start: String
    let onDone: (String?) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(start: String, onDone: @escaping (String?) -> Void) {
        self.start = start
        self.onDone = onDone
        _text = State(initialValue: start)
    }

    var body: some View {
        StudioDialog(title: "Name this snake", onDismiss: { onDone(nil) }) {
            TextField("", text: $text)
                .font(.androidWyrm(17, .semibold))
                .foregroundColor(ATheme.ink)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if !blank { onDone(text) } }
                .onChange(of: text) { value in if value.count > 28 { text = String(value.prefix(28)) } }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            HStack(spacing: 10) {
                Spacer()
                StudioCapsule(label: "Cancel", filled: false) { onDone(nil) }
                StudioCapsule(label: "Save", icon: "checkmark", enabled: !blank) { onDone(text) }
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { focused = true } }
    }

    private var blank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - the snake

/// Bead to bead along the body, in bead widths: the classic Skin preview's (and the arena's) 8/48.
let studioBeadStep: CGFloat = 8.0 / 48.0

/// Resolved pictures for one frame of a Canvas.
struct StudioImages {
    private let context: GraphicsContext
    private let source: (String) -> CGImage?
    private var resolved: [String: GraphicsContext.ResolvedImage] = [:]

    init(_ context: GraphicsContext, _ source: @escaping (String) -> CGImage?) {
        self.context = context
        self.source = source
    }

    mutating func bead(_ id: String) -> GraphicsContext.ResolvedImage? {
        if let hit = resolved[id] { return hit }
        guard let cg = source(id) else { return nil }
        let image = context.resolve(Image(decorative: cg, scale: 1))
        resolved[id] = image
        return image
    }
}

/// A Studio snake laid along any line: [place] gives bead [i]'s centre
/// (0 = the head), the beads are drawn from the tail so the head sits on top,
/// each turned to where it travels, then the eyes. A bead is 29 snake units
/// across, as in the arena. [look] is where the pupils look, in snake units.
func drawStudioSnake(_ context: GraphicsContext, skin: WyrmStudioSkin, count: Int, bead: CGFloat,
                     place: (Int) -> CGPoint, image: @escaping (String) -> CGImage?,
                     look: CGPoint = CGPoint(x: 1, y: 0), eyes: [WyrmStudioEye]? = nil,
                     shadow: Bool = true, eyesShown: Bool = true) {
    guard !skin.pattern.isEmpty, count > 0 else { return }
    func heading(_ i: Int) -> CGFloat {
        let a = place(i)
        let b: CGPoint
        if i == 0 {
            let p0 = place(0), p1 = place(1)
            b = CGPoint(x: p0.x + (p0.x - p1.x), y: p0.y + (p0.y - p1.y))
        } else {
            b = place(i - 1)
        }
        return atan2(b.y - a.y, b.x - a.x)
    }
    if shadow {
        let drop = CGPoint(x: bead * 0.04, y: bead * 0.09)
        for i in stride(from: count - 1, through: 0, by: -1) {
            let p = place(i)
            let r = bead * 0.5
            context.fill(Path(ellipseIn: CGRect(x: p.x + drop.x - r, y: p.y + drop.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.black.opacity(0.10)))
        }
    }
    var images = StudioImages(context, image)
    for i in stride(from: count - 1, through: 0, by: -1) {
        guard let picture = images.bead(skin.pattern[i % skin.pattern.count]) else { continue }
        let p = place(i)
        var c = context
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(Double(heading(i))))
        c.draw(picture, in: CGRect(x: -bead / 2, y: -bead / 2, width: bead, height: bead))
    }
    if eyesShown {
        drawStudioEyes(context, eyes: eyes ?? skin.eyes, head: place(0), angle: heading(0), unit: bead / 29, look: look)
    }
}

/// The eyes on a head at [head] turned [angle] radians; [unit] points per snake unit.
func drawStudioEyes(_ context: GraphicsContext, eyes: [WyrmStudioEye], head: CGPoint, angle: CGFloat, unit: CGFloat,
                    look: CGPoint) {
    let c = cos(angle), s = sin(angle)
    func at(_ fwd: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: head.x + (c * fwd - s * side) * unit, y: head.y + (s * fwd + c * side) * unit)
    }
    func put(_ cg: CGImage?, _ centre: CGPoint, _ d: CGFloat) {
        guard let cg else { return }
        var g = context
        g.translateBy(x: centre.x, y: centre.y)
        g.rotate(by: .radians(Double(angle)))
        g.draw(Image(decorative: cg, scale: 1), in: CGRect(x: -d / 2, y: -d / 2, width: d, height: d))
    }
    for eye in eyes {
        let centre = at(CGFloat(eye.fwd), CGFloat(eye.side))
        if eye.white > 0 { put(WyrmStudioArt.whiteImage(eye), centre, CGFloat(eye.white) * 2 * unit) }
        if eye.pupil > 0 {
            let lx = look.x * CGFloat(eye.look), ly = look.y * CGFloat(eye.look)
            put(WyrmStudioArt.pupilImage(eye), at(CGFloat(eye.fwd) + 0.5 + lx, CGFloat(eye.side) + ly), CGFloat(eye.pupil) * 2 * unit)
        }
    }
}

/// A short straight Studio snake for cards and tiles, head on the right.
func drawStudioStrip(_ context: GraphicsContext, size: CGSize, skin: WyrmStudioSkin,
                     image: @escaping (String) -> CGImage?, beads: Int = 34) {
    let bead = size.height * 0.7
    let step = bead * studioBeadStep
    let span = bead + step * CGFloat(beads - 1)
    let scale = span > size.width ? size.width / span : 1
    let b = bead * scale
    let st = step * scale
    let y = size.height / 2
    let headX = (size.width + (b + st * CGFloat(beads - 1))) / 2 - b / 2
    drawStudioSnake(context, skin: skin, count: beads, bead: b,
                    place: { i in CGPoint(x: headX - CGFloat(i) * st, y: y + sin(CGFloat(i) * 0.25) * b * 0.06) },
                    image: image, shadow: false)
}

/// A picture laid into a square, or nothing.
struct StudioPicture: View {
    let image: CGImage?
    var body: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
        } else {
            Color.clear
        }
    }
}

/// A clock for the Studio's animated canvases: time runs faster while boosted.
final class StudioClock {
    private var last: Date?
    private(set) var time: CGFloat = 0
    var boost: CGFloat = 0

    /// Advances to [now]; returns the running time.
    func advance(to now: Date) -> CGFloat {
        if let last {
            let dt = min(CGFloat(now.timeIntervalSince(last)), 0.05)
            if dt > 0 {
                time += dt * (1 + boost * 1.6)
                boost = max(0, boost - dt * 0.9)
            }
        }
        last = now
        return time
    }
}
