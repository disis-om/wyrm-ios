import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: - Atlas (res/textures/wyrm_extras.png + .json, Wyrm Android tools/wyrm-extras/make.py)

/// The engine's extras atlas (OM, 2026-11-07): AIR's special-skin art, NTL's
/// minimap icons (numbered as NTL's `di`) and Wyrm's own minimap icons.
/// Android twin: `ui/WyrmExtras.kt`.
final class WyrmExtrasAtlas {
    static let shared = WyrmExtrasAtlas()
    private var sheet: CGImage?
    private var json: [String: Any] = [:]
    private var cache: [String: CGImage] = [:]
    private let lock = NSLock()

    @discardableResult
    func load() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if sheet != nil { return true }
        guard let root = Bundle.main.resourceURL else { return false }
        let png = root.appendingPathComponent("res/textures/wyrm_extras.png")
        let meta = root.appendingPathComponent("res/textures/wyrm_extras.json")
        guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let data = try? Data(contentsOf: meta),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        sheet = image
        json = object
        return true
    }

    private func cut(_ key: String, _ r: [Int]) -> CGImage? {
        if let hit = cache[key] { return hit }
        guard r.count >= 4, let sheet,
              let image = sheet.cropping(to: CGRect(x: r[0], y: r[1], width: r[2], height: r[3])) else { return nil }
        cache[key] = image
        return image
    }

    private static func ints(_ value: Any?) -> [Int] {
        (value as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
    }

    var wyrmCount: Int { (json["wyrm"] as? [Any])?.count ?? 0 }
    var ntlCount: Int { (json["ntl"] as? [Any])?.count ?? 0 }

    func wyrmIcon(_ index: Int) -> CGImage? {
        load()
        lock.lock(); defer { lock.unlock() }
        guard let list = json["wyrm"] as? [[Any]], list.indices.contains(index) else { return nil }
        let r = list[index].dropFirst().compactMap { ($0 as? NSNumber)?.intValue }
        return cut("wyrm:\(index)", Array(r))
    }

    func ntlIcon(_ di: Int) -> CGImage? {
        load()
        lock.lock(); defer { lock.unlock() }
        if let list = json["ntl"] as? [Any], list.indices.contains(di) {
            return cut("ntl:\(di)", Self.ints(list[di]))
        }
        if (996...1000).contains(di), let special = json["ntlSpecial"] as? [String: Any] {
            return cut("ntl:\(di)", Self.ints(special[String(di)]))
        }
        return nil
    }

    /// AIR art by name, with its pivot (fractions of its size).
    /// AIR art: a square cell with the piece in its middle; `ow` its own width.
    func art(_ name: String) -> (image: CGImage, pivotX: CGFloat, pivotY: CGFloat, ow: CGFloat)? {
        load()
        lock.lock(); defer { lock.unlock() }
        guard let air = json["air"] as? [String: Any], let row = air[name] as? [Any], row.count >= 6 else { return nil }
        let r = row.prefix(4).compactMap { ($0 as? NSNumber)?.intValue }
        guard let image = cut("air:\(name)", r) else { return nil }
        let ow = row.count > 6 ? CGFloat((row[6] as? NSNumber)?.doubleValue ?? Double(image.width)) : CGFloat(image.width)
        return (image, CGFloat((row[4] as? NSNumber)?.doubleValue ?? 0.5), CGFloat((row[5] as? NSNumber)?.doubleValue ?? 0.5), ow)
    }
}

