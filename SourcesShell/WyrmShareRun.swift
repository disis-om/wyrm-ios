import SwiftUI
import UIKit

/*
 * "Share this run" and "Try this skin" (OM, 2026-09-30). Android behaves the
 * same and posts the same skin JSON.
 *
 * Share run: after a match the lobby offers it (WyrmLobby), and WyrmDesignRoot
 * draws the Trails studio in its share mode, portrait, over the app. The
 * studio (WyrmTrailStudio, `run`) puts the death screenshot or a colour
 * behind the player's snake as a sticker (`WyrmSkinSticker`) and a stats box
 * (`WyrmStatsBox`), exports them with its usual render and posts through the
 * usual trail flow, with the player's look (`WyrmTrailSkin`) when "Share my
 * skin" is on.
 *
 * Try this skin: a card whose trail carries a skin offers it. The look opens
 * in the Skin tab as a draft (`WyrmSkinTrial`); nothing reaches the engine or
 * the saved skin until Wear.
 */

// MARK: - The skin a trail carries

/// The poster's look, exactly the JSON the backend validates
/// (`backend/src/trails.mjs`); every field is required.
///
/// iOS mapping: `custom`, `preset`, `accessory` and the pattern come from the
/// Skin tab's AppStorage (`wyrm.ios.skin.*`); `code` is
/// `WyrmSkinCatalog.code(for:)` of the pattern and `colours` holds one
/// "AARRGGBB" per code position, the stored UInt32 as is ("00000000" = the
/// bead's own palette colour; the top byte keeps Wyrm and AIR bead tags). The
/// looks are `WyrmLookStore`'s, whose hair colour is already a 0...1 tone.
struct WyrmTrailSkin: Codable, Equatable {
    struct Look: Codable, Equatable {
        var hair: Int
        var hairTone: Double
        var ears: Int
        var glasses: Int
    }

    var v = 1
    var custom: Bool
    var preset: Int
    var code: String
    var colours: [String]
    var accessory: Int
    var look: Look
    /// The NTL tag worn, in NTL's numbering (OM, 2026-10-04); nil for none.
    /// Written only when one is worn; older skins have none.
    var tag: Int? = nil

    /// The player's own look, as the Skin tab saved it.
    static func current() -> WyrmTrailSkin {
        let d = UserDefaults.standard
        let preset = d.object(forKey: "wyrm.ios.skin.preset") as? Int ?? 2
        let customOn = d.object(forKey: "wyrm.ios.skin.custom-enabled") as? Bool ?? false
        let pattern = d.string(forKey: "wyrm.ios.skin.custom-groups") ?? "7,9,7,9"
        let stored = d.string(forKey: "wyrm.ios.skin.custom-colors") ?? ""
        let accessory = d.object(forKey: "wyrm.ios.skin.accessory-id") as? Int ?? -1
        let tagIndex = d.object(forKey: "wyrm.ios.skin.tag-id") as? Int ?? -1
        let groups = Array(pattern.split(separator: ",").compactMap { Int($0) }
            .filter { WyrmSkinCatalog.validGroups.contains($0) }.prefix(256))
        let parsed = stored.split(separator: ",", omittingEmptySubsequences: false)
            .prefix(256).map { UInt32($0, radix: 16) ?? 0 }
        let custom = customOn && !groups.isEmpty
        let colours: [UInt32] = custom ? groups.indices.map { $0 < parsed.count ? parsed[$0] : 0 } : []
        let look = WyrmLookStore.shared
        return WyrmTrailSkin(
            custom: custom,
            preset: min(max(preset, 0), 255),
            code: custom ? WyrmSkinCatalog.code(for: groups) : "",
            colours: colours.map { String(format: "%08X", $0) },
            accessory: WyrmSkinCatalog.accessories.contains(where: { $0.id == accessory }) ? accessory : -1,
            look: Look(hair: look.hair, hairTone: look.hairTone.isFinite ? min(max(look.hairTone, 0), 1) : 0,
                       ears: look.ears, glasses: look.glasses),
            // Wyrm's own tags have no number the Trails backend takes (0..65535).
            tag: WyrmSkinCatalog.tags.indices.contains(tagIndex) && !WyrmSkinCatalog.isWyrmTag(WyrmSkinCatalog.tags[tagIndex].ntlID)
                ? WyrmSkinCatalog.tags[tagIndex].ntlID : nil)
    }

