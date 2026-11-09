import SwiftUI
import UIKit

/*
 * Discord markdown, link embeds and the composer for global chat and direct
 * messages (OM, 2026-11-07: "every kind of markdown, links embedded, spaces
 * and Enter like Discord; select text for bold, fancy, link"). Android twin:
 * ChatMarkdown.kt (same rules).
 *
 * Blocks: ``` code ```, "# ", "## ", "### " headings, "-# " small text,
 * "> " quotes, "- " / "* " bullets. Inline: `code`, [text](https://link),
 * bare https:// links, ***bold italic***, **bold**, __underline__,
 * ~~strike~~, ||spoiler||, *italic*, _italic_, @mentions. Line breaks and
 * spaces stay as typed.
 */

/// Someone with Wyrm open right now (global chat's "{n} active").
struct WyrmChatPerson: Identifiable, Equatable {
    let id: String
    let name: String
    let username: String
    let arena: String
}

/// A chat link's embed: the server's reading of the page's Open Graph tags.
struct WyrmLinkPreview: Equatable {
    let url: String
    let title: String
    let description: String
    let image: String
    let siteName: String
}

enum WyrmChatMarkdown {
    private static let inline = try! NSRegularExpression(pattern:
        "(`+)([^`\\n]+?)\\1" +
        "|\\[([^\\]\\n]{1,200})\\]\\((https?://[^)\\s]{1,2000})\\)" +
        "|(https?://[^\\s<]+[^\\s<.,:;\"')\\]!?*_~|])" +
        "|\\*\\*\\*(.+?)\\*\\*\\*" +
        "|\\*\\*(.+?)\\*\\*" +
        "|__(.+?)__" +
        "|~~(.+?)~~" +
        "|\\|\\|(.+?)\\|\\|" +
        "|\\*([^*\\s](?:[^*]*?[^*\\s])?)\\*" +
        "|(?<![A-Za-z0-9])_([^_\\s](?:[^_]*?[^_\\s])?)_(?![A-Za-z0-9])" +
        "|(?<![A-Za-z0-9_])@([A-Za-z0-9_]{3,20})")
    private static let link = try! NSRegularExpression(pattern: "https?://[^\\s<]+[^\\s<.,:;\"')\\]!?*_~|]")

    private static let www = try! NSRegularExpression(pattern:
        "(?<![A-Za-z0-9/@.])www\\.[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+[^\\s<]*[^\\s<.,:;\"')\\]!?*_~|]")

