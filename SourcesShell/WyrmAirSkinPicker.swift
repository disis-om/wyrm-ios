import SwiftUI

/// The slither.io Android (AIR) client's Build-a-Slither colour model, ported
/// from `gaim.Main` (`buildColorWheel`, the two pointer `touchMove`s and
/// `setSkin`). Units are the AIR wheel's own: radius 128, bezel 18 wide,
/// bezel pointer on radius 151.
enum WyrmAirSkin {
    /// A wheel bead keeps its exact RGB and names its AIR texture in the
    /// alpha byte; the engine and the preview both read it back from there.
    static let plainMarker: UInt32 = 0xFE00_0000   // nsk 0, `kmc_ts[9][0]`
    static let rimMarker: UInt32 = 0xFD00_0000     // nsk 1, `kmc_ts[29][0]`

    static func marker(kind: Int) -> UInt32 { kind == 0 ? plainMarker : rimMarker }

    static func kind(of rgba: UInt32) -> Int? {
        switch rgba >> 24 {
        case 0xFE: return 0
        case 0xFD: return 1
        default: return nil
        }
    }

    static let wheelRadius = 128.0
    static let bezelWidth = 18.0
    static let bezelPointerRadius = 151.0
    /// `_loc11_ = _loc9_ - _loc10_ + 3`: how far the wheel pointer may go.
    static let pointerLimit = 128.0 - 24.0 + 3.0

    /// `hypah.mod.Mod.closestMod`, including its AS3 remainder semantics.
    static func closestMod(_ value: Double, _ target: Double, _ period: Double) -> Double {
        var base: Double
        if value < 0 {
            base = period - (period - value).truncatingRemainder(dividingBy: period)
            if base == period { base = 0 }
        } else {
            base = value.truncatingRemainder(dividingBy: period)
        }
        var best = base > target ? base - target : target - base
        var other = base - period > target ? base - period - target : target - (base - period)
        if other < best {
            best = other
            other = base + period > target ? base + period - target : target - (base + period)
            return other < best ? base + period : base - period
        }
        other = base + period > target ? base + period - target : target - (base + period)
        return other < best ? base + period : base
    }

    /// The unrounded wheel colour under the pointer (`_loc15_.._loc17_`).
    static func pure(x: Double, y: Double) -> (Double, Double, Double) {
        let inner = 16.0, outer = 24.0, rad = 128.0
        var d = (x * x + y * y).squareRoot() - inner
        if d < 0 { d = 0 }
        if d > rad - outer - inner { d = rad - outer - inner }
        let saturation = min(1, max(0, d) / (rad - outer - inner))
        let angle = atan2(y, x)
        let twoPi = Double.pi * 2, k1 = Double.pi * 2 / 3, k2 = Double.pi * 4 / 3
        let channels = [
            (1 - abs(closestMod(angle, 0, twoPi)) / .pi - 1.0 / 3) * 3,
            (1 - abs(closestMod(angle, k1, twoPi) - k1) / .pi - 1.0 / 3) * 3,
            (1 - abs(closestMod(angle, k2, twoPi) - k2) / .pi - 1.0 / 3) * 3,
        ].map { 128 + (256 * min(1, max(0, $0)) - 128) * saturation }
        return (channels[0], channels[1], channels[2])
    }

    /// `bsk_br` for a bezel angle: top half lightens to 1, bottom darkens to -0.5.
    static func brightness(angle: Double) -> Double {
        var amount: Double
        if angle <= 0 {
            amount = abs(angle + .pi / 2) / (.pi / 2)
            amount = max(0, min(1, 1.1 * (1 - amount)))
            return amount
        }
        amount = abs(angle - .pi / 2) / (.pi / 2)
        amount = max(0, min(1, 1.1 * (1 - amount)))
        return max(-0.5, -amount * 0.5)
    }

    /// Applies `bsk_br` and rounds, as both pointers do.
    static func shaded(_ colour: (Double, Double, Double), brightness br: Double) -> UInt32 {
        func channel(_ value: Double) -> UInt32 {
            let v = br >= 0 ? value + (255 - value) * br : value + value * br
            return UInt32(max(0, min(255, (v + 0.5).rounded(.down))))  // Math.round
        }
        return channel(colour.0) << 16 | channel(colour.1) << 8 | channel(colour.2)
    }

    /// `Math.round` then clamp: the stored `bsk_orr/ogg/obb`.
    static func rounded(_ colour: (Double, Double, Double)) -> (Double, Double, Double) {
        func r(_ v: Double) -> Double { max(0, min(255, (v + 0.5).rounded(.down))) }
        return (r(colour.0), r(colour.1), r(colour.2))
    }

