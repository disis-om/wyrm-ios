import CoreGraphics
import Foundation
import SwiftUI

/*
 * Skin Studio (OM, 2026-10-12; iOS 2026-10-13): the Skin tab's default page.
 * Android twin: ui/StudioModel.kt (`SkinStudio`), the same library format,
 * limits and wear rules.
 *
 * A player makes beads (a finish, colour, hue, saturation, brightness,
 * opacity, smoothness, detail and their own painting), builds snakes from
 * them (up to 256 beads, up to 48 different ones), and gives each snake its
 * own eyes (any number, anywhere on the head, each with its own white and
 * pupil).
 *
 * Only this phone sees a Studio skin. The arena gets one black bead
 * (slither's colour group 11, `f`), which it repeats along the body; the
 * engine draws the player's own snake from an atlas this file bakes
 * (game/studio.h, WyrmIOSStudioSet). Nothing here goes to the account or to
 * Trails (OM): the library lives in Application Support/skin_studio/ and
 * stays on the phone, through a log out too.
 */

struct WyrmStudioBead: Equatable, Identifiable {
    var id: String
    /// 0xAARRGGBB, opaque.
    var color: UInt32 = 0xFF3F_EE96
    /// `WyrmStudioArt.finishes` index.
    var finish = 0
    /// Degrees, -180..180.
    var hue: Float = 0
    /// 0..2, 1 = unchanged.
    var saturation: Float = 1
    /// 0..2, 1 = unchanged.
    var brightness: Float = 1
    /// 0.15..1.
    var opacity: Float = 1
    /// 0..1: a softer edge and a softer painting.
    var smoothness: Float = 0
    /// 0..1: how strongly the finish shows.
    var detail: Float = 0.7
    /// A painting lives in paint/<id>.png.
    var painted = false
    /// Bumped on every edit: the picture caches key on it.
    var rev = 0
}

struct WyrmStudioEye: Equatable {
    /// Snake units from the head's centre, forward.
    var fwd: Float = 6
    /// Snake units, + = the snake's right.
    var side: Float = 6.5
    /// The white's radius, snake units.
    var white: Float = 6
    /// The pupil's radius, snake units.
    var pupil: Float = 3.5
    /// How far the pupil follows where the snake looks (1 = slither).
    var look: Float = 1
    var whiteColor: UInt32 = 0xFFFF_FFFF
    var pupilColor: UInt32 = 0xFF00_0000
    /// `WyrmStudioArt.whiteShapes` index.
    var whiteShape = 0
    /// `WyrmStudioArt.pupilShapes` index.
    var pupilShape = 0

    /// slither's own eyes: forward 6, 6.5 either side, white 6, pupil 3.5.
    static func pair() -> [WyrmStudioEye] { [WyrmStudioEye(side: -6.5), WyrmStudioEye(side: 6.5)] }
}

struct WyrmStudioSkin: Equatable, Identifiable {
    var id: String
    var name: String
    /// Bead ids, head first; repeated along the snake.
    var pattern: [String]
    var eyes: [WyrmStudioEye] = WyrmStudioEye.pair()
    var updated: Int64 = WyrmStudio.now()
}

/// What the classic Skin page wore before the first Studio skin went on.
struct WyrmStudioClassic {
    var custom: Bool
    var preset: Int
    var groups: String
    var colors: String
}

/// The paintings, readable from any thread (the atlas bakes off the main thread).
final class WyrmStudioPaints {
    static let shared = WyrmStudioPaints()
    private let lock = NSLock()
    private var cache: [String: CGImage] = [:]
    private(set) var folder: URL?

    func attach(_ folder: URL) {
        lock.lock(); self.folder = folder; lock.unlock()
    }

    func image(_ id: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[id] { return hit }
        guard let folder else { return nil }
        let url = folder.appendingPathComponent("\(id).png")
        guard FileManager.default.fileExists(atPath: url.path), let loaded = WyrmStudioArt.loadPNG(url) else { return nil }
        cache[id] = loaded
        return loaded
    }

