import SwiftUI
import UIKit
import AVFoundation
import Photos

/*
 * The Trails studio (OM, 2026-09-28): where a trail is made.
 *
 *   Photo   — live camera on top, recent photos below. A picked or taken photo
 *             opens in the editor: crop, text, drawing.
 *   Text    — words only; posted as a text trail.
 *   Canvas  — a plain colour to write and draw on.
 *
 * The editor draws on screen and exports with the same code, so the posted
 * image is exactly what the player saw: `WyrmStudioInk.draw` paints strokes,
 * `WyrmStudioText.draw` paints text, `WyrmStudioDraft.photoRect` places the
 * photo. Wyrm's own brush is Beads: a stroke laid down as a snake of beads.
 * Android mirrors this file in `ui/TrailStudio.kt`.
 */

// MARK: - Palette and fonts

enum WyrmStudioPalette {
    static let colours: [UInt32] = [
        0xFFFFFF, 0x111111, 0xF2B84B, 0xFF5E5B, 0xFF8FC0, 0xAA7DF0,
        0x3D5AFE, 0x00B8D9, 0x2FA45E, 0xB8F2E6, 0xF6E4C4, 0x1E2F5C,
    ]
    static func ui(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
    static func color(_ rgb: UInt32) -> Color { Color(ui(rgb)) }
    /// Dark text on light colours, light text on dark ones.
    static func contrast(_ rgb: UInt32) -> UInt32 {
        let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 150 ? 0x111111 : 0xFFFFFF
    }
    /// The studio's colours and then the theme's own: Share run's backgrounds.
    static var withTheme: [UInt32] {
        var list = colours
        for colour in [ATheme.paper, ATheme.card, ATheme.ink, ATheme.live] {
            let value = Self.rgb(of: UIColor(colour))
            if !list.contains(value) { list.append(value) }
        }
        return list
    }
    static func rgb(of colour: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32(min(max((v * 255).rounded(), 0), 255)) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}

enum WyrmStudioFont: String, CaseIterable {
    case sans, serif
    func ui(_ size: CGFloat) -> UIFont {
        let family = self == .sans ? "Manrope" : "Bodoni Moda"
        let weight: UIFont.Weight = self == .sans ? .bold : .semibold
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family, .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        return font.familyName == family ? font : UIFont.systemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Model

enum WyrmStudioBrush: String, CaseIterable { case pen, marker, beads }

struct WyrmStudioStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var rgb: UInt32
    var width: CGFloat
    var brush: WyrmStudioBrush
}

struct WyrmStudioText: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var rgb: UInt32
    var font: WyrmStudioFont
    var filled: Bool
    var center: CGPoint
    var scale: CGFloat = 1
    var rotation: Angle = .zero

    static let baseSize: CGFloat = 30
    static let maxWidth: CGFloat = 250

    private var attributed: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: font.ui(Self.baseSize),
            .foregroundColor: WyrmStudioPalette.ui(filled ? WyrmStudioPalette.contrast(rgb) : rgb),
            .paragraphStyle: style,
        ])
    }

    /// The item's own size in canvas points, before its scale and rotation.
    var size: CGSize {
        let box = attributed.boundingRect(with: CGSize(width: Self.maxWidth, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let pad: CGFloat = filled ? 14 : 4
        return CGSize(width: ceil(box.width) + pad * 2, height: ceil(box.height) + pad * 1.4)
    }

    /// Paints the item centred on the context's origin.
    func draw(in cg: CGContext) {
        let s = size
        let rect = CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height)
        UIGraphicsPushContext(cg)
        if filled {
            WyrmStudioPalette.ui(rgb).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: min(16, s.height / 2)).fill()
        } else {
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        }
        let textBox = rect.insetBy(dx: filled ? 14 : 4, dy: filled ? 14 * 0.7 : 4 * 0.7)
        attributed.draw(with: textBox, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        UIGraphicsPopContext()
    }

    /// The item as a crisp image, for the editor.
    func image() -> UIImage {
        let s = size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: s, format: format).image { context in
            context.cgContext.translateBy(x: s.width / 2, y: s.height / 2)
            draw(in: context.cgContext)
        }
    }
}

/// Strokes, the same on screen and in the exported image.
enum WyrmStudioInk {
    static func draw(_ strokes: [WyrmStudioStroke], in cg: CGContext) {
        for stroke in strokes { draw(stroke, in: cg) }
    }

    static func draw(_ stroke: WyrmStudioStroke, in cg: CGContext) {
        guard let first = stroke.points.first else { return }
        let colour = WyrmStudioPalette.ui(stroke.rgb)
        switch stroke.brush {
        case .pen, .marker:
            cg.saveGState()
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(stroke.brush == .marker ? stroke.width * 2.6 : stroke.width)
            cg.setStrokeColor(colour.withAlphaComponent(stroke.brush == .marker ? 0.45 : 1).cgColor)
            if stroke.brush == .marker { cg.setBlendMode(.multiply) }
            cg.beginPath()
            cg.move(to: first)
            if stroke.points.count == 1 {
                cg.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
            } else {
                // Smoothed through the midpoints, so fast strokes stay round.
                for i in 1..<stroke.points.count {
                    let a = stroke.points[i - 1], b = stroke.points[i]
                    cg.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
                }
                cg.addLine(to: stroke.points[stroke.points.count - 1])
            }
            cg.strokePath()
            cg.restoreGState()
        case .beads:
            // Wyrm's brush: beads laid along the path like a snake's body, each
            // lit from the top left, head last.
            let radius = stroke.width * 1.1
            let spacing = radius * 1.35
            var beads: [CGPoint] = [first]
            var carry: CGFloat = 0
            for i in 1..<max(stroke.points.count, 1) {
                let a = stroke.points[i - 1], b = stroke.points[i]
                let length = hypot(b.x - a.x, b.y - a.y)
                var travelled = spacing - carry
                while travelled <= length {
                    let t = travelled / max(length, 0.0001)
                    beads.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                    travelled += spacing
                }
                carry = length - (travelled - spacing)
            }
            let light = colour.blended(with: .white, 0.6)
            let dark = colour.blended(with: .black, 0.35)
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: [light.cgColor, colour.cgColor, dark.cgColor] as CFArray,
                                            locations: [0, 0.55, 1]) else { return }
            for (index, point) in beads.enumerated() {
                let r = index == beads.count - 1 ? radius * 1.25 : radius
                cg.saveGState()
                cg.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
                cg.clip()
                cg.drawRadialGradient(gradient, startCenter: CGPoint(x: point.x - r * 0.35, y: point.y - r * 0.35), startRadius: 0,
                                      endCenter: point, endRadius: r, options: [.drawsAfterEndLocation])
                cg.restoreGState()
            }
            if beads.count > 1, let head = beads.last {
                // Two eyes on the last bead, looking along the stroke.
                let prev = beads[beads.count - 2]
                let angle = atan2(head.y - prev.y, head.x - prev.x)
                let r = radius * 1.25
                for side in [-1.0, 1.0] {
                    let eye = CGPoint(x: head.x + cos(angle + side * 0.7) * r * 0.5, y: head.y + sin(angle + side * 0.7) * r * 0.5)
                    cg.setFillColor(UIColor.white.cgColor)
                    cg.fillEllipse(in: CGRect(x: eye.x - r * 0.28, y: eye.y - r * 0.28, width: r * 0.56, height: r * 0.56))
                    cg.setFillColor(UIColor.black.cgColor)
                    cg.fillEllipse(in: CGRect(x: eye.x - r * 0.14, y: eye.y - r * 0.14, width: r * 0.28, height: r * 0.28))
                }
            }
        }
    }
}