    /// `setSkin`: the colour a bead is drawn with once it is on the body.
    static func bodyTint(_ rgba: UInt32) -> UInt32 {
        var c = [Double((rgba >> 16) & 0xff), Double((rgba >> 8) & 0xff), Double(rgba & 0xff)]
        let lo = c.min()!, hi = c.max()!
        let mid = c.reduce(0, +) - lo - hi
        if mid + hi < 255 {
            let lift = 1 + (255 - (mid + hi)) / 2
            c = c.map { min(255, $0 + lift) }
        }
        return UInt32(c[0]) << 16 | UInt32(c[1]) << 8 | UInt32(c[2])
    }

    /// The engine's own colour-group palette (`game_data.c` cg_colors), used
    /// to give each wheel bead the arena colour other clients will see.
    private static let palette: [(Double, Double, Double)] = [
        (0.75, 0.5, 0.99609375), (0.5625, 0.59765625, 0.99609375), (0.5, 0.8125, 0.8125),
        (0.5, 0.99609375, 0.5), (0.9296875, 0.9296875, 0.4375), (0.99609375, 0.625, 0.375),
        (0.99609375, 0.5625, 0.5625), (0.99609375, 0.25, 0.25), (0.875, 0.1875, 0.875),
        (0.99609375, 0.99609375, 0.99609375), (0.5625, 0.59765625, 0.99609375), (0.3125, 0.3125, 0.3125),
        (0.99609375, 0.75, 0.3125), (0.15625, 0.53125, 0.375), (0.390625, 0.45703125, 0.99609375),
        (0.46875, 0.5234375, 0.99609375), (0.28125, 0.328125, 0.99609375), (0.625, 0.3125, 0.99609375),
        (0.99609375, 0.875, 0.25), (0.21875, 0.265625, 0.99609375), (0.21875, 0.265625, 0.99609375),
        (0.3046875, 0.13671875, 0.75), (0.99609375, 0.3359375, 0.03515625), (0.39453125, 0.78125, 0.90625),
        (0.5, 0.515625, 0.5625), (0.234375, 0.75, 0.28125), (0, 0.99609375, 0.32421875),
        (0.84765625, 0.26953125, 0.26953125), (0.99609375, 0.25, 0.25), (0.5625, 0.5625, 0.5625),
        (0.125, 0.125, 0.9375), (0.9375, 0.125, 0.125), (0.9375, 0.9375, 0.125),
        (0.9375, 0.5625, 0.125), (0.9375, 0.125, 0.9375), (0.125, 0.9375, 0.125),
        (0.15625, 0.234375, 0.67578125), (0.40625, 0.5, 0.99609375), (0, 0, 0.4375),
        (0.40625, 0.15625, 0.6640625), (1, 1, 1), (0.5, 0.5, 0.99609375),
    ]

    /// Android Wyrm's `nearestGroup`: green-weighted, dead groups excluded.
    static func nearestGroup(_ rgb: UInt32) -> Int {
        let r = Double((rgb >> 16) & 0xff) / 255, g = Double((rgb >> 8) & 0xff) / 255, b = Double(rgb & 0xff) / 255
        var best = WyrmSkinCatalog.validGroups.first ?? 0
        var bestDistance = Double.greatestFiniteMagnitude
        for group in WyrmSkinCatalog.validGroups where palette.indices.contains(group) {
            let c = palette[group]
            let dr = (c.0 - r) * 0.30, dg = (c.1 - g) * 0.59, db = (c.2 - b) * 0.11
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance { bestDistance = distance; best = group }
        }
        return best
    }
}

extension Color {
    init(airRGB rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255)
    }
}

/// Liquid Glass on iOS 26, a material lens before it.
private struct WyrmAirGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = true

    @ViewBuilder
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }

#if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glass: Glass {
        let base = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        return base.interactive(interactive)
    }
#endif

    private func fallback(_ content: Content) -> some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(tint ?? .clear).opacity(0.55))
            .overlay(shape.stroke(Color.white.opacity(0.55), lineWidth: 0.8))
            .overlay(shape.stroke(ATheme.ink.opacity(0.1), lineWidth: 0.5))
    }
}

extension View {
    fileprivate func airGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(WyrmAirGlass(shape: shape, tint: tint, interactive: interactive))
    }
}