    /// Stores (or, nil, clears) bead [id]'s painting.
    func store(_ id: String, _ image: CGImage?) {
        lock.lock()
        defer { lock.unlock() }
        guard let folder else { return }
        let url = folder.appendingPathComponent("\(id).png")
        if let image, let data = WyrmStudioArt.png(image) {
            try? data.write(to: url, options: .atomic)
            cache[id] = image
        } else {
            try? FileManager.default.removeItem(at: url)
            cache[id] = nil
        }
    }
}

@MainActor
final class WyrmStudio: ObservableObject {
    static let shared = WyrmStudio()

    nonisolated static let maxPattern = 256
    /// Distinct beads one snake may wear: the atlas' bead cells.
    nonisolated static let maxDistinct = 48
    nonisolated static let maxEyes = 8
    /// slither's darkest bead, colour group 11 ("black"): what the arena gets.
    nonisolated static let arenaGroup = 11

    @Published private(set) var beads: [WyrmStudioBead] = []
    @Published private(set) var skins: [WyrmStudioSkin] = []
    /// The skin being edited on the Studio page.
    @Published private(set) var selected: String?
    /// The skin worn now, or nil.
    @Published private(set) var worn: String?
    /// Bumped when a painting changes, so pictures redraw.
    @Published private(set) var paintRevision = 0

    /// The classic Skin page is the Skin tab's default (OM, 2026-10-13); the Studio opens
    /// from it. CI's Studio probe starts on the Studio.
    @Published var classicOpen = !ProcessInfo.processInfo.arguments.contains("--smoke-skin-studio")

    weak var engine: WyrmShellStore?
    private var root: URL?
    private var classicBefore: WyrmStudioClassic?
    private var rewearGeneration = 0
    private var bakeGeneration = 0
    private var bakeCounter = 0
    private let bakeQueue = DispatchQueue(label: "wyrm.studio.bake", qos: .userInitiated)
    /// The engine's mailbox exists from its first frame; until then a wear waits.
    private var pendingSend: (path: String, text: String)?
    private var sendTimer: Timer?

    nonisolated static var arenaCode: String { WyrmSkinCatalog.code(for: [arenaGroup]) }

    nonisolated static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private init() {}

    /// Once, when the shell's engine store starts: the library, and the worn skin back on the engine.
    func attach(_ engine: WyrmShellStore) {
        self.engine = engine
        guard root == nil else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("skin_studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("paint", isDirectory: true),
                                                 withIntermediateDirectories: true)
        root = dir
        WyrmStudioPaints.shared.attach(dir.appendingPathComponent("paint", isDirectory: true))
        load()
        if beads.isEmpty && skins.isEmpty { seed() }
        if selected == nil || !skins.contains(where: { $0.id == selected }) { selected = worn ?? skins.first?.id }
        // The engine has (re)started: it needs the worn skin again.
        if let skin = skin(worn) { bakeAndSend(skin) }
    }

    // MARK: library

    func bead(_ id: String) -> WyrmStudioBead? { beads.first { $0.id == id } }
    func skin(_ id: String?) -> WyrmStudioSkin? { id.flatMap { wanted in skins.first { $0.id == wanted } } }

    func select(_ id: String) {
        if skins.contains(where: { $0.id == id }) { selected = id }
    }

    @discardableResult
    func newBead(from: WyrmStudioBead? = nil) -> WyrmStudioBead {
        var bead = from ?? WyrmStudioBead(id: "")
        bead.id = newID("b")
        bead.painted = false
        bead.rev = 0
        beads.append(bead)
        if let source = from, source.painted, let picture = WyrmStudioPaints.shared.image(source.id) {
            savePaint(bead.id, picture)
        }
        save()
        return self.bead(bead.id) ?? bead
    }

    func updateBead(_ bead: WyrmStudioBead) {
        beads = beads.map { old in
            guard old.id == bead.id else { return old }
            var next = bead
            next.rev = old.rev + 1
            return next
        }
        save()
        rewearIfWorn { $0.pattern.contains(bead.id) }
    }

    /// A bead no snake wears any more goes; one that is worn stays.
    @discardableResult
    func deleteBead(_ id: String) -> Bool {
        if skins.contains(where: { $0.pattern.contains(id) }) { return false }
        beads.removeAll { $0.id == id }
        WyrmStudioPaints.shared.store(id, nil)
        save()
        return true
    }