    /// The body for the POST: plain JSON types, so JSONSerialization writes
    /// true/false and integers exactly.
    var json: [String: Any] {
        var body: [String: Any] = ["v": 1, "custom": custom, "preset": preset, "code": code, "colours": colours,
                                   "accessory": accessory,
                                   "look": ["hair": look.hair, "hairTone": look.hairTone, "ears": look.ears,
                                            "glasses": look.glasses]]
        if let tag, (0...65535).contains(tag) { body["tag"] = tag }
        return body
    }

    /// The pattern as Wyrm wears it, bead group and colour position for
    /// position; a character Wyrm does not know is dropped with its colour.
    /// Empty for a preset skin.
    var pattern: (groups: [Int], colors: [UInt32]) {
        guard custom else { return ([], []) }
        var groups: [Int] = []
        var colors: [UInt32] = []
        for (index, character) in code.lowercased().prefix(256).enumerated() {
            guard let group = WyrmSkinCatalog.group(for: character) else { continue }
            groups.append(group)
            colors.append(index < colours.count ? (UInt32(colours[index], radix: 16) ?? 0) : 0)
        }
        return (groups, colors)
    }

    /// Whether it wears its own pattern (a custom skin that still has beads).
    var wearsPattern: Bool { !pattern.groups.isEmpty }

    /// One repeat of the body: the pattern, or the preset's beads.
    var body: (groups: [Int], colors: [UInt32]) {
        let own = pattern
        if !own.groups.isEmpty { return own }
        let presets = WyrmSkinCatalog.presets
        return (presets.indices.contains(preset) ? presets[preset] : [7], [])
    }

    /// What the engine would wear: the body repeated to 256 positions.
    var wornGroups: [Int] {
        let source = body.groups.isEmpty ? [7] : body.groups
        return (0..<256).map { source[$0 % source.count] }
    }

    var wornColors: [UInt32] {
        let source = body.colors
        return (0..<256).map { source.isEmpty ? 0 : source[$0 % source.count] }
    }

    /// The tag as an index in `WyrmSkinCatalog.tags` (what the Skin tab
    /// saves), or -1 when there is none or this app does not have it.
    var wornTagIndex: Int {
        guard let tag else { return -1 }
        return WyrmSkinCatalog.tags.first(where: { $0.ntlID == tag })?.id ?? -1
    }

    /// A known accessory, or -1.
    var wornAccessory: Int { WyrmSkinCatalog.accessories.contains(where: { $0.id == accessory }) ? accessory : -1 }
}

// Decoded leniently: a skin missing a field or with a wrong type becomes a
// plain one instead of failing the whole feed page. In extensions, so the
// memberwise initialisers stay.
extension WyrmTrailSkin {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 1
        custom = (try? c.decodeIfPresent(Bool.self, forKey: .custom)) ?? false
        preset = (try? c.decodeIfPresent(Int.self, forKey: .preset)) ?? 0
        code = String(((try? c.decodeIfPresent(String.self, forKey: .code)) ?? "").prefix(256))
        colours = Array(((try? c.decodeIfPresent([String].self, forKey: .colours)) ?? []).prefix(256))
        accessory = (try? c.decodeIfPresent(Int.self, forKey: .accessory)) ?? -1
        look = (try? c.decodeIfPresent(Look.self, forKey: .look)) ?? Look(hair: -1, hairTone: 0, ears: -1, glasses: -1)
        tag = (try? c.decodeIfPresent(Int.self, forKey: .tag)).flatMap { (0...65535).contains($0) ? $0 : nil }
    }
}

extension WyrmTrailSkin.Look {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A style this app does not have is none (a newer app's look).
        func style(_ key: CodingKeys, _ count: Int) -> Int {
            let value = (try? c.decodeIfPresent(Int.self, forKey: key)) ?? -1
            return (0..<count).contains(value) ? value : -1
        }
        hair = style(.hair, WyrmLook.hairNames.count)
        let tone = (try? c.decodeIfPresent(Double.self, forKey: .hairTone)) ?? 0
        hairTone = tone.isFinite ? min(max(tone, 0), 1) : 0
        ears = style(.ears, WyrmLook.earNames.count)
        glasses = style(.glasses, WyrmLook.glassesNames.count)
    }
}

