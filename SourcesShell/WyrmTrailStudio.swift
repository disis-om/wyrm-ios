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

    var ratio: CGFloat {
        if aspect == .free { return freeRatio }
        return mode == .canvas ? (aspect == .original ? 0.8 : aspect.ratio(for: nil)) : aspect.ratio(for: image)
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
            if let image {
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

// MARK: - Studio

struct WyrmTrailStudio: View {
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    @StateObject private var draft = WyrmStudioDraft()
    @StateObject private var camera = WyrmTrailCamera()
    @StateObject private var gallery = WyrmTrailGallery()
    @ObservedObject private var store = WyrmTrailsStore.shared
    @State private var step: Step = .pick
    @State private var picking = false
    @State private var loadingPhoto = false
    @State private var canvasSize: CGSize = .zero
    /// The finished picture, made once when the caption step opens.
    @State private var rendered: UIImage?

    enum Step { case pick, edit, caption }

    var body: some View {
        ZStack {
            ATheme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                switch step {
                case .pick:
                    if draft.mode == .text { textComposer } else if draft.mode == .canvas { editor } else { picker }
                case .edit: editor
                case .caption: captionStep
                }
            }
        }
        .foregroundColor(ATheme.ink)
        .onAppear {
            store.token = { [weak account] in account?.sessionToken ?? "" }
            store.resetPosting()
            camera.start()
            gallery.load()
        }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $picking) {
            WyrmPhotoPicker { picked in
                picking = false
                if let picked { open(picked) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { back() } label: {
                Image(systemName: step == .pick ? "xmark" : "chevron.left")
                    .font(.system(size: 16, weight: .bold)).frame(width: 38, height: 38)
                    .background(Circle().fill(ATheme.well))
            }.buttonStyle(.plain)
            Spacer()
            Text(title).font(.androidWyrm(16, .bold))
            Spacer()
            actionButton
        }
        .padding(.horizontal, 14).frame(height: 56)
    }

    private var title: String {
        switch step {
        case .pick: return draft.mode == .text ? "Text trail" : draft.mode == .canvas ? "Canvas" : "New trail"
        case .edit: return "Edit"
        case .caption: return "Caption"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        let ready: Bool = {
            switch step {
            case .pick: return draft.mode == .text ? !draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : draft.mode == .canvas
            case .edit: return true
            case .caption: return !store.posting.busy
            }
        }()
        let label = (step == .caption || (step == .pick && draft.mode == .text)) ? "Post" : "Next"
        Button { forward() } label: {
            Text(label).font(.androidWyrm(14, .bold)).foregroundColor(ATheme.onInk)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Capsule().fill(ATheme.ink.opacity(ready ? 1 : 0.3)))
        }
        .buttonStyle(WSPressStyle())
        .disabled(!ready)
    }

    private func back() {
        switch step {
        case .pick: close()
        case .edit: withAnimation(.easeOut(duration: 0.2)) { step = .pick; if draft.mode == .photo { draft.image = nil } }
        case .caption: withAnimation(.easeOut(duration: 0.2)) { step = draft.mode == .canvas ? .pick : .edit }
        }
    }

    private func forward() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        switch step {
        case .pick:
            if draft.mode == .text { post(image: nil) }
            else if draft.mode == .canvas {
                rendered = draft.render(canvas: canvasSize)
                withAnimation(.easeOut(duration: 0.2)) { step = .caption }
            }
        case .edit:
            rendered = draft.render(canvas: canvasSize)
            withAnimation(.easeOut(duration: 0.2)) { step = .caption }
        case .caption: post(image: rendered ?? draft.render(canvas: canvasSize))
        }
    }

    private func post(image: UIImage?) {
        guard !store.posting.busy else { return }
        let caption = draft.caption
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { _ = await store.post(image: image, caption: caption) }
        close()
    }

    private func open(_ image: UIImage) {
        draft.reset(for: .photo)
        draft.image = image
        camera.stop()
        withAnimation(.easeOut(duration: 0.22)) { step = .edit }
    }

    // MARK: Pick (camera and gallery)

    private var picker: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Group {
                    switch camera.state {
                    case .running: WyrmCameraPreview(session: camera.session)
                    case .denied: cameraNote("Camera is off for Wyrm", "Allow it in Settings to take a photo here.")
                    case .unavailable: cameraNote("No camera", "Pick a photo from your library below.")
                    case .idle: ATheme.well
                    }
                }
                .frame(maxWidth: .infinity).aspectRatio(0.8, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        Button { camera.flip() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white).frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22).padding(.bottom, 18)
                }
            }
            .padding(.horizontal, 12)
            modeBar.padding(.top, 12)
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

    private var modeBar: some View {
        WSSegmented(options: WyrmStudioMode.allCases.map(\.rawValue),
                    selected: WyrmStudioMode.allCases.firstIndex(of: draft.mode) ?? 0) { index in
            let next = WyrmStudioMode.allCases[index]
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.2)) {
                draft.reset(for: next)
                step = .pick
            }
            if next == .photo { camera.start() } else { camera.stop() }
        }
        .padding(.horizontal, 16)
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

    // MARK: Text trail

    private var textComposer: some View {
        VStack(spacing: 0) {
            modeBar.padding(.top, 6).padding(.bottom, 14)
            ZStack(alignment: .topLeading) {
                if draft.caption.isEmpty {
                    Text("Leave a thought…").font(.wyrmDisplay(28)).foregroundColor(ATheme.quiet)
                        .padding(.horizontal, 6).padding(.vertical, 10)
                }
                TextEditor(text: $draft.caption)
                    .font(.wyrmDisplay(28))
                    .onAppear { UITextView.appearance().backgroundColor = .clear }
                    .onChange(of: draft.caption) { value in if value.count > 500 { draft.caption = String(value.prefix(500)) } }
            }
            .padding(14)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .padding(.horizontal, 14)
            Text("\(draft.caption.count)/500").font(.androidWyrm(11)).monospacedDigit().foregroundColor(ATheme.quiet)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    // MARK: Editor

    private var editor: some View {
        WyrmStudioEditor(draft: draft, canvasSize: $canvasSize, showModes: step == .pick, modeBar: AnyView(modeBar))
    }

    // MARK: Caption

    private var captionStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(uiImage: rendered ?? UIImage())
                        .resizable().scaledToFit()
                        .frame(width: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    ZStack(alignment: .topLeading) {
                        if draft.caption.isEmpty {
                            Text("Write a caption…").font(.androidWyrm(15)).foregroundColor(ATheme.quiet)
                                .padding(.horizontal, 5).padding(.vertical, 8)
                        }
                        TextEditor(text: $draft.caption)
                            .font(.androidWyrm(15)).frame(minHeight: 140)
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
            }
        }
    }
}

