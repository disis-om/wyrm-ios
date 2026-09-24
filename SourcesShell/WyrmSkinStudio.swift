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
    private(set) var accessoryThumbnails: [Int: CGImage] = [:]
    private(set) var tagThumbnails: [Int: CGImage] = [:]
    private(set) var backgrounds: [Int: CGImage] = [:]
    private var loading = false

    func prepare() {
        guard !ready, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let atlasURL = try Self.resource("res/textures/tex_atlas_8k.png")
                let tagURL = try Self.resource("res/textures/wyrm_tags.png")
                guard let atlas = Self.downsample(atlasURL, maxPixel: 4032),
                      let tagAtlas = Self.downsample(tagURL, maxPixel: 4096) else {
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
                var accessoryThumbs: [Int: CGImage] = [:]
                for id in 0..<32 {
                    accessoryImages[id] = Self.crop(atlas,
                        x: 5.0 / 7 + Double(id % 8) / 28,
                        y: 8.0 / 9 + Double(id / 8) / 36,
                        width: 1.0 / 28, height: 1.0 / 36)
                    if let image = accessoryImages[id] {
                        accessoryThumbs[id] = Self.removingSoftShadow(image)
                    }
                }

                var tagImages: [Int: CGImage] = [:]
                var tagThumbs: [Int: CGImage] = [:]
                for tag in WyrmSkinCatalog.tags {
                    tagImages[tag.id] = Self.crop(tagAtlas,
                        x: tag.minU, y: tag.minV,
                        width: tag.maxU - tag.minU, height: tag.maxV - tag.minV)
                    if let image = tagImages[tag.id] {
                        tagThumbs[tag.id] = Self.removingSoftShadow(image)
                    }
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
                    self.accessoryThumbnails = accessoryThumbs
                    self.tagThumbnails = tagThumbs
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

    /// Picker cells use a crisp derivative of the original sprite. The atlas'
    /// soft game shadow belongs in the arena and hero preview, not in the asset
    /// catalogue where it made every icon look low-resolution and muddy.
    private static func removingSoftShadow(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let result: CGImage? = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: colourSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return nil
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            for offset in stride(from: 0, to: buffer.count, by: 4) {
                let alpha = Int(buffer[offset + 3])
                if alpha < 76 {
                    buffer[offset] = 0; buffer[offset + 1] = 0; buffer[offset + 2] = 0; buffer[offset + 3] = 0
                } else if alpha < 176 {
                    buffer[offset + 3] = UInt8(max(0, min(255, (alpha - 76) * 255 / 100)))
                }
            }
            return context.makeImage()
        }
        return result ?? image
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
    @AppStorage("wyrm.ios.skin.custom-colors") private var patternColors = ""
    @AppStorage("wyrm.ios.skin.accessory-id") private var accessory = -1
    @AppStorage("wyrm.ios.skin.tag-id") private var tag = -1
    @AppStorage("wyrm.ios.skin.background-id") private var background = 0
    @AppStorage("wyrm.ios.skin.tag-chain") private var chain = 1.0
    @AppStorage("wyrm.ios.skin.tag-swing") private var swing = 1.0
    @AppStorage("wyrm.ios.skin.tag-scale") private var tagScale = 1.0

    private static let palette: [UInt32] = (0..<400).map { index in
        let family = index / 100
        let slot = index % 100
        let hue = Double(slot % 20) / 20
        let variation = Double(slot / 20) / 4
        let saturation: Double
        let brightness: Double
        switch family {
        case 0: saturation = 0.72; brightness = 0.54 + variation * 0.40
        case 1: saturation = 0.53 + variation * 0.27; brightness = 0.91 + variation * 0.09
        case 2: saturation = 0.68 + variation * 0.25; brightness = 0.22 + variation * 0.23
        default: saturation = 0.62 + variation * 0.22; brightness = 0.48 + variation * 0.26
        }
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).wyrmRGBA
    }

    private static func paletteColor(_ index: Int) -> UInt32 { palette[index] }

    init(engine: WyrmShellStore) {
        self.engine = engine
        let arguments = ProcessInfo.processInfo.arguments
        let initial: WyrmSkinStudioSection = arguments.contains("--smoke-skin-tags") ? .tags
            : arguments.contains("--smoke-skin-accessories") ? .accessories
            : arguments.contains("--smoke-skin-presets") ? .presets
            : arguments.contains("--smoke-skin-pattern") ? .pattern
            : .overview
        _section = State(initialValue: initial)
    }

    private var customGroups: [Int] {
        let result = pattern.split(separator: ",").compactMap { Int($0) }
            .filter { WyrmSkinCatalog.validGroups.contains($0) }
        return Array(result.prefix(256))
    }

    private var customColors: [UInt32] {
        let parsed = patternColors.split(separator: ",", omittingEmptySubsequences: false)
            .prefix(256).map { UInt32($0, radix: 16) ?? 0 }
        return (0..<customGroups.count).map { $0 < parsed.count ? parsed[$0] : 0 }
    }

    private var activeGroups: [Int] {
        guard WyrmSkinCatalog.presets.indices.contains(preset) else { return [7] }
        let base = WyrmSkinCatalog.presets[preset]
        guard customEnabled else { return base }
        return (0..<256).map { $0 < customGroups.count ? customGroups[$0] : base[$0 % base.count] }
    }

    private var activeColors: [UInt32] {
        (0..<256).map { customEnabled && $0 < customColors.count ? customColors[$0] : 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            WyrmScreenHeader(kicker: "WYRM", title: "Skin")
            WyrmSkinPreview(textures: textures, groups: activeGroups, colors: activeColors,
                            preset: preset, custom: customEnabled,
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
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                studioRow(.presets, value: "\(WyrmSkinCatalog.presets.count)")
                studioRow(.pattern, value: customEnabled ? "Custom" : "Preset")
                studioRow(.accessories, value: accessory < 0 ? "None" : String(format: "%02d", accessory + 1))
                studioRow(.tags, value: WyrmSkinCatalog.tags[safe: tag].map { "#\($0.ntlID)" } ?? "None")
                studioRow(.background, value: WyrmSkinCatalog.backgrounds[safe: background]?.label ?? "Wyrm")
            }
            if let failure = textures.failure {
                Text(failure).font(.androidWyrm(11)).foregroundColor(.red).padding(12)
            }
        }
    }

    private func studioRow(_ target: WyrmSkinStudioSection, value: String) -> some View {
        WyrmListRow(title: target.title, value: value) { enter(target) }
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
            LazyVStack(spacing: 0) {
                ForEach(WyrmSkinCatalog.presets.indices, id: \.self) { index in
                    Button {
                        preset = index; customEnabled = false; apply(preset: index, custom: false)
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(.androidWyrm(10.5, .bold)).foregroundColor(ATheme.quiet).frame(width: 24)
                            WyrmMiniSnake(textures: textures, groups: WyrmSkinCatalog.presets[index])
                                .frame(height: 38)
                            if !customEnabled && preset == index { Image(systemName: "checkmark.circle.fill").foregroundColor(ATheme.live) }
                        }.frame(maxWidth: .infinity).frame(height: 57)
                    }.buttonStyle(.plain).accessibilityLabel("Default skin \(index + 1)")
                    Rectangle().fill(ATheme.rule).frame(height: 1)
                }
            }.padding(.horizontal, 20)
        }
    }

    private var patternPanel: some View {
        VStack(spacing: 0) {
            inlineHeader
            HStack(spacing: 10) {
                Text("\(customGroups.count) / 256 beads").font(.androidWyrm(11, .semibold)).foregroundColor(ATheme.quiet)
                Spacer()
                Button("UNDO") {
                    var groups = customGroups; if !groups.isEmpty { groups.removeLast() }
                    savePattern(groups, colors: Array(customColors.prefix(groups.count)))
                }.font(.androidWyrm(9.5, .bold)).buttonStyle(.plain)
                Button("CLEAR") { savePattern([], colors: []) }
                    .font(.androidWyrm(9.5, .bold)).foregroundColor(.red).buttonStyle(.plain)
            }.padding(.horizontal, 20).padding(.bottom, 10)
            TextField("Type or paste a skin code", text: Binding(
                get: { WyrmSkinCatalog.code(for: customGroups) },
                set: { typed in
                    let groups = typed.lowercased().prefix(256).compactMap { WyrmSkinCatalog.group(for: $0) }
                    let common = zip(groups, customGroups).prefix { pair in pair.0 == pair.1 }.count
                    savePattern(groups, colors: groups.indices.map { $0 < common ? customColors[$0] : 0 })
                }
            ))
                .font(.system(size: 15, design: .monospaced))
                .textInputAutocapitalization(.never).disableAutocorrection(true)
                .padding(13).background(Color.white.opacity(0.9)).cornerRadius(11)
                .padding(.horizontal, 20)
            WyrmSectionLabel("Build a Wyrm")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(WyrmSkinCatalog.validGroups, id: \.self) { group in
                    Button {
                        var groups = customGroups
                        if groups.count < 256 { groups.append(group); savePattern(groups, colors: customColors + [0]) }
                    } label: {
                        WyrmAtlasImage(image: textures.beads[group]).padding(5)
                            .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                            .background(Color.white.opacity(0.72)).clipShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Bead group \(group)")
                }
                ForEach(0..<400, id: \.self) { index in
                    let color = WyrmSkinRoot.paletteColor(index)
                    Button {
                        guard customGroups.count < 256 else { return }
                        var groups = customGroups; groups.append(9)
                        savePattern(groups, colors: customColors + [color])
                    } label: {
                        WyrmTintedBead(image: textures.beads[40], rgba: color)
                            .padding(5).frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                    }.buttonStyle(.plain).accessibilityLabel("Custom colour \(index + 1)")
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
                            WyrmAtlasImage(image: textures.accessoryThumbnails[item.id]).padding(8)
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
                            WyrmAtlasImage(image: textures.tagThumbnails[item.id]).padding(7)
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

    private func savePattern(_ groups: [Int], colors: [UInt32]) {
        pattern = groups.map(String.init).joined(separator: ",")
        patternColors = colors.prefix(groups.count).map { String($0, radix: 16) }.joined(separator: ",")
        customEnabled = true
        apply(custom: true)
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
            groups: groups ?? activeGroups,
            colors: activeColors,
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
    let colors: [UInt32]
    let preset: Int
    let custom: Bool
    let accessoryID: Int
    let tagID: Int
    let backgroundID: Int
    let chain: Double
    let swing: Double
    let tagScale: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let segmentsPerRow = 128
            let nativeSpan = 1 + CGFloat(segmentsPerRow - 1) * (8.0 / 48.0)
            let scale = min((proxy.size.width - 28) / nativeSpan,
                            (proxy.size.height - 24) / 2.16)
            let step = 8 * (scale / 48)
            let gap = scale * 0.16
            let bodyWidth = scale + step * CGFloat(segmentsPerRow - 1)
            let x = proxy.size.width * 0.5 - bodyWidth * 0.5
            let centreY = proxy.size.height * 0.48
            let headY = centreY - scale * 0.5 - gap * 0.5
            let tailY = centreY + scale * 0.5 + gap * 0.5
            let head = CGPoint(x: x + scale * 0.5 + step * CGFloat(segmentsPerRow - 1), y: headY)
            ZStack {
                ATheme.paper
                if let image = textures.backgrounds[backgroundID] {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(0.13)
                        .mask(RadialGradient(colors: [.black, .black.opacity(0.42), .clear], center: .center,
                                             startRadius: 10,
                                             endRadius: min(proxy.size.width, proxy.size.height) * 0.56))
                }
                nativeBodyCanvas(x: x, headY: headY, tailY: tailY,
                                 scale: scale, step: step, segmentsPerRow: segmentsPerRow)
                eyes(at: head, scale: scale)
                if let item = WyrmSkinCatalog.accessories[safe: accessoryID],
                   let image = textures.accessories[accessoryID] {
                    let unit = scale / 29
                    let size = scale * CGFloat(item.scale)
                    WyrmAtlasImage(image: image).frame(width: size, height: size)
                        .position(x: head.x + CGFloat(item.offset) * 6 * unit, y: head.y)
                }
                if let item = WyrmSkinCatalog.tags[safe: tagID],
                   let image = textures.tags[tagID] {
                    WyrmSwingTag(item: item, image: image, head: head,
                                   headSize: scale, bounds: proxy.size,
                                   chain: chain, swing: swing, tagScale: tagScale,
                                   reduceMotion: reduceMotion)
                }
                if !textures.ready {
                    ProgressView().tint(ATheme.ink).position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func nativeBodyCanvas(x: CGFloat, headY: CGFloat, tailY: CGFloat,
                                  scale: CGFloat, step: CGFloat,
                                  segmentsPerRow: Int) -> some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, _ in
            let totalSegments = segmentsPerRow * 2
            for row in 0..<2 {
                let firstSegment = row * segmentsPerRow
                for local in 0..<segmentsPerRow {
                    let segment = firstSegment + local
                    let codeIndex = totalSegments - 1 - segment
                    let group = groups.isEmpty ? 7 : groups[codeIndex % groups.count]
                    let rgba = codeIndex < colors.count ? colors[codeIndex] : 0
                    guard let bead = textures.beads[rgba == 0 ? group : 40] else { continue }
                    let point = segmentPoint(segment, x: x, headY: headY, tailY: tailY,
                                             scale: scale, step: step,
                                             segmentsPerRow: segmentsPerRow)
                    let image = Image(decorative: bead, scale: 1)
                    var inked = context
                    if rgba != 0 { inked.addFilter(.colorMultiply(Color(rgb: rgba))) }
                    if row == 1 {
                        var rotated = inked
                        rotated.translateBy(x: point.x, y: point.y)
                        rotated.rotate(by: .degrees(180))
                        rotated.draw(image, in: CGRect(x: -scale * 0.5, y: -scale * 0.5,
                                                       width: scale, height: scale))
                    } else {
                        inked.draw(image, in: CGRect(x: point.x - scale * 0.5,
                                                       y: point.y - scale * 0.5,
                                                       width: scale, height: scale))
                    }
                }
            }
        }
    }

    private func segmentPoint(_ segment: Int, x: CGFloat, headY: CGFloat,
                              tailY: CGFloat, scale: CGFloat, step: CGFloat,
                              segmentsPerRow: Int) -> CGPoint {
        let local = segment % segmentsPerRow
        let slot = segment < segmentsPerRow ? segmentsPerRow - 1 - local : local
        return CGPoint(x: x + scale * 0.5 + CGFloat(slot) * step,
                       y: segment < segmentsPerRow ? tailY : headY)
    }

    private func eyes(at head: CGPoint, scale: CGFloat) -> some View {
        let unit = scale / 29
        let iris = 12 * unit
        let pupil = (custom ? 7 : preset == 63 ? 5 : 7) * unit
        let irisColor: Color = !custom && preset == 63 ? .black :
            !custom && preset == 64 ? Color(red: 1, green: 1, blue: 0.50196) :
            !custom && preset == 25 ? Color(red: 1, green: 0.3373, blue: 0.0353) :
            !custom && preset == 44 ? Color(red: 0.8314, green: 0.8314, blue: 0.8314) : .white
        let pupilColor: Color = !custom && preset == 63 ? Color(white: 0.8) : .black
        return ZStack {
            ForEach(0..<2, id: \.self) { side in
                let ey = side == 0 ? -6 * unit - 0.5 : 6 * unit
                WyrmAtlasImage(image: textures.beads[40]).colorMultiply(irisColor)
                    .frame(width: iris, height: iris).offset(y: ey)
                WyrmAtlasImage(image: textures.beads[40]).colorMultiply(pupilColor)
                    .frame(width: pupil, height: pupil)
                    .offset(x: 0.5 + 2 * unit, y: side == 0 ? -6 * unit : 6 * unit)
            }
        }.position(x: head.x + 6 * unit, y: head.y)
    }

    private func tagPreview(item: WyrmTagAsset, image: CGImage, head: CGPoint,
                            headSize: CGFloat, phase: Double) -> some View {
        let unit = headSize / 29
        let anchor = CGPoint(x: head.x - 8 * unit, y: head.y)
        let segment = 4 * CGFloat(max(1, chain)) * unit
        let points = simulatedNTLRope(anchor: anchor, segment: segment,
                                      unit: unit, phase: phase)
        let end = points.last ?? anchor
        let previous = points.dropLast().last ?? anchor
        let rawWidth = CGFloat(item.width) * 0.285 * unit * CGFloat(tagScale)
        let rawHeight = CGFloat(item.height) * 0.285 * unit * CGFloat(tagScale)
        let fit = min(1, 108 / max(rawWidth, rawHeight))
        let width = rawWidth * fit
        let height = rawHeight * fit
        let attachX = CGFloat(item.anchorX) * 0.285 * unit * CGFloat(tagScale) * fit
        let attachY = CGFloat(item.anchorY) * 0.285 * unit * CGFloat(tagScale) * fit
        let angle = atan2(end.y - previous.y, end.x - previous.x)
        let cs = cos(angle), sn = sin(angle)
        let localX = attachX + width * 0.5
        let localY = attachY + height * 0.5
        let imageCentre = CGPoint(x: end.x + cs * localX - sn * localY,
                                  y: end.y + sn * localX + cs * localY)
        return ZStack {
            nativeRopePath(points, to: 1, closeToAnchor: false)
                .stroke(Color(rgb: item.accentA), style: StrokeStyle(lineWidth: 5 * unit, lineCap: .round, lineJoin: .round))
            nativeRopePath(points, to: 2, closeToAnchor: true)
                .stroke(Color(rgb: item.accentB).opacity(0.5), style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round, lineJoin: .round))
            nativeRopePath(points, to: 2, closeToAnchor: true)
                .stroke(Color(rgb: item.accentB).opacity(0.5), style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round, lineJoin: .round))
            nativeRopePath(points, to: 2, closeToAnchor: true)
                .stroke(Color(rgb: item.accentB).opacity(0.5), style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round, lineJoin: .round))
            WyrmAtlasImage(image: image).frame(width: width, height: height)
                .rotationEffect(.radians(Double(angle)))
                .position(x: imageCentre.x, y: imageCentre.y)
        }
    }

    private func simulatedNTLRope(anchor: CGPoint, segment: CGFloat,
                                  unit: CGFloat, phase: Double) -> [CGPoint] {
        let count = 10
        var points = (0..<count).map {
            CGPoint(x: anchor.x - CGFloat($0) * segment, y: anchor.y)
        }
        var velocity = Array(repeating: CGVector.zero, count: count)
        let loose = CGFloat(max(0, min(1, (swing - 1) * 0.5)))
        let push = (3.3332 + 0.6668 * loose) * CGFloat(max(1, chain)) * unit
        let stiffness = 0.08333 + 0.01667 * loose
        let damping = min(0.985, 0.838 + 0.145 * loose)
        let frame = reduceMotion ? 0 : Int((phase * 60).truncatingRemainder(dividingBy: 300))
        for tick in 0...max(1, frame) {
            let t = CGFloat(tick) / 60
            points[0] = CGPoint(x: anchor.x + sin(t * 1.35) * unit * 1.25,
                                y: anchor.y + sin(t * 0.74) * unit * 0.55)
            for index in 1..<count {
                let previous = points[index - 1]
                let dx = points[index].x - previous.x
                let dy = points[index].y - previous.y
                let angle = (dx == 0 && dy == 0) ? CGFloat.pi : atan2(dy, dx)
                let target = CGPoint(x: previous.x + push * cos(angle),
                                     y: previous.y + push * sin(angle))
                velocity[index].dx += stiffness * (target.x - points[index].x)
                velocity[index].dy += stiffness * (target.y - points[index].y)
                points[index].x += velocity[index].dx
                points[index].y += velocity[index].dy
                velocity[index].dx *= damping
                velocity[index].dy *= damping
                let limitX = points[index].x - previous.x
                let limitY = points[index].y - previous.y
                let distance = hypot(limitX, limitY)
                if distance > segment {
                    let limitAngle = atan2(limitY, limitX)
                    points[index] = CGPoint(x: previous.x + segment * cos(limitAngle),
                                            y: previous.y + segment * sin(limitAngle))
                }
                velocity[index].dy += 0.30 * unit
                velocity[index].dx += 0.14 * unit * cos(t - 7 * CGFloat(index) / 9)
            }
        }
        return points
    }

    private func nativeRopePath(_ points: [CGPoint], to: Int,
                                closeToAnchor: Bool) -> Path {
        var path = Path()
        guard let last = points.last else { return path }
        path.move(to: last)
        guard points.count > to else { return path }
        for index in stride(from: points.count - 2, through: to, by: -1) {
            let control = points[index]
            let end = CGPoint(x: (points[index].x + points[index - 1].x) * 0.5,
                              y: (points[index].y + points[index - 1].y) * 0.5)
            path.addQuadCurve(to: end, control: control)
        }
        if closeToAnchor {
            path.addQuadCurve(to: points[0], control: points[1])
        }
        return path
    }
}

private struct WyrmMiniSnake: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let groups: [Int]
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let bead = min(size.height * 0.87, 38)
            let step = bead * (8.0 / 48.0)
            let count = max(1, Int(ceil(size.width / step)) + 1)
            for index in 0..<count {
                let group = groups.isEmpty ? 7 : groups[index % groups.count]
                guard let texture = textures.beads[group] else { continue }
                context.draw(Image(decorative: texture, scale: 1),
                             in: CGRect(x: CGFloat(index) * step, y: (size.height - bead) * 0.5,
                                        width: bead, height: bead))
            }
        }.frame(maxWidth: .infinity)
    }
}

private struct WyrmTintedBead: View {
    let image: CGImage?
    let rgba: UInt32
    var body: some View {
        if let image {
            let mask = Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            mask.colorMultiply(Color(rgb: rgba))
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.47), location: 0),
                        .init(color: .clear, location: 0.29),
                        .init(color: .clear, location: 0.69),
                        .init(color: .black.opacity(0.53), location: 1)
                    ], startPoint: .top, endPoint: .bottom).mask(mask)
                }
        } else { Color.clear }
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

private extension UIColor {
    var wyrmRGBA: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((a * 255).rounded()) << 24) |
            (UInt32((r * 255).rounded()) << 16) |
            (UInt32((g * 255).rounded()) << 8) |
            UInt32((b * 255).rounded())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
