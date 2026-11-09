import SwiftUI
import ImageIO

/*
 * Notice blocks (OM, 2026-10-30), the same as Android ui/NoticeBlocks.kt: the
 * Observatory's builder lays a notice out as blocks, each with its own size,
 * width, alignment and colour, and the phone draws exactly that. Widths are a
 * share of the message's width, so a picture set to 60% is 60% on every
 * phone, upright or sideways. Backend shape: notices.mjs NOTICE_BLOCK.
 */

enum WyrmNoticeBlock: Equatable {
    case heading(text: String, size: Int, align: String, color: String)
    case text(text: String, size: String, align: String, color: String)
    case image(url: String, alt: String, width: Double, align: String, radius: Double)
    case button(label: String, url: String, style: String, width: Double, align: String)
    case divider
    case space(Double)
    case list(items: [String], ordered: Bool, color: String)
    case quote(text: String, color: String)

    /// One block from the server; an unknown type is skipped.
    static func from(_ raw: [String: Any]) -> WyrmNoticeBlock? {
        func s(_ key: String, _ fallback: String = "") -> String { raw[key] as? String ?? fallback }
        func d(_ key: String, _ fallback: Double) -> Double { (raw[key] as? NSNumber)?.doubleValue ?? fallback }
        switch raw["t"] as? String {
        case "heading": return .heading(text: s("text"), size: min(max(Int(d("size", 2)), 1), 3), align: s("align", "left"), color: s("color", "ink"))
        case "text": return .text(text: s("text"), size: s("size", "m"), align: s("align", "left"), color: s("color", "ink"))
        case "image":
            let url = s("url")
            return url.isEmpty ? nil : .image(url: url, alt: s("alt"), width: d("width", 100), align: s("align", "center"), radius: d("radius", 12))
        case "button": return .button(label: s("label"), url: s("url"), style: s("style", "filled"), width: d("width", 100), align: s("align", "center"))
        case "divider": return .divider
        case "space": return .space(d("height", 16))
        case "list": return .list(items: (raw["items"] as? [Any] ?? []).compactMap { $0 as? String }, ordered: (raw["ordered"] as? Bool) ?? false, color: s("color", "ink"))
        case "quote": return .quote(text: s("text"), color: s("color", "ink"))
        default: return nil
        }
    }
}

enum WyrmNoticeStyle {
    /// Text sizes in points: s / m / l, and headings 1 / 2 / 3 (Android's dp).
    static func textSize(_ size: String) -> CGFloat { size == "s" ? 13 : size == "l" ? 18 : 15 }
    static func headingSize(_ level: Int) -> CGFloat { level == 1 ? 26 : level == 3 ? 17 : 21 }
    static func colour(_ name: String) -> Color {
        switch name {
        case "quiet": return ATheme.quiet
        case "link": return ATheme.link
        case "live": return ATheme.live
        case "red": return Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
        case "gold": return Color(red: 0xC2 / 255, green: 0x8A / 255, blue: 0x2C / 255)
        default: return ATheme.ink
        }
    }
    static func textAlign(_ align: String) -> TextAlignment { align == "center" ? .center : align == "right" ? .trailing : .leading }
    static func frameAlign(_ align: String) -> Alignment { align == "left" ? .leading : align == "right" ? .trailing : .center }

    /// A bare address that is a picture: an image file, or an Observatory upload.
    static func isPictureAddress(_ text: String) -> Bool {
        guard text.hasPrefix("https://") || text.hasPrefix("http://"), !text.contains(where: { $0.isWhitespace }) else { return false }
        let path = (text.components(separatedBy: "?").first ?? text).lowercased()
        return [".png", ".jpg", ".jpeg", ".webp", ".gif"].contains(where: { path.hasSuffix($0) }) || path.contains("/v1/notice/images/")
    }

    /// A Markdown picture's layout from its title: `![alt](url "w=60 a=center")`.
    static func imageLayout(_ title: String) -> (width: Double, align: String) {
        var width = 100.0, align = "center"
        for part in title.split(whereSeparator: { $0 == " " || $0 == ";" || $0 == "," }) {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            if pair[0] == "w", let value = Double(pair[1].replacingOccurrences(of: "%", with: "")) { width = min(max(value, 10), 100) }
            if pair[0] == "a", ["left", "center", "right"].contains(pair[1]) { align = pair[1] }
        }
        return (width, align)
    }
}

/// Pictures for notices: any public link or the Observatory's uploads, kept in memory.
final class WyrmNoticeImageLoader: ObservableObject {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    @Published private(set) var image: UIImage?
    @Published private(set) var failed = false