    @discardableResult
    func newSkin(name: String? = nil, pattern: [String]? = nil, eyes: [WyrmStudioEye]? = nil) -> WyrmStudioSkin {
        let start = pattern ?? [beads.first?.id ?? newBead().id]
        let skin = WyrmStudioSkin(id: newID("s"), name: name ?? nextName(), pattern: Array(start.prefix(Self.maxPattern)),
                                  eyes: eyes ?? WyrmStudioEye.pair())
        skins.insert(skin, at: 0)
        selected = skin.id
        save()
        return skin
    }

    @discardableResult
    func duplicateSkin(_ id: String) -> WyrmStudioSkin? {
        guard let source = skin(id) else { return nil }
        return newSkin(name: "\(source.name) copy", pattern: source.pattern, eyes: source.eyes)
    }

    func renameSkin(_ id: String, _ name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(28))
        guard !clean.isEmpty else { return }
        skins = skins.map { $0.id == id ? WyrmStudioSkin(id: $0.id, name: clean, pattern: $0.pattern, eyes: $0.eyes, updated: Self.now()) : $0 }
        save()
    }

    func deleteSkin(_ id: String) {
        if worn == id { takeOff() }
        skins.removeAll { $0.id == id }
        if selected == id { selected = skins.first?.id }
        save()
    }

    /// Whether a pattern still fits the atlas.
    func fits(_ pattern: [String]) -> Bool {
        pattern.count <= Self.maxPattern && Set(pattern).count <= Self.maxDistinct
    }

    @discardableResult
    func setPattern(_ id: String, _ pattern: [String]) -> Bool {
        let clean = Array(pattern.filter { bead($0) != nil }.prefix(Self.maxPattern))
        guard !clean.isEmpty, fits(clean) else { return false }
        skins = skins.map { s in
            guard s.id == id else { return s }
            var next = s
            next.pattern = clean
            next.updated = Self.now()
            return next
        }
        save()
        rewearIfWorn { $0.id == id }
        return true
    }

    func setEyes(_ id: String, _ eyes: [WyrmStudioEye]) {
        skins = skins.map { s in
            guard s.id == id else { return s }
            var next = s
            next.eyes = Array(eyes.prefix(Self.maxEyes))
            next.updated = Self.now()
            return next
        }
        save()
        rewearIfWorn { $0.id == id }
    }

    // MARK: painting

    func paint(_ id: String) -> CGImage? { WyrmStudioPaints.shared.image(id) }

    /// Stores a painting for bead [id]; nil clears it.
    func savePaint(_ id: String, _ image: CGImage?) {
        WyrmStudioPaints.shared.store(id, image)
        paintRevision += 1
        beads = beads.map { b in
            guard b.id == id else { return b }
            var next = b
            next.painted = image != nil
            next.rev = b.rev + 1
            return next
        }
        save()
        rewearIfWorn { $0.pattern.contains(id) }
    }

    // MARK: wearing

    /// Wear [id]: bake the atlas, hand it to the engine, and send the arena its one black bead.
    func wear(_ id: String) {
        guard let skin = skin(id) else { return }
        if worn == nil { classicBefore = Self.classicNow() }
        worn = skin.id
        save()
        wearArenaBead()
        bakeAndSend(skin)
    }

    /// Back to the classic skin that was on before the Studio.
    func takeOff() {
        guard worn != nil else { return }
        worn = nil
        send(path: "", text: "")
        if let before = classicBefore { wearClassic(before) }
        classicBefore = nil
        save()
    }

    /// A classic skin reached the engine (WyrmShellStore.applySkin): anything
    /// but the Studio's own black bead ends the Studio skin.
    func classicApplied(custom: Bool, code: String) {
        guard worn != nil else { return }
        if custom && code == Self.arenaCode { return }
        worn = nil
        classicBefore = nil
        send(path: "", text: "")
        save()
    }

    /// Log out: the engine's skin is back to its defaults, so no Studio skin is on. The library stays.
    func dropWorn() {
        guard worn != nil else { return }
        worn = nil
        classicBefore = nil
        send(path: "", text: "")
        save()
    }

    private func rewearIfWorn(_ match: (WyrmStudioSkin) -> Bool) {
        guard let skin = skin(worn), match(skin) else { return }
        rewearGeneration += 1
        let mine = rewearGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.rewearGeneration == mine, let now = self.skin(self.worn) else { return }
            self.bakeAndSend(now)
        }
    }

    private static func classicNow() -> WyrmStudioClassic {
        let d = UserDefaults.standard
        return WyrmStudioClassic(custom: d.bool(forKey: "wyrm.ios.skin.custom-enabled"),
                                 preset: d.object(forKey: "wyrm.ios.skin.preset") as? Int ?? 2,
                                 groups: d.string(forKey: "wyrm.ios.skin.custom-groups") ?? "7,9,7,9",
                                 colors: d.string(forKey: "wyrm.ios.skin.custom-colors") ?? "")
    }

    /// The arena's one black bead, through the classic page's own keys (so the
    /// account's shared skin carries it, as Android's does).
    private func wearArenaBead() {
        let d = UserDefaults.standard
        d.set(String(Self.arenaGroup), forKey: "wyrm.ios.skin.custom-groups")
        d.set("0", forKey: "wyrm.ios.skin.custom-colors")
        d.set(true, forKey: "wyrm.ios.skin.custom-enabled")
        if let engine { WyrmAccountSync.reapplySkin(engine) }
    }

    private func wearClassic(_ classic: WyrmStudioClassic) {
        let d = UserDefaults.standard
        d.set(classic.preset, forKey: "wyrm.ios.skin.preset")
        d.set(classic.groups, forKey: "wyrm.ios.skin.custom-groups")
        d.set(classic.colors, forKey: "wyrm.ios.skin.custom-colors")
        d.set(classic.custom, forKey: "wyrm.ios.skin.custom-enabled")
        if let engine { WyrmAccountSync.reapplySkin(engine) }
    }

    private func bakeAndSend(_ skin: WyrmStudioSkin) {
        guard let root else { return }
        bakeGeneration += 1
        bakeCounter += 1
        let generation = bakeGeneration
        let counter = bakeCounter
        var table: [String: WyrmStudioBead] = [:]
        var paints: [String: CGImage] = [:]
        for id in Set(skin.pattern) {
            guard let bead = bead(id) else { continue }
            table[id] = bead
            if bead.painted, let picture = paint(id) { paints[id] = picture }
        }
        // The Slither finish is slither's own white bead, tinted: the textures
        // load once (held here until the bake is done).
        let textures = WyrmSkinTextureLibrary.acquire()
        textures.prepare()
        bakeQueue.async { [weak self] in
            var waited = 0
            while !textures.ready && textures.failure == nil && waited < 80 {
                Thread.sleep(forTimeInterval: 0.1)
                waited += 1
            }
            let white = textures.beads[40]
            guard let baked = WyrmStudioArt.bakeAtlas(skin, beads: table, paints: paints, white: white),
                  let data = WyrmStudioArt.png(baked.atlas) else { return }
            let file = root.appendingPathComponent("worn_\(Self.now())_\(counter).png")
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
            // Older atlases go once two newer ones exist (the engine may still be decoding the last).
            let fm = FileManager.default
            let olds = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("worn_") && $0.pathExtension == "png" }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da > db
                }
            for old in olds.dropFirst(3) { try? fm.removeItem(at: old) }
            let path = file.path, text = baked.text
            Task { @MainActor in
                guard let self, generation == self.bakeGeneration, self.worn == skin.id else { return }
                self.send(path: path, text: text)
            }
        }
    }

    /// To the engine; before its first frame the mailbox does not exist yet, so it is tried again.
    private func send(path: String, text: String) {
        pendingSend = (path, text)
        flushSend()
        guard pendingSend != nil, sendTimer == nil else { return }
        sendTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushSend() }
        }
    }

    private func flushSend() {
        guard let next = pendingSend else { return }
        let accepted = next.path.withCString { p in next.text.withCString { t in WyrmIOSStudioSet(p, t) } }
        guard accepted else { return }
        pendingSend = nil
        sendTimer?.invalidate()
        sendTimer = nil
        WyrmDiagnostics.record("studio skin sent worn=\(next.path.isEmpty ? "off" : "on")", category: "SKIN")
    }

    // MARK: storage

    private func newID(_ prefix: String) -> String {
        prefix + String(UInt64.random(in: 0...0x7FFF_FFFF_FFFF), radix: 16)
    }

    private func nextName() -> String {
        var n = skins.count + 1
        while skins.contains(where: { $0.name == "Snake \(n)" }) { n += 1 }
        return "Snake \(n)"
    }

    /// Android's library.json, field for field (colours as signed 32-bit numbers).
    private func load() {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("library.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        func f(_ o: [String: Any], _ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Float {
            let v = (o[key] as? NSNumber)?.doubleValue ?? fallback
            return Float(min(max(v.isFinite ? v : fallback, range.lowerBound), range.upperBound))
        }
        func colour(_ o: [String: Any], _ key: String, _ fallback: UInt32) -> UInt32 {
            guard let n = o[key] as? NSNumber else { return fallback }
            return UInt32(truncatingIfNeeded: n.int64Value) | 0xFF00_0000
        }
        func int(_ o: [String: Any], _ key: String, _ range: ClosedRange<Int>) -> Int {
            min(max((o[key] as? NSNumber)?.intValue ?? 0, range.lowerBound), range.upperBound)
        }
        beads = ((json["beads"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let id = o["id"] as? String, !id.isEmpty else { return nil }
            return WyrmStudioBead(id: id, color: colour(o, "color", 0xFF3F_EE96),
                                  finish: int(o, "finish", 0...(WyrmStudioArt.finishes.count - 1)),
                                  hue: f(o, "hue", 0, -180...180), saturation: f(o, "saturation", 1, 0...2),
                                  brightness: f(o, "brightness", 1, 0...2), opacity: f(o, "opacity", 1, 0.15...1),
                                  smoothness: f(o, "smoothness", 0, 0...1), detail: f(o, "detail", 0.7, 0...1),
                                  painted: o["painted"] as? Bool ?? false)
        }
        let known = Set(beads.map(\.id))
        skins = ((json["skins"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let id = o["id"] as? String, !id.isEmpty else { return nil }
            let pattern = Array(((o["pattern"] as? [String]) ?? []).filter { known.contains($0) }.prefix(Self.maxPattern))
            guard !pattern.isEmpty else { return nil }
            let eyes = ((o["eyes"] as? [[String: Any]]) ?? []).prefix(Self.maxEyes).map { e in
                WyrmStudioEye(fwd: f(e, "fwd", 6, -30...30), side: f(e, "side", 6.5, -30...30),
                              white: f(e, "white", 6, 0...20), pupil: f(e, "pupil", 3.5, 0...20),
                              look: f(e, "look", 1, 0...3),
                              whiteColor: colour(e, "whiteColor", 0xFFFF_FFFF),
                              pupilColor: colour(e, "pupilColor", 0xFF00_0000),
                              whiteShape: int(e, "whiteShape", 0...(WyrmStudioArt.whiteShapes.count - 1)),
                              pupilShape: int(e, "pupilShape", 0...(WyrmStudioArt.pupilShapes.count - 1)))
            }
            let name = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Snake"
            return WyrmStudioSkin(id: id, name: name, pattern: pattern, eyes: Array(eyes),
                                  updated: (o["updated"] as? NSNumber)?.int64Value ?? Self.now())
        }
        let wornID = json["worn"] as? String ?? ""
        worn = skins.contains(where: { $0.id == wornID }) ? wornID : nil
        let selectedID = json["selected"] as? String ?? ""
        selected = skins.contains(where: { $0.id == selectedID }) ? selectedID : nil
        if let c = json["classicBefore"] as? [String: Any] {
            classicBefore = WyrmStudioClassic(custom: c["custom"] as? Bool ?? false,
                                              preset: (c["preset"] as? NSNumber)?.intValue ?? 2,
                                              groups: c["groups"] as? String ?? "7,9,7,9",
                                              colors: c["colors"] as? String ?? "")
        }
    }

    private func save() {
        guard let root else { return }
        func signed(_ c: UInt32) -> Int { Int(Int32(bitPattern: c)) }
        var json: [String: Any] = [
            "version": 1,
            "beads": beads.map { b -> [String: Any] in
                ["id": b.id, "color": signed(b.color), "finish": b.finish,
                 "hue": Double(b.hue), "saturation": Double(b.saturation), "brightness": Double(b.brightness),
                 "opacity": Double(b.opacity), "smoothness": Double(b.smoothness), "detail": Double(b.detail),
                 "painted": b.painted]
            },
            "skins": skins.map { s -> [String: Any] in
                ["id": s.id, "name": s.name, "updated": s.updated, "pattern": s.pattern,
                 "eyes": s.eyes.map { e -> [String: Any] in
                     ["fwd": Double(e.fwd), "side": Double(e.side), "white": Double(e.white),
                      "pupil": Double(e.pupil), "look": Double(e.look),
                      "whiteColor": signed(e.whiteColor), "pupilColor": signed(e.pupilColor),
                      "whiteShape": e.whiteShape, "pupilShape": e.pupilShape]
                 }]
            },
            "worn": worn ?? "",
            "selected": selected ?? "",
        ]
        if let c = classicBefore {
            // iOS keeps its classic skin as the Skin page's own keys.
            json["classicBefore"] = ["custom": c.custom, "preset": c.preset, "groups": c.groups, "colors": c.colors]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        try? data.write(to: root.appendingPathComponent("library.json"), options: .atomic)
    }

    /// A first library, so the Studio opens on something to wear and to edit.
    private func seed() {
        func b(_ color: UInt32, _ finish: Int) -> WyrmStudioBead { WyrmStudioBead(id: newID("b"), color: color, finish: finish) }
        let green = b(0xFF3F_EE96, WyrmStudioArt.finishGlossy)
        let deep = b(0xFF0F_6B46, WyrmStudioArt.finishGlossy)
        let pearl = b(0xFFE9_E3FF, WyrmStudioArt.finishPearl)
        let night = b(0xFF24_1B4A, WyrmStudioArt.finishPearl)
        let gold = b(0xFFF2_B33D, WyrmStudioArt.finishMetal)
        let ember = b(0xFFFF_5A1F, WyrmStudioArt.finishGradient)
        let neon = b(0xFF22_E3FF, WyrmStudioArt.finishNeon)
        let candy = b(0xFFFF_4F9A, WyrmStudioArt.finishStripes)
        let scales = b(0xFF2F_B36B, WyrmStudioArt.finishScales)
        beads = [green, deep, pearl, night, gold, ember, neon, candy, scales]
        func times(_ n: Int, _ bead: WyrmStudioBead) -> [String] { Array(repeating: bead.id, count: n) }
        skins = [
            WyrmStudioSkin(id: newID("s"), name: "Wyrm", pattern: times(6, green) + times(2, deep)),
            WyrmStudioSkin(id: newID("s"), name: "Moonlight", pattern: times(4, pearl) + times(4, night)),
            WyrmStudioSkin(id: newID("s"), name: "Sunset", pattern: times(3, gold) + times(3, ember) + times(2, candy)),
            WyrmStudioSkin(id: newID("s"), name: "Neon", pattern: times(5, neon) + times(3, night),
                           eyes: WyrmStudioEye.pair().map { var e = $0; e.pupilShape = WyrmStudioArt.pupilCat; e.whiteColor = 0xFFFF_F27A; return e }),
            WyrmStudioSkin(id: newID("s"), name: "Viper", pattern: times(4, scales) + times(1, deep),
                           eyes: WyrmStudioEye.pair().map { var e = $0; e.pupilShape = WyrmStudioArt.pupilCat; e.whiteColor = 0xFFFF_C23D; e.white = 5.5; return e }),
        ]
        selected = skins.first?.id
        save()
    }

    /// Numbers for the engine: always '.', whatever the phone's language.
    nonisolated static func num(_ value: Float) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(value)) }
}