/// Try this skin: a trail's look, previewed in the Skin tab as a draft. Wear
/// (`WyrmSkinRoot`) makes it the player's; Back to mine, or leaving the Skin
/// tab, drops it. Nothing is saved or sent to the engine before Wear.
@MainActor
final class WyrmSkinTrial: ObservableObject {
    static let shared = WyrmSkinTrial()

    @Published private(set) var skin: WyrmTrailSkin?
    @Published private(set) var author = ""
    /// Bumped on every Try this skin tap: WyrmDesignMain shows the Skin tab.
    @Published private(set) var request = 0

    func start(_ skin: WyrmTrailSkin, author: String) {
        self.skin = skin
        self.author = author
        request += 1
        WyrmDiagnostics.record("trying a trail skin custom=\(skin.custom) beads=\(skin.code.count)", category: "SKIN")
    }

    func end() {
        guard skin != nil else { return }
        skin = nil
        author = ""
    }
}

/// Share run's presenter: the lobby opens it (or the Skin tab's "Share this
/// skin", with no run), WyrmDesignRoot draws the studio over everything, and
/// a finished post asks WyrmDesignMain for the feed.
@MainActor
final class WyrmShareRun: ObservableObject {
    static let shared = WyrmShareRun()

    @Published private(set) var run: WyrmLastRun?
    /// "Share this skin": the studio is open on the skin alone.
    @Published private(set) var skinOnly = false
    /// Bumped after a post: WyrmDesignMain opens the Trails feed.
    @Published private(set) var trailsRequest = 0

    var isOpen: Bool { run != nil || skinOnly }

    func open(_ run: WyrmLastRun) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            skinOnly = false
            self.run = run
        }
    }

    /// Skin › Share this skin; closing leaves the Skin tab where it was.
    func openSkin() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            run = nil
            skinOnly = true
        }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.25)) {
            run = nil
            skinOnly = false
        }
    }

    func posted() {
        close()
        trailsRequest += 1
    }

    /// A death picture that lands after the editor opened joins the same run.
    func refresh() {
        guard let open = run, open.screenshot == nil, let latest = WyrmRunCapture.lastRun,
              latest.endedAt == open.endedAt, latest.screenshot != nil else { return }
        run = latest
    }
}

// MARK: - Sticker art

/// The bead and look images the skin sticker draws, shrunk once and tinted
/// once per colour (SwiftUI's `colorMultiply`, done on the pixels, so the
/// same picture can be drawn into any CGContext). Each entry holds its source
/// image, so a freed image's address can never be mistaken for another.
@MainActor
final class WyrmStickerArt {
    let textures: WyrmSkinTextureLibrary
    private struct Key: Hashable { let source: ObjectIdentifier; let tint: UInt32?; let side: Int }
    private var cache: [Key: (source: CGImage, image: CGImage)] = [:]

    init(textures: WyrmSkinTextureLibrary) { self.textures = textures }