/// The pattern toggle: a colour-wheel glyph while the beads are showing,
/// the bead grid glyph while the wheel is.
struct WyrmAirWheelToggle: View {
    let showingWheel: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if showingWheel {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ATheme.ink)
                } else {
                    Circle()
                        .fill(AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                                              center: .center))
                        .overlay(Circle().fill(RadialGradient(gradient: Gradient(colors: [Color(white: 0.5), Color(white: 0.5).opacity(0)]),
                                                              center: .center, startRadius: 0, endRadius: 7)))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5).frame(width: 8, height: 8))
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .airGlass(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingWheel ? "Show bead palette" : "Show colour wheel")
    }
}

/// The AIR colour wheel, its two bead buttons and their live colour.
///
/// Dragging only touches this view's own `@State`; the persisted values are
/// written once, when the finger lifts. Writing `@AppStorage` every frame
/// re-rendered the whole Skin page (and its 256-bead preview) per touch
/// sample, and live Liquid Glass on the moving knobs and on a bezel whose
/// tint changes every frame re-sampled the backdrop each frame: together
/// they made the picker flicker and lag (Build 56 device report). The
/// moving parts are therefore glass-styled but drawn as plain layers.
struct WyrmAirWheelPanel: View {
    let wheel: CGImage?
    let beads: [Int: CGImage]
    @Binding var storedX: Double
    @Binding var storedY: Double
    @Binding var storedAngle: Double
    @Binding var storedRGB: Int
    let onAdd: (_ kind: Int, _ rgb: UInt32) -> Void

    @State private var pointerX: Double
    @State private var pointerY: Double
    @State private var bezelAngle: Double
    @State private var rgb: UInt32
    @State private var drag: WheelDrag?

    /// A pointer drag remembers where the pointer started; the finger's
    /// translation is added to it.
    private enum WheelDrag { case pointer(x: Double, y: Double), bezel }

    init(wheel: CGImage?, beads: [Int: CGImage],
         storedX: Binding<Double>, storedY: Binding<Double>,
         storedAngle: Binding<Double>, storedRGB: Binding<Int>,
         onAdd: @escaping (_ kind: Int, _ rgb: UInt32) -> Void) {
        self.wheel = wheel
        self.beads = beads
        _storedX = storedX
        _storedY = storedY
        _storedAngle = storedAngle
        _storedRGB = storedRGB
        self.onAdd = onAdd
        _pointerX = State(initialValue: storedX.wrappedValue)
        _pointerY = State(initialValue: storedY.wrappedValue)
        _bezelAngle = State(initialValue: storedAngle.wrappedValue)
        _rgb = State(initialValue: UInt32(truncatingIfNeeded: storedRGB.wrappedValue) & 0xFF_FFFF)
    }

    private var pureColour: (Double, Double, Double) { WyrmAirSkin.pure(x: pointerX, y: pointerY) }
    private var brightness: Double { WyrmAirSkin.brightness(angle: bezelAngle) }

    var body: some View {
        VStack(spacing: 18) {
            wheelView
                .frame(maxWidth: 300)
                .padding(.horizontal, 20)
            HStack(spacing: 22) {
                ForEach(0..<2, id: \.self) { kind in
                    WyrmAirBeadButton(image: beads[kind], rgb: rgb,
                                      label: kind == 0 ? "Add plain bead" : "Add rim bead") {
                        onAdd(kind, rgb)
                    }
                }
            }
        }
    }

