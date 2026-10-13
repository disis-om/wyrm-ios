import CoreGraphics
import Foundation
import ImageIO
import UIKit

/*
 * Skin Studio's pictures (OM, 2026-10-12; iOS 2026-10-13). Android twin:
 * ui/StudioArt.kt, the same finishes, numbers and atlas layout.
 *
 * Every bead, eye white and pupil is drawn here, the same way for the
 * Studio's previews and for the atlas the engine wears (game/studio.h: 8 x 8
 * cells of 128 px; beads 0-47, eye whites 48-55, pupils 56-63). Everything is
 * baked into the picture — the finish, the painting, hue, saturation,
 * brightness, smoothness and opacity — so the arena draws a Studio bead
 * exactly as cheaply as any other.
 *
 * A bead is drawn facing +x, the way the arena lays it along the body; the
 * engine turns it with the body and an eye with the head. Drawing uses
 * Android's y-down coordinates (StudioCanvas flips the context), and the
 * colour matrix, edge, blur and averages are pixel passes with Android's
 * own numbers.
 */

/// A premultiplied RGBA bitmap drawn in y-down coordinates (as Android's Canvas).
final class StudioCanvas {
    let width: Int
    let height: Int
    let context: CGContext

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init?(width: Int, height: Int) {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: StudioCanvas.colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        self.width = width
        self.height = height
        self.context = context
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
    }

    /// Row 0 is the top, as in the y-down drawing.
    var bytes: UnsafeMutablePointer<UInt8> {
        context.data!.assumingMemoryBound(to: UInt8.self)
    }
    var rowBytes: Int { context.bytesPerRow }

    func image() -> CGImage? { context.makeImage() }

    func clear() {
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }

    /// [image] into [rect] (y-down), upright.
    func draw(_ image: CGImage, in rect: CGRect, alpha: CGFloat = 1, blend: CGBlendMode = .normal) {
        context.saveGState()
        context.setAlpha(alpha)
        context.setBlendMode(blend)
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// A copy of these pixels in a new canvas.
    func copy() -> StudioCanvas? {
        guard let out = StudioCanvas(width: width, height: height) else { return nil }
        memcpy(out.bytes, bytes, rowBytes * height)
        return out
    }

    func load(from other: StudioCanvas) {
        guard other.width == width, other.height == height else { return }
        memcpy(bytes, other.bytes, rowBytes * height)
    }

    var isEmpty: Bool {
        let b = bytes
        for y in 0..<height {
            let row = b + y * rowBytes
            for x in 0..<width where row[x * 4 + 3] != 0 { return false }
        }
        return true
    }

    /// Unpremultiplied 0xAARRGGBB at a pixel (Android's getPixel).
    func pixel(_ x: Int, _ y: Int) -> UInt32 {
        let p = bytes + min(max(y, 0), height - 1) * rowBytes + min(max(x, 0), width - 1) * 4
        let a = UInt32(p[3])
        guard a > 0 else { return 0 }
        func un(_ c: UInt8) -> UInt32 { min(255, (UInt32(c) * 255 + a / 2) / a) }
        return a << 24 | un(p[0]) << 16 | un(p[1]) << 8 | un(p[2])
    }
}

enum WyrmStudioArt {
    static let finishSlither = 0
    static let finishFlat = 1
    static let finishGlossy = 2
    static let finishMatte = 3
    static let finishMetal = 4
    static let finishPearl = 5
    static let finishGlass = 6
    static let finishNeon = 7
    static let finishStripes = 8
    static let finishDots = 9
    static let finishScales = 10
    static let finishGlitter = 11
    static let finishMarble = 12
    static let finishCarbon = 13
    static let finishGradient = 14
    static let finishRings = 15

    static let finishes = [
        "Slither", "Flat", "Glossy", "Matte", "Metal", "Pearl", "Glass", "Neon",
        "Stripes", "Dots", "Scales", "Glitter", "Marble", "Carbon", "Gradient", "Rings",
    ]

    static let whiteShapes = ["Round", "Almond", "Outline", "Square", "Glow"]

    static let pupilRound = 0
    static let pupilCat = 2
    static let pupilShapes = [
        "Round", "Dot", "Cat", "Goat", "Heart", "Star", "Diamond", "Cross",
        "Plus", "Square", "Ring", "Spiral", "Flower", "Moon", "Spark", "Twin",
    ]

    static let cell = 128
    static let grid = 8
    static let atlasSize = cell * grid
    static let firstWhite = 48
    static let firstPupil = 56

    /// The bead's disc inside its square: a hair inside, so mip levels never bleed.
    static let disc: CGFloat = 0.94

    // MARK: beads

    /// [bead] as a [size]-px picture, [paint] laid over its finish.
    static func renderBead(_ bead: WyrmStudioBead, paint: CGImage?, size: Int, white: CGImage?) -> CGImage? {
        guard let layer = StudioCanvas(width: size, height: size) else { return nil }
        let half = CGFloat(size) / 2
        let r = half * disc
        drawFinish(layer, bead, cx: half, cy: half, r: r, white: white)
        if let paint {
            let soft = CGFloat(bead.smoothness) * CGFloat(size) / 64
            let source = soft >= 0.75 ? (blurred(paint, radius: soft * CGFloat(paint.width) / CGFloat(size)) ?? paint) : paint
            let c = layer.context
            c.saveGState()
            c.addEllipse(in: CGRect(x: half - r, y: half - r, width: 2 * r, height: 2 * r))
            c.clip()
            layer.draw(source, in: CGRect(x: half - r, y: half - r, width: 2 * r, height: 2 * r))
            c.restoreGState()
        }
        // Hue, saturation and brightness over the whole bead, then its edge and opacity.
        adjust(layer, matrix: adjustMatrix(hue: bead.hue, saturation: bead.saturation, brightness: bead.brightness),
               alpha: Double((min(max(bead.opacity, 0.15), 1) * 255).rounded()) / 255)
        featherEdge(layer, half: half, r: r, smoothness: bead.smoothness)
        return layer.image()
    }

