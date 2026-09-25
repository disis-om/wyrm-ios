import SwiftUI
import UIKit

/// The NTL VANCED image arrows, in the order Scripts/generate-arrow-skins.py
/// packs them into Resources/ArrowSkins.png. Append only: a saved choice is an
/// index into this list and into the atlas the engine draws from.
enum WyrmArrowImages {
    static let names = [
        "Blue 3D", "Blue 3D II", "Red 3D", "Yellow 3D", "Red arrow",
        "Wing", "Arrow I", "Arrow II", "Arrow III", "Neon Ice",
        "Neon Magenta", "Volt", "Inferno", "Aqua", "Heat",
        "Jade", "Chrome", "Twin Volt", "Sunset", "Streak",
    ]
    private static let columns = 5
    private static let cell: CGFloat = 256

    private static let atlas: CGImage? = {
        guard let url = Bundle.main.url(forResource: "ArrowSkins", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.cgImage
    }()

    private static var cache: [Int: UIImage] = [:]

    /// One right-facing arrow cut from the atlas.
    static func image(_ index: Int) -> UIImage? {
        guard names.indices.contains(index), let atlas else { return nil }
        if let cached = cache[index] { return cached }
        let rect = CGRect(x: CGFloat(index % columns) * cell, y: CGFloat(index / columns) * cell, width: cell, height: cell)
        guard let piece = atlas.cropping(to: rect) else { return nil }
        let image = UIImage(cgImage: piece)
        cache[index] = image
        return image
    }
}

/// Which arrow the arena draws and how bright. Kept on the device like every
/// other control choice and handed to the engine through WyrmIOSSetArrowSkin;
/// the polygon styles themselves stay the engine's own `arrow.style` setting.
final class WyrmArrowSkinStore: ObservableObject {
    static let shared = WyrmArrowSkinStore()
    private static let skinKey = "wyrm.ios.arrow.skin"
    private static let brightnessKey = "wyrm.ios.arrow.brightness"

    /// -1: one of the engine's drawn styles; 0…19: an image arrow.
    @Published private(set) var skin: Int
    /// 0.2…1.0, multiplied into the arrow's colour (images and drawn alike).
    @Published private(set) var brightness: Double

    private init() {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: Self.skinKey) as? Int ?? -1
        skin = WyrmArrowImages.names.indices.contains(stored) ? stored : -1
        brightness = min(1, max(0.2, defaults.object(forKey: Self.brightnessKey) as? Double ?? 1))
    }

    func publish() { WyrmIOSSetArrowSkin(Int32(skin), Float(brightness)) }

    func select(image index: Int) {
        skin = WyrmArrowImages.names.indices.contains(index) ? index : -1
        UserDefaults.standard.set(skin, forKey: Self.skinKey)
        publish()
    }

    func setBrightness(_ value: Double) {
        brightness = min(1, max(0.2, value))
        UserDefaults.standard.set(brightness, forKey: Self.brightnessKey)
        publish()
    }
}

/// The arrow as the arena draws it, for previews and picker tiles.
struct WyrmArrowGlyph: View {
    let codeStyle: Int
    let imageSkin: Int
    let colour: [Double]
    let brightness: Double
    var body: some View {
        if imageSkin >= 0, let image = WyrmArrowImages.image(imageSkin) {
            Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                .colorMultiply(Color(white: brightness))
        } else {
            Canvas { context, size in
                let length = min(size.width, size.height * 1.4) * 0.62
                let path = WyrmArrowShapes.path(style: codeStyle, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                length: length, width: length * 30 / 52)
                context.fill(path, with: .color(Color(.sRGB, red: colour[0] * brightness, green: colour[1] * brightness,
                                                      blue: colour[2] * brightness, opacity: 1)))
                context.stroke(path, with: .color(Color(red: 0.016, green: 0.024, blue: 0.035)), lineWidth: 1.6)
            }
        }
    }
}

