import SwiftUI
import UIKit
import ImageIO

/// SwiftUI owns this editor and its preview. It reads the exact immutable
/// textures bundled with the engine; no engine render surface is embedded.
final class WyrmSkinTextureLibrary: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var failure: String?

    private(set) var beads: [Int: CGImage] = [:]
    private(set) var accessories: [Int: CGImage] = [:]
    private(set) var tags: [Int: CGImage] = [:]
    private(set) var backgrounds: [Int: CGImage] = [:]
    private var loading = false

    func prepare() {
        guard !ready, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let atlasURL = try Self.resource("res/textures/tex_atlas_8k.png")
                let tagURL = try Self.resource("res/textures/wyrm_tags.png")
                guard let atlas = Self.downsample(atlasURL, maxPixel: 2016),
                      let tagAtlas = Self.downsample(tagURL, maxPixel: 2048) else {
                    throw TextureError.decode
                }

                var beadImages: [Int: CGImage] = [:]
                for id in 0..<42 {
                    let column = id % 7
                    let row = id / 7
                    beadImages[id] = Self.crop(atlas,
                        x: Double(column) / 7, y: Double(row) / 9,
                        width: 1.0 / 7, height: 1.0 / 9)
                }

                var accessoryImages: [Int: CGImage] = [:]
                for id in 0..<32 {
                    accessoryImages[id] = Self.crop(atlas,
                        x: 5.0 / 7 + Double(id % 8) / 28,
                        y: 8.0 / 9 + Double(id / 8) / 36,
                        width: 1.0 / 28, height: 1.0 / 36)
                }

                var tagImages: [Int: CGImage] = [:]
                for tag in WyrmSkinCatalog.tags {
                    tagImages[tag.id] = Self.crop(tagAtlas,
                        x: tag.minU, y: tag.minV,
                        width: tag.maxU - tag.minU, height: tag.maxV - tag.minV)
                }

                var backgroundImages: [Int: CGImage] = [:]
                for background in WyrmSkinCatalog.backgrounds {
                    guard let path = background.resourcePath,
                          let url = try? Self.resource(path),
                          let image = Self.downsample(url, maxPixel: 520) else { continue }
                    backgroundImages[background.id] = image
                }

                DispatchQueue.main.async {
                    self.beads = beadImages
                    self.accessories = accessoryImages
                    self.tags = tagImages
                    self.backgrounds = backgroundImages
                    self.ready = true
                    self.loading = false
                    NSLog("Wyrm native skin textures ready beads=%d accessories=%d tags=%d backgrounds=%d",
                          beadImages.count, accessoryImages.count, tagImages.count, backgroundImages.count)
                }
            } catch {
                DispatchQueue.main.async {
                    self.failure = error.localizedDescription
                    self.loading = false
                    NSLog("Wyrm native skin textures failed: %@", error.localizedDescription)
                }
            }
        }
    }

    private enum TextureError: LocalizedError {
        case missing(String), decode
        var errorDescription: String? {
            switch self {
            case .missing(let path): return "Missing original texture: \(path)"
            case .decode: return "Original skin textures could not be decoded"
            }
        }
    }

    private static func resource(_ path: String) throws -> URL {
        guard let root = Bundle.main.resourceURL else { throw TextureError.missing(path) }
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw TextureError.missing(path) }
        return url
    }

    private static func downsample(_ url: URL, maxPixel: Int) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    private static func crop(_ image: CGImage, x: Double, y: Double,
                             width: Double, height: Double) -> CGImage? {
        let pixelRect = CGRect(
            x: (x * Double(image.width)).rounded(.down),
            y: (y * Double(image.height)).rounded(.down),
            width: max(1, (width * Double(image.width)).rounded()),
            height: max(1, (height * Double(image.height)).rounded())
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixelRect.isNull, pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        return image.cropping(to: pixelRect)
    }
}

private enum WyrmSkinStudioSection: String, CaseIterable, Identifiable {
    case overview, presets, pattern, accessories, tags, background
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Skin wardrobe"
        case .presets: return "Default skins"
        case .pattern: return "Pattern"
        case .accessories: return "Accessory"
        case .tags: return "Tag"
        case .background: return "Arena background"
        }
    }
}