/// Main.as setSkin antenna skins: preset -> bulb, tint (atc2), bulb scale, base (atc1).
enum WyrmAirAntennas {
    struct Antenna { let bulb: String; let tint: UInt32; let scale: CGFloat; let base: UInt32 }
    static let all: [Int: Antenna] = [
        24: .init(bulb: "acbulb", tint: 6605031, scale: 0.25, base: 26764),
        25: .init(bulb: "cdbulb", tint: 5648599, scale: 0.34, base: 0),
        37: .init(bulb: "kwkbulb", tint: 16738323, scale: 0.45, base: 3150848),
        39: .init(bulb: "pwdbulb", tint: 4510975, scale: 0.25, base: 1913413),
        42: .init(bulb: "playbulb", tint: 8442064, scale: 0.36, base: 10280),
        45: .init(bulb: "leafbulb", tint: 16728128, scale: 0.33, base: 12591136),
        46: .init(bulb: "swissbulb", tint: 16728128, scale: 0.285, base: 12591136),
        47: .init(bulb: "moldovabulb", tint: 6316287, scale: 0.33, base: 3158271),
        48: .init(bulb: "vietbulb", tint: 16728128, scale: 0.3, base: 12591136),
        49: .init(bulb: "argentinabulb", tint: 8707327, scale: 0.33, base: 6597839),
        59: .init(bulb: "movbulb", tint: 16769088, scale: 0.33, base: 8939544),
        62: .init(bulb: "bonkbulb", tint: 16761359, scale: 0.25, base: 4203008),
        65: .init(bulb: "fgteevbulb", tint: 16777215, scale: 0.33, base: 8421504),
    ]
}

// MARK: - Minimap icons (Settings › Display › Minimap icons)

/// The icon NTL teammates see for you (NTL's numbering, 1000 = its plain dot)
/// and the one Wyrm friends see (Wyrm's own icons). Synced (`wyrm.ios.minimap-icons.`)
/// and account-wide: shared keys `ntlMinimapIcon`, `wyrmMinimapIcon`.
/// Android twin: `data/MinimapIcons.kt`.
@MainActor
final class WyrmMinimapIcons: ObservableObject {
    static let shared = WyrmMinimapIcons()
    static let ntlKey = "wyrm.ios.minimap-icons.ntl"
    static let wyrmKey = "wyrm.ios.minimap-icons.wyrm"
    static let ntlDefault = 1000
    static let wyrmCount = 20

    @Published private(set) var ntl: Int
    @Published private(set) var wyrm: Int

    static func validNtl(_ v: Int) -> Bool { (0...741).contains(v) || (996...1000).contains(v) }
    static func validWyrm(_ v: Int) -> Bool { (0..<wyrmCount).contains(v) }

    private init() {
        let d = UserDefaults.standard
        let n = d.object(forKey: Self.ntlKey) as? Int ?? Self.ntlDefault
        let w = d.object(forKey: Self.wyrmKey) as? Int ?? 0
        ntl = Self.validNtl(n) ? n : Self.ntlDefault
        wyrm = Self.validWyrm(w) ? w : 0
    }

    func reload() {
        let d = UserDefaults.standard
        let n = d.object(forKey: Self.ntlKey) as? Int ?? Self.ntlDefault
        let w = d.object(forKey: Self.wyrmKey) as? Int ?? 0
        ntl = Self.validNtl(n) ? n : Self.ntlDefault
        wyrm = Self.validWyrm(w) ? w : 0
    }

    func setNtl(_ v: Int) { guard Self.validNtl(v) else { return }; ntl = v; UserDefaults.standard.set(v, forKey: Self.ntlKey) }
    func setWyrm(_ v: Int) { guard Self.validWyrm(v) else { return }; wyrm = v; UserDefaults.standard.set(v, forKey: Self.wyrmKey) }

    /// Shared document restore: each key on its own, an unknown number skipped.
    static func restore(ntl: Int?, wyrm: Int?) {
        let d = UserDefaults.standard
        if let ntl, validNtl(ntl) { d.set(ntl, forKey: ntlKey) }
        if let wyrm, validWyrm(wyrm) { d.set(wyrm, forKey: wyrmKey) }
    }
}

