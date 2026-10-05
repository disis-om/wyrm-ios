import SwiftUI
import UIKit
import CoreImage

/*
 * Trails looks (OM, 2026-10-05): the colour filters and adjustments of the
 * photo editor and the video editor, one definition for both.
 *
 * A look is a 4 x 5 colour matrix in 0..255 units, built exactly as Wyrm
 * Android builds it with `android.graphics.ColorMatrix` (`ui/TrailLooks.kt`:
 * same looks, same numbers, same order of steps), so a look is the same
 * colour on both phones. Here it runs as Core Image's CIColorMatrix on
 * gamma-encoded sRGB values (the picture is taken out of Core Image's linear
 * working space for the matrix and put back after), which is what Android's
 * matrix does to its pixels. The editor's photo, the video player, the video
 * export and the poster all use `WyrmTrailLooks.apply`.
 */

/// One named look: the editors' filter strip.
struct WyrmTrailLook: Equatable, Identifiable {
    let name: String
    var saturation: Float = 1
    var contrast: Float = 1
    /// -1..1, about a quarter of the range at the ends.
    var brightness: Float = 0
    /// -1..1: warm (red up, blue down) to cool.
    var warmth: Float = 0
    /// -1..1: green to magenta.
    var tint: Float = 0
    /// 0..1: lifted blacks, a softer picture.
    var fade: Float = 0
    var sepia = false
    var id: String { name }
}

/// The adjustment sliders, each -1..1 with 0 as "unchanged".
struct WyrmTrailAdjust: Equatable {
    var brightness: Float = 0
    var contrast: Float = 0
    var saturation: Float = 0
    var warmth: Float = 0
    var untouched: Bool { brightness == 0 && contrast == 0 && saturation == 0 && warmth == 0 }
}

/// A 4 x 5 colour matrix, row by row, in 0..255 units (Android's layout).
struct WyrmLookMatrix: Equatable {
    var m: [Float]
    static let identity = WyrmLookMatrix(m: [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0])

    /// Android's `postConcat(next)`: `next` applied after this one.
    func then(_ next: WyrmLookMatrix) -> WyrmLookMatrix {
        var out = [Float](repeating: 0, count: 20)
        for row in 0..<4 {
            for col in 0..<5 {
                var sum: Float = 0
                for k in 0..<4 { sum += next.m[row * 5 + k] * m[k * 5 + col] }
                if col == 4 { sum += next.m[row * 5 + 4] }
                out[row * 5 + col] = sum
            }
        }
        return WyrmLookMatrix(m: out)
    }
}

enum WyrmTrailLooks {
    static let all: [WyrmTrailLook] = [
        WyrmTrailLook(name: "Normal"),
        WyrmTrailLook(name: "Vivid", saturation: 1.35, contrast: 1.12),
        WyrmTrailLook(name: "Arena", saturation: 1.15, contrast: 1.08, warmth: -0.25, tint: -0.35),
        WyrmTrailLook(name: "Neon", saturation: 1.55, contrast: 1.2, brightness: 0.04, tint: 0.35),
        WyrmTrailLook(name: "Sunset", saturation: 1.15, contrast: 1.05, warmth: 0.7),
        WyrmTrailLook(name: "Frost", saturation: 0.85, brightness: 0.06, warmth: -0.7),
        WyrmTrailLook(name: "Fade", saturation: 0.8, contrast: 0.88, fade: 0.45),
        WyrmTrailLook(name: "Retro", contrast: 1.05, fade: 0.2, sepia: true),
        WyrmTrailLook(name: "Mono", saturation: 0, contrast: 1.1),
        WyrmTrailLook(name: "Noir", saturation: 0, contrast: 1.45, brightness: -0.06),
    ]

    static var normal: WyrmTrailLook { all[0] }

    static func isIdentity(_ look: WyrmTrailLook, _ adjust: WyrmTrailAdjust) -> Bool {
        look.name == "Normal" && adjust.untouched
    }

