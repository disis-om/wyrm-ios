import SwiftUI
import ImageIO

/// Wyrm skins (OM, 2026-10-13): creatures and strip looks the engine draws
/// over a snake instead of its beads (game/wyrm_skins.c). The number is what
/// travels; never renumber, only append. Pictures: Resources/WyrmSkins.webp
/// (Wyrm Android tools/wyrm-skins/make.py), one cell per skin in `all`'s order.
///
/// The worn skin is the engine setting `skin.wyrm` (0 = none), so it is saved
/// with the engine's settings and goes to the account (shared key `wyrmSkin`).
/// While one is worn the arena gets no tag and no accessory: the skin's number
/// rides where a tag would. Same list as Android's WyrmSkins.kt.
struct WyrmSkinItem: Identifiable, Equatable {
    let number: Int
    let name: String
    var id: Int { number }
    var strip: Bool { number > 100 }
}

enum WyrmSkins {
    static let sheetColumns = 6
    static let sheetRows = 7
    static let setting = "skin.wyrm"
    /// The moving preview: frames in one sheet per skin, Resources/WyrmSkinsLive/<n>.webp
    /// (Wyrm Android tools/wyrm-skins/make.py --live).
    static let liveFrames = 32
    static let liveColumns = 8
    static let liveRows = 4
    static let liveSeconds = 4.0

    /// A skin's frames, cut from its sheet (kept for the last few skins shown).
    @MainActor private static var liveCache: [Int: [CGImage]] = [:]
    @MainActor static func liveSheetFrames(_ number: Int) -> [CGImage] {
        if let cached = liveCache[number] { return cached }
        guard let url = Bundle.main.url(forResource: "\(number)", withExtension: "webp", subdirectory: "WyrmSkinsLive"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let cw = sheet.width / liveColumns, ch = sheet.height / liveRows
        let frames: [CGImage] = (0..<liveFrames).compactMap { f in
            sheet.cropping(to: CGRect(x: (f % liveColumns) * cw, y: (f / liveColumns) * ch, width: cw, height: ch))
        }
        if liveCache.count > 3 { liveCache.removeAll() }
        liveCache[number] = frames
        return frames
    }

    static let creatures: [WyrmSkinItem] = [
        .init(number: 1, name: "Centipede"), .init(number: 2, name: "Dragon"), .init(number: 3, name: "Skeleton"),
        .init(number: 4, name: "Chinese Dragon"), .init(number: 5, name: "Electric Eel"), .init(number: 6, name: "Train"),
        .init(number: 7, name: "Robot Snake"), .init(number: 8, name: "Phoenix"), .init(number: 9, name: "Ice Serpent"),
        .init(number: 10, name: "Caterpillar"), .init(number: 11, name: "Zombie Snake"), .init(number: 12, name: "Cyclops"),
        .init(number: 13, name: "Evil Eye"), .init(number: 14, name: "Argus"), .init(number: 15, name: "Spider Eyes"),
        .init(number: 16, name: "Mega Eye"), .init(number: 17, name: "Bean"), .init(number: 18, name: "Owl"),
        .init(number: 19, name: "Third Eye"), .init(number: 20, name: "Snail"), .init(number: 21, name: "Mantis"),
        .init(number: 22, name: "Eyeball Chain"), .init(number: 23, name: "Jelly"),
    ]
    static let strips: [WyrmSkinItem] = [
        .init(number: 101, name: "Strip"), .init(number: 102, name: "Neon Strip"), .init(number: 103, name: "Glass Strip"),
        .init(number: 104, name: "Outline Strip"), .init(number: 105, name: "Pixel Strip"), .init(number: 106, name: "Rainbow Strip"),
        .init(number: 107, name: "Candy Strip"), .init(number: 108, name: "Tube Strip"), .init(number: 109, name: "Chrome Strip"),
        .init(number: 110, name: "Lava Strip"), .init(number: 111, name: "Ice Strip"), .init(number: 112, name: "Galaxy Strip"),
        .init(number: 113, name: "Ghost Strip"), .init(number: 114, name: "Bead Strip"), .init(number: 115, name: "Zigzag Strip"),
    ]
    /// The sheet's order.
    static let all = creatures + strips

    static func item(_ number: Int) -> WyrmSkinItem? { all.first { $0.number == number } }

    /// Each skin's picture, cut from the sheet, by number.
    static func pictures(_ sheet: CGImage) -> [Int: CGImage] {
        let cw = sheet.width / sheetColumns, ch = sheet.height / sheetRows
        var out: [Int: CGImage] = [:]
        for (cell, skin) in all.enumerated() {
            let rect = CGRect(x: (cell % sheetColumns) * cw, y: (cell / sheetColumns) * ch, width: cw, height: ch)
            if let part = sheet.cropping(to: rect) { out[skin.number] = part }
        }
        return out
    }
}

/// The worn skin on the Skin page's preview, live (OM, 2026-10-25): the arena's own skin
/// drawing (game/wyrm_skin_preview.c) draws a snake that swims, turns and now and then boosts,
/// every frame, for as long as the page is open. It was a 32-frame picture loop, and the loop
/// was cut in `onChange`, which read the view's previous `number` and so showed the skin picked
/// before. Here every frame asks for the `number` it is drawn with. `rgb` is the snake's colour
/// (strip looks wear it).
struct WyrmSkinLive: View {
    let number: Int
    let still: CGImage?
    var rgb: UInt32 = 0x8B8CF0
    @State private var mesh = WyrmSkinMesh()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                if !mesh.draw(number, rgb: rgb, now: now, size: size, into: context), let still {
                    WyrmSkinLive.drawStill(context, still, in: size)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func drawStill(_ context: GraphicsContext, _ image: CGImage, in size: CGSize) {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let scale = min(size.width / w, size.height / h)
        let rect = CGRect(x: (size.width - w * scale) / 2, y: (size.height - h * scale) / 2, width: w * scale, height: h * scale)
        context.draw(Image(decorative: image, scale: 1), in: rect)
    }
}

/// The live preview's buffers, kept across frames, and its drawing: triangles that share a
/// colour go into one path, so a frame is a few dozen fills, not thousands.
final class WyrmSkinMesh {
    static let maxVertices = 30000
    private var xy = [Float](repeating: 0, count: maxVertices * 2)
    private var argb = [UInt32](repeating: 0, count: maxVertices)
    private var idx = [UInt16](repeating: 0, count: maxVertices * 3)