private extension UIColor {
    func blended(with other: UIColor, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}

enum WyrmStudioAspect: String, CaseIterable, Identifiable {
    case original = "Original", free = "Free", square = "1:1", portrait = "4:5", wide = "16:9"
    var id: String { rawValue }
    func ratio(for image: UIImage?) -> CGFloat {
        switch self {
        case .square: return 1
        case .portrait: return 0.8
        case .wide: return 16.0 / 9.0
        case .original, .free:
            guard let image, image.size.height > 0 else { return 0.8 }
            return min(max(image.size.width / image.size.height, 0.8), 1.91)
        }
    }
}

enum WyrmStudioMode: String, CaseIterable { case photo = "Photo", text = "Text", canvas = "Canvas" }

@MainActor
final class WyrmStudioDraft: ObservableObject {
    @Published var mode: WyrmStudioMode = .photo
    @Published var image: UIImage?
    @Published var background: UInt32 = 0x1E2F5C
    @Published var aspect: WyrmStudioAspect = .original
    @Published var photoScale: CGFloat = 1
    @Published var photoOffset: CGSize = .zero
    @Published var strokes: [WyrmStudioStroke] = []
    @Published var texts: [WyrmStudioText] = []
    @Published var caption = ""
    /// The Free crop's shape, set by dragging the canvas edges.
    @Published var freeRatio: CGFloat = 0.8

    // Share run (OM, 2026-09-30): the studio's share mode. Everything below
    // is unused for an ordinary trail (`run` nil).

    /// The finished run being shared.
    @Published var run: WyrmLastRun?
    /// Screenshot (the death picture behind everything) or Skin (a colour).
    @Published var shotMode = false
    @Published var shotScale: CGFloat = 1
    @Published var shotOffset: CGSize = .zero
    @Published var stickers: [WyrmStudioSticker] = []
    /// "Share my skin" on the caption step, on by default (OM).
    @Published var shareSkin = true
    /// The player's look when the studio opened: the skin sticker and the
    /// post's `skin`.
    let skin: WyrmTrailSkin?
    /// The Skin tab's textures, for the skin sticker; set by the studio.
    var textures: WyrmSkinTextureLibrary? {
        didSet {
            art = textures.map { WyrmStickerArt(textures: $0) }
            stickerImages["skin"] = nil
            // Textures that were already loaded bring no change of their own.
            objectWillChange.send()
        }
    }
    private(set) var art: WyrmStickerArt?
    /// The player picked Skin or Screenshot, so a late picture changes nothing.
    private var modeChosen = false
    private var seeded = false
    private var stickerImages: [String: UIImage] = [:]

    init(run: WyrmLastRun? = nil) {
        skin = run == nil ? nil : WyrmTrailSkin.current()
        self.run = run
        if let run {
            aspect = .portrait
            shotMode = run.screenshot != nil
        }
    }

    var sharing: Bool { run != nil }

    var ratio: CGFloat {
        if aspect == .free { return freeRatio }
        if sharing { return aspect.ratio(for: shotMode ? run?.screenshot : nil) }
        return mode == .canvas ? (aspect == .original ? 0.8 : aspect.ratio(for: nil)) : aspect.ratio(for: image)
    }

    /// Where the screenshot sits: covering the canvas, then the player's zoom
    /// and move. It may shrink inside the canvas; the colour shows round it.
    func shotRect(in size: CGSize) -> CGRect {
        guard let shot = run?.screenshot, shot.size.width > 0, shot.size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let fill = max(size.width / shot.size.width, size.height / shot.size.height)
        let w = shot.size.width * fill * shotScale
        let h = shot.size.height * fill * shotScale
        return CGRect(x: (size.width - w) / 2 + shotOffset.width, y: (size.height - h) / 2 + shotOffset.height, width: w, height: h)
    }

    /// Keeps a piece of the screenshot on the canvas after a move or zoom.
    func clampShot(in size: CGSize) {
        let rect = shotRect(in: size)
        let limitX = max(0, (size.width + rect.width) / 2 - 48)
        let limitY = max(0, (size.height + rect.height) / 2 - 48)
        shotOffset = CGSize(width: min(max(shotOffset.width, -limitX), limitX), height: min(max(shotOffset.height, -limitY), limitY))
    }

    /// Skin or Screenshot. The first switch to Skin brings the skin sticker.
    func setShotMode(_ on: Bool, canvas size: CGSize) {
        guard on != shotMode, !on || run?.screenshot != nil else { return }
        modeChosen = true
        shotMode = on
        if !on && !stickers.contains(where: { $0.kind == .skin }) && !skinAdded { addSticker(.skin, in: size) }
    }
    private var skinAdded = false

    /// A death picture that landed after the studio opened.
    func adopt(_ latest: WyrmLastRun?) {
        guard let latest, latest.screenshot != nil, run?.screenshot == nil, latest.endedAt == run?.endedAt else { return }
        run = latest
        if !modeChosen { shotMode = true }
    }

    /// The first layout: the stats box always, the skin sticker in Skin mode.
    func seedShare(in size: CGSize) {
        guard sharing, !seeded, size.width > 0, size.height > 0 else { return }
        seeded = true
        if !shotMode { addSticker(.skin, in: size) }
        addSticker(.stats, in: size)
    }

    func addSticker(_ kind: WyrmStudioSticker.Kind, in size: CGSize) {
        guard sharing, !stickers.contains(where: { $0.kind == kind }), size.width > 0 else { return }
        if kind == .skin { skinAdded = true }
        var sticker = WyrmStudioSticker(kind: kind, center: CGPoint(x: size.width / 2, y: size.height * (kind == .skin ? 0.42 : 0.78)))
        let natural = stickerSize(sticker)
        sticker.scale = min(1, size.width * (kind == .skin ? 0.8 : 0.84) / max(natural.width, 1))
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) { stickers.append(sticker) }
    }

    func removeSticker(_ id: UUID) { stickers.removeAll { $0.id == id } }

    /// The stats box's look: tap cycles, the strip picks.
    func setStatsStyle(_ style: Int) {
        guard let i = stickers.firstIndex(where: { $0.kind == .stats }) else { return }
        let count = WyrmStatsBox.styles.count
        stickers[i].style = ((style % count) + count) % count
    }