    private var wheelView: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / (2 * 172)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let rounded = WyrmAirSkin.rounded(pureColour)
            let pure = UInt32(rounded.0) << 16 | UInt32(rounded.1) << 8 | UInt32(rounded.2)
            let bezelDiameter = 2 * (WyrmAirSkin.wheelRadius + WyrmAirSkin.bezelWidth) * unit
            ZStack {
                bezel(tint: Color(airRGB: pure), diameter: bezelDiameter)
                    .position(centre)
                Group {
                    if let wheel {
                        Image(decorative: wheel, scale: 1).resizable().interpolation(.high)
                    } else {
                        Circle().fill(Color.gray)
                    }
                }
                .frame(width: 256 * unit, height: 256 * unit)
                .position(centre)
                // `bsk_cwt_ii`: white or black over the wheel, alpha |bsk_br|.
                Circle()
                    .fill(brightness > 0 ? Color.white : Color.black)
                    .opacity(abs(brightness))
                    .frame(width: 2 * 128 * 1.005 * unit, height: 2 * 128 * 1.005 * unit)
                    .position(centre)
                knob(diameter: 46 * unit)
                    .position(x: centre.x + pointerX * unit, y: centre.y + pointerY * unit)
                knob(diameter: 42 * unit)
                    .position(x: centre.x + cos(bezelAngle) * WyrmAirSkin.bezelPointerRadius * unit,
                              y: centre.y + sin(bezelAngle) * WyrmAirSkin.bezelPointerRadius * unit)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // One gesture for the whole control, so a finger never has to
            // land exactly on a small knob, and it wins over the scroll view.
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in dragChanged(value, centre: centre, unit: unit) }
                .onEnded { _ in dragEnded() })
            .accessibilityElement()
            .accessibilityLabel("Colour wheel")
            .accessibilityValue(String(format: "#%06X", rgb))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Glass-styled, but rendered as plain layers: a tinted body, a light
    /// top and a shaded bottom (AIR's `cwbo` highlight and shade) and a rim.
    private func bezel(tint: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(tint.opacity(0.88))
            .overlay(Circle().fill(LinearGradient(gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.42), location: 0),
                .init(color: Color.white.opacity(0.06), location: 0.46),
                .init(color: Color.black.opacity(0.16), location: 1),
            ]), startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().stroke(LinearGradient(gradient: Gradient(colors: [
                Color.white.opacity(0.85), Color.white.opacity(0.18),
            ]), startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
    }

    private func knob(diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient(gradient: Gradient(colors: [
                Color.white.opacity(0.62), Color.white.opacity(0.30),
            ]), startPoint: .top, endPoint: .bottom))
            Circle().stroke(LinearGradient(gradient: Gradient(colors: [
                Color.white.opacity(0.98), Color.white.opacity(0.35),
            ]), startPoint: .top, endPoint: .bottom), lineWidth: 1.6)
            Circle()
                .fill(Color(airRGB: rgb))
                .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: 1.5))
                .padding(diameter * 0.17)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }

    /// Where the finger lands decides what it drives. On the hue pointer it
    /// moves the pointer by the drag, as AIR does; elsewhere on the wheel the
    /// pointer starts under the finger. On the bezel the knob follows the
    /// finger's angle. Colour follows AIR's `touchMove` maths.
    private func dragChanged(_ value: DragGesture.Value, centre: CGPoint, unit: CGFloat) {
        if drag == nil {
            let sx = Double((value.startLocation.x - centre.x) / unit)
            let sy = Double((value.startLocation.y - centre.y) / unit)
            if hypot(sx - pointerX, sy - pointerY) <= 30 {
                drag = .pointer(x: pointerX, y: pointerY)
            } else if (sx * sx + sy * sy).squareRoot() <= WyrmAirSkin.wheelRadius {
                drag = .pointer(x: sx, y: sy)
            } else {
                drag = .bezel
            }
        }
        switch drag {
        case .pointer(let originX, let originY):
            var x = originX + Double(value.translation.width / unit)
            var y = originY + Double(value.translation.height / unit)
            let d = (x * x + y * y).squareRoot()
            if d > WyrmAirSkin.pointerLimit {
                x *= WyrmAirSkin.pointerLimit / d
                y *= WyrmAirSkin.pointerLimit / d
            }
            pointerX = x
            pointerY = y
            rgb = WyrmAirSkin.shaded(WyrmAirSkin.pure(x: x, y: y), brightness: brightness)
        case .bezel:
            let x = Double((value.location.x - centre.x) / unit)
            let y = Double((value.location.y - centre.y) / unit)
            bezelAngle = atan2(y, x)
            rgb = WyrmAirSkin.shaded(WyrmAirSkin.rounded(pureColour),
                                     brightness: WyrmAirSkin.brightness(angle: bezelAngle))
        case nil:
            break
        }
    }

    private func dragEnded() {
        drag = nil
        storedX = pointerX
        storedY = pointerY
        storedAngle = bezelAngle
        storedRGB = Int(rgb)
    }
}

/// One of the two AIR bead buttons: its texture tinted with the picked colour,
/// turned half a revolution as AIR shows it. The button itself never moves,
/// so its Liquid Glass backing does not re-sample every frame.
struct WyrmAirBeadButton: View {
    let image: CGImage?
    let rgb: UInt32
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high)
                        .colorMultiply(Color(airRGB: rgb))
                        .rotationEffect(.degrees(180))
                } else {
                    Color.clear
                }
            }
            .padding(9)
            .frame(width: 66, height: 66)
            .background(Circle().fill(Color.clear).airGlass(Circle(), interactive: false))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