    /// `source` at most `side` pixels on its long side, its colour multiplied
    /// by `tint` (RGB, the low 24 bits); nil tint keeps its own colour.
    func image(_ source: CGImage, tint: UInt32?, side: Int) -> CGImage? {
        let rgb = tint.map { $0 & 0xFF_FFFF }
        let key = Key(source: ObjectIdentifier(source), tint: rgb, side: side)
        if let hit = cache[key] { return hit.image }
        let fit = min(1, CGFloat(side) / CGFloat(max(source.width, source.height, 1)))
        let w = max(1, Int((CGFloat(source.width) * fit).rounded()))
        let h = max(1, Int((CGFloat(source.height) * fit).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let rgb, let data = context.data {
            // Premultiplied channels times the tint: exactly colorMultiply.
            let r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF
            let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            for i in stride(from: 0, to: w * h * 4, by: 4) {
                pixels[i] = UInt8((UInt32(pixels[i]) * r + 127) / 255)
                pixels[i + 1] = UInt8((UInt32(pixels[i + 1]) * g + 127) / 255)
                pixels[i + 2] = UInt8((UInt32(pixels[i + 2]) * b + 127) / 255)
            }
        }
        guard let made = context.makeImage() else { return nil }
        if cache.count > 400 { cache.removeAll() }
        cache[key] = (source, made)
        return made
    }

    /// Draws a CGImage upright into a y-down context (UIKit, SwiftUI Canvas).
    static func put(_ image: CGImage, in rect: CGRect, cg: CGContext) {
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        cg.restoreGState()
    }
}

// MARK: - Skin sticker

/// The player's snake as a sticker, exactly as the Skin tab's preview draws
/// it (OM, 2026-09-30: "same to same"): both rows of 128 beads, 8/48 of a
/// bead apart, the tail row under the head row, the head row's beads turned
/// half round, the same atlas beads, Wyrm and AIR beads, wheel colours, eyes,
/// accessory and Wyrm looks, the head at the top row's right end facing
/// right. `draw` paints it centred on the context's origin in sticker points,
/// for the editor's image and the posted picture alike. Android draws it with
/// the preview's own code (`drawSkinRows`).
enum WyrmSkinSticker {
    /// One bead's size in sticker points.
    static let bead: CGFloat = 18
    /// Beads in each of the preview's two rows.
    static let row = 128

    /// Segment centres from the head (code position 0) to the tail, each with
    /// the direction it travels: +x along the head row, -x along the tail row,
    /// which `draw` turns into the preview's 180 and 0 degree beads.
    static let segments: [(point: CGPoint, heading: CGFloat)] = {
        let b = bead
        let step = b * 8 / 48
        let gap = b * 0.16
        let bodyWidth = b + step * CGFloat(row - 1)
        let x = -bodyWidth / 2
        let headY = -b * 0.5 - gap * 0.5
        let tailY = b * 0.5 + gap * 0.5
        // WyrmSkinPreview.segmentPoint, indexed by code position instead of segment.
        return (0..<(row * 2)).map { codeIndex -> (point: CGPoint, heading: CGFloat) in
            let segment = row * 2 - 1 - codeIndex
            let local = segment % row
            let top = segment >= row
            let slot = top ? local : row - 1 - local
            return (CGPoint(x: x + b * 0.5 + CGFloat(slot) * step, y: top ? headY : tailY), top ? 0 : CGFloat.pi)
        }
    }()

    /// The drawing's box in sticker points: the body, and round the head room
    /// for the hair, ears, glasses and accessory.
    static let bounds: CGRect = {
        var box = CGRect.null
        for segment in segments {
            box = box.union(CGRect(x: segment.point.x - bead / 2, y: segment.point.y - bead / 2, width: bead, height: bead))
        }
        if let head = segments.first?.point {
            box = box.union(CGRect(x: head.x - 2.2 * bead, y: head.y - 1.3 * bead, width: 3.6 * bead, height: 2.6 * bead))
        }
        return box.insetBy(dx: -3, dy: -3)
    }()

    static var size: CGSize { bounds.size }

    /// Paints the sticker centred on the context's origin, in sticker points.
    /// Nothing until the textures are ready.
    @MainActor
    static func draw(_ skin: WyrmTrailSkin, art: WyrmStickerArt, in cg: CGContext) {
        let textures = art.textures
        guard textures.ready, let head = segments.first else { return }
        let body = skin.body
        cg.saveGState()
        cg.translateBy(x: -bounds.midX, y: -bounds.midY)
        // Tail first, head last, as the preview and the arena draw them.
        for codeIndex in stride(from: segments.count - 1, through: 0, by: -1) {
            let segment = segments[codeIndex]
            let group = body.groups.isEmpty ? 7 : body.groups[codeIndex % body.groups.count]
            let rgba: UInt32 = body.colors.isEmpty ? 0 : body.colors[codeIndex % body.colors.count]
            let air = WyrmAirSkin.kind(of: rgba)
            let wyrm = WyrmBead.kind(of: rgba)
            guard let source = wyrm.flatMap({ textures.wyrmBeads[$0] })
                    ?? air.flatMap({ textures.airBeads[$0] })
                    ?? textures.beads[rgba == 0 ? group : 40] else { continue }
            let tint: UInt32?
            if let wyrm {
                tint = WyrmBead.tinted[wyrm] ? rgba : nil
            } else if air != nil {
                tint = WyrmAirSkin.bodyTint(rgba)
            } else {
                tint = rgba != 0 ? rgba : nil
            }
            guard let image = art.image(source, tint: tint, side: 192) else { continue }
            cg.saveGState()
            cg.translateBy(x: segment.point.x, y: segment.point.y)
            // The head row's beads turned half round, the tail row's upright, as in the preview.
            cg.rotate(by: segment.heading + .pi)
            WyrmStickerArt.put(image, in: CGRect(x: -bead / 2, y: -bead / 2, width: bead, height: bead), cg: cg)
            cg.restoreGState()
        }
        // The head's own frame: origin at its centre, +x forward.
        cg.translateBy(x: head.point.x, y: head.point.y)
        cg.rotate(by: head.heading)
        drawEyes(skin, art: art, in: cg)
        let unit = bead / 29
        if let item = WyrmSkinCatalog.accessories.first(where: { $0.id == skin.wornAccessory }),
           let source = textures.accessories[item.id],
           let image = art.image(source, tint: nil, side: 256) {
            // Fitted into a square of the catalogue's size, as the preview does.
            let side = bead * CGFloat(item.scale)
            let fit = min(side / CGFloat(image.width), side / CGFloat(image.height))
            let w = CGFloat(image.width) * fit, h = CGFloat(image.height) * fit
            let x = CGFloat(item.offset) * 6 * unit
            WyrmStickerArt.put(image, in: CGRect(x: x - w / 2, y: -h / 2, width: w, height: h), cg: cg)
        }
        drawLook(skin.look, art: art, r: bead / 2, in: cg)
        drawTag(skin, art: art, in: cg)
        cg.restoreGState()
    }

    /// The tag (OM, 2026-10-04): `WyrmSwingTag`'s rope and art at rest
    /// (chain 1, size 1), hanging straight back from the head, in the head's
    /// frame. Android's `drawSkinSticker` draws the same.
    @MainActor
    private static func drawTag(_ skin: WyrmTrailSkin, art: WyrmStickerArt, in cg: CGContext) {
        let index = skin.wornTagIndex
        guard WyrmSkinCatalog.tags.indices.contains(index), let image: CGImage = art.textures.tags[index] else { return }
        let item = WyrmSkinCatalog.tags[index]
        let unit = bead / 29
        let anchor = CGPoint(x: -8 * unit, y: 0)
        let end = CGPoint(x: anchor.x - 9 * 4 * unit, y: 0)
        let width = CGFloat(item.width) * 0.285 * unit
        let height = CGFloat(item.height) * 0.285 * unit
        // At rest the rope points straight back (angle pi), so the art turns half way.
        let centre = CGPoint(x: end.x - (CGFloat(item.anchorX) * 0.285 * unit + width / 2),
                             y: end.y - (CGFloat(item.anchorY) * 0.285 * unit + height / 2))
        func rgb(_ value: UInt32, _ alpha: CGFloat) -> CGColor {
            CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
        }
        cg.saveGState()
        cg.setLineCap(.round)
        for (lineWidth, colour) in [(5 * unit, rgb(item.accentA, 1)), (4 * unit, rgb(item.accentB, 0.5)),
                                    (3 * unit, rgb(item.accentB, 0.5)), (2 * unit, rgb(item.accentB, 0.5))] {
            cg.setStrokeColor(colour)
            cg.setLineWidth(lineWidth)
            cg.move(to: anchor)
            cg.addLine(to: end)
            cg.strokePath()
        }
        cg.translateBy(x: centre.x, y: centre.y)
        cg.rotate(by: .pi)
        let pixelsWide = CGFloat(max(image.width, 1))
        let pixelsHigh = CGFloat(max(image.height, 1))
        let fit: CGFloat = min(width / pixelsWide, height / pixelsHigh)
        let w = pixelsWide * fit, h = pixelsHigh * fit
        WyrmStickerArt.put(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cg: cg)
        cg.restoreGState()
    }

    /// The preview's eyes (preset-specific colours included), in the head's frame.
    @MainActor
    private static func drawEyes(_ skin: WyrmTrailSkin, art: WyrmStickerArt, in cg: CGContext) {
        guard let eye = art.textures.beads[40] else { return }
        let custom = skin.wearsPattern
        let preset = skin.preset
        let unit = bead / 29
        let iris = 12 * unit
        let pupil = (custom ? 7 : preset == 63 ? 5 : 7) * unit
        let irisRGB: UInt32 = custom ? 0xFFFFFF
            : preset == 63 ? 0x000000 : preset == 64 ? 0xFFFF80 : preset == 25 ? 0xFF5609 : preset == 44 ? 0xD4D4D4 : 0xFFFFFF
        let pupilRGB: UInt32 = !custom && preset == 63 ? 0xCCCCCC : 0x000000
        guard let irisImage = art.image(eye, tint: irisRGB == 0xFFFFFF ? nil : irisRGB, side: 96),
              let pupilImage = art.image(eye, tint: pupilRGB, side: 96) else { return }
        for side in 0..<2 {
            let irisY = side == 0 ? -6 * unit - 0.5 : 6 * unit
            let pupilY = side == 0 ? -6 * unit : 6 * unit
            WyrmStickerArt.put(irisImage, in: CGRect(x: 6 * unit - iris / 2, y: irisY - iris / 2, width: iris, height: iris), cg: cg)
            WyrmStickerArt.put(pupilImage, in: CGRect(x: 6 * unit + 0.5 + 2 * unit - pupil / 2, y: pupilY - pupil / 2,
                                                      width: pupil, height: pupil), cg: cg)
        }
    }

    /// `WyrmLook.draw` for a CGContext, in the head's frame: hair at rest
    /// (flows straight back), then ears and glasses.
    @MainActor
    private static func drawLook(_ look: WyrmTrailSkin.Look, art: WyrmStickerArt, r: CGFloat, in cg: CGContext) {
        let cells = art.textures.looks
        if WyrmLook.hairNames.indices.contains(look.hair) {
            let tint = WyrmLook.hairTone(look.hairTone)
            for flow in WyrmLook.flows(look.hair) {
                guard let source = cells[flow.cell], let image = art.image(source, tint: tint, side: 256) else { continue }
                let side = WyrmLook.flowSpan * r
                let root = CGPoint(x: flow.x * r, y: flow.y * r)
                cg.saveGState()
                cg.translateBy(x: root.x, y: 0)
                cg.scaleBy(x: -1, y: 1)
                cg.translateBy(x: -root.x, y: 0)
                WyrmStickerArt.put(image, in: CGRect(x: root.x, y: root.y - side / 2, width: side, height: side), cg: cg)
                cg.restoreGState()
            }
            if let source = cells[look.hair], let image = art.image(source, tint: tint, side: 256) {
                let side = WyrmLook.capSide * r
                WyrmStickerArt.put(image, in: CGRect(x: -WyrmLook.capBack * r - side / 2, y: -side / 2, width: side, height: side), cg: cg)
            }
        }
        if WyrmLook.earNames.indices.contains(look.ears), let source = cells[16 + look.ears],
           let image = art.image(source, tint: nil, side: 256) {
            WyrmStickerArt.put(image, in: CGRect(x: -2 * r, y: -2 * r, width: 4 * r, height: 4 * r), cg: cg)
        }
        if WyrmLook.glassesNames.indices.contains(look.glasses), let source = cells[28 + look.glasses],
           let image = art.image(source, tint: nil, side: 256) {
            WyrmStickerArt.put(image, in: CGRect(x: -2 * r, y: -2 * r, width: 4 * r, height: 4 * r), cg: cg)
        }
    }

    /// The sticker as a crisp image, for the editor.
    @MainActor
    static func image(_ skin: WyrmTrailSkin, art: WyrmStickerArt) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            draw(skin, art: art, in: context.cgContext)
        }
    }
}