    /// Every link in a message, in order, each once (OM, 2026-11-07: a link in
    /// the middle of a message, or in a second message, had no embed). Not GIF
    /// links, not inside code; at most 5, as Discord. "www." links count too.
    static func links(_ body: String) -> [String] {
        var text = body.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "`[^`\\n]+`", with: " ", options: .regularExpression)
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var found: [(Int, String)] = link.matches(in: text, range: all).map { ($0.range.location, ns.substring(with: $0.range)) }
        found += www.matches(in: text, range: all).map { ($0.range.location, "https://" + ns.substring(with: $0.range)) }
        var seen = Set<String>()
        return found.sorted { $0.0 < $1.0 }.map(\.1)
            .filter { !WyrmChatKit.isGif($0) && seen.insert($0).inserted }
            .prefix(5).map { $0 }
    }

    static func firstLink(_ body: String) -> String? { links(body).first }

    struct Style {
        var size: CGFloat = 15
        var weight: Font.Weight = .regular
        var italic = false
        var mono = false
        var color: Color? = nil
        var background: Color? = nil
        var underline = false
        var strike = false
        var link: URL? = nil
    }

    static func render(_ body: String, meUsername: String, colours: WyrmThemeColours) -> AttributedString {
        var out = AttributedString()
        var inCode = false
        for (index, raw) in body.components(separatedBy: "\n").enumerated() {
            if index > 0 { out += AttributedString("\n") }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                let rest = inCode ? "" : String(trimmed.dropFirst(3))
                if !rest.isEmpty { out += inlineText(rest, Style(), meUsername, colours) }
                continue
            }
            if inCode {
                out += piece(raw, Style(size: 13.5, mono: true, color: colours.ink, background: colours.well))
                continue
            }
            if raw.hasPrefix("### ") { out += inlineText(String(raw.dropFirst(4)), Style(size: 16, weight: .heavy), meUsername, colours) }
            else if raw.hasPrefix("## ") { out += inlineText(String(raw.dropFirst(3)), Style(size: 18, weight: .heavy), meUsername, colours) }
            else if raw.hasPrefix("# ") { out += inlineText(String(raw.dropFirst(2)), Style(size: 21, weight: .heavy), meUsername, colours) }
            else if raw.hasPrefix("-# ") { out += inlineText(String(raw.dropFirst(3)), Style(size: 12, color: colours.quiet), meUsername, colours) }
            else if raw.hasPrefix("> ") || raw == ">" {
                out += piece("▎ ", Style(weight: .black, color: colours.rule))
                out += inlineText(raw == ">" ? "" : String(raw.dropFirst(2)), Style(color: colours.mute), meUsername, colours)
            } else if raw.hasPrefix("- ") || raw.hasPrefix("* ") {
                out += piece("  •  ", Style())
                out += inlineText(String(raw.dropFirst(2)), Style(), meUsername, colours)
            } else {
                out += inlineText(raw, Style(), meUsername, colours)
            }
        }
        return out
    }

    private static func piece(_ text: String, _ style: Style) -> AttributedString {
        var part = AttributedString(text)
        var font: Font = style.mono ? .system(size: style.size, design: .monospaced) : .androidWyrm(style.size, style.weight)
        if style.mono && style.weight != .regular { font = font.weight(style.weight) }
        if style.italic { font = font.italic() }
        part.font = font
        if let color = style.color { part.foregroundColor = color }
        if let background = style.background { part.backgroundColor = background }
        if style.underline { part.underlineStyle = .single }
        if style.strike { part.strikethroughStyle = .single }
        if let url = style.link { part.link = url }
        return part
    }

    private static func inlineText(_ text: String, _ base: Style, _ me: String, _ colours: WyrmThemeColours) -> AttributedString {
        let ns = text as NSString
        var out = AttributedString()
        var at = 0
        for match in inline.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location < at { continue }
            out += piece(ns.substring(with: NSRange(location: at, length: match.range.location - at)), base)
            func group(_ i: Int) -> String? {
                let r = match.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            var style = base
            if let code = group(2) {
                style.mono = true; style.size = 13.5; style.background = colours.well
                out += piece(code, style)
            } else if let label = group(3), let target = group(4) {
                style.link = URL(string: target); style.color = colours.link; style.underline = true
                out += inlineText(label, style, me, colours)
            } else if let target = group(5) {
                style.link = URL(string: target); style.color = colours.link; style.underline = true
                out += piece(target, style)
            } else if let inner = group(6) {
                style.weight = .heavy; style.italic = true; out += inlineText(inner, style, me, colours)
            } else if let inner = group(7) {
                style.weight = .heavy; out += inlineText(inner, style, me, colours)
            } else if let inner = group(8) {
                style.underline = true; out += inlineText(inner, style, me, colours)
            } else if let inner = group(9) {
                style.strike = true; out += inlineText(inner, style, me, colours)
            } else if let inner = group(10) {
                style.background = colours.ink.opacity(0.82); style.color = colours.paper; out += piece(inner, style)
            } else if let inner = group(11) ?? group(12) {
                style.italic = true; out += inlineText(inner, style, me, colours)
            } else if let name = group(13) {
                let mine = !me.isEmpty && name.caseInsensitiveCompare(me) == .orderedSame
                style.weight = .bold
                style.color = mine ? Color(red: 0.69, green: 0.48, blue: 0.06) : colours.link
                style.background = mine ? Color(red: 0.95, green: 0.71, blue: 0.27).opacity(0.25) : colours.link.opacity(0.14)
                out += piece("@" + name, style)
            }
            at = match.range.location + match.range.length
        }
        out += piece(ns.substring(from: at), base)
        return out
    }

    // MARK: Composing

    /// 𝓕𝓪𝓷𝓬𝔂 letters: A-Z, a-z and 0-9 to bold script; everything else as it is.
    static func fancy(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let mapped: UInt32? = (65...90).contains(v) ? 0x1D4D0 + v - 65
                : (97...122).contains(v) ? 0x1D4EA + v - 97
                : (48...57).contains(v) ? 0x1D7CE + v - 48 : nil
            if let mapped, let made = Unicode.Scalar(mapped) { out.unicodeScalars.append(made) } else { out.unicodeScalars.append(scalar) }
        }
        return out
    }

    /// Wraps [range] (UTF-16) in markers, or takes them off when already there. Returns text and new selection.
    static func wrap(_ text: String, _ range: NSRange, _ marker: String, _ end: String? = nil) -> (String, NSRange) {
        let close = end ?? marker
        let ns = text as NSString
        let m = (marker as NSString).length, c = (close as NSString).length
        let inner = ns.substring(with: range)
        if range.location >= m, range.location + range.length + c <= ns.length,
           ns.substring(with: NSRange(location: range.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: range.location + range.length, length: c)) == close {
            let next = ns.replacingCharacters(in: NSRange(location: range.location - m, length: range.length + m + c), with: inner)
            return (next, NSRange(location: range.location - m, length: range.length))
        }
        let next = ns.replacingCharacters(in: range, with: marker + inner + close)
        return (next, NSRange(location: range.location + m, length: range.length))
    }

    static func fancySelection(_ text: String, _ range: NSRange) -> (String, NSRange) {
        let ns = text as NSString
        let made = fancy(ns.substring(with: range))
        return (ns.replacingCharacters(in: range, with: made), NSRange(location: range.location, length: (made as NSString).length))
    }

    static func linkSelection(_ text: String, _ range: NSRange) -> (String, NSRange) {
        let ns = text as NSString
        let inner = ns.substring(with: range)
        let next = ns.replacingCharacters(in: range, with: "[" + inner + "](https://)")
        return (next, NSRange(location: range.location + 1 + (inner as NSString).length + 10, length: 0))
    }

    static func quoteLine(_ text: String, _ range: NSRange) -> (String, NSRange) {
        let ns = text as NSString
        let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
        let next = ns.replacingCharacters(in: NSRange(location: lineStart, length: 0), with: "> ")
        return (next, NSRange(location: range.location + 2, length: range.length))
    }
}