    /// The look then the sliders, as one matrix (Android `TrailLooks.matrix`).
    static func matrix(_ look: WyrmTrailLook, _ adjust: WyrmTrailAdjust = WyrmTrailAdjust()) -> WyrmLookMatrix {
        var out = WyrmLookMatrix.identity
        if look.sepia {
            out = out.then(WyrmLookMatrix(m: [
                0.393, 0.769, 0.189, 0, 0,
                0.349, 0.686, 0.168, 0, 0,
                0.272, 0.534, 0.131, 0, 0,
                0, 0, 0, 1, 0,
            ]))
        }
        out = out.then(saturation(look.saturation * (1 + adjust.saturation)))
        out = out.then(contrast(look.contrast * (1 + adjust.contrast * 0.5)))
        out = out.then(offsets(brightness: look.brightness + adjust.brightness * 0.25,
                               warmth: look.warmth + adjust.warmth, tint: look.tint))
        if look.fade > 0 { out = out.then(fade(look.fade)) }
        return out
    }

    /// Android `ColorMatrix.setSaturation`.
    private static func saturation(_ value: Float) -> WyrmLookMatrix {
        let s = min(max(value, 0), 3)
        let inv = 1 - s
        let r = 0.213 * inv, g = 0.715 * inv, b = 0.072 * inv
        return WyrmLookMatrix(m: [
            r + s, g, b, 0, 0,
            r, g + s, b, 0, 0,
            r, g, b + s, 0, 0,
            0, 0, 0, 1, 0,
        ])
    }

    private static func contrast(_ value: Float) -> WyrmLookMatrix {
        let k = min(max(value, 0.2), 3)
        let t = 128 * (1 - k)
        return WyrmLookMatrix(m: [k, 0, 0, 0, t, 0, k, 0, 0, t, 0, 0, k, 0, t, 0, 0, 0, 1, 0])
    }

    private static func offsets(brightness: Float, warmth: Float, tint: Float) -> WyrmLookMatrix {
        let b = min(max(brightness, -1), 1) * 64
        let w = min(max(warmth, -1), 1) * 26
        let g = min(max(tint, -1), 1) * 18
        return WyrmLookMatrix(m: [
            1, 0, 0, 0, b + w + g * 0.5,
            0, 1, 0, 0, b - g,
            0, 0, 1, 0, b - w + g * 0.5,
            0, 0, 0, 1, 0,
        ])
    }

    private static func fade(_ value: Float) -> WyrmLookMatrix {
        let f = min(max(value, 0), 1)
        let k = 1 - 0.22 * f
        let lift = 255 * 0.16 * f
        return WyrmLookMatrix(m: [k, 0, 0, 0, lift, 0, k, 0, 0, lift, 0, 0, k, 0, lift, 0, 0, 0, 1, 0])
    }

    // MARK: Core Image