/// "Choose arrow": the engine's drawn styles first, then every image skin,
/// each drawn exactly as it will look. Tap one to use it.
struct WyrmArrowPicker: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var store = WyrmArrowSkinStore.shared
    let close: () -> Void

    var body: some View {
        let style = engine.setting("arrow.style")
        let colour = engine.setting("arrow.color")?.channels ?? [1, 1, 1, 1]
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WSSectionLabel("Wyrm arrows", top: 12)
                    grid {
                        ForEach(0..<WyrmArrowShapes.points.count, id: \.self) { index in
                            tile(name: styleName(style, index), selected: store.skin < 0 && (style?.index ?? 0) == index) {
                                WyrmArrowGlyph(codeStyle: index, imageSkin: -1, colour: colour, brightness: store.brightness)
                            } action: {
                                store.select(image: -1)
                                if let style { engine.write(style, values: [Double(index)]) }
                            }
                        }
                    }
                    WSSectionLabel("Image arrows")
                    grid {
                        ForEach(WyrmArrowImages.names.indices, id: \.self) { index in
                            tile(name: WyrmArrowImages.names[index], selected: store.skin == index) {
                                WyrmArrowGlyph(codeStyle: 0, imageSkin: index, colour: colour, brightness: store.brightness)
                            } action: { store.select(image: index) }
                        }
                    }
                    WSCaption("Size and brightness apply to every arrow; colour applies to the Wyrm arrows.")
                }
            }
            .background(ATheme.paper.ignoresSafeArea())
            .navigationTitle("Choose arrow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        .navigationViewStyle(.stack)
    }

    private func styleName(_ setting: EngineSetting?, _ index: Int) -> String {
        guard let options = setting?.options, options.indices.contains(index) else { return "Arrow \(index + 1)" }
        return options[index].capitalized
    }

    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) { content() }
            .padding(.horizontal, 16)
    }

    private func tile<Glyph: View>(name: String, selected: Bool, @ViewBuilder glyph: () -> Glyph,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                glyph().frame(height: 58).padding(.horizontal, 8)
                Text(name).font(.androidWyrm(11, selected ? .bold : .semibold))
                    .foregroundColor(selected ? ATheme.ink : ATheme.mute).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.well))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(WSPressStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Controls › arrow block: the chosen arrow with a way into the picker,
/// then size, brightness and — for the drawn styles — colour.
struct WyrmArrowSettingsCard: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var store = WyrmArrowSkinStore.shared
    @State var choosing = false

    var body: some View {
        let style = engine.setting("arrow.style")
        let colour = engine.setting("arrow.color")
        let size = engine.setting("arrow.size")
        let others = engine.settings.filter { $0.group == "controls.arrow" && !["arrow.style", "arrow.color", "arrow.size"].contains($0.id) }
        WSCard {
            Button { choosing = true } label: {
                HStack(spacing: 14) {
                    WyrmArrowGlyph(codeStyle: style?.index ?? 0, imageSkin: store.skin, colour: colour?.channels ?? [1, 1, 1, 1],
                                   brightness: store.brightness)
                        .frame(width: 64, height: 44).padding(6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ATheme.well))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Arrow style").font(.androidWyrm(15.5)).foregroundColor(ATheme.ink)
                        Text(currentName(style)).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                    }
                    Spacer()
                    Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron)
                }
                .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(WSPressStyle())
            if let size { WSTypedRow(setting: size, engine: engine) }
            WSSliderRow(title: "Brightness", valueText: "\(Int((store.brightness * 100).rounded()))%",
                        value: store.brightness, range: 0.2...1) { store.setBrightness($0) }
            if store.skin < 0, let colour { WSColourRow(setting: colour, engine: engine) }
            WSRows(rows: others, engine: engine)
        }
        .sheet(isPresented: $choosing) { WyrmArrowPicker(engine: engine) { choosing = false } }
    }

    private func currentName(_ style: EngineSetting?) -> String {
        if WyrmArrowImages.names.indices.contains(store.skin) { return WyrmArrowImages.names[store.skin] }
        guard let style, style.options.indices.contains(style.index) else { return "Wyrm arrow" }
        return style.options[style.index].capitalized
    }
}