// MARK: - Stats box

/// The run's numbers as a sticker: SCORE, KILLS and TIME (m:ss) in one of six
/// looks. Like `WyrmStudioText` it paints itself centred on the origin, for
/// the editor's image and the posted picture alike.
struct WyrmStatsBox: Equatable {
    static let styles = ["Paper card", "Ink card", "Glass", "Neon", "Minimal line", "Big number"]
    /// Room round the box for its shadow or glow.
    static let margin: CGFloat = 12

    var style: Int
    let score: Int
    let kills: Int
    let seconds: Double

    private static let numbers: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var scoreText: String { Self.numbers.string(from: NSNumber(value: score)) ?? "\(score)" }
    var killsText: String { "\(kills)" }
    var timeText: String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    private struct Look {
        var fill: UIColor?
        var stroke: UIColor?
        var strokeWidth: CGFloat = 1
        var value: UIColor
        var label: UIColor
        /// A glow on the text (Neon) or a soft shadow under it (on photos).
        var textGlow: UIColor?
        var textShadow = false
        var cardShadow = false
        var strokeGlow: UIColor?
        var separators: UIColor?
    }

    private var look: Look {
        switch style {
        case 0: return Look(fill: WyrmStudioPalette.ui(0xF6F1E7), stroke: UIColor(white: 0.07, alpha: 0.12),
                            value: WyrmStudioPalette.ui(0x111111), label: UIColor(white: 0.07, alpha: 0.55), cardShadow: true)
        case 1: return Look(fill: WyrmStudioPalette.ui(0x111111), value: .white, label: UIColor(white: 1, alpha: 0.6), cardShadow: true)
        case 2: return Look(fill: UIColor(white: 1, alpha: 0.2), stroke: UIColor(white: 1, alpha: 0.5),
                            value: .white, label: UIColor(white: 1, alpha: 0.8), textShadow: true)
        case 3: return Look(fill: WyrmStudioPalette.ui(0x0B0B1A).withAlphaComponent(0.88), stroke: WyrmStudioPalette.ui(0xFF3EA5),
                            strokeWidth: 2, value: WyrmStudioPalette.ui(0x3EF2FF), label: WyrmStudioPalette.ui(0xFF8FD0),
                            textGlow: WyrmStudioPalette.ui(0x3EF2FF), strokeGlow: WyrmStudioPalette.ui(0xFF3EA5))
        default: return Look(value: .white, label: UIColor(white: 1, alpha: 0.85), textShadow: true,
                             separators: UIColor(white: 1, alpha: 0.75))
        }
    }