struct WyrmMinimapIconsSection: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var colours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    @ObservedObject private var icons = WyrmMinimapIcons.shared
    @State private var ready = false
    @State private var picking: String?

    var body: some View {
        VStack(spacing: 0) {
            WSSectionLabel("Minimap icons")
            WSCard {
                row("NTL team", "What NTL teammates see for you on their map.",
                    ready ? WyrmExtrasAtlas.shared.ntlIcon(icons.ntl) : nil, first: true) { picking = "ntl" }
                row("Wyrm friends", "What Wyrm friends see for you on their map. Friends are people you follow who follow you back.",
                    ready ? WyrmExtrasAtlas.shared.wyrmIcon(icons.wyrm) : nil, first: false) { picking = "wyrm" }
            }
            WSCaption("Your own place keeps the green arrow. Friends and teammates in your arena show with the icon they chose.")
        }
        .task { ready = await Task.detached { WyrmExtrasAtlas.shared.load() }.value }
        .sheet(item: Binding(get: { picking.map { WyrmPickKind(id: $0) } }, set: { picking = $0?.id })) { kind in
            WyrmIconPicker(kind: kind.id) { picking = nil }
        }
    }

    private func row(_ title: String, _ detail: String, _ icon: CGImage?, first: Bool, open: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            Button(action: open) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.androidWyrm(15.5)).foregroundColor(colours.ink)
                        Text(detail).font(.androidWyrm(12.5)).foregroundColor(colours.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    ZStack {
                        Circle().fill(colours.ink.opacity(0.08)).frame(width: 40, height: 40)
                        if let icon { Image(decorative: icon, scale: 1).resizable().interpolation(.medium).frame(width: 28, height: 28) }
                    }
                    Text("›").font(.androidWyrm(17)).foregroundColor(colours.quiet)
                }.padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

private struct WyrmPickKind: Identifiable { let id: String }

private struct WyrmIconPicker: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var colours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    @ObservedObject private var icons = WyrmMinimapIcons.shared
    let kind: String
    let close: () -> Void

    private var choices: [Int] {
        kind == "ntl" ? [WyrmMinimapIcons.ntlDefault] + Array(0..<WyrmExtrasAtlas.shared.ntlCount)
                      : Array(0..<WyrmExtrasAtlas.shared.wyrmCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == "ntl" ? "NTL team icon" : "Wyrm friends icon")
                .font(.androidWyrm(18, .bold)).foregroundColor(colours.ink)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                    ForEach(choices, id: \.self) { value in
                        let selected = kind == "ntl" ? icons.ntl == value : icons.wyrm == value
                        Button {
                            if kind == "ntl" { icons.setNtl(value) } else { icons.setWyrm(value) }
                            close()
                        } label: {
                            ZStack {
                                Circle().fill(colours.ink.opacity(selected ? 0.12 : 0.04))
                                if selected { Circle().stroke(colours.ink, lineWidth: 2) }
                                if let image = kind == "ntl" ? WyrmExtrasAtlas.shared.ntlIcon(value) : WyrmExtrasAtlas.shared.wyrmIcon(value) {
                                    Image(decorative: image, scale: 1).resizable().interpolation(.medium).frame(width: 28, height: 28)
                                }
                            }.frame(width: 42, height: 42)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(colours.card.ignoresSafeArea())
        .wyrmHalfSheet()
    }
}

// MARK: - Wyrm friends on the minimap

/// Friends' places from the live socket (backend friend-locations.mjs), kept six
/// seconds, handed to the engine once a second; your own place goes out while a
/// friend plays in your arena. Android twin: WyrmOverlay.tickFriendLocations.
@MainActor
final class WyrmFriendMarks {
    static let shared = WyrmFriendMarks()
    private struct Mark { let x: Int; let y: Int; let icon: Int; let at: Date }
    private var marks: [String: Mark] = [:]
    private var timer: Timer?
    private var sent = ""
    /// The shell says whether an online match (not Play with AI) is on screen.
    var playing: () -> Bool = { false }

    func record(id: String, x: Int, y: Int, icon: Int) {
        marks[id] = Mark(x: x, y: y, icon: icon, at: Date())
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in WyrmFriendMarks.shared.tick() }
        }
    }

    private func tick() {
        let inMatch = playing()
        if inMatch, WyrmLiveInbox.shared.locationWanted, let me = WyrmTeamPresence.current(), me.x != 0 || me.y != 0 {
            WyrmLiveInbox.shared.sendLocation(x: me.x, y: me.y, icon: WyrmMinimapIcons.shared.wyrm)
        }
        let now = Date()
        marks = marks.filter { now.timeIntervalSince($0.value.at) < 6 }
        let packed = inMatch ? marks.values.map { "\($0.x)\t\($0.y)\t\($0.icon)" }.joined(separator: "\n") : ""
        if packed != sent {
            sent = packed
            packed.withCString { WyrmIOSSetFriendMarks($0) }
        }
    }
}