    /// The actual game renderer on the wardrobe's head-first jiggle path; no roaming simulation.
    /// Runs the native pose into this mesh's buffers; (vertices, indices), or nil.
    private func pose(_ skin: Int, points: [CGPoint], radius: CGFloat, rgb: UInt32, now: Double) -> (Int, Int)? {
        guard points.count >= 2, points.count <= 256 else { return nil }
        let xs = points.map { Float($0.x) }, ys = points.map { Float($0.y) }
        var count: Int32 = 0
        let vertices = xs.withUnsafeBufferPointer { px in ys.withUnsafeBufferPointer { py in
            xy.withUnsafeMutableBufferPointer { output in argb.withUnsafeMutableBufferPointer { colors in
                idx.withUnsafeMutableBufferPointer { indices in
                    wyrm_skin_preview_pose(Int32(skin), px.baseAddress, py.baseAddress, Int32(points.count), Float(radius), now,
                        Float((rgb >> 16) & 255) / 255, Float((rgb >> 8) & 255) / 255, Float(rgb & 255) / 255,
                        (now + Double(skin) * 0.17).truncatingRemainder(dividingBy: 9) > 7.2 ? 1 : 0,
                        output.baseAddress, colors.baseAddress, Int32(Self.maxVertices),
                        indices.baseAddress, Int32(Self.maxVertices * 3), &count)
                }
            }}
        }}
        guard vertices > 0, count >= 3 else { return nil }
        return (Int(vertices), min(Int(count), Self.maxVertices * 3))
    }

    /// The same posed mesh handed to the wardrobe's GPU pass (WyrmWardrobeGPU).
    func appendPosed(_ skin: Int, points: [CGPoint], radius: CGFloat, rgb: UInt32,
                     now: Double, opacity: Double, into gpu: WyrmWardrobeGPU) {
        guard let (vertices, count) = pose(skin, points: points, radius: radius, rgb: rgb, now: now) else { return }
        xy.withUnsafeBufferPointer { p in argb.withUnsafeBufferPointer { c in idx.withUnsafeBufferPointer { i in
            gpu.append(xy: p, argb: c, vertexCount: vertices, idx: i, indexCount: count, opacity: opacity)
        }}}
    }