// MARK: - Link embeds

@MainActor
final class WyrmLinkPreviewCache: ObservableObject {
    static let shared = WyrmLinkPreviewCache()
    @Published private(set) var values: [String: WyrmLinkPreview] = [:]
    private var askedAt: [String: Date] = [:]
    /// Set by the chat screen (services.linkPreview); nil = no embeds.
    var loader: ((String) async -> WyrmLinkPreview?)?
    /// A found preview is kept; a link with none is asked again after a minute.
    func load(_ url: String) {
        guard let loader, values[url] == nil else { return }
        if let last = askedAt[url], Date().timeIntervalSince(last) < 60 { return }
        askedAt[url] = Date()
        Task { if let value = await loader(url) { values[url] = value } }
    }
}

/// Discord's embed under a message: a bar, the site, the title as a link, the text, the picture.
struct WyrmChatLinkEmbed: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    @Environment(\.openURL) private var openURL
    @ObservedObject private var cache = WyrmLinkPreviewCache.shared
    let url: String

    /// No page details (a site that hides them, or not loaded yet): still a
    /// small card with the site and the link (OM, 2026-11-07).
    private var shown: WyrmLinkPreview {
        if let preview = cache.values[url] { return preview }
        let host = (URL(string: url)?.host ?? "").replacingOccurrences(of: "www.", with: "")
        let bare = url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        return WyrmLinkPreview(url: url, title: String(bare.prefix(120)), description: "", image: "", siteName: host)
    }

    var body: some View {
        Group {
            if true {
                let preview = shown
                Button { if let target = URL(string: url) { openURL(target) } } label: {
                    HStack(spacing: 0) {
                        Rectangle().fill(wyrmScopedColours.link).frame(width: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            if !preview.siteName.isEmpty {
                                Text(preview.siteName).font(.androidWyrm(11.5)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                            }
                            if !preview.title.isEmpty {
                                Text(preview.title).font(.androidWyrm(14.5, .heavy)).foregroundColor(wyrmScopedColours.link)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                            if !preview.description.isEmpty {
                                Text(preview.description).font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.mute)
                                    .lineLimit(3).multilineTextAlignment(.leading)
                            }
                            if !preview.image.isEmpty {
                                WyrmGifView(url: preview.image, fill: true)
                                    .frame(maxWidth: .infinity).frame(height: 170)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .padding(.top, 5)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(wyrmScopedColours.well))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .onAppear { cache.load(url) }
    }
}

// MARK: - A real text view

/// A UITextView in Wyrm's font (OM, 2026-11-07): the system's own editing,
/// so the cursor can be dragged (hold the space bar or the text), and hold
/// gives Select, Select All, Copy, Paste as everywhere on iOS. Grows to
/// [maxLines], then scrolls. Return makes a new line unless [singleLine].
struct WyrmTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var focused: Bool
    var placeholder: String
    var fontSize: CGFloat = 15
    var maxLines = 6
    var limit = 1000
    var singleLine = false
    var monospaced = false
    var keyboard: UIKeyboardType = .default
    var onReturn: (() -> Void)? = nil
    /// Only these characters may go in (lowercased first when [lowercase]);
    /// others are dropped where they are typed or pasted, cursor kept.
    var allow: ((Character) -> Bool)? = nil
    var lowercase = false
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private var font: UIFont {
        monospaced ? .monospacedSystemFont(ofSize: fontSize, weight: .medium)
            : (UIFont(name: "Manrope", size: fontSize) ?? .systemFont(ofSize: fontSize))
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = font
        view.textContainerInset = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.keyboardType = keyboard
        view.autocorrectionType = singleLine ? .no : .default
        view.autocapitalizationType = singleLine ? .none : .sentences
        view.returnKeyType = singleLine ? .done : .default
        view.delegate = context.coordinator
        view.text = text
        let label = UILabel()
        label.font = font
        label.tag = 7_701
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 11),
        ])
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let colours = WyrmThemeColours(palette: WyrmThemeStore.shared.palette)
        view.textColor = UIColor(colours.ink)
        view.tintColor = UIColor(colours.ink)
        if view.text != text { view.text = text }
        if let label = view.viewWithTag(7_701) as? UILabel {
            label.text = placeholder
            // The theme's mute ink: readable on every theme's field (OM, 2026-11-07).
            label.textColor = UIColor(colours.mute)
            label.isHidden = !text.isEmpty
        }
        // A selection set from SwiftUI (the format bar) goes to the view; the
        // view's own cursor moves are never pushed back while their report is
        // still on its way (that is what made a dragged cursor jump back).
        let length = (view.text as NSString).length
        let start = min(max(0, selection.location == NSNotFound ? length : selection.location), length)
        let wanted = NSRange(location: start, length: min(max(0, selection.length), length - start))
        if context.coordinator.pending == 0, view.selectedRange != wanted {
            view.selectedRange = wanted
        }
        if focused && !view.isFirstResponder && view.window != nil {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !focused && view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
        context.coordinator.measure(view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: WyrmTextView
        /// Selection reports not yet written to the binding.
        var pending = 0
        init(_ parent: WyrmTextView) { self.parent = parent }

        private func report(_ range: NSRange) {
            pending += 1
            DispatchQueue.main.async {
                self.parent.selection = range
                self.pending -= 1
            }
        }

        func measure(_ view: UITextView) {
            let lineHeight = view.font?.lineHeight ?? 18
            let maxHeight = lineHeight * CGFloat(parent.maxLines) + 22
            let fit = view.sizeThatFits(CGSize(width: max(view.bounds.width, 40), height: .greatestFiniteMagnitude)).height
            let next = min(max(fit, lineHeight + 22), maxHeight)
            view.isScrollEnabled = fit > maxHeight
            if abs(next - parent.height) > 0.5 { DispatchQueue.main.async { self.parent.height = next } }
        }
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", parent.singleLine || parent.onReturn != nil {
                parent.onReturn?()
                if parent.singleLine { view.resignFirstResponder() }
                return false
            }
            let current = view.text as NSString
            if parent.allow != nil || parent.lowercase {
                var cleaned = parent.lowercase ? text.lowercased() : text
                if let allow = parent.allow { cleaned = String(cleaned.filter(allow)) }
                let room = parent.limit - (current.length - range.length)
                if room <= 0 && !cleaned.isEmpty { return false }
                if (cleaned as NSString).length > room { cleaned = String(cleaned.prefix(room)) }
                if cleaned != text {
                    view.text = current.replacingCharacters(in: range, with: cleaned)
                    view.selectedRange = NSRange(location: range.location + (cleaned as NSString).length, length: 0)
                    textViewDidChange(view)
                    return false
                }
                return true
            }
            return current.length - range.length + (text as NSString).length <= parent.limit
        }
        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            report(view.selectedRange)
            measure(view)
        }
        func textViewDidChangeSelection(_ view: UITextView) {
            report(view.selectedRange)
        }
        func textViewDidBeginEditing(_ view: UITextView) { if !parent.focused { DispatchQueue.main.async { self.parent.focused = true } } }
        func textViewDidEndEditing(_ view: UITextView) { if parent.focused { DispatchQueue.main.async { self.parent.focused = false } } }
    }
}