    private func text(_ string: String, _ font: UIFont, _ colour: UIColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: colour, .kern: kern])
    }

    private var columns: [(value: NSAttributedString, label: NSAttributedString)] {
        let look = self.look
        let valueFont = WyrmStudioFont.sans.ui(26)
        let labelFont = WyrmStudioFont.sans.ui(9.5)
        let pairs: [(String, String)] = [(scoreText, "SCORE"), (killsText, "KILLS"), (timeText, "TIME")]
        return pairs.map { pair in
            (value: text(pair.0, valueFont, look.value), label: text(pair.1, labelFont, look.label, kern: 1.6))
        }
    }

    private static let padH: CGFloat = 20
    private static let padV: CGFloat = 14
    private static let gap: CGFloat = 24

    /// The box alone, without the margin.
    private var box: CGSize {
        if style == 5 {
            let parts = bigParts
            let width = max(parts.label.size().width, parts.value.size().width, parts.footer.size().width)
            return CGSize(width: ceil(width) + 32,
                          height: ceil(parts.label.size().height + parts.value.size().height + parts.footer.size().height) + 22)
        }
        let cols = columns
        let widths = cols.map { ceil(max($0.value.size().width, $0.label.size().width)) }
        let valueHeight = ceil(cols.map { $0.value.size().height }.max() ?? 0)
        let labelHeight = ceil(cols.map { $0.label.size().height }.max() ?? 0)
        return CGSize(width: widths.reduce(0, +) + Self.gap * CGFloat(max(cols.count - 1, 0)) + Self.padH * 2,
                      height: valueHeight + 2 + labelHeight + Self.padV * 2)
    }

    /// The item's own size in canvas points, margin included, before its
    /// scale and rotation.
    var size: CGSize {
        let b = box
        return CGSize(width: b.width + Self.margin * 2, height: b.height + Self.margin * 2)
    }

    private var bigParts: (label: NSAttributedString, value: NSAttributedString, footer: NSAttributedString) {
        let white = UIColor.white
        return (text("SCORE", WyrmStudioFont.sans.ui(10), white.withAlphaComponent(0.8), kern: 2.2),
                text(scoreText, WyrmStudioFont.serif.ui(58), white),
                text("\(killsText) KILLS · \(timeText)", WyrmStudioFont.sans.ui(13), white.withAlphaComponent(0.88), kern: 1.2))
    }

    /// Paints the box centred on the context's origin.
    func draw(in cg: CGContext) {
        let b = box
        let rect = CGRect(x: -b.width / 2, y: -b.height / 2, width: b.width, height: b.height)
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }
        if style == 5 {
            let parts = bigParts
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 6, color: UIColor.black.withAlphaComponent(0.4).cgColor)
            var y = rect.minY + 11
            for part in [parts.label, parts.value, parts.footer] {
                let s = part.size()
                part.draw(at: CGPoint(x: -s.width / 2, y: y))
                y += s.height
            }
            cg.restoreGState()
            return
        }
        let look = self.look
        let path = UIBezierPath(roundedRect: rect, cornerRadius: style == 2 ? 20 : 18)
        if let fill = look.fill {
            cg.saveGState()
            if look.cardShadow {
                cg.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.22).cgColor)
            }
            fill.setFill()
            path.fill()
            cg.restoreGState()
        }
        if let stroke = look.stroke {
            cg.saveGState()
            if let glow = look.strokeGlow { cg.setShadow(offset: .zero, blur: 10, color: glow.cgColor) }
            let edge = UIBezierPath(roundedRect: rect.insetBy(dx: look.strokeWidth / 2, dy: look.strokeWidth / 2),
                                    cornerRadius: (style == 2 ? 20 : 18) - look.strokeWidth / 2)
            edge.lineWidth = look.strokeWidth
            stroke.setStroke()
            edge.stroke()
            cg.restoreGState()
        }
        let cols = columns
        let widths = cols.map { ceil(max($0.value.size().width, $0.label.size().width)) }
        let valueHeight = ceil(cols.map { $0.value.size().height }.max() ?? 0)
        var x = rect.minX + Self.padH
        let top = rect.minY + Self.padV
        cg.saveGState()
        if let glow = look.textGlow {
            cg.setShadow(offset: .zero, blur: 8, color: glow.cgColor)
        } else if look.textShadow {
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: UIColor.black.withAlphaComponent(0.4).cgColor)
        }
        for (index, column) in cols.enumerated() {
            let width = widths[index]
            let valueSize = column.value.size()
            let labelSize = column.label.size()
            column.value.draw(at: CGPoint(x: x + (width - valueSize.width) / 2, y: top + (valueHeight - valueSize.height)))
            column.label.draw(at: CGPoint(x: x + (width - labelSize.width) / 2, y: top + valueHeight + 2))
            if let line = look.separators, index < cols.count - 1 {
                line.setFill()
                cg.fill(CGRect(x: x + width + Self.gap / 2 - 0.5, y: rect.minY + Self.padV * 0.6, width: 1,
                               height: rect.height - Self.padV * 1.2))
            }
            x += width + Self.gap
        }
        cg.restoreGState()
    }

    /// The box as a crisp image, for the editor.
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

/// A sticker on the share canvas: the skin or the stats box.
struct WyrmStudioSticker: Identifiable, Equatable {
    enum Kind: Equatable { case skin, stats }
    let id = UUID()
    let kind: Kind
    var center: CGPoint
    var scale: CGFloat = 1
    var rotation: Angle = .zero
    /// The stats box's look, an index into `WyrmStatsBox.styles`.
    var style = 0
}

/// Try this skin on a trail card: far right in the like/reply row.
struct WyrmTrySkinCapsule: View {
    let action: () -> Void
    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paintpalette").font(.system(size: 13, weight: .semibold))
                Text("Try this skin").font(.androidWyrm(13, .semibold)).lineLimit(1)
            }
            .foregroundColor(ATheme.ink)
            .padding(.horizontal, 12).frame(height: 34)
            .background(Capsule().fill(ATheme.well))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Try this skin")
    }
}