// MARK: - Your own photos as the arena floor

/// Gallery floors (OM, 2026-11-08): shrunk on the phone (long side 2048 px,
/// JPEG), kept in Application Support, worn as engine background index 200.
/// Phone only (`wyrm.ios.custom-floors.` wipes on log out; the photos are
/// never uploaded). Android twin: `data/CustomFloors.kt`.
@MainActor
final class WyrmCustomFloors: ObservableObject {
    static let shared = WyrmCustomFloors()
    static let index = 200
    static let listKey = "wyrm.ios.custom-floors.list"
    static let chosenKey = "wyrm.ios.custom-floors.chosen"

    struct Floor: Codable, Identifiable, Equatable { let id: String; let file: String; let width: Int; let height: Int }

    @Published private(set) var floors: [Floor] = []
    @Published private(set) var chosen: String?

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("custom_floors", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func path(_ floor: Floor) -> String { folder.appendingPathComponent(floor.file).path }

    func reload() {
        let d = UserDefaults.standard
        let list = (d.data(forKey: Self.listKey)).flatMap { try? JSONDecoder().decode([Floor].self, from: $0) } ?? []
        floors = list.filter { FileManager.default.fileExists(atPath: path($0)) }
        let keep = Set(floors.map(\.file))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        chosen = d.string(forKey: Self.chosenKey).flatMap { id in floors.contains { $0.id == id } ? id : nil }
        publish()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(floors), forKey: Self.listKey)
        d.set(chosen, forKey: Self.chosenKey)
    }

    private func publish() {
        let floor = floors.first { $0.id == chosen }
        let p = floor.map(path) ?? ""
        p.withCString { WyrmIOSSetCustomFloor($0, Int32(floor?.width ?? 0), Int32(floor?.height ?? 0)) }
    }

    /// Shrinks and saves the photo off the main thread.
    func add(data: Data) async -> Floor? {
        let folder = self.folder
        return await Task.detached { () -> Floor? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, // turned the way it was taken
                kCGImageSourceThumbnailMaxPixelSize: 2048,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let id = UUID().uuidString
            let url = folder.appendingPathComponent("\(id).jpg")
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return Floor(id: id, file: "\(id).jpg", width: image.width, height: image.height)
        }.value
    }

    func keep(_ floor: Floor) { floors.append(floor); save() }

    func choose(_ id: String) { chosen = id; save(); publish() }

    /// True when the worn photo was among the deleted.
    func delete(_ ids: Set<String>) -> Bool {
        for floor in floors where ids.contains(floor.id) { try? FileManager.default.removeItem(atPath: path(floor)) }
        floors.removeAll { ids.contains($0.id) }
        let wornGone = chosen.map(ids.contains) ?? false
        if wornGone { chosen = nil }
        save(); publish()
        return wornGone
    }

    func thumbnail(_ floor: Floor) -> CGImage? {
        let url = URL(fileURLWithPath: path(floor))
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256,
        ] as CFDictionary)
    }
}