    func cycleStatsStyle() {
        guard let stats = stickers.first(where: { $0.kind == .stats }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        setStatsStyle(stats.style + 1)
    }

    func statsBox(_ style: Int) -> WyrmStatsBox? {
        guard let run else { return nil }
        return WyrmStatsBox(style: style, score: run.score, kills: run.kills, seconds: run.seconds)
    }

    /// A sticker's own size in canvas points, before its scale and rotation.
    func stickerSize(_ sticker: WyrmStudioSticker) -> CGSize {
        switch sticker.kind {
        case .skin: return WyrmSkinSticker.size
        case .stats: return statsBox(sticker.style)?.size ?? CGSize(width: 200, height: 80)
        }
    }

    /// The sticker as the editor shows it; nil while the skin's textures load.
    func stickerImage(_ sticker: WyrmStudioSticker) -> UIImage? {
        switch sticker.kind {
        case .skin:
            guard let skin, let art, art.textures.ready else { return nil }
            if let hit = stickerImages["skin"] { return hit }
            let made = WyrmSkinSticker.image(skin, art: art)
            stickerImages["skin"] = made
            return made
        case .stats:
            let key = "stats-\(sticker.style)"
            if let hit = stickerImages[key] { return hit }
            guard let made = statsBox(sticker.style)?.image() else { return nil }
            stickerImages[key] = made
            return made
        }
    }

    /// Paints a sticker centred on the context's origin, in canvas points.
    func drawSticker(_ sticker: WyrmStudioSticker, in cg: CGContext) {
        switch sticker.kind {
        case .skin: if let skin, let art { WyrmSkinSticker.draw(skin, art: art, in: cg) }
        case .stats: statsBox(sticker.style)?.draw(in: cg)
        }
    }

    /// Keeps stickers and words on a canvas that changed shape.
    func keepItems(in size: CGSize) {
        guard sharing, size.width > 0, size.height > 0 else { return }
        func inside(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height)) }
        for i in stickers.indices where inside(stickers[i].center) != stickers[i].center { stickers[i].center = inside(stickers[i].center) }
        for i in texts.indices where inside(texts[i].center) != texts[i].center { texts[i].center = inside(texts[i].center) }
    }

    func reset(for mode: WyrmStudioMode) {
        self.mode = mode
        image = nil
        aspect = mode == .canvas ? .portrait : .original
        photoScale = 1
        photoOffset = .zero
        strokes = []
        texts = []
    }

    /// Where the photo sits in a canvas of `size`: filling it, then the
    /// player's zoom and pan.
    func photoRect(in size: CGSize) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let fill = max(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * fill * photoScale
        let h = image.size.height * fill * photoScale
        return CGRect(x: (size.width - w) / 2 + photoOffset.width, y: (size.height - h) / 2 + photoOffset.height, width: w, height: h)
    }

    /// Keeps the photo covering the canvas after a pan or zoom.
    func clampOffset(in size: CGSize) {
        let rect = photoRect(in: CGSize(width: size.width, height: size.height))
        let maxX = max(0, (rect.width - size.width) / 2)
        let maxY = max(0, (rect.height - size.height) / 2)
        photoOffset = CGSize(width: min(max(photoOffset.width, -maxX), maxX), height: min(max(photoOffset.height, -maxY), maxY))
    }

    /// The finished picture, 1440 px wide, drawn by the same code as the editor.
    func render(canvas size: CGSize) -> UIImage {
        let k = 1440 / max(size.width, 1)
        let out = CGSize(width: 1440, height: (size.height * k).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: out, format: format).image { context in
            let cg = context.cgContext
            if sharing {
                // Share run: the colour, the screenshot over it, then the
                // stickers; strokes and words go on top as in any trail.
                WyrmStudioPalette.ui(background).setFill()
                cg.fill(CGRect(origin: .zero, size: out))
                if shotMode, let shot = run?.screenshot {
                    let r = shotRect(in: size)
                    shot.draw(in: CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k))
                }
                for sticker in stickers {
                    cg.saveGState()
                    cg.translateBy(x: sticker.center.x * k, y: sticker.center.y * k)
                    cg.rotate(by: CGFloat(sticker.rotation.radians))
                    cg.scaleBy(x: sticker.scale * k, y: sticker.scale * k)
                    drawSticker(sticker, in: cg)
                    cg.restoreGState()
                }
            } else if let image {
                UIColor.black.setFill()
                cg.fill(CGRect(origin: .zero, size: out))
                let r = photoRect(in: size)
                image.draw(in: CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k))
            } else {
                WyrmStudioPalette.ui(background).setFill()
                cg.fill(CGRect(origin: .zero, size: out))
            }
            cg.saveGState()
            cg.scaleBy(x: k, y: k)
            WyrmStudioInk.draw(strokes, in: cg)
            cg.restoreGState()
            for item in texts {
                cg.saveGState()
                cg.translateBy(x: item.center.x * k, y: item.center.y * k)
                cg.rotate(by: CGFloat(item.rotation.radians))
                cg.scaleBy(x: item.scale * k, y: item.scale * k)
                item.draw(in: cg)
                cg.restoreGState()
            }
        }
    }
}

// MARK: - Camera

final class WyrmTrailCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum State { case idle, running, denied, unavailable }
    @Published private(set) var state: State = .idle
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "wyrm.trails.camera")
    private var configured = false
    private var position: AVCaptureDevice.Position = .back
    private var onPhoto: ((UIImage?) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { if granted { self.run() } else { self.state = .denied } }
            }
        default: state = .denied
        }
    }

    private func run() {
        queue.async {
            if !self.configured { self.configure() }
            guard self.configured else { DispatchQueue.main.async { self.state = .unavailable }; return }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.state = .running }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        configured = true
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func flip() {
        queue.async {
            guard self.configured else { return }
            let next: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            for old in self.session.inputs { self.session.removeInput(old) }
            if self.session.canAddInput(input) { self.session.addInput(input); self.position = next }
            self.session.commitConfiguration()
        }
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        guard state == .running else { done(nil); return }
        onPhoto = done
        queue.async { self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        if position == .front, let shot = image, let cg = shot.cgImage {
            image = UIImage(cgImage: cg, scale: shot.scale, orientation: .leftMirrored)
        }
        DispatchQueue.main.async {
            self.onPhoto?(image)
            self.onPhoto = nil
        }
    }
}

struct WyrmCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
}

// MARK: - Gallery

@MainActor
final class WyrmTrailGallery: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    let manager = PHCachingImageManager()

    func load() {
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { next in
                Task { @MainActor in self.status = next; self.fetch() }
            }
        } else { fetch() }
    }

    private func fetch() {
        guard status == .authorized || status == .limited else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 300
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
    }

    func full(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            manager.requestImage(for: asset, targetSize: CGSize(width: 2400, height: 2400), contentMode: .aspectFit,
                                 options: options) { image, _ in continuation.resume(returning: image) }
        }
    }
}