    /// One context for every look in the app (Core Image keeps its own caches).
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// The matrix on a Core Image picture, in Android's units: gamma-encoded
    /// 0..1 values, clamped like Android's 0..255 bytes.
    static func apply(_ image: CIImage, _ matrix: WyrmLookMatrix) -> CIImage {
        let m = matrix.m
        func vector(_ row: Int) -> CIVector {
            CIVector(x: CGFloat(m[row * 5]), y: CGFloat(m[row * 5 + 1]), z: CGFloat(m[row * 5 + 2]), w: CGFloat(m[row * 5 + 3]))
        }
        return image
            .applyingFilter("CILinearToSRGBToneCurve")
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": vector(0),
                "inputGVector": vector(1),
                "inputBVector": vector(2),
                "inputAVector": vector(3),
                "inputBiasVector": CIVector(x: CGFloat(m[4] / 255), y: CGFloat(m[9] / 255), z: CGFloat(m[14] / 255),
                                            w: CGFloat(m[19] / 255)),
            ])
            .applyingFilter("CIColorClamp")
            .applyingFilter("CISRGBToneCurveToLinear")
    }

    /// A photo in a look, upright, at most `longest` px on its long side
    /// (nil: its own size). Normal with no adjustment returns it as it is.
    static func apply(_ image: UIImage, _ look: WyrmTrailLook, _ adjust: WyrmTrailAdjust, longest: CGFloat? = nil) -> UIImage {
        if isIdentity(look, adjust) && longest == nil { return image }
        guard var source = upright(image) else { return image }
        if let longest {
            let side = max(source.extent.width, source.extent.height)
            if side > longest {
                let k = longest / side
                source = source.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: k, kCIInputAspectRatioKey: 1])
            }
        }
        let output = isIdentity(look, adjust) ? source : apply(source, matrix(look, adjust))
        let extent = source.extent.integral
        guard let cg = context.createCGImage(output.cropped(to: extent), from: extent) else { return image }
        return UIImage(cgImage: cg)
    }

    /// The photo as Core Image sees it, turned the way UIKit shows it.
    static func upright(_ image: UIImage) -> CIImage? {
        let base: CIImage
        if let cg = image.cgImage { base = CIImage(cgImage: cg) }
        else if let ci = image.ciImage { base = ci }
        else { return nil }
        let turned = base.oriented(orientation(image.imageOrientation))
        return turned.transformed(by: CGAffineTransform(translationX: -turned.extent.minX, y: -turned.extent.minY))
    }

    private static func orientation(_ value: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch value {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// The matrix the video player's frames are filtered with right now; set from
/// the main thread, read on the player's rendering thread.
final class WyrmLookBox {
    private let lock = NSLock()
    private var matrix: WyrmLookMatrix?

    func set(_ look: WyrmTrailLook, _ adjust: WyrmTrailAdjust) {
        let next = WyrmTrailLooks.isIdentity(look, adjust) ? nil : WyrmTrailLooks.matrix(look, adjust)
        lock.lock(); matrix = next; lock.unlock()
    }

    func apply(_ image: CIImage) -> CIImage {
        lock.lock(); let current = matrix; lock.unlock()
        guard let current else { return image }
        return WyrmTrailLooks.apply(image, current)
    }
}

/// Looks and Adjust (OM, 2026-10-05): the filter strip, each swatch the
/// picture itself in that look, and four sliders. A video takes the same look.
/// Android: `LooksPanel` in `ui/TrailStudio.kt`.
struct WyrmTrailLooksPanel: View {
    @Binding var look: WyrmTrailLook
    @Binding var adjust: WyrmTrailAdjust
    /// A small frame of the picture or the clip, for the swatches.
    let sample: UIImage?
    let done: () -> Void
    @State private var adjusting = false
    @State private var swatches: [String: UIImage] = [:]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                WyrmStudioChip(label: "Looks", selected: !adjusting) { adjusting = false }
                WyrmStudioChip(label: "Adjust", selected: adjusting) { adjusting = true }
                Spacer()
                if !WyrmTrailLooks.isIdentity(look, adjust) {
                    WyrmStudioChip(label: "Reset", selected: false) { look = WyrmTrailLooks.normal; adjust = WyrmTrailAdjust() }
                }
                WyrmStudioChip(label: "Done", selected: true, action: done)
            }
            .padding(.horizontal, 16)
            if !adjusting {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WyrmTrailLooks.all) { item in
                            let selected = look == item
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                look = item
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        ATheme.well
                                        if let image = swatches[item.name] {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        }
                                    }
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(ATheme.ink, lineWidth: selected ? 2.5 : 0))
                                    Text(item.name).font(.androidWyrm(10.5, selected ? .bold : .medium))
                                        .foregroundColor(selected ? ATheme.ink : ATheme.mute)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                VStack(spacing: 2) {
                    row("Brightness", adjust.brightness) { adjust.brightness = $0 }
                    row("Contrast", adjust.contrast) { adjust.contrast = $0 }
                    row("Saturation", adjust.saturation) { adjust.saturation = $0 }
                    row("Warmth", adjust.warmth) { adjust.warmth = $0 }
                }
                .padding(.horizontal, 20)
            }
        }
        .task(id: sample.map { ObjectIdentifier($0) }) { await makeSwatches() }
    }

    private func row(_ label: String, _ value: Float, _ change: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.androidWyrm(11.5, .semibold)).foregroundColor(ATheme.mute).frame(width: 78, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { change(Float(($0 * 20).rounded() / 20)) }), in: -1...1)
                .tint(ATheme.ink)
            Text("\(Int((value * 100).rounded()))").font(.androidWyrm(11)).monospacedDigit().foregroundColor(ATheme.quiet)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(height: 28)
    }

    private func makeSwatches() async {
        guard let sample else { return }
        let made = await Task.detached(priority: .userInitiated) { () -> [String: UIImage] in
            let small = WyrmTrailLooks.apply(sample, WyrmTrailLooks.normal, WyrmTrailAdjust(), longest: 140)
            var out: [String: UIImage] = [:]
            for item in WyrmTrailLooks.all { out[item.name] = WyrmTrailLooks.apply(small, item, WyrmTrailAdjust()) }
            return out
        }.value
        swatches = made
    }
}