/// Your photos and the Add tile, above the built-in floors in Skin › Arena background.
struct WyrmCustomFloorsGrid: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var colours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    @ObservedObject private var store = WyrmCustomFloors.shared
    let worn: Int
    let wear: (Int) -> Void
    @State private var picking = false
    @State private var busy = false
    @State private var failed = false
    @State private var deleting: Set<String>?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(store.floors) { floor in
                tile(label: "Your photo", selected: worn == WyrmCustomFloors.index && store.chosen == floor.id,
                     image: store.thumbnail(floor))
                    .onTapGesture { store.choose(floor.id); wear(WyrmCustomFloors.index) }
                    .onLongPressGesture { deleting = [floor.id] }
            }
            Button { if !busy { picking = true } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 13).fill(colours.ink.opacity(0.06)).frame(height: 78)
                        .overlay(Text(busy ? "…" : "+").font(.androidWyrm(30)).foregroundColor(colours.ink))
                    Text(failed ? "Could not read it" : "Your photo").font(.androidWyrm(10.5, .semibold))
                        .foregroundColor(failed ? .red : colours.ink).lineLimit(1)
                }.padding(8).background(colours.card.opacity(0.92)).cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(colours.rule, lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(.bottom, 10)
        .sheet(isPresented: $picking) {
            WyrmFloorPhotoPicker { data in
                picking = false
                guard let data else { return }
                busy = true; failed = false
                Task {
                    let floor = await store.add(data: data)
                    busy = false
                    if let floor { store.keep(floor); store.choose(floor.id); wear(WyrmCustomFloors.index) } else { failed = true }
                }
            }
        }
        .sheet(item: Binding(get: { deleting.map { WyrmDeleteSet(ids: $0) } }, set: { deleting = $0?.ids })) { set in
            WyrmFloorDeleteSheet(start: set.ids) { wornGone in
                deleting = nil
                if wornGone && worn == WyrmCustomFloors.index { wear(0) }
            } cancel: { deleting = nil }
        }
    }

    private func tile(label: String, selected: Bool, image: CGImage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 13).fill(colours.ink).frame(maxWidth: .infinity).frame(height: 78)
                .overlay { if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() } }
                .clipShape(RoundedRectangle(cornerRadius: 13))
            HStack { Text(label).font(.androidWyrm(10.5, .semibold)).lineLimit(1); Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) } }
        }.padding(8).background(colours.card.opacity(0.92)).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? colours.ink : colours.rule, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
    }
}

private struct WyrmDeleteSet: Identifiable { let ids: Set<String>; var id: String { ids.sorted().joined() } }

private struct WyrmFloorDeleteSheet: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var colours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    @ObservedObject private var store = WyrmCustomFloors.shared
    @State private var ticked: Set<String>
    let done: (Bool) -> Void
    let cancel: () -> Void

    init(start: Set<String>, done: @escaping (Bool) -> Void, cancel: @escaping () -> Void) {
        _ticked = State(initialValue: start); self.done = done; self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your photos").font(.androidWyrm(18, .bold)).foregroundColor(colours.ink)
            Text("Tick the ones to delete.").font(.androidWyrm(13)).foregroundColor(colours.quiet)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(store.floors) { floor in
                        let on = ticked.contains(floor.id)
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 12).fill(colours.ink).frame(height: 80)
                                .overlay { if let image = store.thumbnail(floor) { Image(decorative: image, scale: 1).resizable().scaledToFill() } }
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.red : .clear, lineWidth: 3))
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(on ? .red : .white).padding(6)
                        }.onTapGesture { if on { ticked.remove(floor.id) } else { ticked.insert(floor.id) } }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).foregroundColor(colours.ink)
                Button(ticked.isEmpty ? "Delete" : "Delete \(ticked.count)") { done(store.delete(ticked)) }
                    .font(.androidWyrm(15, .bold)).foregroundColor(ticked.isEmpty ? colours.quiet : .red)
                    .disabled(ticked.isEmpty).padding(.leading, 16)
            }
        }
        .padding(20)
        .background(colours.card.ignoresSafeArea())
        .wyrmHalfSheet()
    }
}

private extension View {
    /// Half height first (iOS 16+); a full sheet before.
    @ViewBuilder
    func wyrmHalfSheet() -> some View {
        if #available(iOS 16.0, *) { self.presentationDetents([.medium, .large]) } else { self }
    }
}

/// The system photo picker (PHPicker, iOS 14+): one image's data, or nil.
private struct WyrmFloorPhotoPicker: UIViewControllerRepresentable {
    let done: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                DispatchQueue.main.async { self.done(nil) }
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async { self.done(data) }
            }
        }
    }
}