private struct WyrmGalleryCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    @State private var image: UIImage?
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { ATheme.well } })
            .clipped()
            .onAppear {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = true
                manager.requestImage(for: asset, targetSize: CGSize(width: 260, height: 260), contentMode: .aspectFill,
                                     options: options) { picked, _ in if let picked { image = picked } }
            }
    }
}

// MARK: - System camera

/// The phone's own camera, full screen; photos only for now (video is off).
struct WyrmSystemCamera: UIViewControllerRepresentable {
    let onShot: (UIImage?) -> Void
    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onShot: onShot) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onShot: (UIImage?) -> Void
        init(onShot: @escaping (UIImage?) -> Void) { self.onShot = onShot }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onShot(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onShot(nil) }
    }
}

// MARK: - Studio

struct WyrmTrailStudio: View {
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    /// Share run: the finished run to share. The studio then opens straight
    /// in its share editor (no camera, no photos) and `onPosted` replaces
    /// `close` after Post.
    let run: WyrmLastRun?
    let onPosted: (() -> Void)?
    @StateObject private var draft: WyrmStudioDraft
    @StateObject private var camera = WyrmTrailCamera()
    @StateObject private var gallery = WyrmTrailGallery()
    /// The skin sticker's textures (shared with the Skin tab while both live).
    @StateObject private var textures = WyrmSkinTextureLibrary.acquire()
    @ObservedObject private var store = WyrmTrailsStore.shared
    @State private var step: Step
    @State private var picking = false
    @State private var systemCamera = false
    @State private var loadingPhoto = false
    @State private var canvasSize: CGSize = .zero
    @State private var rendered: UIImage?
    @State private var forward = true

    enum Step { case pick, edit, caption }

    init(account: WyrmAccountStore, close: @escaping () -> Void, run: WyrmLastRun? = nil,
         onPosted: (() -> Void)? = nil) {
        self.account = account
        self.close = close
        self.run = run
        self.onPosted = onPosted
        _draft = StateObject(wrappedValue: WyrmStudioDraft(run: run))
        _step = State(initialValue: run == nil ? .pick : .edit)
    }

    /// One number per page, so a change slides the right way.
    private var page: Int {
        switch step {
        case .pick: return WyrmStudioMode.allCases.firstIndex(of: draft.mode) ?? 0
        case .edit: return 3
        case .caption: return 4
        }
    }