    /// CoreGraphics fallback when Metal is unavailable.
    func drawPosed(_ skin: Int, points: [CGPoint], radius: CGFloat, rgb: UInt32,
                   now: Double, into context: GraphicsContext) {
        guard let (vertices, count) = pose(skin, points: points, radius: radius, rgb: rgb, now: now) else { return }
        context.withCGContext { cg in
            let space = CGColorSpaceCreateDeviceRGB()
            func components(_ value: UInt32) -> [CGFloat] {
                [CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255,
                 CGFloat(value & 255) / 255, CGFloat((value >> 24) & 255) / 255]
            }
            var solid = CGMutablePath(), solidColor: UInt32?
            func flush() {
                if let color = solidColor {
                    cg.setFillColor(CGColor(colorSpace: space, components: components(color))!)
                    cg.addPath(solid); cg.fillPath(); solid = CGMutablePath()
                }
                solidColor = nil
            }
            for triangle in stride(from: 0, to: count - 2, by: 3) {
                let ids = (0..<3).map { Int(idx[triangle + $0]) }
                guard ids.allSatisfy({ $0 < vertices }) else { continue }
                let p = ids.map { CGPoint(x: CGFloat(xy[2 * $0]), y: CGFloat(xy[2 * $0 + 1])) }
                let color = ids.map { argb[$0] }
                let path = CGMutablePath(); path.move(to: p[0]); path.addLine(to: p[1]); path.addLine(to: p[2]); path.closeSubpath()
                if color[0] == color[1] && color[1] == color[2] {
                    if solidColor != color[0] { flush(); solidColor = color[0] }
                    solid.addPath(path); continue
                }
                flush()
                // Native quads use two paint stops. Solve their affine gradient over
                // each triangle instead of flattening it to a single averaged colour.
                let c = color.map(components)
                let pairs = [(0,1), (0,2), (1,2)]
                let pair = pairs.max { a, b in
                    zip(c[a.0], c[a.1]).map { pair in pow(pair.0 - pair.1, 2) }.reduce(0, +) <
                    zip(c[b.0], c[b.1]).map { pair in pow(pair.0 - pair.1, 2) }.reduce(0, +)
                }!
                let lo = c[pair.0], hi = c[pair.1]
                let delta = zip(hi, lo).map { $0.0 - $0.1 }
                let norm = delta.map { $0 * $0 }.reduce(0, +)
                let t = c.map { value in zip(zip(value, lo).map { $0.0 - $0.1 }, delta).map { $0.0 * $0.1 }.reduce(0, +) / max(norm, 0.000001) }
                let dx1 = p[1].x - p[0].x, dy1 = p[1].y - p[0].y
                let dx2 = p[2].x - p[0].x, dy2 = p[2].y - p[0].y
                let determinant = dx1 * dy2 - dx2 * dy1
                if abs(determinant) < 0.000001 { continue }
                let gx = ((t[1] - t[0]) * dy2 - (t[2] - t[0]) * dy1) / determinant
                let gy = (dx1 * (t[2] - t[0]) - dx2 * (t[1] - t[0])) / determinant
                let length = gx * gx + gy * gy
                guard length > 0.0000001,
                      let a = CGColor(colorSpace: space, components: lo), let b = CGColor(colorSpace: space, components: hi),
                      let gradient = CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1]) else { continue }
                let start = CGPoint(x: p[0].x - gx * t[0] / length, y: p[0].y - gy * t[0] / length)
                cg.saveGState(); cg.addPath(path); cg.clip()
                cg.drawLinearGradient(gradient, start: start, end: CGPoint(x: start.x + gx / length, y: start.y + gy / length),
                                      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                cg.restoreGState()
            }
            flush()
        }
    }