// MARK: - Editor

private enum WyrmStudioTool { case move, draw }

private struct WyrmStudioEditor: View {
    @ObservedObject var draft: WyrmStudioDraft
    @Binding var canvasSize: CGSize
    let showModes: Bool
    let modeBar: AnyView
    @State private var tool: WyrmStudioTool = .move
    @State private var brush: WyrmStudioBrush = .beads
    @State private var inkRGB: UInt32 = 0xF2B84B
    @State private var live: WyrmStudioStroke?
    @State private var editing: WyrmStudioText?
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var cropStart: CGSize?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width - 24
            let maxHeight = proxy.size.height - (showModes ? 230 : 180)
            let height = min(width / draft.ratio, maxHeight)
            let size = CGSize(width: height * draft.ratio, height: height)
            VStack(spacing: 12) {
                if showModes { modeBar }
                canvas(size)
                    .overlay { if draft.aspect == .free && tool == .move { freeHandles(size, maxWidth: width, maxHeight: maxHeight) } }
                    .onAppear { canvasSize = size }
                    .onChange(of: size) { canvasSize = $0 }
                toolbar
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .overlay { if editing != nil { textEditorOverlay(size) } }
        }
    }

    // The canvas: photo or colour, then strokes, then text.
    private func canvas(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let image = draft.image {
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
            ForEach(draft.texts) { item in
                let s = item.size
                Image(uiImage: item.image()).resizable().frame(width: s.width, height: s.height)
                    .scaleEffect(item.scale).rotationEffect(item.rotation)
                    .position(item.center)
                    .gesture(tool == .move ? textGesture(item.id, size) : nil)
                    .onTapGesture { if tool == .move { editing = item } }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(tool == .draw ? drawGesture(size) : nil)
        .simultaneousGesture(tool == .move && draft.image != nil ? photoGesture(size) : nil)
    }

    /// Free crop: drag an edge to reshape the canvas; the photo stays covering it.
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

    private func textGesture(_ id: UUID, _ size: CGSize) -> some Gesture {
        SimultaneousGesture(
            DragGesture().onChanged { value in
                guard let i = draft.texts.firstIndex(where: { $0.id == id }) else { return }
                draft.texts[i].center = CGPoint(x: min(max(value.location.x, 0), size.width), y: min(max(value.location.y, 0), size.height))
            },
            SimultaneousGesture(
                MagnificationGesture().onChanged { value in
                    guard let i = draft.texts.firstIndex(where: { $0.id == id }) else { return }
                    draft.texts[i].scale = min(max(value, 0.4), 4)
                },
                RotationGesture().onChanged { value in
                    guard let i = draft.texts.firstIndex(where: { $0.id == id }) else { return }
                    draft.texts[i].rotation = value
                }
            )
        )
    }

    // MARK: Toolbar

    private var toolbar: some View {
        VStack(spacing: 10) {
            if tool == .draw {
                HStack(spacing: 8) {
                    ForEach(WyrmStudioBrush.allCases, id: \.self) { kind in
                        chip(kind.rawValue.capitalized, selected: brush == kind) { brush = kind }
                    }
                    Spacer()
                    iconButton("arrow.uturn.backward") { if !draft.strokes.isEmpty { draft.strokes.removeLast() } }
                }
                swatches(selected: inkRGB) { inkRGB = $0 }
            } else if draft.image != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(WyrmStudioAspect.allCases) { aspect in
                            chip(aspect.rawValue, selected: draft.aspect == aspect) {
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
            } else {
                HStack(spacing: 8) {
                    ForEach([WyrmStudioAspect.portrait, .square, .wide]) { aspect in
                        chip(aspect.rawValue, selected: draft.aspect == aspect) { withAnimation(.easeOut(duration: 0.2)) { draft.aspect = aspect } }
                    }
                    Spacer()
                }.padding(.horizontal, 16)
                swatches(selected: draft.background) { draft.background = $0 }
            }
            HStack(spacing: 10) {
                toolButton("Text", icon: "textformat", on: false) {
                    tool = .move
                    let rgb: UInt32 = draft.image == nil ? WyrmStudioPalette.contrast(draft.background) : 0xFFFFFF
                    editing = WyrmStudioText(text: "", rgb: rgb, font: .sans, filled: false,
                                             center: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
                }
                toolButton("Draw", icon: "scribble", on: tool == .draw) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    tool = tool == .draw ? .move : .draw
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.androidWyrm(12.5, .bold))
                .foregroundColor(selected ? ATheme.onInk : ATheme.ink)
                .padding(.horizontal, 13).frame(height: 32)
                .background(Capsule().fill(selected ? ATheme.ink : ATheme.well))
        }.buttonStyle(.plain)
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundColor(ATheme.ink)
                .frame(width: 34, height: 34).background(Circle().fill(ATheme.well))
        }.buttonStyle(.plain)
    }

    private func toolButton(_ label: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(label).font(.androidWyrm(13.5, .bold))
            }
            .foregroundColor(on ? ATheme.onInk : ATheme.ink)
            .frame(maxWidth: .infinity).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? ATheme.ink : ATheme.well))
        }.buttonStyle(WSPressStyle())
    }

    private func swatches(selected: UInt32, pick: @escaping (UInt32) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(WyrmStudioPalette.colours, id: \.self) { rgb in
                    Button { UISelectionFeedbackGenerator().selectionChanged(); pick(rgb) } label: {
                        Circle().fill(WyrmStudioPalette.color(rgb)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(ATheme.rule, lineWidth: 1))
                            .overlay(Circle().stroke(ATheme.ink, lineWidth: selected == rgb ? 2.5 : 0).padding(-4))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20).padding(.vertical, 4)
        }
    }

    // MARK: Text editing

    private func textEditorOverlay(_ size: CGSize) -> some View {
        let binding = Binding<WyrmStudioText>(get: { editing ?? WyrmStudioText(text: "", rgb: 0xFFFFFF, font: .sans, filled: false, center: .zero) },
                                             set: { editing = $0 })
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { commitText() }
            VStack(spacing: 16) {
                HStack {
                    Button("Delete") {
                        if let current = editing { draft.texts.removeAll { $0.id == current.id } }
                        editing = nil
                    }.font(.androidWyrm(14, .bold)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Button { binding.wrappedValue.font = binding.wrappedValue.font == .sans ? .serif : .sans } label: {
                        Text("Aa").font(binding.wrappedValue.font == .sans ? .androidWyrm(16, .bold) : .wyrmDisplay(18))
                            .foregroundColor(.white).frame(width: 40, height: 36).background(Capsule().fill(Color.white.opacity(0.18)))
                    }.buttonStyle(.plain)
                    Button { binding.wrappedValue.filled.toggle() } label: {
                        Image(systemName: binding.wrappedValue.filled ? "a.square.fill" : "a.square")
                            .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 40, height: 36).background(Capsule().fill(Color.white.opacity(0.18)))
                    }.buttonStyle(.plain)
                    Button("Done") { commitText() }.font(.androidWyrm(14, .bold)).foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                TextField("", text: binding.text)
                    .font(binding.wrappedValue.font == .sans ? .androidWyrm(30, .bold) : .wyrmDisplay(32))
                    .foregroundColor(WyrmStudioPalette.color(binding.wrappedValue.rgb))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .submitLabel(.done)
                    .onSubmit { commitText() }
                swatches(selected: binding.wrappedValue.rgb) { binding.wrappedValue.rgb = $0 }
            }
        }
    }

    private func commitText() {
        guard var item = editing else { return }
        item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = draft.texts.firstIndex(where: { $0.id == item.id }) {
            if item.text.isEmpty { draft.texts.remove(at: i) } else { draft.texts[i] = item }
        } else if !item.text.isEmpty {
            draft.texts.append(item)
        }
        editing = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