    var body: some View {
        ZStack {
            ATheme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                // The mode pill sits here, in one place, for every mode; only
                // the page under it moves.
                if step == .pick { modeBar.padding(.bottom, 12) }
                if step == .edit && draft.sharing { shareModeBar.padding(.bottom, 10) }
                ZStack {
                    content
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .foregroundColor(ATheme.ink)
        .onAppear {
            store.token = { [weak account] in account?.sessionToken ?? "" }
            store.resetPosting()
            if draft.sharing {
                // Share run needs no camera or photos, only the skin's textures.
                draft.textures = textures
                textures.prepare()
                WyrmKeyboardController.shared.embedded = false
            } else {
                camera.start()
                gallery.load()
            }
        }
        .onDisappear { camera.stop() }
        .onChange(of: run?.screenshot != nil) { _ in draft.adopt(run) }
        .sheet(isPresented: $picking) {
            WyrmPhotoPicker { picked in
                picking = false
                if let picked { open(picked) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $systemCamera) {
            WyrmSystemCamera { shot in
                systemCamera = false
                if let shot { open(shot) } else { camera.start() }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .caption: captionStep
        case .edit: WyrmStudioEditor(draft: draft, canvasSize: $canvasSize, textures: textures)
        case .pick:
            switch draft.mode {
            case .photo: picker
            case .text: WyrmTextTrailComposer(draft: draft)
            case .canvas: WyrmStudioEditor(draft: draft, canvasSize: $canvasSize, textures: textures)
            }
        }
    }

    private func go(_ next: Step) {
        let before = page
        let target: Int = next == .pick ? (WyrmStudioMode.allCases.firstIndex(of: draft.mode) ?? 0) : (next == .edit ? 3 : 4)
        forward = target >= before
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { step = next }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { back() } label: {
                Image(systemName: step == .pick || (draft.sharing && step == .edit) ? "xmark" : "chevron.left")
                    .font(.system(size: 16, weight: .bold)).frame(width: 38, height: 38)
                    .background(Circle().fill(ATheme.well))
            }.buttonStyle(.plain)
            Spacer()
            Text(step == .pick ? "New trail" : step == .edit ? (draft.sharing ? "Share run" : "Edit") : "Caption")
                .font(.androidWyrm(16, .bold))
            Spacer()
            actionButton
        }
        .padding(.horizontal, 14).frame(height: 56)
    }

    @ViewBuilder
    private var actionButton: some View {
        let ready: Bool = {
            switch step {
            case .pick: return draft.mode == .text ? !draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : draft.mode == .canvas
            // Share run waits for the skin sticker's textures before export.
            case .edit: return !(draft.sharing && draft.stickers.contains(where: { $0.kind == .skin }) && !textures.ready)
            case .caption: return !store.posting.busy
            }
        }()
        let label = (step == .caption || (step == .pick && draft.mode == .text)) ? "Post" : "Next"
        Button { advance() } label: {
            Text(label).font(.androidWyrm(14, .bold)).foregroundColor(ATheme.onInk)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Capsule().fill(ATheme.ink.opacity(ready ? 1 : 0.3)))
        }
        .buttonStyle(WSPressStyle())
        .disabled(!ready)
    }

    private var modeBar: some View {
        WSSegmented(options: WyrmStudioMode.allCases.map(\.rawValue),
                    selected: WyrmStudioMode.allCases.firstIndex(of: draft.mode) ?? 0) { index in
            let next = WyrmStudioMode.allCases[index]
            guard next != draft.mode else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            forward = index > (WyrmStudioMode.allCases.firstIndex(of: draft.mode) ?? 0)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { draft.reset(for: next) }
            if next == .photo { camera.start() } else { camera.stop() }
        }
        .padding(.horizontal, 16)
    }

    /// Share run: Skin | Screenshot. Screenshot is off when the run has no picture.
    private var shareModeBar: some View {
        let hasShot = draft.run?.screenshot != nil
        return VStack(spacing: 6) {
            HStack(spacing: 3) {
                shareSegment("Skin", selected: !draft.shotMode, enabled: true) {
                    draft.setShotMode(false, canvas: canvasSize)
                }
                shareSegment("Screenshot", selected: draft.shotMode, enabled: hasShot) {
                    draft.setShotMode(true, canvas: canvasSize)
                }
            }
            .padding(3)
            .background(Capsule().fill(ATheme.well))
            if !hasShot {
                Text("No screenshot for this run").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
            }
        }
        .padding(.horizontal, 16)
    }

    private func shareSegment(_ label: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled, !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { action() }
        } label: {
            Text(label).font(.androidWyrm(13.5, .bold))
                .foregroundColor(selected ? ATheme.onInk : ATheme.ink)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Capsule().fill(selected ? ATheme.ink : Color.clear))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func back() {
        switch step {
        case .pick: close()
        case .edit:
            // Share run opens on its editor, so back is close.
            if draft.sharing { close(); return }
            if draft.mode == .photo { draft.image = nil; camera.start() }
            go(.pick)
        case .caption: go(draft.mode == .canvas ? .pick : .edit)
        }
    }

    private func advance() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        switch step {
        case .pick:
            if draft.mode == .text { post(image: nil) }
            else if draft.mode == .canvas { rendered = draft.render(canvas: canvasSize); go(.caption) }
        case .edit:
            rendered = draft.render(canvas: canvasSize)
            go(.caption)
        case .caption: post(image: rendered ?? draft.render(canvas: canvasSize))
        }
    }

    private func post(image: UIImage?) {
        guard !store.posting.busy else { return }
        let caption = draft.caption
        // Share run: the player's look goes along only with Share my skin on.
        let share = draft.sharing && draft.shareSkin && draft.skin != nil
        let skin = share ? draft.skin : nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { _ = await store.post(image: image, caption: caption, skin: skin, shareSkin: share) }
        if let onPosted { onPosted() } else { close() }
    }

    private func open(_ image: UIImage) {
        draft.reset(for: .photo)
        draft.image = image
        camera.stop()
        go(.edit)
    }

    // MARK: Pick (camera and gallery)

    private var picker: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    switch camera.state {
                    case .running: WyrmCameraPreview(session: camera.session)
                    case .denied: cameraNote("Camera is off for Wyrm", "Allow it in Settings, or use the phone's camera.")
                    case .unavailable: cameraNote("No camera", "Pick a photo from your library below.")
                    case .idle: ATheme.well
                    }
                }
                .frame(maxWidth: .infinity).aspectRatio(0.8, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack {
                    HStack {
                        Spacer()
                        if WyrmSystemCamera.available {
                            // Full screen: the phone's own camera.
                            WyrmStudioRoundButton(symbol: "arrow.up.left.and.arrow.down.right") {
                                camera.stop()
                                systemCamera = true
                            }
                        }
                    }
                    Spacer()
                    if camera.state == .running {
                        HStack {
                            Spacer().frame(width: 44)
                            Spacer()
                            Button {
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                camera.capture { shot in if let shot { open(shot) } }
                            } label: {
                                Circle().stroke(Color.white, lineWidth: 5).frame(width: 70, height: 70)
                                    .overlay(Circle().fill(Color.white.opacity(0.9)).padding(9))
                            }.buttonStyle(WSPressStyle())
                            Spacer()
                            WyrmStudioRoundButton(symbol: "arrow.triangle.2.circlepath") { camera.flip() }
                        }
                    }
                }
                .padding(14)
            }
            .aspectRatio(0.8, contentMode: .fit)
            .padding(.horizontal, 12)
            galleryGrid.padding(.top, 10)
        }
    }

    private func cameraNote(_ title: String, _ note: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "camera").font(.system(size: 26, weight: .semibold)).foregroundColor(ATheme.quiet)
            Text(title).font(.androidWyrm(15, .bold))
            Text(note).font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(ATheme.well)
    }

    private var galleryGrid: some View {
        ScrollView(showsIndicators: false) {
            if gallery.status == .authorized || gallery.status == .limited {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                    Button { picking = true } label: {
                        ZStack {
                            ATheme.well
                            VStack(spacing: 4) {
                                Image(systemName: "photo.on.rectangle").font(.system(size: 18, weight: .semibold))
                                Text("All photos").font(.androidWyrm(10.5, .bold))
                            }.foregroundColor(ATheme.mute)
                        }.aspectRatio(1, contentMode: .fit)
                    }.buttonStyle(.plain)
                    ForEach(gallery.assets, id: \.localIdentifier) { asset in
                        Button {
                            guard !loadingPhoto else { return }
                            loadingPhoto = true
                            Task {
                                if let image = await gallery.full(asset) { open(image) }
                                loadingPhoto = false
                            }
                        } label: { WyrmGalleryCell(asset: asset, manager: gallery.manager) }
                            .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
            } else {
                VStack(spacing: 10) {
                    Text("Your photos").font(.androidWyrm(15, .bold))
                    Text("Allow Wyrm to show your photos here, or pick one from the library.")
                        .font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
                    WSPrimaryButton(label: "Choose a photo") { picking = true }
                }
                .padding(20)
            }
            Spacer().frame(height: 40)
        }
        .overlay(Group { if loadingPhoto { ProgressView().padding(14).background(Circle().fill(ATheme.card)) } })
    }

    // MARK: Caption

    private var captionStep: some View {
        WyrmStudioCaption(draft: draft, rendered: rendered)
    }
}

/// A round dark glass button on top of the picture.
struct WyrmStudioRoundButton: View {
    var symbol: String? = nil
    var text: String? = nil
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: 16, weight: .bold)) }
                else { Text(text ?? "").font(.androidWyrm(16, .bold)) }
            }
            .foregroundColor(on ? .black : .white)
            .frame(width: 42, height: 42)
            .background(Circle().fill(on ? Color.white : Color.black.opacity(0.42)))
            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(WSPressStyle())
    }
}

/// A text trail: the page opens with the keyboard up.
private struct WyrmTextTrailComposer: View {
    @ObservedObject var draft: WyrmStudioDraft
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if draft.caption.isEmpty {
                    Text("Leave a thought…").font(.wyrmDisplay(28)).foregroundColor(ATheme.quiet)
                        .padding(.horizontal, 6).padding(.vertical, 10)
                }
                TextEditor(text: $draft.caption)
                    .font(.wyrmDisplay(28))
                    .focused($focused)
                    .onAppear { UITextView.appearance().backgroundColor = .clear }
                    .onChange(of: draft.caption) { value in if value.count > 500 { draft.caption = String(value.prefix(500)) } }
            }
            .padding(14)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .padding(.horizontal, 14)
            Text("\(draft.caption.count)/500").font(.androidWyrm(11)).monospacedDigit().foregroundColor(ATheme.quiet)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 20).padding(.vertical, 10)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }
}

private struct WyrmStudioCaption: View {
    @ObservedObject var draft: WyrmStudioDraft
    let rendered: UIImage?
    @FocusState private var focused: Bool
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(uiImage: rendered ?? UIImage()).resizable().scaledToFit()
                        .frame(width: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    ZStack(alignment: .topLeading) {
                        if draft.caption.isEmpty {
                            Text("Write a caption…").font(.androidWyrm(15)).foregroundColor(ATheme.quiet)
                                .padding(.horizontal, 5).padding(.vertical, 8)
                        }
                        TextEditor(text: $draft.caption)
                            .font(.androidWyrm(15)).frame(minHeight: 140)
                            .focused($focused)
                            .onAppear { UITextView.appearance().backgroundColor = .clear }
                            .onChange(of: draft.caption) { value in if value.count > 500 { draft.caption = String(value.prefix(500)) } }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .padding(.horizontal, 14).padding(.top, 8)
                Text("\(draft.caption.count)/500").font(.androidWyrm(11)).monospacedDigit().foregroundColor(ATheme.quiet)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 20).padding(.top, 6)
                if draft.sharing {
                    // Share run: whether others may try the player's skin from this post.
                    WSBoolRow(title: "Share my skin",
                              detail: "Others can try your skin from this post. Turn it off to keep it to yourself.",
                              on: draft.shareSkin, first: true) { draft.shareSkin = $0 }
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                        .padding(.horizontal, 14).padding(.top, 14)
                }
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }
}