    /// False when nothing was drawn (no such skin, or a box too small).
    func draw(_ skin: Int, rgb: UInt32, now: Double, size: CGSize, into context: GraphicsContext) -> Bool {
        var ni: Int32 = 0
        let r = Float((rgb >> 16) & 0xFF) / 255, g = Float((rgb >> 8) & 0xFF) / 255, b = Float(rgb & 0xFF) / 255
        let nv = xy.withUnsafeMutableBufferPointer { pxy in
            argb.withUnsafeMutableBufferPointer { pc in
                idx.withUnsafeMutableBufferPointer { pi in
                    wyrm_skin_preview_frame(Int32(skin), Float(size.width), Float(size.height), now, r, g, b,
                                            pxy.baseAddress, pc.baseAddress, Int32(WyrmSkinMesh.maxVertices),
                                            pi.baseAddress, Int32(WyrmSkinMesh.maxVertices * 3), &ni)
                }
            }
        }
        guard nv > 0, ni >= 3 else { return false }
        var path = Path()
        var current: UInt32 = 0
        var started = false
        func flush() {
            guard started else { return }
            let a = Double((current >> 24) & 0xFF) / 255
            let color = Color(red: Double((current >> 16) & 0xFF) / 255, green: Double((current >> 8) & 0xFF) / 255,
                              blue: Double(current & 0xFF) / 255, opacity: a)
            context.fill(path, with: .color(color))
            path = Path()
        }
        var t = 0
        let count = Int(ni)
        while t + 2 < count {
            let i0 = Int(idx[t]), i1 = Int(idx[t + 1]), i2 = Int(idx[t + 2])
            t += 3
            let c = WyrmSkinMesh.mix(argb[i0], argb[i1], argb[i2])
            if (c >> 24) == 0 { continue }
            if !started || c != current {
                flush()
                current = c
                started = true
            }
            path.move(to: CGPoint(x: CGFloat(xy[2 * i0]), y: CGFloat(xy[2 * i0 + 1])))
            path.addLine(to: CGPoint(x: CGFloat(xy[2 * i1]), y: CGFloat(xy[2 * i1 + 1])))
            path.addLine(to: CGPoint(x: CGFloat(xy[2 * i2]), y: CGFloat(xy[2 * i2 + 1])))
            path.closeSubpath()
        }
        flush()
        return true
    }

    /// One colour for a triangle: its corners' average (they are equal on solid fills).
    private static func mix(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32 {
        if a == b && b == c { return a }
        func ch(_ v: UInt32, _ s: UInt32) -> UInt32 { (v >> s) & 0xFF }
        func avg(_ s: UInt32) -> UInt32 { (ch(a, s) + ch(b, s) + ch(c, s)) / 3 }
        return (avg(24) << 24) | (avg(16) << 16) | (avg(8) << 8) | avg(0)
    }
}

/// The worn skin's picture, filling the Skin page's preview.
struct WyrmSkinPicture: View {
    let image: CGImage?
    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One picker tile: the skin's picture and its name.
struct WyrmSkinTile: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let selected: Bool
    let label: String
    let image: CGImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    } else {
                        Text("NONE").font(.androidWyrm(9, .bold)).tracking(0.7).foregroundColor(wyrmScopedColours.ink)
                    }
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold))
                            .foregroundColor(wyrmScopedColours.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(label).font(.androidWyrm(11.5, .semibold))
                    .foregroundColor(selected ? wyrmScopedColours.ink : wyrmScopedColours.quiet).lineLimit(1)
            }
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 8)
            .aspectRatio(1.45, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 15).fill(wyrmScopedColours.card.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? wyrmScopedColours.ink : wyrmScopedColours.rule, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Wyrm skins page: None, the creatures, then the strip looks.
struct WyrmSkinsPanel: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let pictures: [Int: CGImage]
    let selected: Int
    let onPick: (Int) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private func caption(_ text: String) -> some View {
        Text(text).font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            caption("Pick one and your snake becomes it in the arena.")
            LazyVGrid(columns: columns, spacing: 10) {
                WyrmSkinTile(selected: selected == 0, label: "None", image: nil) { onPick(0) }
                ForEach(WyrmSkins.creatures) { skin in
                    WyrmSkinTile(selected: selected == skin.number, label: skin.name, image: pictures[skin.number]) {
                        onPick(skin.number)
                    }
                }
            }
            .padding(.horizontal, 16)
            WyrmSectionLabel("Strip looks")
            caption("A strip look keeps your own skin's colour.")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WyrmSkins.strips) { skin in
                    WyrmSkinTile(selected: selected == skin.number, label: skin.name, image: pictures[skin.number]) {
                        onPick(skin.number)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