    @MainActor
    func load(_ raw: String) async {
        let address = WyrmTrailsClient.absolute(raw.trimmingCharacters(in: .whitespaces))
        if let hit = Self.cache.object(forKey: address as NSString) { image = hit; return }
        guard let url = URL(string: address), url.scheme == "https" || url.scheme == "http" else { failed = true; return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? false,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 2048,
                  ] as CFDictionary) else { failed = true; return }
            let picture = UIImage(cgImage: cg)
            Self.cache.setObject(picture, forKey: address as NSString, cost: cg.width * cg.height * 4)
            image = picture
        } catch {
            failed = true
        }
    }
}

/// One picture: `width` percent of the message's width, placed left, centre or right.
struct WyrmNoticeImage: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let url: String
    let alt: String
    let width: Double
    let align: String
    var radius: Double = 12
    @StateObject private var loader = WyrmNoticeImageLoader()
    @State private var available: CGFloat = 0

    var body: some View {
        let share = CGFloat(min(max(width, 10), 100) / 100)
        let shape = RoundedRectangle(cornerRadius: CGFloat(min(max(radius, 0), 32)), style: .continuous)
        Group {
            if let image = loader.image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).clipShape(shape)
            } else if loader.failed {
                Text(alt.isEmpty ? "The picture could not load." : alt).font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(shape.fill(wyrmScopedColours.well))
            } else {
                shape.fill(wyrmScopedColours.well).aspectRatio(16 / 9, contentMode: .fit)
            }
        }
        .frame(width: available > 0 ? available * share : nil)
        .frame(maxWidth: .infinity, alignment: WyrmNoticeStyle.frameAlign(align))
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { available = geometry.size.width }
                .onChange(of: geometry.size.width) { available = $0 }
        })
        .accessibilityLabel(alt)
        .task(id: url) { await loader.load(url) }
    }
}

/// The builder's blocks, top to bottom, as the Observatory's preview shows them.
struct WyrmNoticeBlocksView: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let blocks: [WyrmNoticeBlock]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in row(block) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ block: WyrmNoticeBlock) -> some View {
        switch block {
        case let .heading(text, size, align, color):
            Text(WyrmMarkdownBlock.inline(text)).font(.androidWyrm(WyrmNoticeStyle.headingSize(size), .bold))
                .foregroundColor(WyrmNoticeStyle.colour(color)).multilineTextAlignment(WyrmNoticeStyle.textAlign(align))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: WyrmNoticeStyle.frameAlign(align))
        case let .text(text, size, align, color):
            Text(WyrmMarkdownBlock.inline(text)).font(.androidWyrm(WyrmNoticeStyle.textSize(size)))
                .foregroundColor(WyrmNoticeStyle.colour(color)).multilineTextAlignment(WyrmNoticeStyle.textAlign(align))
                .lineSpacing(WyrmNoticeStyle.textSize(size) * 0.3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: WyrmNoticeStyle.frameAlign(align))
        case let .image(url, alt, width, align, radius):
            WyrmNoticeImage(url: url, alt: alt, width: width, align: align, radius: radius)
        case let .button(label, url, style, width, align):
            WyrmNoticeButton(label: label, url: url, filled: style != "outline", width: width, align: align) { link in openURL(link) }
        case .divider:
            Rectangle().fill(wyrmScopedColours.rule).frame(height: 1)
        case let .space(height):
            Color.clear.frame(height: CGFloat(min(max(height, 4), 96)))
        case let .list(items, ordered, color):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(ordered ? "\(index + 1)." : "—").font(.androidWyrm(15)).foregroundColor(wyrmScopedColours.quiet).frame(width: 24, alignment: .leading)
                        Text(WyrmMarkdownBlock.inline(item)).font(.androidWyrm(15)).foregroundColor(WyrmNoticeStyle.colour(color))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case let .quote(text, color):
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(wyrmScopedColours.link).frame(width: 3)
                Text(WyrmMarkdownBlock.inline(text)).font(.androidWyrm(15)).foregroundColor(WyrmNoticeStyle.colour(color))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A button block: a link, filled or outlined, at its width and place.
private struct WyrmNoticeButton: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let label: String
    let url: String
    let filled: Bool
    let width: Double
    let align: String
    let open: (URL) -> Void
    @State private var available: CGFloat = 0

    var body: some View {
        Button {
            if let link = URL(string: WyrmTrailsClient.absolute(url)) { open(link) }
        } label: {
            Text(label).font(.androidWyrm(15, .bold)).lineLimit(1)
                .foregroundColor(filled ? wyrmScopedColours.onInk : wyrmScopedColours.ink)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Capsule().fill(filled ? wyrmScopedColours.ink : Color.clear))
                .overlay(Capsule().stroke(filled ? Color.clear : wyrmScopedColours.ink, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .frame(width: available > 0 ? available * CGFloat(min(max(width, 10), 100) / 100) : nil)
        .frame(maxWidth: .infinity, alignment: WyrmNoticeStyle.frameAlign(align))
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { available = geometry.size.width }
                .onChange(of: geometry.size.width) { available = $0 }
        })
    }
}