// MARK: - Editor

/// What the editor is doing: nothing (move and pinch), writing, drawing or cropping.
private enum WyrmStudioTool { case none, text, draw, crop }

/// The editor, story-style: the picture fills the page, tools stand in a rail
/// on its right edge (Aa, draw, crop, undo), and each tool takes the whole
/// screen while it is in use. Text is dragged, pinched and turned in place and
/// thrown into the bin at the bottom to delete it.
private struct WyrmStudioEditor: View {
    @ObservedObject var draft: WyrmStudioDraft
    @Binding var canvasSize: CGSize
    /// Share run's skin sticker appears once these are ready.
    @ObservedObject var textures: WyrmSkinTextureLibrary
    @State private var tool: WyrmStudioTool = .none
    @State private var brush: WyrmStudioBrush = .beads
    @State private var inkRGB: UInt32 = 0xF2B84B
    @State private var live: WyrmStudioStroke?
    @State private var editing: WyrmStudioText?
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var cropStart: CGSize?
    @State private var dragStart: [UUID: CGPoint] = [:]
    @State private var dragging = false
    @State private var overBin = false
    // Share run: where a sticker's move, pinch and turn began, and the
    // screenshot's.
    @State private var stickerDrag: [UUID: CGPoint] = [:]
    @State private var stickerZoom: [UUID: CGFloat] = [:]
    @State private var stickerTurn: [UUID: Angle] = [:]
    @State private var pinching = false
    @State private var shotPan: CGSize?
    @State private var shotZoom: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let bottomBar: CGFloat = (tool == .crop || draft.image == nil) ? 100 : 44
            let width = proxy.size.width - 24
            let maxHeight = proxy.size.height - bottomBar - 8
            let height = min(width / draft.ratio, maxHeight)
            let size = CGSize(width: height * draft.ratio, height: height)
            VStack(spacing: 8) {
                canvas(size, maxWidth: width, maxHeight: maxHeight)
                    .onAppear {
                        canvasSize = size
                        draft.seedShare(in: size)
                    }
                    .onChange(of: size) { next in
                        canvasSize = next
                        draft.seedShare(in: next)
                        draft.keepItems(in: next)
                    }
                bottom.frame(height: bottomBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay { if let current = editing { WyrmStudioTextEditor(item: current, update: { editing = $0 }, done: commit) } }
        }
    }

    // MARK: Canvas