struct WyrmSkinRoot: View {
    @ObservedObject var engine: WyrmShellStore
    @StateObject private var textures = WyrmSkinTextureLibrary()
    @State private var section: WyrmSkinStudioSection

    @AppStorage("wyrm.ios.skin.preset") private var preset = 2
    @AppStorage("wyrm.ios.skin.custom-enabled") private var customEnabled = false
    @AppStorage("wyrm.ios.skin.custom-groups") private var pattern = "7,9,7,9"
    @AppStorage("wyrm.ios.skin.accessory-id") private var accessory = -1
    @AppStorage("wyrm.ios.skin.tag-id") private var tag = -1
    @AppStorage("wyrm.ios.skin.background-id") private var background = 0
    @AppStorage("wyrm.ios.skin.tag-chain") private var chain = 1.0
    @AppStorage("wyrm.ios.skin.tag-swing") private var swing = 1.0
    @AppStorage("wyrm.ios.skin.tag-scale") private var tagScale = 1.0

    init(engine: WyrmShellStore) {
        self.engine = engine
        let arguments = ProcessInfo.processInfo.arguments
        let initial: WyrmSkinStudioSection = arguments.contains("--smoke-skin-tags") ? .tags
            : arguments.contains("--smoke-skin-accessories") ? .accessories
            : .overview
        _section = State(initialValue: initial)
    }

    private var customGroups: [Int] {
        let result = pattern.split(separator: ",").compactMap { Int($0) }
            .filter { WyrmSkinCatalog.validGroups.contains($0) }
        return result.isEmpty ? [7, 9] : Array(result.prefix(64))
    }

    private var activeGroups: [Int] {
        if customEnabled { return customGroups }
        guard WyrmSkinCatalog.presets.indices.contains(preset) else { return [7] }
        return WyrmSkinCatalog.presets[preset]
    }

    var body: some View {
        VStack(spacing: 0) {
            WyrmScreenHeader(kicker: "WYRM", title: "Skin")
            WyrmSkinPreview(textures: textures, groups: activeGroups,
                            accessoryID: accessory, tagID: tag,
                            backgroundID: background, chain: chain,
                            swing: swing, tagScale: tagScale)
                .frame(height: 218)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live native preview of the selected Wyrm skin")

            Rectangle().fill(ATheme.rule).frame(height: 1).padding(.horizontal, 20)

            ScrollView(showsIndicators: false) {
                Group {
                    switch section {
                    case .overview: overview
                    case .presets: presetsPanel
                    case .pattern: patternPanel
                    case .accessories: accessoriesPanel
                    case .tags: tagsPanel
                    case .background: backgroundsPanel
                    }
                }
                .id(section)
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                .padding(.bottom, 108)
            }
        }
        .background(ATheme.paper)
        .onAppear {
            textures.prepare()
            if ProcessInfo.processInfo.arguments.contains("--smoke-skin-accessories"), accessory < 0 { accessory = 0 }
            if ProcessInfo.processInfo.arguments.contains("--smoke-skin-tags"), tag < 0 { tag = 0 }
            NSLog("Wyrm SwiftUI skin studio presented section=%@", section.rawValue)
        }
    }

    private var overview: some View {
        VStack(spacing: 0) {
            WyrmSectionLabel("Build your Wyrm")
            WyrmPaperCard {
                studioRow(.presets, value: "\(WyrmSkinCatalog.presets.count)", detail: "Original engine skins")
                studioRow(.pattern, value: customEnabled ? "Custom" : "Preset", detail: "Original bead groups")
                studioRow(.accessories, value: accessory < 0 ? "None" : String(format: "%02d", accessory + 1), detail: "\(WyrmSkinCatalog.accessories.count) atlas pieces")
                studioRow(.tags, value: WyrmSkinCatalog.tags[safe: tag].map { "#\($0.ntlID)" } ?? "None", detail: "\(WyrmSkinCatalog.tags.count) original tags")
                studioRow(.background, value: WyrmSkinCatalog.backgrounds[safe: background]?.label ?? "Wyrm", detail: "Arena floor")
            }
            HStack(spacing: 7) {
                Circle().fill(textures.ready ? ATheme.live : ATheme.quiet).frame(width: 7, height: 7)
                Text(textures.ready ? "ORIGINAL TEXTURES READY" : "LOADING ORIGINAL TEXTURES")
                    .font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(ATheme.quiet)
            }.padding(.top, 18)
            if let failure = textures.failure {
                Text(failure).font(.androidWyrm(11)).foregroundColor(.red).padding(12)
            }
        }
    }