/// Discord's bar over the composer while text is selected.
struct WyrmChatFormatBar: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    @Binding var text: String
    @Binding var selection: NSRange
    var applied: () -> Void = {}

    private func apply(_ result: (String, NSRange)) {
        text = result.0
        selection = result.1
        applied()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                key(Text("B").font(.androidWyrm(14, .black))) { apply(WyrmChatMarkdown.wrap(text, selection, "**")) }
                key(Text("I").font(.androidWyrm(14, .bold).italic())) { apply(WyrmChatMarkdown.wrap(text, selection, "*")) }
                key(Text("U").font(.androidWyrm(14, .bold)).underline()) { apply(WyrmChatMarkdown.wrap(text, selection, "__")) }
                key(Text("S").font(.androidWyrm(14, .bold)).strikethrough()) { apply(WyrmChatMarkdown.wrap(text, selection, "~~")) }
                key(Text("</>").font(.system(size: 13, weight: .bold, design: .monospaced))) { apply(WyrmChatMarkdown.wrap(text, selection, "`")) }
                key(Text("||").font(.androidWyrm(14, .black))) { apply(WyrmChatMarkdown.wrap(text, selection, "||")) }
                key(Text("❝").font(.androidWyrm(14, .black))) { apply(WyrmChatMarkdown.quoteLine(text, selection)) }
                key(Text("Link").font(.androidWyrm(14, .bold)).foregroundColor(wyrmScopedColours.link)) { apply(WyrmChatMarkdown.linkSelection(text, selection)) }
                key(Text(WyrmChatMarkdown.fancy("Fancy")).font(.system(size: 14))) { apply(WyrmChatMarkdown.fancySelection(text, selection)) }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(wyrmScopedColours.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(wyrmScopedColours.rule))
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func key(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.foregroundColor(wyrmScopedColours.ink).padding(.horizontal, 11).frame(height: 34).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// The skin code as a normal field (OM, 2026-11-07: the cursor jumped to the
/// end when dragged and hold gave no Select all / Copy). A real text view:
/// letters that are not beads are dropped where typed or pasted, cursor kept;
/// the field takes the pattern's code back only when the pattern changed
/// somewhere else (a bead tapped, Undo, Clear).
struct WyrmSkinCodeField: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    let groups: [Int]
    var maxBeads = 256
    var placeholder = "Type or paste a skin code"
    @Binding var focused: Bool
    let onCode: (String) -> Void
    @State private var text = ""
    @State private var seen: String?
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var height: CGFloat = 44

    var body: some View {
        let code = WyrmSkinCatalog.code(for: groups)
        WyrmTextView(text: Binding(get: { text }, set: { typed in
                         text = typed
                         if typed != code { onCode(typed) }
                     }),
                     selection: $selection, focused: $focused, placeholder: placeholder,
                     maxLines: 1, limit: maxBeads, singleLine: true, monospaced: true,
                     allow: { WyrmSkinCatalog.group(for: $0) != nil }, lowercase: true, height: $height)
            .frame(height: height)
            .padding(.horizontal, 13)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(wyrmScopedColours.card))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(wyrmScopedColours.rule))
            .onAppear { if seen == nil { seen = code; text = code } }
            .onChange(of: code) { next in
                guard next != seen else { return }
                seen = next
                if next != text { text = next; selection = NSRange(location: (next as NSString).length, length: 0) }
            }
    }
}