    private func canvas(_ size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let bin = CGPoint(x: size.width / 2, y: size.height - 46)
        return ZStack(alignment: .topLeading) {
            if draft.sharing {
                // Share run: the colour, the screenshot over it, the stickers.
                WyrmStudioPalette.color(draft.background)
                if draft.shotMode, let shot = draft.run?.screenshot {
                    let rect = draft.shotRect(in: size)
                    Image(uiImage: shot).resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
                ForEach(draft.stickers) { sticker in
                    let s = draft.stickerSize(sticker)
                    Group {
                        if let image = draft.stickerImage(sticker) {
                            Image(uiImage: image).resizable()
                        } else {
                            ProgressView().tint(WyrmStudioPalette.color(WyrmStudioPalette.contrast(draft.background)))
                        }
                    }
                    .frame(width: s.width, height: s.height)
                    .contentShape(Rectangle())
                    .scaleEffect(sticker.scale).rotationEffect(sticker.rotation)
                    .position(sticker.center)
                    .gesture(tool == .none ? stickerGesture(sticker.id, size, bin: bin) : nil)
                    .onTapGesture { if tool == .none && sticker.kind == .stats { draft.cycleStatsStyle() } }
                }
            } else if let image = draft.image {
                let rect = draft.photoRect(in: size)
                Color.black
                Image(uiImage: image).resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            } else {
                WyrmStudioPalette.color(draft.background)
            }
            Canvas { context, _ in
                context.withCGContext { cg in
                    WyrmStudioInk.draw(draft.strokes, in: cg)
                    if let live { WyrmStudioInk.draw(live, in: cg) }
                }
            }
            .allowsHitTesting(false)
            if tool == .crop {
                // The rule of thirds while cropping.
                Path { path in
                    for i in 1...2 {
                        let x = size.width * CGFloat(i) / 3, y = size.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false)
            }
            ForEach(draft.texts) { item in
                let s = item.size
                Image(uiImage: item.image()).resizable().frame(width: s.width, height: s.height)
                    .scaleEffect(item.scale).rotationEffect(item.rotation)
                    .position(item.center)
                    .gesture(tool == .none ? textGesture(item.id, size, bin: bin) : nil)
                    .onTapGesture { if tool == .none { editing = item; tool = .text } }
            }
            if dragging {
                Circle().fill(overBin ? Color(red: 0.9, green: 0.28, blue: 0.3) : Color.black.opacity(0.45))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "trash").font(.system(size: 18, weight: .bold)).foregroundColor(.white))
                    .scaleEffect(overBin ? 1.25 : 1)
                    .position(bin)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: overBin)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .gesture(tool == .draw ? drawGesture(size) : nil)
        .simultaneousGesture((tool == .none || tool == .crop) && draft.image != nil ? photoGesture(size) : nil)
        .simultaneousGesture((tool == .none || tool == .crop) && draft.sharing && draft.shotMode ? shotGesture(size) : nil)
        .overlay(alignment: .topTrailing) { rail }
        .overlay(alignment: .top) { if tool == .draw { drawBar } }
        .overlay(alignment: .trailing) { if tool == .draw { inkColumn } }
        .overlay { if tool == .crop && draft.aspect == .free { freeHandles(size, maxWidth: maxWidth, maxHeight: maxHeight) } }
    }

    @ViewBuilder
    private var rail: some View {
        if tool == .none && !dragging {
            VStack(spacing: 10) {
                WyrmStudioRoundButton(text: "Aa") {
                    let rgb: UInt32 = draft.image == nil && !(draft.sharing && draft.shotMode)
                        ? WyrmStudioPalette.contrast(draft.background) : 0xFFFFFF
                    editing = WyrmStudioText(text: "", rgb: rgb, font: .sans, filled: false,
                                             center: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
                    tool = .text
                }
                WyrmStudioRoundButton(symbol: "scribble") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    tool = .draw
                }
                // Share run changes its canvas shape in both of its modes.
                if draft.image != nil || draft.sharing { WyrmStudioRoundButton(symbol: "crop") { tool = .crop } }
                if !draft.strokes.isEmpty { WyrmStudioRoundButton(symbol: "arrow.uturn.backward") { draft.strokes.removeLast() } }
            }
            .padding(10)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
        }
    }

    private var drawBar: some View {
        HStack(spacing: 6) {
            ForEach(WyrmStudioBrush.allCases, id: \.self) { kind in
                WyrmStudioChip(label: kind.rawValue.capitalized, selected: brush == kind, dark: true) { brush = kind }
            }
            Spacer()
            if !draft.strokes.isEmpty { WyrmStudioRoundButton(symbol: "arrow.uturn.backward") { draft.strokes.removeLast() } }
            WyrmStudioChip(label: "Done", selected: true, dark: true) { tool = .none }
        }
        .padding(10)
    }

    private var inkColumn: some View {
        VStack(spacing: 8) {
            ForEach(WyrmStudioPalette.colours, id: \.self) { rgb in
                Button { UISelectionFeedbackGenerator().selectionChanged(); inkRGB = rgb } label: {
                    Circle().fill(WyrmStudioPalette.color(rgb))
                        .frame(width: inkRGB == rgb ? 28 : 22, height: inkRGB == rgb ? 28 : 22)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }.buttonStyle(.plain)
            }
        }
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private var bottom: some View {
        if tool == .crop {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WyrmStudioAspect.allCases) { aspect in
                            WyrmStudioChip(label: aspect.rawValue, selected: draft.aspect == aspect) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if aspect == .free { draft.freeRatio = draft.ratio }
                                    draft.aspect = aspect
                                    draft.photoScale = 1
                                    draft.photoOffset = .zero
                                }
                            }
                        }
                    }.padding(.horizontal, 16)
                }
                WyrmStudioChip(label: "Done", selected: true) { tool = .none }
            }
        } else if draft.sharing && tool == .none {
            shareBottom
        } else if draft.image == nil && tool == .none {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach([WyrmStudioAspect.portrait, .square, .wide]) { aspect in
                        WyrmStudioChip(label: aspect.rawValue, selected: draft.aspect == aspect) {
                            withAnimation(.easeOut(duration: 0.2)) { draft.aspect = aspect }
                        }
                    }
                    Spacer()
                }.padding(.horizontal, 16)
                WyrmStudioSwatches(selected: draft.background) { draft.background = $0 }
            }
        } else if tool == .none {
            Text("Aa to write · draw with the pen · pinch to zoom").font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
        }
    }

    /// Share run: "+ Skin" / "+ Stats" when binned, the stats box's looks,
    /// and the background colours (the studio's and the theme's).
    private var shareBottom: some View {
        let stats = draft.stickers.first { $0.kind == .stats }
        return VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !draft.stickers.contains(where: { $0.kind == .skin }) {
                        WyrmStudioChip(label: "+ Skin", selected: false) { draft.addSticker(.skin, in: canvasSize) }
                    }
                    if let stats {
                        ForEach(WyrmStatsBox.styles.indices, id: \.self) { index in
                            WyrmStudioChip(label: WyrmStatsBox.styles[index], selected: stats.style == index) {
                                UISelectionFeedbackGenerator().selectionChanged()
                                draft.setStatsStyle(index)
                            }
                        }
                    } else {
                        WyrmStudioChip(label: "+ Stats", selected: false) { draft.addSticker(.stats, in: canvasSize) }
                    }
                }
                .padding(.horizontal, 16)
            }
            WyrmStudioSwatches(selected: draft.background, colours: WyrmStudioPalette.withTheme) { draft.background = $0 }
        }
    }

    // MARK: Gestures

    /// Share run: a sticker moves, pinches and turns like words do, and is
    /// thrown into the bin to remove it.
    private func stickerGesture(_ id: UUID, _ size: CGSize, bin: CGPoint) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard let i = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
                    let start = stickerDrag[id] ?? draft.stickers[i].center
                    if stickerDrag[id] == nil { stickerDrag[id] = start }
                    draft.stickers[i].center = CGPoint(x: min(max(start.x + value.translation.width, 0), size.width),
                                                       y: min(max(start.y + value.translation.height, 0), size.height))
                    if !dragging { withAnimation(.easeOut(duration: 0.15)) { dragging = true } }
                    let near = hypot(draft.stickers[i].center.x - bin.x, draft.stickers[i].center.y - bin.y) < 46
                    if near != overBin {
                        overBin = near
                        if near { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    }
                }
                .onEnded { _ in
                    if overBin { withAnimation(.easeOut(duration: 0.2)) { draft.removeSticker(id) } }
                    stickerDrag[id] = nil
                    withAnimation(.easeOut(duration: 0.15)) { dragging = false }
                    overBin = false
                },
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        guard let i = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
                        let start = stickerZoom[id] ?? draft.stickers[i].scale
                        if stickerZoom[id] == nil { stickerZoom[id] = start }
                        pinching = true
                        draft.stickers[i].scale = min(max(start * value, 0.3), 5)
                    }
                    .onEnded { _ in
                        stickerZoom[id] = nil
                        pinching = false
                    },
                RotationGesture()
                    .onChanged { value in
                        guard let i = draft.stickers.firstIndex(where: { $0.id == id }) else { return }
                        let start = stickerTurn[id] ?? draft.stickers[i].rotation
                        if stickerTurn[id] == nil { stickerTurn[id] = start }
                        pinching = true
                        draft.stickers[i].rotation = .radians(start.radians + value.radians)
                    }
                    .onEnded { _ in
                        stickerTurn[id] = nil
                        pinching = false
                    }
            )
        )
    }

    /// Share run's screenshot: dragged and pinched behind the stickers, free
    /// to shrink inside the canvas (the colour shows round it).
    private func shotGesture(_ size: CGSize) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard !dragging, !pinching else { return }
                    let start = shotPan ?? draft.shotOffset
                    if shotPan == nil { shotPan = start }
                    draft.shotOffset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                    draft.clampShot(in: size)
                }
                .onEnded { _ in shotPan = nil },
            MagnificationGesture()
                .onChanged { value in
                    guard !dragging, !pinching else { return }
                    let start = shotZoom ?? draft.shotScale
                    if shotZoom == nil { shotZoom = start }
                    draft.shotScale = min(max(start * value, 0.3), 5)
                    draft.clampShot(in: size)
                }
                .onEnded { _ in shotZoom = nil }
        )
    }

    private func drawGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = CGPoint(x: min(max(value.location.x, 0), size.width), y: min(max(value.location.y, 0), size.height))
                if live == nil {
                    live = WyrmStudioStroke(points: [point], rgb: inkRGB, width: brush == .beads ? 7 : 5, brush: brush)
                } else if let last = live?.points.last, hypot(last.x - point.x, last.y - point.y) > 1.5 {
                    live?.points.append(point)
                }
            }
            .onEnded { _ in
                if let live { draft.strokes.append(live) }
                live = nil
            }
    }

    private func photoGesture(_ size: CGSize) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard !dragging else { return }
                    let start = panStart ?? draft.photoOffset
                    if panStart == nil { panStart = start }
                    draft.photoOffset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                    draft.clampOffset(in: size)
                }
                .onEnded { _ in panStart = nil },
            MagnificationGesture()
                .onChanged { value in
                    let start = zoomStart ?? draft.photoScale
                    if zoomStart == nil { zoomStart = start }
                    draft.photoScale = min(max(start * value, 1), 5)
                    draft.clampOffset(in: size)
                }
                .onEnded { _ in zoomStart = nil }
        )
    }

    private func textGesture(_ id: UUID, _ size: CGSize, bin: CGPoint) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard let i = draft.texts.firstIndex(where: { $0.id == id }) else { return }
                    let start = dragStart[id] ?? draft.texts[i].center
                    if dragStart[id] == nil { dragStart[id] = start }
                    draft.texts[i].center = CGPoint(x: min(max(start.x + value.translation.width, 0), size.width),
                                                    y: min(max(start.y + value.translation.height, 0), size.height))
                    if !dragging { withAnimation(.easeOut(duration: 0.15)) { dragging = true } }
                    let near = hypot(draft.texts[i].center.x - bin.x, draft.texts[i].center.y - bin.y) < 46
                    if near != overBin {
                        overBin = near
                        if near { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    }
                }
                .onEnded { _ in
                    if overBin { draft.texts.removeAll { $0.id == id } }
                    dragStart[id] = nil
                    withAnimation(.easeOut(duration: 0.15)) { dragging = false }
                    overBin = false
                },
            SimultaneousGesture(
                MagnificationGesture().onChanged { value in
                    guard let i = draft.texts.firstIndex(where: { $0.id == id }) else { return }
                    draft.texts[i].scale = min(max(value, 0.4), 5)
                },
                RotationGesture().onChanged { value in
                    guard let i = draft.texts.firstIndex(where: { $0.id == id }) else { return }
                    draft.texts[i].rotation = value
                }
            )
        )
    }

    /// Free crop: drag an edge to reshape the frame; the photo stays covering it.
    private func freeHandles(_ size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { edge in
                let horizontal = edge < 2
                Capsule().fill(Color.white)
                    .frame(width: horizontal ? 6 : 42, height: horizontal ? 42 : 6)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .position(x: edge == 0 ? 0 : edge == 1 ? size.width : size.width / 2,
                              y: edge == 2 ? 0 : edge == 3 ? size.height : size.height / 2)
                    .gesture(DragGesture().onChanged { value in
                        let start = cropStart ?? size
                        if cropStart == nil { cropStart = start }
                        var w = start.width, h = start.height
                        switch edge {
                        case 0: w = start.width - value.translation.width * 2
                        case 1: w = start.width + value.translation.width * 2
                        case 2: h = start.height - value.translation.height * 2
                        default: h = start.height + value.translation.height * 2
                        }
                        w = min(max(w, 120), maxWidth)
                        h = min(max(h, 120), maxHeight)
                        draft.freeRatio = min(max(w / h, 0.5), 2)
                        draft.clampOffset(in: CGSize(width: h * draft.freeRatio, height: h))
                    }.onEnded { _ in cropStart = nil })
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func commit(_ done: WyrmStudioText) {
        var item = done
        item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = draft.texts.firstIndex(where: { $0.id == item.id }) {
            if item.text.isEmpty { draft.texts.remove(at: i) } else { draft.texts[i] = item }
        } else if !item.text.isEmpty {
            draft.texts.append(item)
        }
        editing = nil
        tool = .none
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct WyrmStudioChip: View {
    let label: String
    let selected: Bool
    var dark = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.androidWyrm(12.5, .bold))
                .foregroundColor(dark ? (selected ? .black : .white) : (selected ? ATheme.onInk : ATheme.ink))
                .padding(.horizontal, 13).frame(height: 32)
                .background(Capsule().fill(dark ? (selected ? Color.white : Color.black.opacity(0.42)) : (selected ? ATheme.ink : ATheme.well)))
        }.buttonStyle(.plain)
    }
}