    private func studioRow(_ target: WyrmSkinStudioSection, value: String, detail: String) -> some View {
        WyrmListRow(title: target.title, detail: detail, value: value) { enter(target) }
    }

    private var inlineHeader: some View {
        HStack(spacing: 10) {
            Button { enter(.overview) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34).background(Color.white.opacity(0.92)).clipShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel("Back to skin wardrobe")
            Text(section.title).font(.androidWyrm(18, .bold))
            Spacer()
            Text("AUTO-SAVED").font(.androidWyrm(8.5, .bold)).tracking(1).foregroundColor(ATheme.live)
        }.padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 12)
    }

    private var presetsPanel: some View {
        VStack(spacing: 0) {
            inlineHeader
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(WyrmSkinCatalog.presets.indices, id: \.self) { index in
                    Button {
                        preset = index; customEnabled = false; apply(preset: index, custom: false)
                    } label: {
                        VStack(spacing: 8) {
                            WyrmMiniSnake(textures: textures, groups: WyrmSkinCatalog.presets[index])
                                .frame(height: 35)
                            Text(String(format: "%02d", index + 1)).font(.androidWyrm(10.5, .bold))
                        }.frame(maxWidth: .infinity).frame(height: 76)
                            .background(Color.white.opacity(0.92)).cornerRadius(15)
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(!customEnabled && preset == index ? ATheme.ink : ATheme.rule, lineWidth: !customEnabled && preset == index ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("Default skin \(index + 1)")
                }
            }.padding(.horizontal, 16)
        }
    }

    private var patternPanel: some View {
        VStack(spacing: 0) {
            inlineHeader
            HStack(spacing: 10) {
                Text("\(customGroups.count) / 64 beads").font(.androidWyrm(11, .semibold)).foregroundColor(ATheme.quiet)
                Spacer()
                Button("UNDO") {
                    var groups = customGroups; if groups.count > 1 { groups.removeLast() }
                    savePattern(groups)
                }.font(.androidWyrm(9.5, .bold)).buttonStyle(.plain)
                Button("CLEAR") { savePattern([7, 9]) }
                    .font(.androidWyrm(9.5, .bold)).foregroundColor(.red).buttonStyle(.plain)
            }.padding(.horizontal, 20).padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: -6) {
                    ForEach(Array(customGroups.enumerated()), id: \.offset) { _, group in
                        WyrmAtlasImage(image: textures.beads[group]).frame(width: 38, height: 38)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 6)
            }
            WyrmSectionLabel("Tap an original bead")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(WyrmSkinCatalog.validGroups, id: \.self) { group in
                    Button {
                        var groups = customGroups
                        if groups.count < 64 { groups.append(group); savePattern(groups) }
                    } label: {
                        WyrmAtlasImage(image: textures.beads[group]).padding(5)
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            .background(Color.white.opacity(0.72)).clipShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Bead group \(group)")
                }
            }.padding(.horizontal, 16)
        }
    }

    private var accessoriesPanel: some View {
        VStack(spacing: 0) {
            inlineHeader
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 10)], spacing: 10) {
                selectionTile(selected: accessory < 0, label: "None") {
                    accessory = -1; apply(accessory: -1)
                }
                ForEach(WyrmSkinCatalog.accessories) { item in
                    Button {
                        accessory = item.id; apply(accessory: item.id)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.92))
                            WyrmAtlasImage(image: textures.accessories[item.id]).padding(11)
                            if accessory == item.id { selectionCheck }
                        }.aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(accessory == item.id ? ATheme.ink : ATheme.rule, lineWidth: accessory == item.id ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("Accessory \(item.id + 1)")
                }
            }.padding(.horizontal, 16)
        }
    }

    private var tagsPanel: some View {
        VStack(spacing: 0) {
            inlineHeader
            VStack(spacing: 12) {
                skinSlider("Chain", value: $chain, range: 1...3, setting: "tags.chain")
                skinSlider("Swing", value: $swing, range: 1...2, setting: "tags.swing")
                skinSlider("Size", value: $tagScale, range: 0.4...2, setting: "tags.scale")
            }.padding(.horizontal, 20).padding(.bottom, 4)
            WyrmSectionLabel("All original tags")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                selectionTile(selected: tag < 0, label: "None") { tag = -1; apply(tag: -1) }
                ForEach(WyrmSkinCatalog.tags) { item in
                    Button {
                        tag = item.id; apply(tag: item.id)
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.92))
                            WyrmAtlasImage(image: textures.tags[item.id]).padding(10)
                            Text("\(item.ntlID)").font(.androidWyrm(7.5, .bold)).foregroundColor(ATheme.quiet).padding(6)
                            if tag == item.id { selectionCheck }
                        }.aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(tag == item.id ? ATheme.ink : ATheme.rule, lineWidth: tag == item.id ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("Tag \(item.ntlID)")
                }
            }.padding(.horizontal, 16)
        }
    }

    private var backgroundsPanel: some View {
        VStack(spacing: 0) {
            inlineHeader
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(WyrmSkinCatalog.backgrounds) { item in
                    Button {
                        background = item.id; apply(background: item.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 13).fill(item.id == 1 ? ATheme.paper : ATheme.ink.opacity(0.05))
                                if let image = textures.backgrounds[item.id] {
                                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                                } else if item.id == 1 {
                                    Image(systemName: "circle.slash").foregroundColor(ATheme.quiet)
                                }
                            }.frame(height: 78).clipShape(RoundedRectangle(cornerRadius: 13))
                            HStack { Text(item.label).font(.androidWyrm(10.5, .semibold)).lineLimit(1); Spacer(); if background == item.id { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) } }
                        }.padding(8).background(Color.white.opacity(0.92)).cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(background == item.id ? ATheme.ink : ATheme.rule, lineWidth: background == item.id ? 2 : 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }

    private var selectionCheck: some View {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold))
            .foregroundColor(ATheme.ink).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func selectionTile(selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.92))
                Text(label.uppercased()).font(.androidWyrm(9, .bold)).tracking(0.7)
                if selected { selectionCheck }
            }.aspectRatio(1, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain)
    }

    private func skinSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, setting: String) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title).font(.androidWyrm(11.5, .semibold)); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) }
            Slider(value: value, in: range).tint(ATheme.ink)
                .onChange(of: value.wrappedValue) { next in writeTagSetting(setting, next) }
        }.padding(12).background(Color.white.opacity(0.88)).cornerRadius(14)
    }

    private func enter(_ target: WyrmSkinStudioSection) {
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.1)) { section = target }
    }

    private func savePattern(_ groups: [Int]) {
        pattern = groups.map(String.init).joined(separator: ",")
        customEnabled = true
        apply(groups: groups, custom: true)
    }

    private func writeTagSetting(_ id: String, _ value: Double) {
        guard let setting = engine.settings.first(where: { $0.id == id }) else { return }
        engine.write(setting, values: [value])
    }

    private func apply(preset newPreset: Int? = nil, groups: [Int]? = nil,
                       custom: Bool? = nil, accessory newAccessory: Int? = nil,
                       tag newTag: Int? = nil, background newBackground: Int? = nil) {
        engine.applySkin(
            preset: newPreset ?? preset,
            groups: groups ?? customGroups,
            custom: custom ?? customEnabled,
            accessory: newAccessory ?? accessory,
            tag: newTag ?? tag,
            background: newBackground ?? background
        )
    }
}

