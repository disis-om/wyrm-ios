import SwiftUI

/*
 * Markdown for notifications, block by block (OM, 2026-09-30: "duniya ka har
 * trah ka markdown", Enter and spaces kept). `AttributedString(markdown:)`
 * with `.full` joins every block into one run of text, so a notice read as one
 * paragraph. Here the blocks are parsed line by line and each is drawn on its
 * own; inline syntax (bold, italic, code, links, strikethrough) goes through
 * `.inlineOnlyPreservingWhitespace`, which keeps every line break and space.
 *
 * Blocks: ATX and setext headings, paragraphs (one Enter = a new line, extra
 * blank lines = extra space), bullet / numbered / task lists with nesting,
 * block quotes (nested), fenced and indented code, thematic breaks, GFM
 * tables with alignment, and `<br>`. Android draws the same with commonmark
 * (`WyrmMarkdown.kt`).
 */

indirect enum WyrmMarkdownBlock: Equatable {
    enum Marker: Equatable { case bullet, number(Int), task(Bool) }
    enum Align: Equatable { case leading, center, trailing }
    struct Item: Equatable { let depth: Int; let marker: Marker; let text: String }

    case heading(Int, String)
    case paragraph(String)
    case space(Int)
    case list([Item])
    case quote([WyrmMarkdownBlock])
    case code(String, String)
    case rule
    case table([String], [Align], [[String]])

    // MARK: Parsing

    static func parse(_ source: String) -> [WyrmMarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [WyrmMarkdownBlock] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank lines: one is a paragraph break; each extra one is kept as space.
            if trimmed.isEmpty {
                var run = 0
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty { run += 1; i += 1 }
                if run > 1 && !blocks.isEmpty && i < lines.count { blocks.append(.space(run - 1)) }
                continue
            }

            // Fenced code.
            if let fence = fenceOpening(trimmed) {
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { body.append(lines[i]); i += 1 }
                i += 1
                blocks.append(.code(language, body.joined(separator: "\n")))
                continue
            }

            // Indented code (four spaces or a tab), not inside a list.
            if (line.hasPrefix("    ") || line.hasPrefix("\t")) && !isListLine(line) {
                var body: [String] = []
                while i < lines.count, lines[i].hasPrefix("    ") || lines[i].hasPrefix("\t") || lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    let raw = lines[i]
                    body.append(raw.hasPrefix("\t") ? String(raw.dropFirst()) : String(raw.dropFirst(min(4, raw.count))))
                    i += 1
                }
                while body.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeLast() }
                blocks.append(.code("", body.joined(separator: "\n")))
                continue
            }

            if let heading = atxHeading(trimmed) { blocks.append(heading); i += 1; continue }
            if isRule(trimmed) { blocks.append(.rule); i += 1; continue }

            // Tables: a header row, then a separator row.
            if trimmed.contains("|"), i + 1 < lines.count, let aligns = tableSeparator(lines[i + 1]) {
                let header = cells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    rows.append(cells(row)); i += 1
                }
                blocks.append(.table(header, aligns, rows))
                continue
            }

            // Block quotes, parsed again inside.
            if trimmed.hasPrefix(">") {
                var inner: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var rest = t.dropFirst()
                    if rest.hasPrefix(" ") { rest = rest.dropFirst() }
                    inner.append(String(rest)); i += 1
                }
                blocks.append(.quote(parse(inner.joined(separator: "\n"))))
                continue
            }

            // Lists; an indented plain line continues the item above it.
            if isListLine(line) {
                var items: [Item] = []
                while i < lines.count {
                    let raw = lines[i]
                    if let item = listItem(raw) { items.append(item); i += 1; continue }
                    let t = raw.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty, raw.hasPrefix("  "), let last = items.popLast() {
                        items.append(Item(depth: last.depth, marker: last.marker, text: last.text + "\n" + t)); i += 1; continue
                    }
                    break
                }
                blocks.append(.list(items))
                continue
            }

            // A paragraph: every line as typed, until a blank line or another block.
            var text: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let t = next.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                // Setext headings: a line of = or - under the text.
                if !t.isEmpty && t.allSatisfy({ $0 == "=" }) { blocks.append(.heading(1, text.joined(separator: "\n"))); text = []; i += 1; break }
                if t.count >= 2 && t.allSatisfy({ $0 == "-" }) { blocks.append(.heading(2, text.joined(separator: "\n"))); text = []; i += 1; break }
                if fenceOpening(t) != nil || atxHeading(t) != nil || isRule(t) || t.hasPrefix(">") || isListLine(next) { break }
                if t.contains("|"), i + 1 < lines.count, tableSeparator(lines[i + 1]) != nil { break }
                text.append(next); i += 1
            }
            if !text.isEmpty { blocks.append(.paragraph(text.joined(separator: "\n"))) }
        }
        return blocks
    }

    private static func fenceOpening(_ t: String) -> String? {
        for mark in ["```", "~~~"] where t.hasPrefix(mark) {
            return String(t.prefix(while: { $0 == mark.first }))
        }
        return nil
    }

    private static func atxHeading(_ t: String) -> WyrmMarkdownBlock? {
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of #s is not part of the heading.
        while text.hasSuffix("#") { text.removeLast() }
        return .heading(hashes, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ t: String) -> Bool {
        let compact = t.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isListLine(_ raw: String) -> Bool { listItem(raw) != nil }

    private static func listItem(_ raw: String) -> Item? {
        let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let t = raw.trimmingCharacters(in: .whitespaces)
        var marker: Marker
        var rest: Substring
        if let first = t.first, "-*+".contains(first), t.dropFirst().first == " " || t.count == 1 {
            marker = .bullet
            rest = t.dropFirst().drop(while: { $0 == " " })
        } else {
            let digits = t.prefix(while: { $0.isNumber })
            guard !digits.isEmpty, digits.count <= 9 else { return nil }
            let after = t.dropFirst(digits.count)
            guard let dot = after.first, dot == "." || dot == ")", after.dropFirst().first == " " || after.count == 1 else { return nil }
            marker = .number(Int(digits) ?? 1)
            rest = after.dropFirst().drop(while: { $0 == " " })
        }
        // Task items: "- [ ] …" and "- [x] …".
        if rest.hasPrefix("[ ] ") || rest == "[ ]" { marker = .task(false); rest = rest.dropFirst(3).drop(while: { $0 == " " }) }
        else if rest.lowercased().hasPrefix("[x] ") || rest.lowercased() == "[x]" { marker = .task(true); rest = rest.dropFirst(3).drop(while: { $0 == " " }) }
        return Item(depth: min(indent / 2, 6), marker: marker, text: String(rest))
    }

    private static func cells(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var out: [String] = []
        var cell = ""
        var escaped = false
        for c in t {
            if escaped { cell.append(c); escaped = false; continue }
            if c == "\\" { escaped = true; cell.append(c); continue }
            if c == "|" { out.append(cell.trimmingCharacters(in: .whitespaces)); cell = ""; continue }
            cell.append(c)
        }
        out.append(cell.trimmingCharacters(in: .whitespaces))
        return out.map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    private static func tableSeparator(_ raw: String) -> [Align]? {
        let parts = cells(raw)
        guard !parts.isEmpty else { return nil }
        var aligns: [Align] = []
        for part in parts {
            let p = part.trimmingCharacters(in: .whitespaces)
            let core = p.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }
            let left = p.hasPrefix(":"), right = p.hasSuffix(":")
            aligns.append(left && right ? .center : right ? .trailing : .leading)
        }
        return aligns
    }

    /// The words without Markdown's marks, one line per block: for the
    /// two-line in-app banner.
    static func plainText(_ source: String) -> String {
        func flat(_ text: String) -> String { String(inline(text).characters) }
        func lines(_ blocks: [WyrmMarkdownBlock]) -> [String] {
            blocks.flatMap { block -> [String] in
                switch block {
                case .heading(_, let text), .paragraph(let text): return [flat(text)]
                case .list(let items): return items.map { "• " + flat($0.text) }
                case .quote(let inner): return lines(inner)
                case .code(_, let text): return [text]
                case .table(let header, _, let rows): return ([header] + rows).map { $0.map(flat).joined(separator: " · ") }
                case .space, .rule: return []
                }
            }
        }
        return lines(parse(source)).joined(separator: "\n")
    }

    // MARK: Inline

    /// Bold, italic, code, links and strikethrough, with every space and line break kept.
    static func inline(_ text: String) -> AttributedString {
        let source = text.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false,
                                                              interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

/// A notification's body (or any Markdown) in Wyrm's type, block by block.
struct WyrmMarkdown: View {
    let source: String
    var size: CGFloat = 12.5
    var ink: Color = ATheme.mute

    var body: some View {
        blocks(WyrmMarkdownBlock.parse(source))
    }

    private func blocks(_ list: [WyrmMarkdownBlock]) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, block in self.block(block) }
        })
    }

    private func block(_ block: WyrmMarkdownBlock) -> AnyView {
        switch block {
        case .heading(let level, let text):
            let sizes: [CGFloat] = [22, 18, 15.5, 14, 13, 12.5]
            return AnyView(Text(WyrmMarkdownBlock.inline(text))
                .font(.androidWyrm(sizes[min(max(level, 1), 6) - 1], .bold))
                .foregroundColor(ATheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 1))
        case .paragraph(let text):
            return AnyView(Text(WyrmMarkdownBlock.inline(text))
                .font(.androidWyrm(size)).foregroundColor(ink).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading))
        case .space(let lines):
            return AnyView(Color.clear.frame(height: CGFloat(lines) * size * 1.3))
        case .list(let items):
            return AnyView(VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker(item)
                        Text(WyrmMarkdownBlock.inline(item.text))
                            .font(.androidWyrm(size)).foregroundColor(ink).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, CGFloat(item.depth) * 14)
                }
            })
        case .quote(let inner):
            return AnyView(HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(ATheme.link.opacity(0.7)).frame(width: 2.5)
                blocks(inner)
            }.fixedSize(horizontal: false, vertical: true))
        case .code(let language, let text):
            return AnyView(VStack(alignment: .leading, spacing: 5) {
                if !language.isEmpty {
                    Text(language.uppercased()).font(.androidWyrm(9, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text).font(.system(size: max(size - 1, 10), design: .monospaced)).foregroundColor(ATheme.ink)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ATheme.well))
            })
        case .rule:
            return AnyView(Rectangle().fill(ATheme.rule).frame(height: 1).padding(.vertical, 4))
        case .table(let header, let aligns, let rows):
            let columns = max(header.count, rows.map(\.count).max() ?? 0)
            return AnyView(ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    tableRow(header, aligns: aligns, columns: columns, header: true)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Rectangle().fill(ATheme.rule).frame(height: 1)
                        tableRow(row, aligns: aligns, columns: columns, header: false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            })
        }
    }

    @ViewBuilder
    private func marker(_ item: WyrmMarkdownBlock.Item) -> some View {
        switch item.marker {
        case .bullet:
            Text(["•", "◦", "▪"][item.depth % 3]).font(.androidWyrm(size, .bold)).foregroundColor(ATheme.quiet)
        case .number(let n):
            Text("\(n).").font(.androidWyrm(size, .semibold)).foregroundColor(ATheme.quiet).monospacedDigit()
        case .task(let done):
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(done ? ATheme.live : ATheme.quiet)
        }
    }

    private func tableRow(_ row: [String], aligns: [WyrmMarkdownBlock.Align], columns: Int, header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columns, id: \.self) { column in
                let align = column < aligns.count ? aligns[column] : .leading
                Text(WyrmMarkdownBlock.inline(column < row.count ? row[column] : ""))
                    .font(.androidWyrm(header ? size - 0.5 : size, header ? .bold : .regular))
                    .foregroundColor(header ? ATheme.ink : ink)
                    .multilineTextAlignment(align == .center ? .center : align == .trailing ? .trailing : .leading)
                    .frame(minWidth: 96, maxWidth: 220,
                           alignment: align == .center ? .center : align == .trailing ? .trailing : .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(header ? ATheme.well : Color.clear)
            }
        }
    }
}