struct WyrmStudioSwatches: View {
    let selected: UInt32
    var colours: [UInt32] = WyrmStudioPalette.colours
    let pick: (UInt32) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(colours, id: \.self) { rgb in
                    Button { UISelectionFeedbackGenerator().selectionChanged(); pick(rgb) } label: {
                        Circle().fill(WyrmStudioPalette.color(rgb)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                            .overlay(Circle().stroke(Color.white, lineWidth: selected == rgb ? 2.5 : 0).padding(-4))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20).padding(.vertical, 6)
        }
    }
}

/// Writing, story-style: the screen dims, the keyboard comes straight up and
/// the words appear large in the middle as they are typed. Font and background
/// at the top, colours just above the keyboard. Tap anywhere or Done to place it.
private struct WyrmStudioTextEditor: View {
    let item: WyrmStudioText
    let update: (WyrmStudioText) -> Void
    let done: (WyrmStudioText) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let text = Binding<String>(get: { item.text }, set: { var next = item; next.text = String($0.prefix(160)); update(next) })
        let shown = WyrmStudioPalette.color(item.filled ? WyrmStudioPalette.contrast(item.rgb) : item.rgb)
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea().onTapGesture { done(item) }
            VStack {
                HStack(spacing: 8) {
                    WyrmStudioChip(label: item.font == .serif ? "Serif" : "Clean", selected: true, dark: true) {
                        var next = item; next.font = item.font == .serif ? .sans : .serif; update(next)
                    }
                    WyrmStudioChip(label: item.filled ? "Fill" : "Plain", selected: item.filled, dark: true) {
                        var next = item; next.filled.toggle(); update(next)
                    }
                    Spacer()
                    WyrmStudioChip(label: "Done", selected: true, dark: true) { done(item) }
                }
                .padding(.horizontal, 14).padding(.top, 10)
                Spacer()
                ZStack {
                    if item.text.isEmpty {
                        Text("Type something").font(item.font == .serif ? .wyrmDisplay(32) : .androidWyrm(32, .bold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    TextField("", text: text)
                        .font(item.font == .serif ? .wyrmDisplay(32) : .androidWyrm(32, .bold))
                        .foregroundColor(shown)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { done(item) }
                        .padding(.horizontal, item.filled ? 14 : 0).padding(.vertical, item.filled ? 8 : 0)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(item.filled ? WyrmStudioPalette.color(item.rgb) : Color.clear))
                        .fixedSize(horizontal: !item.text.isEmpty, vertical: false)
                }
                .padding(.horizontal, 24)
                Spacer()
                WyrmStudioSwatches(selected: item.rgb) { rgb in var next = item; next.rgb = rgb; update(next) }
                    .padding(.bottom, 8)
            }
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true } }
    }
}