private struct WyrmSkinPreview: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let groups: [Int]
    let accessoryID: Int
    let tagID: Int
    let backgroundID: Int
    let chain: Double
    let swing: Double
    let tagScale: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            GeometryReader { proxy in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let head = CGPoint(x: proxy.size.width * 0.79,
                                   y: proxy.size.height * 0.48 + CGFloat(sin(phase * 1.2)) * 3)
                ZStack {
                    if let image = textures.backgrounds[backgroundID] {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .opacity(0.2)
                            .mask(RadialGradient(colors: [.black, .black.opacity(0.55), .clear], center: .center, startRadius: 15, endRadius: proxy.size.width * 0.52))
                    }
                    ForEach(0..<20, id: \.self) { index in
                        let p = CGFloat(index) / 19
                        let x = proxy.size.width * (0.14 + 0.65 * p)
                        let wave = sin(Double(p) * 5.2 + phase * 1.35) * 17
                        let y = proxy.size.height * 0.5 + CGFloat(wave) * (0.35 + p * 0.65)
                        let size = 23 + p * 23
                        let group = groups.isEmpty ? 7 : groups[(19 - index) % groups.count]
                        WyrmAtlasImage(image: textures.beads[group])
                            .frame(width: size, height: size).position(x: x, y: y)
                            .shadow(color: ATheme.ink.opacity(0.12), radius: 2, y: 2)
                    }
                    eyes(at: head)
                    if let item = WyrmSkinCatalog.accessories[safe: accessoryID],
                       let image = textures.accessories[accessoryID] {
                        let size = 29 * CGFloat(item.scale)
                        WyrmAtlasImage(image: image).frame(width: size, height: size)
                            .position(x: head.x + CGFloat(item.offset) * 5.4, y: head.y - 1)
                    }
                    if let item = WyrmSkinCatalog.tags[safe: tagID],
                       let image = textures.tags[tagID] {
                        tagPreview(item: item, image: image, head: head, phase: phase)
                    }
                    if !textures.ready {
                        ProgressView().tint(ATheme.ink).position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                    Text("NATIVE ATLAS PREVIEW").font(.androidWyrm(8.5, .bold)).tracking(1.35).foregroundColor(ATheme.quiet)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 12)
                }.clipped()
            }
        }
    }

    private func eyes(at head: CGPoint) -> some View {
        ZStack {
            Circle().fill(.white).frame(width: 13, height: 13).offset(y: -7)
            Circle().fill(.white).frame(width: 13, height: 13).offset(y: 7)
            Circle().fill(ATheme.ink).frame(width: 5, height: 5).offset(x: 3, y: -7)
            Circle().fill(ATheme.ink).frame(width: 5, height: 5).offset(x: 3, y: 7)
        }.position(x: head.x + 13, y: head.y)
    }

    private func tagPreview(item: WyrmTagAsset, image: CGImage, head: CGPoint, phase: Double) -> some View {
        let rope = CGFloat(28 * chain)
        let sway = CGFloat(sin(phase * 1.5) * 11 * swing)
        let end = CGPoint(x: head.x - rope + sway, y: head.y + rope * 0.72)
        let colour = Color(rgb: item.accentB)
        let width = min(72, CGFloat(item.width) * 0.28 * CGFloat(tagScale))
        let height = min(72, CGFloat(item.height) * 0.28 * CGFloat(tagScale))
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: head.x - 13, y: head.y + 3))
                path.addQuadCurve(to: end, control: CGPoint(x: head.x - rope * 0.25, y: head.y + rope * 0.88))
            }.stroke(colour.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            WyrmAtlasImage(image: image).frame(width: width, height: height).position(end)
                .shadow(color: colour.opacity(0.3), radius: 5)
        }
    }
}

private struct WyrmMiniSnake: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let groups: [Int]
    var body: some View {
        HStack(spacing: -8) {
            ForEach(0..<8, id: \.self) { index in
                WyrmAtlasImage(image: textures.beads[groups.isEmpty ? 7 : groups[index % groups.count]])
                    .frame(width: CGFloat(22 + index), height: CGFloat(22 + index))
            }
        }.frame(maxWidth: .infinity)
    }
}

private struct WyrmAtlasImage: View {
    let image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit() }
            else { Color.clear }
        }
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