    /// A bead's finish alone, unadjusted, for the bead editor's canvas.
    static func renderBase(_ bead: WyrmStudioBead, size: Int, white: CGImage?) -> CGImage? {
        guard let out = StudioCanvas(width: size, height: size) else { return nil }
        let half = CGFloat(size) / 2
        drawFinish(out, bead, cx: half, cy: half, r: half * disc, white: white)
        return out.image()
    }

    private static func drawFinish(_ canvas: StudioCanvas, _ bead: WyrmStudioBead, cx: CGFloat, cy: CGFloat,
                                   r: CGFloat, white: CGImage?) {
        let c = canvas.context
        let col = bead.color | 0xFF00_0000
        let detail = CGFloat(min(max(bead.detail, 0), 1))
        let discRect = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
        func fill(_ color: UInt32) {
            c.setFillColor(cg(color))
            c.fillEllipse(in: discRect)
        }
        func clip(_ block: () -> Void) {
            c.saveGState()
            c.addEllipse(in: discRect)
            c.clip()
            block()
            c.restoreGState()
        }
        func shade(_ strength: CGFloat) {
            // A soft dark rim and a light top-left, as a lit sphere.
            radial(c, clipTo: discRect, center: CGPoint(x: cx - r * 0.32, y: cy - r * 0.36), radius: r * 1.45,
                   colors: [withAlpha(0xFFFF_FFFF, 0.30 * strength), 0, withAlpha(0xFF00_0000, 0.45 * strength)],
                   stops: [0, 0.45, 1])
        }
        switch bead.finish {
        case finishSlither:
            if let white {
                fill(blend(col, darker(col, 0.25), 0.5))
                // The white bead's own art fills its cell a little past the disc.
                let grow = r * 1.04
                if let tinted = multiplied(white, by: col) {
                    clip {
                        canvas.draw(tinted, in: CGRect(x: cx - grow, y: cy - grow, width: 2 * grow, height: 2 * grow),
                                    alpha: CGFloat((255 * (0.55 + 0.45 * detail)).rounded()) / 255)
                    }
                }
            } else {
                fill(col); shade(0.9)
            }
        case finishFlat:
            fill(col)
        case finishGlossy:
            radial(c, clipTo: discRect, center: CGPoint(x: cx - r * 0.3, y: cy - r * 0.35), radius: r * 1.5,
                   colors: [lighter(col, 0.45 * detail), col, darker(col, 0.45 * detail)], stops: [0, 0.5, 1])
            radial(c, clipTo: CGRect(x: cx - r * 0.72, y: cy - r * 0.78, width: r * 0.77, height: r * 0.70), oval: true,
                   center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.42), radius: r * 0.42,
                   colors: [withAlpha(0xFFFF_FFFF, 0.75 * detail), 0], stops: [0, 1])
        case finishMatte:
            radial(c, clipTo: discRect, center: CGPoint(x: cx, y: cy - r * 0.15), radius: r * 1.2,
                   colors: [lighter(col, 0.12 * detail), darker(col, 0.28 * detail)], stops: [0, 1])
        case finishMetal:
            let hi = lighter(col, 0.6 * detail)
            let lo = darker(col, 0.55 * detail)
            sweep(c, clipTo: discRect, center: CGPoint(x: cx, y: cy), radius: r, colors: [hi, col, lo, col, hi, col, lo, col, hi])
            shade(0.8 * detail)
            radial(c, clipTo: CGRect(x: cx - r * 0.5, y: cy - r * 0.5, width: r, height: r), center: CGPoint(x: cx, y: cy),
                   radius: r * 0.5, colors: [withAlpha(0xFFFF_FFFF, 0.35 * detail), 0], stops: [0, 1])
        case finishPearl:
            let a = lighter(hueShift(col, 40), 0.35)
            let b = lighter(hueShift(col, -40), 0.35)
            sweep(c, clipTo: discRect, center: CGPoint(x: cx, y: cy), radius: r, colors: [lighter(col, 0.3), a, col, b, lighter(col, 0.3)])
            radial(c, clipTo: discRect, center: CGPoint(x: cx - r * 0.2, y: cy - r * 0.25), radius: r,
                   colors: [withAlpha(0xFFFF_FFFF, 0.65 * detail), withAlpha(0xFFFF_FFFF, 0.1 * detail), 0], stops: [0, 0.6, 1])
        case finishGlass:
            radial(c, clipTo: discRect, center: CGPoint(x: cx, y: cy), radius: r,
                   colors: [withAlpha(col, 0.28), withAlpha(col, 0.55), col], stops: [0, 0.72, 1])
            let w = r * (0.08 + 0.12 * detail)
            c.setStrokeColor(cg(lighter(col, 0.35)))
            c.setLineWidth(w)
            c.strokeEllipse(in: discRect.insetBy(dx: w / 2, dy: w / 2))
            let hr = r * 0.35
            let hc = CGPoint(x: cx - r * 0.35, y: cy - r * 0.4)
            radial(c, clipTo: CGRect(x: hc.x - hr, y: hc.y - hr, width: 2 * hr, height: 2 * hr), center: hc, radius: hr,
                   colors: [withAlpha(0xFFFF_FFFF, 0.85), 0], stops: [0, 1])
        case finishNeon:
            fill(darker(col, 0.82))
            let ring = CGRect(x: cx - r * 0.66, y: cy - r * 0.66, width: r * 1.32, height: r * 1.32)
            clip {
                softStroke(canvas, path: CGPath(ellipseIn: ring, transform: nil), width: r * 0.36,
                           color: withAlpha(col, 0.55), blur: r * 0.2)
            }
            c.setStrokeColor(cg(lighter(col, 0.25)))
            c.setLineWidth(r * (0.10 + 0.12 * detail))
            c.strokeEllipse(in: ring)
        case finishStripes:
            fill(col)
            c.setFillColor(cg(withAlpha(lighter(col, 0.55), 0.35 + 0.6 * detail)))
            let band = r * 0.26
            clip {
                var x = cx - r - band * 0.5
                while x < cx + r {
                    c.fill(CGRect(x: x, y: cy - r, width: band, height: 2 * r))
                    x += band * 2.2
                }
            }
            shade(0.7)
        case finishDots:
            fill(col)
            c.setFillColor(cg(withAlpha(lighter(col, 0.6), 0.4 + 0.6 * detail)))
            let step = r * 0.55
            clip {
                var row = 0
                var y = cy - r
                while y < cy + r + step {
                    var x = cx - r + (row % 2 == 0 ? 0 : step / 2)
                    while x < cx + r + step {
                        let d = step * 0.2
                        c.fillEllipse(in: CGRect(x: x - d, y: y - d, width: 2 * d, height: 2 * d))
                        x += step
                    }
                    y += step * 0.87
                    row += 1
                }
            }
            shade(0.7)
        case finishScales:
            fill(col)
            c.setStrokeColor(cg(withAlpha(darker(col, 0.6), 0.35 + 0.6 * detail)))
            c.setLineWidth(r * 0.07)
            let s = r * 0.5
            clip {
                var row = 0
                var y = cy - r - s
                while y < cy + r + s {
                    var x = cx - r - s + (row % 2 == 0 ? 0 : s)
                    while x < cx + r + s {
                        // The open side of each scale faces the tail (-x).
                        c.addPath(arcPath(center: CGPoint(x: x, y: y), radius: s, start: 90, sweep: 180))
                        c.strokePath()
                        x += s * 2
                    }
                    y += s
                    row += 1
                }
            }
            shade(0.8)
        case finishGlitter:
            fill(col)
            shade(0.6)
            var rnd = StudioRandom(seed: javaHash(bead.id))
            let count = Int((40 + 180 * detail).rounded())
            clip {
                for _ in 0..<count {
                    let a = rnd.nextFloat() * 2 * CGFloat.pi
                    let d = r * sqrt(rnd.nextFloat())
                    let colour = rnd.nextFloat() < 0.4 ? withAlpha(0xFFFF_FFFF, 0.9)
                        : lighter(hueShift(col, rnd.nextFloat() * 60 - 30), 0.5)
                    let pr = r * (0.015 + rnd.nextFloat() * 0.035)
                    c.setFillColor(cg(colour))
                    c.fillEllipse(in: CGRect(x: cx + cos(a) * d - pr, y: cy + sin(a) * d - pr, width: 2 * pr, height: 2 * pr))
                }
            }
        case finishMarble:
            fill(col)
            var rnd = StudioRandom(seed: javaHash(bead.id))
            clip {
                for k in 0..<5 {
                    let colour = withAlpha(k % 2 == 0 ? lighter(col, 0.7) : darker(col, 0.4), 0.25 + 0.5 * detail)
                    let width = r * (0.03 + rnd.nextFloat() * 0.06)
                    let path = CGMutablePath()
                    var y = cy - r + rnd.nextFloat() * 2 * r
                    path.move(to: CGPoint(x: cx - r, y: y))
                    var x = cx - r
                    while x < cx + r {
                        let nx = x + r * 0.4
                        let ny = y + (rnd.nextFloat() - 0.5) * r * 0.8
                        path.addQuadCurve(to: CGPoint(x: nx, y: ny),
                                          control: CGPoint(x: x + r * 0.2, y: y + (rnd.nextFloat() - 0.5) * r * 0.9))
                        x = nx; y = ny
                    }
                    softStroke(canvas, path: path, width: width, color: colour, blur: r * 0.03, cap: .round)
                }
            }
            shade(0.6)
        case finishCarbon:
            fill(darker(col, 0.35))
            let s = r * 0.24
            c.setFillColor(cg(withAlpha(lighter(col, 0.15), 0.5 + 0.5 * detail)))
            clip {
                var j = 0
                var y = cy - r
                while y < cy + r {
                    var i = 0
                    var x = cx - r
                    while x < cx + r {
                        if (i + j) % 2 == 0 { c.fill(CGRect(x: x, y: y, width: s, height: s)) }
                        x += s; i += 1
                    }
                    y += s; j += 1
                }
            }
            shade(0.9)
        case finishGradient:
            linear(c, clipTo: discRect, from: CGPoint(x: cx - r, y: cy), to: CGPoint(x: cx + r, y: cy),
                   colors: [darker(hueShift(col, -30 * detail), 0.2), col, lighter(hueShift(col, 45 * detail), 0.3)])
            shade(0.6)
        case finishRings:
            fill(col)
            c.setStrokeColor(cg(withAlpha(darker(col, 0.5), 0.4 + 0.55 * detail)))
            c.setLineWidth(r * 0.12)
            var rr = r * 0.82
            while rr > r * 0.1 {
                c.strokeEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: 2 * rr, height: 2 * rr))
                rr -= r * 0.3
            }
            shade(0.6)
        default:
            fill(col)
        }
    }

    /// Android's DST_IN radial mask: opaque inside `inner`, fading to clear at the disc's edge.
    private static func featherEdge(_ canvas: StudioCanvas, half: CGFloat, r: CGFloat, smoothness: Float) {
        let soft = CGFloat(min(max(smoothness, 0), 1))
        let inner = min(max(1 - 0.04 - soft * 0.32, 0.4), 0.99)
        let b = canvas.bytes
        for y in 0..<canvas.height {
            let row = b + y * canvas.rowBytes
            for x in 0..<canvas.width {
                let dx = CGFloat(x) + 0.5 - half
                let dy = CGFloat(y) + 0.5 - half
                let t = sqrt(dx * dx + dy * dy) / r
                let m: CGFloat = t <= inner ? 1 : t >= 1 ? 0 : (1 - (t - inner) / (1 - inner))
                if m >= 1 { continue }
                let p = row + x * 4
                for k in 0..<4 { p[k] = UInt8((CGFloat(p[k]) * m).rounded()) }
            }
        }
    }

    /// A 4x5 colour matrix (Android's ColorMatrix: rows R, G, B, A; offsets in 0-255).
    typealias Matrix = [Float]

    static let identity: Matrix = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]

    /// Android's postConcat: [next] applied after [m].
    private static func concat(_ m: Matrix, then next: Matrix) -> Matrix {
        var out = Matrix(repeating: 0, count: 20)
        for row in 0..<4 {
            for col in 0..<5 {
                var v: Float = col == 4 ? next[row * 5 + 4] : 0
                for k in 0..<4 { v += next[row * 5 + k] * m[k * 5 + col] }
                out[row * 5 + col] = v
            }
        }
        return out
    }

    /// Hue (degrees), saturation and brightness as one colour matrix.
    static func adjustMatrix(hue: Float, saturation: Float, brightness: Float) -> Matrix {
        var m = identity
        if hue != 0 {
            // The luminance-preserving hue turn (the W3C feColorMatrix hueRotate).
            let a: Float = hue * Float.pi / 180
            let cs: Float = cos(a)
            let sn: Float = sin(a)
            var h = identity
            h[0] = 0.213 + cs * 0.787 - sn * 0.213
            h[1] = 0.715 - cs * 0.715 - sn * 0.715
            h[2] = 0.072 - cs * 0.072 + sn * 0.928
            h[5] = 0.213 - cs * 0.213 + sn * 0.143
            h[6] = 0.715 + cs * 0.285 + sn * 0.140
            h[7] = 0.072 - cs * 0.072 - sn * 0.283
            h[10] = 0.213 - cs * 0.213 - sn * 0.787
            h[11] = 0.715 - cs * 0.715 + sn * 0.715
            h[12] = 0.072 + cs * 0.928 + sn * 0.072
            m = concat(m, then: h)
        }
        if saturation != 1 {
            // Android's ColorMatrix.setSaturation.
            let s: Float = min(max(saturation, 0), 2)
            let inv: Float = 1 - s
            let r: Float = 0.213 * inv, g: Float = 0.715 * inv, b: Float = 0.072 * inv
            var sat = identity
            sat[0] = r + s; sat[1] = g; sat[2] = b
            sat[5] = r; sat[6] = g + s; sat[7] = b
            sat[10] = r; sat[11] = g; sat[12] = b + s
            m = concat(m, then: sat)
        }
        if brightness != 1 {
            let b = min(max(brightness, 0), 2)
            let lift: Float = b > 1 ? (b - 1) * 90 : 0
            let gain: Float = b > 1 ? 1 : b
            var bright = identity
            bright[0] = gain; bright[6] = gain; bright[12] = gain
            bright[4] = lift; bright[9] = lift; bright[14] = lift
            m = concat(m, then: bright)
        }
        return m
    }

    /// The matrix on unpremultiplied colours (as Android's ColorMatrixColorFilter), then [alpha].
    static func adjust(_ canvas: StudioCanvas, matrix m: Matrix, alpha: Double) {
        let plain = m == identity
        if plain && alpha >= 1 { return }
        let fa = Float(alpha)
        let b = canvas.bytes
        for y in 0..<canvas.height {
            let row = b + y * canvas.rowBytes
            for x in 0..<canvas.width {
                let p = row + x * 4
                let a = Float(p[3])
                if a == 0 { continue }
                var r = Float(p[0]) * 255 / a, g = Float(p[1]) * 255 / a, bl = Float(p[2]) * 255 / a
                var na = a
                if !plain {
                    let nr = m[0] * r + m[1] * g + m[2] * bl + m[3] * a + m[4]
                    let ng = m[5] * r + m[6] * g + m[7] * bl + m[8] * a + m[9]
                    let nb = m[10] * r + m[11] * g + m[12] * bl + m[13] * a + m[14]
                    na = m[15] * r + m[16] * g + m[17] * bl + m[18] * a + m[19]
                    r = min(max(nr, 0), 255); g = min(max(ng, 0), 255); bl = min(max(nb, 0), 255)
                    na = min(max(na, 0), 255)
                }
                na *= fa
                let k = na / 255
                p[0] = UInt8((r * k).rounded()); p[1] = UInt8((g * k).rounded())
                p[2] = UInt8((bl * k).rounded()); p[3] = UInt8(na.rounded())
            }
        }
    }

    /// A small two-pass box blur, radius [radius] px (Android's `blurred`).
    static func blurred(_ source: CGImage, radius: CGFloat) -> CGImage? {
        guard let canvas = StudioCanvas(width: source.width, height: source.height) else { return nil }
        canvas.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        boxBlur(canvas, radius: Int(radius.rounded()))
        return canvas.image()
    }

    /// Android's box blur, done on premultiplied pixels (the same as its alpha-weighted sums).
    static func boxBlur(_ canvas: StudioCanvas, radius: Int) {
        let rad = min(max(radius, 1), 12)
        let w = canvas.width, h = canvas.height
        let stride = canvas.rowBytes
        let b = canvas.bytes
        var tmp = [UInt8](repeating: 0, count: stride * h)
        func pass(horizontal: Bool, from: UnsafePointer<UInt8>, to: UnsafeMutablePointer<UInt8>) {
            let lines = horizontal ? h : w
            let len = horizontal ? w : h
            let n = Float(2 * rad + 1)
            for line in 0..<lines {
                for i in 0..<len {
                    var s0: Float = 0, s1: Float = 0, s2: Float = 0, s3: Float = 0
                    for k in -rad...rad {
                        let j = min(max(i + k, 0), len - 1)
                        let p = horizontal ? from + line * stride + j * 4 : from + j * stride + line * 4
                        s0 += Float(p[0]); s1 += Float(p[1]); s2 += Float(p[2]); s3 += Float(p[3])
                    }
                    let q = horizontal ? to + line * stride + i * 4 : to + i * stride + line * 4
                    q[0] = UInt8((s0 / n).rounded()); q[1] = UInt8((s1 / n).rounded())
                    q[2] = UInt8((s2 / n).rounded()); q[3] = UInt8((s3 / n).rounded())
                }
            }
        }
        tmp.withUnsafeMutableBufferPointer { t in
            pass(horizontal: true, from: UnsafePointer(b), to: t.baseAddress!)
            pass(horizontal: false, from: UnsafePointer(t.baseAddress!), to: b)
        }
    }

    /// A stroke with a soft edge (Android's BlurMaskFilter): drawn on its own
    /// layer, blurred, then laid on [canvas] (or cut out of it when [erase]).
    static func softStroke(_ canvas: StudioCanvas, path: CGPath, width: CGFloat, color: UInt32, blur: CGFloat,
                           cap: CGLineCap = .butt, join: CGLineJoin = .miter, erase: Bool = false) {
        let pad = width / 2 + blur * 2 + 2
        let box = path.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad).integral
            .intersection(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        guard !box.isNull, box.width >= 1, box.height >= 1,
              let layer = StudioCanvas(width: Int(box.width), height: Int(box.height)) else { return }
        let c = layer.context
        c.translateBy(x: -box.minX, y: -box.minY)
        c.addPath(path)
        c.setLineWidth(width)
        c.setLineCap(cap)
        c.setLineJoin(join)
        c.setStrokeColor(cg(erase ? 0xFFFF_FFFF : color))
        c.strokePath()
        boxBlur(layer, radius: max(1, Int(blur.rounded())))
        if let image = layer.image() {
            canvas.draw(image, in: box, blend: erase ? .destinationOut : .normal)
        }
    }

    // MARK: eyes

    static func renderWhite(_ eye: WyrmStudioEye, size: Int) -> CGImage? {
        guard let out = StudioCanvas(width: size, height: size) else { return nil }
        let c = out.context
        let half = CGFloat(size) / 2
        let r = half * disc
        let col = eye.whiteColor | 0xFF00_0000
        func circle(_ rr: CGFloat) -> CGRect { CGRect(x: half - rr, y: half - rr, width: 2 * rr, height: 2 * rr) }
        switch eye.whiteShape {
        case 1: // Almond: long across the head
            c.setFillColor(cg(col))
            c.fillEllipse(in: CGRect(x: half - r * 0.62, y: half - r, width: r * 1.24, height: 2 * r))
        case 2: // Outline: a dark rim
            c.setFillColor(cg(darker(col, 0.75)))
            c.fillEllipse(in: circle(r))
            c.setFillColor(cg(col))
            c.fillEllipse(in: circle(r * 0.8))
        case 3: // Square
            c.setFillColor(cg(col))
            c.addPath(CGPath(roundedRect: CGRect(x: half - r * 0.7, y: half - r * 0.7, width: r * 1.4, height: r * 1.4),
                             cornerWidth: r * 0.18, cornerHeight: r * 0.18, transform: nil))
            c.fillPath()
        case 4: // Glow: a soft lit ball
            radial(c, clipTo: circle(r), center: CGPoint(x: half, y: half), radius: r,
                   colors: [lighter(col, 0.4), col, withAlpha(col, 0)], stops: [0, 0.7, 1])
        default:
            c.setFillColor(cg(col))
            c.fillEllipse(in: circle(r))
        }
        return out.image()
    }

    static func renderPupil(_ eye: WyrmStudioEye, size: Int) -> CGImage? {
        guard let out = StudioCanvas(width: size, height: size) else { return nil }
        let c = out.context
        let h = CGFloat(size) / 2
        let r = h * disc
        let colour = cg(eye.pupilColor | 0xFF00_0000)
        c.setFillColor(colour)
        c.setStrokeColor(colour)
        func circle(_ x: CGFloat, _ y: CGFloat, _ rr: CGFloat) -> CGRect { CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr) }
        func star(_ points: Int, _ inner: CGFloat, _ turn: CGFloat = -90) -> CGPath {
            let path = CGMutablePath()
            for i in 0..<(points * 2) {
                let a = (turn + CGFloat(i) * 180 / CGFloat(points)) * .pi / 180
                let d = i % 2 == 0 ? r : r * inner
                let p = CGPoint(x: h + cos(a) * d, y: h + sin(a) * d)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return path
        }
        func strokeLines(_ width: CGFloat, _ lines: [(CGPoint, CGPoint)]) {
            c.setLineWidth(width)
            c.setLineCap(.round)
            for (a, b) in lines { c.move(to: a); c.addLine(to: b) }
            c.strokePath()
        }
        switch eye.pupilShape {
        case 1: c.fillEllipse(in: circle(h, h, r * 0.5))                                   // Dot
        case 2: c.fillEllipse(in: CGRect(x: h - r * 0.3, y: h - r, width: r * 0.6, height: 2 * r)) // Cat
        case 3:                                                                             // Goat
            c.addPath(CGPath(roundedRect: CGRect(x: h - r, y: h - r * 0.32, width: 2 * r, height: r * 0.64),
                             cornerWidth: r * 0.3, cornerHeight: r * 0.3, transform: nil))
            c.fillPath()
        case 4:                                                                             // Heart
            let p = CGMutablePath()
            p.move(to: CGPoint(x: h, y: h + r * 0.85))
            p.addCurve(to: CGPoint(x: h, y: h - r * 0.42), control1: CGPoint(x: h - r * 1.35, y: h - r * 0.05),
                       control2: CGPoint(x: h - r * 0.55, y: h - r * 1.05))
            p.addCurve(to: CGPoint(x: h, y: h + r * 0.85), control1: CGPoint(x: h + r * 0.55, y: h - r * 1.05),
                       control2: CGPoint(x: h + r * 1.35, y: h - r * 0.05))
            p.closeSubpath()
            c.addPath(p); c.fillPath()
        case 5: c.addPath(star(5, 0.45)); c.fillPath()                                      // Star
        case 6:                                                                             // Diamond
            c.move(to: CGPoint(x: h, y: h - r)); c.addLine(to: CGPoint(x: h + r * 0.7, y: h))
            c.addLine(to: CGPoint(x: h, y: h + r)); c.addLine(to: CGPoint(x: h - r * 0.7, y: h))
            c.closePath(); c.fillPath()
        case 7:                                                                             // Cross
            let k = r * 0.62
            strokeLines(r * 0.42, [(CGPoint(x: h - k, y: h - k), CGPoint(x: h + k, y: h + k)),
                                   (CGPoint(x: h - k, y: h + k), CGPoint(x: h + k, y: h - k))])
        case 8:                                                                             // Plus
            let k = r * 0.72
            strokeLines(r * 0.42, [(CGPoint(x: h - k, y: h), CGPoint(x: h + k, y: h)),
                                   (CGPoint(x: h, y: h - k), CGPoint(x: h, y: h + k))])
        case 9: c.fill(CGRect(x: h - r * 0.68, y: h - r * 0.68, width: r * 1.36, height: r * 1.36)) // Square
        case 10:                                                                            // Ring
            c.setLineWidth(r * 0.3)
            c.strokeEllipse(in: circle(h, h, r * 0.75))
        case 11:                                                                            // Spiral
            let path = CGMutablePath()
            path.move(to: CGPoint(x: h, y: h))
            var t: CGFloat = 0
            let end = 3.2 * CGFloat.pi
            while t < end {
                let d = r * 0.9 * t / end
                path.addLine(to: CGPoint(x: h + cos(t) * d, y: h + sin(t) * d))
                t += 0.15
            }
            c.setLineWidth(r * 0.2)
            c.setLineCap(.round)
            c.addPath(path); c.strokePath()
        case 12:                                                                            // Flower
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                c.fillEllipse(in: circle(h + cos(a) * r * 0.5, h + sin(a) * r * 0.5, r * 0.38))
            }
        case 13:                                                                            // Moon
            c.saveGState()
            c.addRect(CGRect(x: 0, y: 0, width: size, height: size))
            c.addEllipse(in: circle(h + r * 0.45, h - r * 0.2, r * 0.75))
            c.clip(using: .evenOdd)
            c.fillEllipse(in: circle(h, h, r * 0.9))
            c.restoreGState()
        case 14: c.addPath(star(4, 0.28)); c.fillPath()                                     // Spark
        case 15:                                                                            // Twin
            c.fillEllipse(in: circle(h, h - r * 0.45, r * 0.42))
            c.fillEllipse(in: circle(h, h + r * 0.45, r * 0.42))
        default: c.fillEllipse(in: circle(h, h, r))                                         // Round
        }
        return out.image()
    }

    // MARK: preview cache

    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 160
        return cache
    }()

    /// [bead] for the Studio's screens, cached by its revision.
    static func beadImage(_ bead: WyrmStudioBead, white: CGImage?, size: Int = cell) -> CGImage? {
        let key = "b:\(bead.id):\(bead.rev):\(size):\(white != nil)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let paint = bead.painted ? WyrmStudioPaints.shared.image(bead.id) : nil
        guard let image = renderBead(bead, paint: paint, size: size, white: white) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func whiteImage(_ eye: WyrmStudioEye) -> CGImage? {
        let key = "w:\(eye.whiteShape):\(eye.whiteColor)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = renderWhite(eye, size: cell) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func pupilImage(_ eye: WyrmStudioEye) -> CGImage? {
        let key = "p:\(eye.pupilShape):\(eye.pupilColor)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = renderPupil(eye, size: cell) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: the atlas

    struct Baked {
        let atlas: CGImage
        let text: String
    }

    /// The engine's atlas and text for [skin] (game/studio.h). Nil when nothing can be worn.
    /// [beads] and [paints] are a snapshot taken on the main thread.
    static func bakeAtlas(_ skin: WyrmStudioSkin, beads: [String: WyrmStudioBead], paints: [String: CGImage],
                          white: CGImage?) -> Baked? {
        var unique: [String] = []
        for id in skin.pattern where !unique.contains(id) { unique.append(id) }
        unique = Array(unique.prefix(WyrmStudio.maxDistinct))
        guard !unique.isEmpty, let atlas = StudioCanvas(width: atlasSize, height: atlasSize) else { return nil }
        var colours = [UInt32](repeating: 0, count: grid * grid)
        func place(_ cellIndex: Int, _ image: CGImage?) {
            guard let image else { return }
            atlas.draw(image, in: CGRect(x: (cellIndex % grid) * cell, y: (cellIndex / grid) * cell, width: cell, height: cell))
            colours[cellIndex] = averageRGB(image)
        }
        for (index, id) in unique.enumerated() {
            let bead = beads[id] ?? WyrmStudioBead(id: id)
            place(index, renderBead(bead, paint: bead.painted ? paints[id] : nil, size: cell, white: white))
        }
        let eyes = Array(skin.eyes.prefix(WyrmStudio.maxEyes))
        for (i, eye) in eyes.enumerated() {
            place(firstWhite + i, renderWhite(eye, size: cell))
            place(firstPupil + i, renderPupil(eye, size: cell))
        }
        var index: [String: Int] = [:]
        for (cellIndex, id) in unique.enumerated() { index[id] = cellIndex }
        var text = "P:" + skin.pattern.prefix(WyrmStudio.maxPattern).map { String(index[$0] ?? 0) }.joined(separator: ",")
        text += "|C:" + colours.map { String(format: "%06x", $0 & 0xFF_FFFF) }.joined(separator: ",")
        if !eyes.isEmpty {
            text += "|E:" + eyes.enumerated().map { i, e in
                [WyrmStudio.num(e.fwd), WyrmStudio.num(e.side), WyrmStudio.num(e.white),
                 WyrmStudio.num(e.pupil), WyrmStudio.num(e.look),
                 String(firstWhite + i), String(firstPupil + i)].joined(separator: ",")
            }.joined(separator: ";")
        }
        guard let image = atlas.image() else { return nil }
        return Baked(atlas: image, text: text)
    }

    /// The picture's own colour: its pixels weighted by how opaque they are (0xRRGGBB).
    static func averageRGB(_ image: CGImage) -> UInt32 {
        guard let canvas = StudioCanvas(width: image.width, height: image.height) else { return 0 }
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let w = canvas.width, h = canvas.height
        let step = max(1, min(w, h) / 32)
        var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, a: UInt64 = 0
        let bytes = canvas.bytes
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let p = bytes + y * canvas.rowBytes + x * 4
                // Premultiplied channel x 255 = the straight channel x alpha.
                r += UInt64(p[0]) * 255; g += UInt64(p[1]) * 255; b += UInt64(p[2]) * 255
                a += UInt64(p[3])
                x += step
            }
            y += step
        }
        guard a > 0 else { return 0 }
        return UInt32(min(255, r / a)) << 16 | UInt32(min(255, g / a)) << 8 | UInt32(min(255, b / a))
    }

    /// An atlas as PNG bytes (straight RGBA, as the engine's stbi_load reads it).
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func loadPNG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: colour (0xAARRGGBB, as Android's Int colours)

    static func withAlpha(_ color: UInt32, _ alpha: CGFloat) -> UInt32 {
        UInt32((min(max(alpha, 0), 1) * 255).rounded()) << 24 | (color & 0xFF_FFFF)
    }

    static func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
        func ch(_ x: UInt32, _ y: UInt32) -> UInt32 {
            UInt32(min(max((CGFloat(x) + (CGFloat(y) - CGFloat(x)) * t).rounded(), 0), 255))
        }
        return 0xFF00_0000 | ch((a >> 16) & 0xFF, (b >> 16) & 0xFF) << 16
            | ch((a >> 8) & 0xFF, (b >> 8) & 0xFF) << 8 | ch(a & 0xFF, b & 0xFF)
    }

    static func lighter(_ color: UInt32, _ t: CGFloat) -> UInt32 { blend(color, 0xFFFF_FFFF, min(max(t, 0), 1)) }
    static func darker(_ color: UInt32, _ t: CGFloat) -> UInt32 { blend(color, 0xFF00_0000, min(max(t, 0), 1)) }

    static func hueShift(_ color: UInt32, _ degrees: CGFloat) -> UInt32 {
        var hsv = toHSV(color)
        hsv.h = ((hsv.h + Double(degrees)).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return fromHSV(hsv.h, hsv.s, hsv.v)
    }

    /// Android's Color.colorToHSV: hue 0-360, saturation and value 0-1.
    static func toHSV(_ color: UInt32) -> (h: Double, s: Double, v: Double) {
        let r = Double((color >> 16) & 0xFF) / 255, g = Double((color >> 8) & 0xFF) / 255, b = Double(color & 0xFF) / 255
        let mx = max(r, g, b), mn = min(r, g, b)
        let d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = (g - b) / d }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// Android's Color.HSVToColor, opaque.
    static func fromHSV(_ h: Double, _ s: Double, _ v: Double) -> UInt32 {
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let ss = min(max(s, 0), 1), vv = min(max(v, 0), 1)
        let i = Int(hh)
        let f = hh - Double(i)
        let p = vv * (1 - ss), q = vv * (1 - ss * f), t = vv * (1 - ss * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (vv, t, p)
        case 1: (r, g, b) = (q, vv, p)
        case 2: (r, g, b) = (p, vv, t)
        case 3: (r, g, b) = (p, q, vv)
        case 4: (r, g, b) = (t, p, vv)
        default: (r, g, b) = (vv, p, q)
        }
        func byte(_ x: Double) -> UInt32 { UInt32(min(max((x * 255).rounded(), 0), 255)) }
        return 0xFF00_0000 | byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    static func cg(_ color: UInt32) -> CGColor {
        CGColor(colorSpace: StudioCanvas.colorSpace,
                components: [CGFloat((color >> 16) & 0xFF) / 255, CGFloat((color >> 8) & 0xFF) / 255,
                             CGFloat(color & 0xFF) / 255, CGFloat((color >> 24) & 0xFF) / 255])
            ?? CGColor(gray: 0, alpha: 1)
    }

    // MARK: drawing helpers

    /// A radial gradient filling [clipTo] (a circle, or an oval), clamped past its end as Android's CLAMP.
    private static func radial(_ c: CGContext, clipTo rect: CGRect, oval: Bool = true, center: CGPoint, radius: CGFloat,
                               colors: [UInt32], stops: [CGFloat]) {
        guard let gradient = CGGradient(colorsSpace: StudioCanvas.colorSpace, colors: colors.map(cg) as CFArray,
                                        locations: stops) else { return }
        c.saveGState()
        if oval { c.addEllipse(in: rect) } else { c.addRect(rect) }
        c.clip()
        c.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }

    private static func linear(_ c: CGContext, clipTo rect: CGRect, from: CGPoint, to: CGPoint, colors: [UInt32]) {
        let stops = colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        guard let gradient = CGGradient(colorsSpace: StudioCanvas.colorSpace, colors: colors.map(cg) as CFArray,
                                        locations: stops) else { return }
        c.saveGState()
        c.addEllipse(in: rect)
        c.clip()
        c.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }

    /// Android's SweepGradient (colours evenly spaced, clockwise from +x), as thin wedges.
    private static func sweep(_ c: CGContext, clipTo rect: CGRect, center: CGPoint, radius: CGFloat, colors: [UInt32]) {
        guard colors.count > 1 else { return }
        c.saveGState()
        c.addEllipse(in: rect)
        c.clip()
        let wedges = 180
        let reach = radius * 1.5
        for i in 0..<wedges {
            let t0 = CGFloat(i) / CGFloat(wedges), t1 = CGFloat(i + 1) / CGFloat(wedges)
            let mid = (t0 + t1) / 2 * CGFloat(colors.count - 1)
            let k = min(Int(mid), colors.count - 2)
            let colour = blendARGB(colors[k], colors[k + 1], mid - CGFloat(k))
            let a0 = t0 * 2 * .pi - 0.004, a1 = t1 * 2 * .pi + 0.004
            c.move(to: center)
            c.addLine(to: CGPoint(x: center.x + cos(a0) * reach, y: center.y + sin(a0) * reach))
            c.addLine(to: CGPoint(x: center.x + cos(a1) * reach, y: center.y + sin(a1) * reach))
            c.closePath()
            c.setFillColor(cg(colour))
            c.fillPath()
        }
        c.restoreGState()
    }

    /// Blends two colours, alpha too (a gradient's colour between stops).
    private static func blendARGB(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UInt32 {
        func ch(_ s: UInt32) -> CGFloat {
            CGFloat((a >> s) & 0xFF) + (CGFloat((b >> s) & 0xFF) - CGFloat((a >> s) & 0xFF)) * t
        }
        func byte(_ v: CGFloat) -> UInt32 { UInt32(min(max(v.rounded(), 0), 255)) }
        return byte(ch(24)) << 24 | byte(ch(16)) << 16 | byte(ch(8)) << 8 | byte(ch(0))
    }

    /// An arc in Android's terms: degrees clockwise from +x (y-down), as a polyline.
    static func arcPath(center: CGPoint, radius: CGFloat, start: CGFloat, sweep: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let steps = 28
        for i in 0...steps {
            let a = (start + sweep * CGFloat(i) / CGFloat(steps)) * .pi / 180
            let p = CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// [image] with every colour multiplied by [color] (Android's PorterDuff MULTIPLY filter).
    private static func multiplied(_ image: CGImage, by color: UInt32) -> CGImage? {
        guard let canvas = StudioCanvas(width: image.width, height: image.height) else { return nil }
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let mr = UInt32((color >> 16) & 0xFF), mg = UInt32((color >> 8) & 0xFF), mb = UInt32(color & 0xFF)
        let b = canvas.bytes
        for y in 0..<canvas.height {
            let row = b + y * canvas.rowBytes
            for x in 0..<canvas.width {
                let p = row + x * 4
                p[0] = UInt8(UInt32(p[0]) * mr / 255)
                p[1] = UInt8(UInt32(p[1]) * mg / 255)
                p[2] = UInt8(UInt32(p[2]) * mb / 255)
            }
        }
        return canvas.image()
    }

    /// Java's String.hashCode, so a bead's glitter and marble fall as on Android.
    static func javaHash(_ text: String) -> Int32 {
        var h: Int32 = 0
        for unit in text.utf16 { h = h &* 31 &+ Int32(unit) }
        return h
    }
}

/// Kotlin's default Random(seed) is XorWow; this is the same generator, so the
/// glitter and marble of a bead come out where Android puts them.
struct StudioRandom {
    private var x: Int32, y: Int32, z: Int32, w: Int32, v: Int32, addend: Int32

    init(seed: Int32) {
        let s = Int64(seed)
        let lo = Int32(truncatingIfNeeded: s)
        let hi = Int32(truncatingIfNeeded: s >> 31)
        x = lo; y = hi; z = 0; w = 0; v = ~lo
        addend = (lo << 10) ^ Int32(bitPattern: UInt32(bitPattern: hi) >> 4)
        for _ in 0..<64 { _ = nextInt() }
    }

    mutating func nextInt() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y; y = z; z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362_437
        return t &+ addend
    }

    /// Kotlin's nextFloat: 24 random bits over 2^24.
    mutating func nextFloat() -> CGFloat {
        let bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 8)
        return CGFloat(bits) / CGFloat(1 << 24)
    }
}
