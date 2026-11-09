import SwiftUI
import UIKit
import ImageIO

/*
 * Global chat and direct messages, the next level (OM, 2026-10-30), laid out
 * like Discord in Wyrm's own paper and ink. Android twin: `ui/WyrmChat.kt`.
 *
 * - Rows, not bubbles: a squircle face (the 128 px copy), name, DEV badge for
 *   the accounts that run Wyrm, time; a run of one author within 7 minutes
 *   shares one head. Day dividers between days.
 * - Reply: swipe a message left, or hold it. A reply shows the line it answers.
 * - Hold: quick reactions (and + for every emoji), Reply, Edit, Copy, Mention,
 *   Pin (DEV only), Delete or Report. A tap on a reaction under a message adds
 *   or takes back yours.
 * - A message that mentions you gets a gold wash and bar; `@` in the composer
 *   lists the people in the room.
 * - Who is typing, Discord's words: "A is typing…", "A and B are typing…",
 *   "A, B and C are typing…", then "Several people are typing…".
 * - GIFs and stickers from KLIPY through the backend (the key never ships).
 * - Search and pins in the bar; older messages load as you scroll up.
 * New messages, reactions, pins and typing come on the live socket
 * (`WyrmLiveInbox.onChatEvent`); the open room still reads again every 20 s.
 */

enum WyrmChatKit {
    static let pink = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x7A / 255)
    static let gold = Color(red: 0xF0 / 255, green: 0xB2 / 255, blue: 0x32 / 255)
    static let quick = ["❤️", "😂", "👍", "🔥", "😮"]
    /// The GIF picker's categories: label and search term ("" = trending). Same list as Android.
    static let gifCategories: [(String, String)] = [
        ("Trending", ""), ("Happy", "happy"), ("LOL", "lol"), ("Love", "love"), ("Sad", "sad"), ("Wow", "wow"),
        ("Angry", "angry"), ("Dance", "dance"), ("GG", "gg"), ("Hype", "hype"), ("Thanks", "thank you"),
        ("Hi", "hello"), ("Bye", "bye"), ("Yes", "yes"), ("No", "no"), ("Cute", "cute"), ("Snake", "snake"),
    ]
    static let emoji: [(String, [String])] = [
        ("Smileys", ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😋", "😛", "😜", "🤪", "🤗", "🤭", "🤫", "🤔", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😌", "😔", "😪", "😴", "😷", "🤒", "🥵", "🥶", "🥴", "😵", "🤯", "🤠", "🥳", "😎", "🤓", "😕", "😟", "🙁", "😮", "😯", "😲", "😳", "🥺", "😦", "😧", "😨", "😰", "😥", "😢", "😭", "😱", "😖", "😣", "😞", "😓", "😩", "😫", "🥱", "😤", "😡", "😠", "🤬", "😈", "👿", "💀", "💩", "🤡", "👻", "👽", "🤖"]),
        ("Gestures", ["👍", "👎", "👊", "✊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "🤝", "🙏", "✌️", "🤞", "🤟", "🤘", "👌", "🤌", "👈", "👉", "👆", "👇", "☝️", "✋", "🤚", "🖐️", "🖖", "👋", "🤙", "💪", "🫡", "👀", "🧠"]),
        ("Hearts", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💯", "💢", "💥", "💫", "💦", "💨", "🔥", "✨", "⭐", "🌟", "⚡"]),
        ("Snakes & play", ["🐍", "🐉", "🐲", "🦎", "🐢", "🐊", "🐛", "🪱", "🍎", "🍏", "🍒", "🍓", "🍇", "🍉", "🍕", "🍔", "🍟", "🎮", "🕹️", "🏆", "🥇", "🥈", "🥉", "🎯", "🎲", "👑", "💎", "🚀", "🎉", "🎊", "🎁", "🌈"]),
    ]

    /// A GIF or sticker message is the KLIPY address and nothing else.
    static func isGif(_ body: String) -> Bool {
        body.range(of: #"^https://[a-z0-9.-]*klipy\.com/\S+$"#, options: .regularExpression) != nil
    }

    /// Discord's words for who is typing.
    static func typingLine(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) is typing…"
        case 2: return "\(names[0]) and \(names[1]) are typing…"
        case 3: return "\(names[0]), \(names[1]) and \(names[2]) are typing…"
        default: return "Several people are typing…"
        }
    }

    static func date(_ raw: String) -> Date? { parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) }

    /// "Today at 3:45 PM", "Yesterday at 9:10 AM", "12/10/2026 3:45 PM".
    static func time(_ raw: String) -> String {
        guard let when = date(raw) else { return "" }
        let clock = clockFormat.string(from: when)
        let calendar = Calendar.current
        if calendar.isDateInToday(when) { return "Today at \(clock)" }
        if calendar.isDateInYesterday(when) { return "Yesterday at \(clock)" }
        return "\(dayFormat.string(from: when)) \(clock)"
    }

    static func clock(_ raw: String) -> String { date(raw).map { clockFormat.string(from: $0) } ?? "" }

    static func day(_ raw: String) -> String {
        guard let when = date(raw) else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(when) { return "Today" }
        if calendar.isDateInYesterday(when) { return "Yesterday" }
        return longDay.string(from: when)
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "W" : letters
    }

    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let clockFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    private static let longDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()
}

/// Someone in the room the composer can `@` (from who has spoken lately).
struct WyrmMentionable {
    let username: String
    let name: String
    let avatarURL: String
}

/// What the room asks of the screen around it.
struct WyrmChatHandlers {
    var onSend: () -> Void
    var onSendGif: (String) -> Void
    var onTyping: () -> Void
    var onAuthor: (String) -> Void
    var onReply: (WyrmChatItem) -> Void
    var onEdit: (WyrmChatItem) -> Void
    var onCancelCompose: () -> Void
    var onDelete: (WyrmChatItem) -> Void
    var onReport: ((WyrmChatItem) -> Void)?
    var onReact: (WyrmChatItem, String) -> Void
    var onPin: ((WyrmChatItem, Bool) -> Void)?
    var onLoadOlder: () -> Void
    var search: (String) async -> [WyrmChatItem]
    var gifs: (Bool, String) async -> [WyrmGifItem]
    /// Who reacted (hold a reaction, OM 2026-10-31).
    var who: (WyrmChatItem) async -> [(String, [WyrmReactionPerson])] = { _ in [] }
    /// @ suggestions from every player (OM 2026-11-07).
    var mentionSearch: (String) async -> [WyrmMentionable] = { _ in [] }
}

private enum WyrmChatSheet: Identifiable {
    case hold(WyrmChatItem)
    case react(WyrmChatItem)
    case picker
    case search
    case pins
    case who(WyrmChatItem, String)
    case active
    var id: String {
        switch self {
        case .active: return "active"
        case .who(let m, let emoji): return "who-" + m.id + emoji
        case .hold(let m): return "hold-" + m.id
        case .react(let m): return "react-" + m.id
        case .picker: return "picker"
        case .search: return "search"
        case .pins: return "pins"
        }
    }
}

/// The bar's two buttons, handed to the header the caller draws.
struct WyrmChatBarActions {
    let search: () -> Void
    let pins: () -> Void
    /// "{n} active" (OM 2026-11-07): who has Wyrm open now.
    var active: () -> Void = {}
}

struct WyrmDiscordChat<Header: View>: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let direct: Bool
    let messages: [WyrmChatItem]
    let meID: String
    let meUsername: String
    /// A direct thread: the other player (their face beside their messages).
    var peer: WyrmServicePlayer? = nil
    var typing: [String] = []
    var canPin = false
    var pins: [WyrmChatItem] = []
    var hasOlder = false
    var loadingOlder = false
    var limit = 280
    var placeholder = "Message"
    var emptyTitle = "Quiet right now"
    var emptyNote = ""
    @Binding var draft: String
    var sending = false
    var error = ""
    var replying: WyrmChatItem?
    var editing: WyrmChatItem?
    let handlers: WyrmChatHandlers
    /// Global chat: who has Wyrm open now ("{n} active", OM 2026-11-07).
    var activeTitle = ""
    var activePeople: [WyrmChatPerson] = []
    let header: (WyrmChatBarActions) -> Header

    @State private var sheet: WyrmChatSheet?
    /// When a reaction was held (its "who reacted" wins over the message's hold).
    @State private var whoAt = Date.distantPast
    @State private var settled = false
    @State private var anchorID: String?
    @State private var focused = false
    /// The composer's selection (UTF-16), for the format bar; and its height.
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var fieldHeight: CGFloat = 42
    /// Players found for the @ being typed (every player, not just the room).
    @State private var remoteMentions: [WyrmMentionable] = []
    /// Older pages (OM 2026-11-07): the top marker must leave the screen
    /// before it may ask again, so one swipe never loads page after page.
    @State private var olderArmed = true

    private var mentionables: [WyrmMentionable] {
        var seen = Set<String>()
        var rows: [WyrmMentionable] = []
        for message in messages.reversed() where message.authorID != meID && !message.authorUsername.isEmpty {
            if seen.insert(message.authorUsername.lowercased()).inserted {
                rows.append(WyrmMentionable(username: message.authorUsername, name: message.authorName, avatarURL: message.authorAvatarURL))
            }
        }
        return rows
    }

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 0) {
                header(WyrmChatBarActions(search: { sheet = .search }, pins: { sheet = .pins }, active: { sheet = .active }))
                Rectangle().fill(wyrmScopedColours.rule).frame(height: 1)
                list
                if !error.isEmpty {
                    Text(error).font(.androidWyrm(11.5)).foregroundColor(wyrmScopedColours.badge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                }
                composerArea
            }
        }
        .foregroundColor(wyrmScopedColours.ink)
        .onAppear { WyrmChatRow.meUsername = meUsername }
        // Any sheet coming up puts the keyboard away, as Discord does (OM, 2026-10-31).
        .onChange(of: sheet?.id) { value in if value != nil { focused = false } }
        .sheet(item: $sheet) { value in
            Group {
                switch value {
                case .hold(let message): holdSheet(message)
                case .react(let message):
                    WyrmChatPicker(emojiOnly: true, gifs: handlers.gifs) { emoji in sheet = nil; handlers.onReact(message, emoji) } onGif: { _ in }
                case .picker:
                    WyrmChatPicker(emojiOnly: false, gifs: handlers.gifs) { emoji in draft += emoji } onGif: { url in sheet = nil; handlers.onSendGif(url) }
                case .search:
                    WyrmChatSearch(direct: direct, search: handlers.search, peer: peer) { sheet = nil }
                case .pins:
                    WyrmChatPins(pins: pins, canPin: canPin) { message in handlers.onPin?(message, false) } close: { sheet = nil }
                case .who(let message, let emoji):
                    WyrmWhoReacted(message: message, first: emoji, load: handlers.who) { id in sheet = nil; handlers.onAuthor(id) }
                case .active:
                    WyrmActivePeople(title: activeTitle, people: activePeople) { id in sheet = nil; handlers.onAuthor(id) }
                }
            }
            .modifier(WyrmChatDetents())
        }
    }

    // MARK: The list

    private var list: some View {
        ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if (hasOlder || loadingOlder) && !messages.isEmpty {
                        HStack(spacing: 8) {
                            Spacer()
                            if loadingOlder {
                                ProgressView().scaleEffect(0.75)
                                Text("Loading messages").font(.androidWyrm(12, .semibold)).foregroundColor(wyrmScopedColours.quiet)
                            }
                            Spacer()
                        }
                        .frame(height: loadingOlder ? 40 : 1)
                        .onAppear {
                            guard settled, !loadingOlder, olderArmed else { return }
                            olderArmed = false
                            anchorID = messages.first?.id
                            handlers.onLoadOlder()
                        }
                        .onDisappear { olderArmed = true }
                    }
                    // The very start of the room (OM, 2026-10-31): Discord's card, no more loading.
                    if !direct && !hasOlder && !loadingOlder && !messages.isEmpty {
                        chatStart
                    }
                    if messages.isEmpty {
                        if direct {
                            WyrmDirectIntro(peer: peer, onPeer: { if let peer { handlers.onAuthor(peer.id) } }).padding(.top, 44)
                        } else {
                            WyrmPaperCard { WyrmEmptyPanel(title: emptyTitle, note: emptyNote) }.padding(.top, 18).padding(.horizontal, 14)
                        }
                    } else if direct && !hasOlder {
                        WyrmDirectIntro(peer: peer, onPeer: { if let peer { handlers.onAuthor(peer.id) } }).padding(.top, 12).padding(.bottom, 6)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        if WyrmChatKit.day(message.createdAt) != previous.map({ WyrmChatKit.day($0.createdAt) }) {
                            dayDivider(WyrmChatKit.day(message.createdAt))
                        }
                        WyrmChatRow(message: message, startsRun: startsRun(message, previous), mine: message.authorID == meID,
                                    mentionsMe: mentionsMe(message), meID: meID, peer: peer, direct: direct,
                                    seenLine: seenLine(index),
                                    onAuthor: handlers.onAuthor, onReply: { handlers.onReply(message); focused = true },
                                    onHold: {
                                        // A hold on a reaction is "who reacted", not the message's hold.
                                        guard Date().timeIntervalSince(whoAt) > 0.8 else { return }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(); focused = false; sheet = .hold(message)
                                    },
                                    onReact: { handlers.onReact(message, $0) }, onMoreReactions: { sheet = .react(message) },
                                    onWho: { emoji in
                                        whoAt = Date()
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred(); focused = false; sheet = .who(message, emoji)
                                    })
                            .id(message.id)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                    Color.clear.frame(height: 6).id("wyrm-chat-bottom")
                }
                .padding(.top, 6)
                .animation(.easeOut(duration: 0.22), value: messages.last?.id)
            }
            .modifier(WyrmChatDismissOnScroll())
            .onAppear {
                reader.scrollTo("wyrm-chat-bottom", anchor: .bottom)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled = true }
            }
            .onChange(of: messages.first?.id) { _ in
                guard let anchorID else { return }
                self.anchorID = nil
                // Put the line being read back at once, with no animation, so
                // the new page lands above it instead of carrying the view up.
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { reader.scrollTo(anchorID, anchor: .top) }
            }
            .onChange(of: messages.last?.id) { _ in
                withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo("wyrm-chat-bottom", anchor: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo("wyrm-chat-bottom", anchor: .bottom) }
            }
        }
    }

    private var chatStart: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(wyrmScopedColours.well)
                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 21, weight: .semibold)).foregroundColor(wyrmScopedColours.ink)
            }
            .frame(width: 52, height: 52)
            .padding(.bottom, 6)
            Text("This is the start of Global chat").font(.wyrmDisplay(22)).foregroundColor(wyrmScopedColours.ink)
            Text("You're all caught up. Messages older than 7 days are cleared.")
                .font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.quiet).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(wyrmScopedColours.rule).frame(height: 1).padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
    }

    private func dayDivider(_ text: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(wyrmScopedColours.rule).frame(height: 1)
            Text(text).font(.androidWyrm(11, .bold)).foregroundColor(wyrmScopedColours.quiet).fixedSize()
            Rectangle().fill(wyrmScopedColours.rule).frame(height: 1)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
    }

    /// A new head: another author, a reply, or 7 minutes since the last line.
    private func startsRun(_ message: WyrmChatItem, _ previous: WyrmChatItem?) -> Bool {
        guard let previous, previous.authorID == message.authorID, message.replyID.isEmpty,
              WyrmChatKit.day(previous.createdAt) == WyrmChatKit.day(message.createdAt),
              let a = WyrmChatKit.date(previous.createdAt), let b = WyrmChatKit.date(message.createdAt) else { return true }
        return b.timeIntervalSince(a) > 7 * 60
    }

    private func mentionsMe(_ message: WyrmChatItem) -> Bool {
        guard !direct, message.authorID != meID else { return false }
        if message.mentions.contains(meID) { return true }
        guard !meUsername.isEmpty else { return false }
        return message.body.range(of: "@" + meUsername + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Seen" or "Sent" under your last direct message.
    private func seenLine(_ index: Int) -> String? {
        guard direct else { return nil }
        guard let last = messages.lastIndex(where: { $0.authorID == meID }), last == index else { return nil }
        return messages[index].readAt.isEmpty ? "Sent" : "Seen"
    }

    // MARK: The composer

    private var composerArea: some View {
        VStack(spacing: 0) {
            if let line = WyrmChatKit.typingLine(typing) {
                HStack(spacing: 8) {
                    WyrmTypingDots()
                    Text(line).font(.androidWyrm(11.5, .semibold)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 4)
                .transition(.opacity)
            }
            if !direct, let query = mentionQuery {
                let rows = mentionRows(query)
                if !rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.username) { row in
                            Button { pickMention(row.username) } label: {
                                HStack(spacing: 10) {
                                    WyrmAvatar(initials: WyrmChatKit.initials(row.name), size: 26, url: row.avatarURL)
                                    Text(row.name).font(.androidWyrm(13.5, .semibold)).lineLimit(1)
                                    Text("@" + row.username).font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 16).frame(height: 42).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .background(wyrmScopedColours.card)
                    .overlay(Rectangle().fill(wyrmScopedColours.rule).frame(height: 1), alignment: .top)
                }
            }
            if let target = editing ?? replying {
                WyrmComposeTarget(editing: editing != nil, name: target.authorName.isEmpty ? (peer?.displayName ?? "") : target.authorName,
                                  body_: WyrmChatKit.isGif(target.body) ? "GIF" : target.body, onCancel: handlers.onCancelCompose)
            }
            composer
        }
        .animation(.easeOut(duration: 0.18), value: typing)
        .task(id: mentionQuery) {
            guard !direct, let query = mentionQuery else { remoteMentions = []; return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            remoteMentions = await handlers.mentionSearch(query)
        }
    }

    /// Every candidate (room, online, then the server's search), best first:
    /// start of the username, start of the name, then anywhere (OM 2026-11-07).
    private func mentionRows(_ query: String) -> [WyrmMentionable] {
        let online = activePeople.filter { !$0.username.isEmpty && $0.id != meID }
            .map { WyrmMentionable(username: $0.username, name: $0.name, avatarURL: "") }
        var seen = Set<String>()
        var ranked: [(WyrmMentionable, Int, Int)] = []
        for (order, row) in (mentionables + online + remoteMentions).enumerated() {
            let key = row.username.lowercased()
            guard !key.isEmpty, key != meUsername.lowercased(), seen.insert(key).inserted else { continue }
            let name = row.name.lowercased()
            let rank = query.isEmpty || key.hasPrefix(query) ? 0 : name.hasPrefix(query) ? 1
                : (key.contains(query) || name.contains(query)) ? 2 : -1
            if rank >= 0 { ranked.append((row, rank, query.isEmpty ? order : key.count)) }
        }
        return Array(ranked.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }.map(\.0).prefix(8))
    }

    /// The word being typed when it starts with "@", without the "@".
    private var mentionQuery: String? {
        guard let last = draft.split(omittingEmptySubsequences: false, whereSeparator: { $0 == " " || $0 == "\n" }).last,
              last.hasPrefix("@"), !draft.hasSuffix(" "), !draft.hasSuffix("\n") else { return nil }
        let word = String(last.dropFirst()).lowercased()
        return word.count <= 20 ? word : nil
    }

    private func pickMention(_ username: String) {
        if let at = draft.range(of: "@", options: .backwards) {
            draft.replaceSubrange(at.lowerBound..<draft.endIndex, with: "@" + username + " ")
        }
        selection = NSRange(location: (draft as NSString).length, length: 0)
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !sending && draft.count <= limit }

    /// Minimal (OM): a plain field, emoji, GIF and Send. No glass.
    private var composer: some View {
        VStack(spacing: 0) {
        if selection.length > 0 && focused {
            WyrmChatFormatBar(text: $draft, selection: $selection)
        }
        HStack(alignment: .bottom, spacing: 8) {
            HStack(alignment: .bottom, spacing: 2) {
                field
                Button { focused = false; sheet = .picker } label: {
                    Image(systemName: "face.smiling").font(.system(size: 19, weight: .regular)).foregroundColor(wyrmScopedColours.quiet)
                        .frame(width: 38, height: 42)
                }.buttonStyle(.plain).accessibilityLabel("Emoji and GIFs")
            }
            .padding(.leading, 14).padding(.trailing, 2)
            .background(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(wyrmScopedColours.well))
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(wyrmScopedColours.rule))
            if canSend || sending {
                Button(action: send) {
                    ZStack {
                        if sending { ProgressView().tint(wyrmScopedColours.onInk).scaleEffect(0.75) }
                        else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(wyrmScopedColours.onInk) }
                    }
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(wyrmScopedColours.ink))
                }
                .buttonStyle(WSPressStyle()).disabled(!canSend).accessibilityLabel("Send")
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Button { focused = false; sheet = .picker } label: {
                    Text("GIF").font(.androidWyrm(12, .heavy)).foregroundColor(wyrmScopedColours.ink)
                        .frame(width: 42, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(wyrmScopedColours.ink, lineWidth: 1.6).padding(5))
                }
                .buttonStyle(.plain).accessibilityLabel("GIFs and stickers")
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canSend || sending)
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
        }
        .modifier(WyrmAboveKeys())
        .background(
            ZStack(alignment: .top) {
                wyrmScopedColours.paper
                Rectangle().fill(wyrmScopedColours.rule).frame(height: 1)
            }.ignoresSafeArea(.container, edges: .bottom)
        )
        .onChange(of: draft) { value in
            if !value.trimmingCharacters(in: .whitespaces).isEmpty { handlers.onTyping() }
        }
        .onAppear {
            // CI screenshot of the composer seated on the keyboard.
            if ProcessInfo.processInfo.arguments.contains("--smoke-chat-keyboard") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { focused = true }
            }
        }
    }

    /// A real text view (OM 2026-11-07): Return makes a new line, Send sends;
    /// the cursor drags and hold selects as everywhere on iOS.
    private var field: some View {
        WyrmTextView(text: $draft, selection: $selection, focused: $focused, placeholder: placeholder,
                     maxLines: 6, limit: 1000, height: $fieldHeight)
            .frame(height: fieldHeight)
    }

    private func send() {
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        handlers.onSend()
    }

    // MARK: Hold

    private func holdSheet(_ message: WyrmChatItem) -> some View {
        let mine = message.authorID == meID
        let gif = WyrmChatKit.isGif(message.body)
        return ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(WyrmChatKit.quick, id: \.self) { emoji in
                        Button { sheet = nil; handlers.onReact(message, emoji) } label: {
                            Text(emoji).font(.system(size: 26)).frame(width: 50, height: 50)
                                .background(Circle().fill(message.reactions.contains { $0.emoji == emoji && $0.mine } ? WyrmChatKit.pink.opacity(0.22) : wyrmScopedColours.well))
                        }.buttonStyle(WSPressStyle())
                    }
                    Button { sheet = .react(message) } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundColor(wyrmScopedColours.ink)
                            .frame(width: 50, height: 50).background(Circle().fill(wyrmScopedColours.well))
                    }.buttonStyle(WSPressStyle()).accessibilityLabel("More reactions")
                }
                .padding(.top, 22)
                VStack(spacing: 0) {
                    if !direct {
                        holdRow("Reply", "arrowshape.turn.up.left") { sheet = nil; handlers.onReply(message); focused = true }
                    }
                    if mine && !gif && !message.body.hasPrefix("##invite:") {
                        holdRow("Edit message", "pencil") { sheet = nil; handlers.onEdit(message); focused = true }
                    }
                    if !gif { holdRow("Copy text", "doc.on.doc") { sheet = nil; UIPasteboard.general.string = message.body } }
                    if !direct && !mine && !message.authorUsername.isEmpty {
                        holdRow("Mention", "at") {
                            sheet = nil
                            draft += (draft.isEmpty || draft.hasSuffix(" ") ? "" : " ") + "@\(message.authorUsername) "
                            focused = true
                        }
                    }
                    if !direct, canPin, let onPin = handlers.onPin {
                        holdRow(message.pinned.isEmpty ? "Pin message" : "Unpin message", "pin", tint: WyrmChatKit.pink) {
                            sheet = nil; onPin(message, message.pinned.isEmpty)
                        }
                    }
                    if mine {
                        holdRow("Delete message", "trash", tint: wyrmScopedColours.badge) { sheet = nil; handlers.onDelete(message) }
                    } else if let onReport = handlers.onReport {
                        holdRow("Report message", "flag", tint: wyrmScopedColours.badge) { sheet = nil; onReport(message) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(wyrmScopedColours.card))
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .background(wyrmScopedColours.paper.ignoresSafeArea())
        .foregroundColor(wyrmScopedColours.ink)
    }

    private func holdRow(_ title: String, _ icon: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 24)
                Text(title).font(.androidWyrm(15, .semibold))
                Spacer()
            }
            .foregroundColor(tint ?? wyrmScopedColours.ink)
            .padding(.horizontal, 18).frame(height: 52).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct WyrmChatFieldStyle: ViewModifier {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    func body(content: Content) -> some View {
        content
            .font(.androidWyrm(15))
            .foregroundColor(wyrmScopedColours.ink)
            .focused(focused)
            .submitLabel(.send)
            .onSubmit(onSubmit)
            .padding(.vertical, 11)
            .frame(minHeight: 42)
    }
}

private struct WyrmChatDismissOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(WyrmDismissKeyboardOnScroll())
    }
}

/// Half height first, the whole screen on a pull (iOS 16+); a full sheet before.
private struct WyrmChatDetents: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

// MARK: One message

private struct WyrmChatRow: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let message: WyrmChatItem
    let startsRun: Bool
    let mine: Bool
    let mentionsMe: Bool
    let meID: String
    let peer: WyrmServicePlayer?
    let direct: Bool
    let seenLine: String?
    let onAuthor: (String) -> Void
    let onReply: () -> Void
    let onHold: () -> Void
    let onReact: (String) -> Void
    let onMoreReactions: () -> Void
    /// Hold a reaction: who reacted with it.
    let onWho: (String) -> Void
    @State private var shift: CGFloat = 0

    private var name: String {
        if direct { return mine ? "You" : (peer?.displayName ?? "Player") }
        return message.authorName.isEmpty ? "Player" : message.authorName
    }
    private var avatarURL: String { direct ? (mine ? "" : peer?.avatarURL ?? "") : message.authorAvatarURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !message.replyID.isEmpty { replyLine }
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if startsRun {
                        Button { onAuthor(direct ? (mine ? meID : peer?.id ?? "") : message.authorID) } label: {
                            WyrmAvatar(initials: WyrmChatKit.initials(name), size: 40, url: avatarURL)
                        }.buttonStyle(.plain)
                    } else {
                        Text(WyrmChatKit.clock(message.createdAt)).font(.androidWyrm(9)).foregroundColor(.clear)
                    }
                }
                .frame(width: 40, alignment: .center)
                VStack(alignment: .leading, spacing: 3) {
                    if startsRun { head }
                    content
                    if !message.editedAt.isEmpty && !WyrmChatKit.isGif(message.body) {
                        Text("(edited)").font(.androidWyrm(10)).foregroundColor(wyrmScopedColours.quiet)
                    }
                    if !message.reactions.isEmpty { reactions }
                    if let seenLine {
                        Text(seenLine).font(.androidWyrm(10.5, .semibold)).foregroundColor(wyrmScopedColours.quiet)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 14).padding(.trailing, 14)
        .padding(.top, startsRun ? 10 : 1).padding(.bottom, 2)
        .background(
            HStack(spacing: 0) {
                if mentionsMe { Rectangle().fill(WyrmChatKit.gold).frame(width: 3) }
                (mentionsMe ? WyrmChatKit.gold.opacity(0.12) : Color.clear)
            }
        )
        .contentShape(Rectangle())
        .offset(x: shift)
        .overlay(alignment: .trailing) {
            Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 14, weight: .bold))
                .foregroundColor(wyrmScopedColours.quiet).opacity(Double(min(-shift / 64, 1))).padding(.trailing, 14)
        }
        // Hold rides along with the scroll (a moving finger cancels it), so it never stops a scroll.
        // The chip's 0.4 s hold must win before the parent's whoAt guard runs.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in onHold() })
        .modifier(WyrmSwipeLeftToReply(enabled: !direct, shift: $shift, onReply: onReply))
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button { onAuthor(direct ? (mine ? meID : peer?.id ?? "") : message.authorID) } label: {
                Text(name).font(.androidWyrm(14.5, .bold)).foregroundColor(wyrmScopedColours.ink).lineLimit(1)
            }.buttonStyle(.plain)
            if message.badge == "DEV" {
                Text("DEV").font(.androidWyrm(9, .heavy)).tracking(0.6).foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(wyrmScopedColours.live))
            }
            if !message.pinned.isEmpty {
                Image(systemName: "pin.fill").font(.system(size: 9, weight: .bold)).foregroundColor(WyrmChatKit.pink)
            }
            Text(WyrmChatKit.time(message.createdAt)).font(.androidWyrm(10.5)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
        }
    }

    /// Discord's reply line: a bent rule, the author, and what they said.
    private var replyLine: some View {
        HStack(spacing: 6) {
            WyrmReplyElbow().stroke(wyrmScopedColours.rule, lineWidth: 2).frame(width: 30, height: 12).padding(.leading, 20)
            Text("@" + message.replyName).font(.androidWyrm(11.5, .bold)).foregroundColor(wyrmScopedColours.mute).lineLimit(1).fixedSize()
            Text(WyrmChatKit.isGif(message.replyBody) ? "GIF" : message.replyBody).font(.androidWyrm(11.5)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
        }
        .padding(.top, startsRun ? 0 : 4)
    }

    @ViewBuilder private var content: some View {
        if WyrmChatKit.isGif(message.body) {
            WyrmGifView(url: message.body, fill: false)
                .frame(width: 220, height: 170, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            // Discord markdown, line breaks and links (OM, 2026-11-07; WyrmChatMarkdown.swift).
            VStack(alignment: .leading, spacing: 0) {
                Text(WyrmChatMarkdown.render(message.body, meUsername: WyrmChatRow.meUsername, colours: wyrmScopedColours))
                    .font(.androidWyrm(15))
                    .foregroundColor(wyrmScopedColours.ink)
                    .tint(wyrmScopedColours.link)
                    .fixedSize(horizontal: false, vertical: true)
                // Every link's embed, as Discord (OM, 2026-11-07).
                ForEach(WyrmChatMarkdown.links(message.body), id: \.self) { link in WyrmChatLinkEmbed(url: link) }
            }
        }
    }
    /// The signed-in player's username, for gold @mentions (set by WyrmDiscordChat).
    static var meUsername = ""

    private var reactions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.reactions, id: \.emoji) { row in
                    // Tap: add or take back yours. Hold: who reacted (Discord).
                    HStack(spacing: 4) {
                        Text(row.emoji).font(.system(size: 15))
                        Text("\(row.count)").font(.androidWyrm(12, .bold)).monospacedDigit()
                            .foregroundColor(row.mine ? WyrmChatKit.pink : wyrmScopedColours.mute)
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(row.mine ? WyrmChatKit.pink.opacity(0.14) : wyrmScopedColours.well))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(row.mine ? WyrmChatKit.pink : Color.clear, lineWidth: 1.2))
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .onTapGesture { UISelectionFeedbackGenerator().selectionChanged(); onReact(row.emoji) }
                    .onLongPressGesture(minimumDuration: 0.4) { onWho(row.emoji) }
                    .accessibilityAddTraits(.isButton)
                }
                Button(action: onMoreReactions) {
                    Image(systemName: "face.smiling").font(.system(size: 13, weight: .semibold)).foregroundColor(wyrmScopedColours.quiet)
                        .overlay(Image(systemName: "plus").font(.system(size: 7, weight: .heavy)).foregroundColor(wyrmScopedColours.quiet).offset(x: 7, y: -6))
                        .frame(width: 34, height: 28)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(wyrmScopedColours.well))
                }.buttonStyle(.plain).accessibilityLabel("Add reaction")
            }
            .padding(.top, 3)
        }
    }
}

/// Swipe a message left to answer it (OM, 2026-10-31: the old SwiftUI drag fought
/// the list's scroll). iOS 18+: a UIKit pan that starts only for a leftward,
/// mostly-sideways move, so an up/down scroll is never taken from the list.
/// Before iOS 18 the plain drag (which did not block scrolling there) stays.
private struct WyrmSwipeLeftToReply: ViewModifier {
    let enabled: Bool
    @Binding var shift: CGFloat
    let onReply: () -> Void

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(iOS 18.0, *) {
            content.gesture(WyrmLeftPan(onMove: { dx in
                shift = max(min(0, dx), -84)
            }, onEnd: {
                if shift <= -64 { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); onReply() }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { shift = 0 }
            }))
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 16)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    shift = max(min(0, value.translation.width), -84)
                }
                .onEnded { _ in
                    if shift <= -64 { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); onReply() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { shift = 0 }
                })
        }
    }
}

@available(iOS 18.0, *)
private struct WyrmLeftPan: UIGestureRecognizerRepresentable {
    let onMove: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onMove(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Only a leftward, mostly sideways start; anything else is the list's scroll.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return v.x < 0 && abs(v.x) > abs(v.y) * 1.6
        }
    }
}

/// The bend from a reply line down to the message (Discord's elbow).
private struct WyrmReplyElbow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 6))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 6, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Text with every `@username` in the link colour and bold.
private struct WyrmChatMentionText: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let body_: String
    init(body: String) { body_ = body }

    var body: some View {
        var result = Text("")
        var rest = Substring(body_)
        while let range = rest.range(of: #"@[A-Za-z0-9_]{3,20}"#, options: .regularExpression) {
            result = result + Text(String(rest[rest.startIndex..<range.lowerBound]))
            result = result + Text(String(rest[range])).bold().foregroundColor(wyrmScopedColours.link)
            rest = rest[range.upperBound...]
        }
        return result + Text(String(rest))
    }
}

/// Three dots that rise in turn, as Discord's typing line.
struct WyrmTypingDots: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @State private var phase = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(wyrmScopedColours.quiet).frame(width: 5, height: 5)
                    .offset(y: phase ? -2.5 : 1.5)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.15), value: phase)
            }
        }
        .onAppear { phase = true }
    }
}

// MARK: Emoji, GIFs and stickers

private struct WyrmChatPicker: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let emojiOnly: Bool
    let gifs: (Bool, String) async -> [WyrmGifItem]
    let onEmoji: (String) -> Void
    let onGif: (String) -> Void
    @State private var tab = 0
    @State private var query = ""
    @State private var items: [WyrmGifItem] = []
    @State private var loading = false
    @State private var loaded = false

    init(emojiOnly: Bool, gifs: @escaping (Bool, String) async -> [WyrmGifItem], onEmoji: @escaping (String) -> Void, onGif: @escaping (String) -> Void) {
        self.emojiOnly = emojiOnly; self.gifs = gifs; self.onEmoji = onEmoji; self.onGif = onGif
    }

    var body: some View {
        VStack(spacing: 10) {
            if !emojiOnly {
                HStack(spacing: 6) {
                    ForEach(Array(["Emoji", "GIFs", "Stickers"].enumerated()), id: \.offset) { index, title in
                        Button { tab = index; query = "" } label: {
                            Text(title).font(.androidWyrm(13, .bold))
                                .foregroundColor(tab == index ? wyrmScopedColours.onInk : wyrmScopedColours.ink)
                                .padding(.horizontal, 14).frame(height: 32)
                                .background(Capsule().fill(tab == index ? wyrmScopedColours.ink : wyrmScopedColours.well))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, 18).padding(.horizontal, 16)
            } else {
                Text("Add a reaction").font(.androidWyrm(15, .bold)).padding(.top, 18)
            }
            if tab != 0 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(wyrmScopedColours.quiet)
                    TextField(tab == 1 ? "Search KLIPY GIFs" : "Search KLIPY stickers", text: $query, prompt: wyrmPrompt(tab == 1 ? "Search KLIPY GIFs" : "Search KLIPY stickers"))
                        .font(.androidWyrm(14)).disableAutocorrection(true).textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(wyrmScopedColours.well))
                .padding(.horizontal, 16)
                // Categories, as Discord's picker (OM, 2026-10-31): each one is a search.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(WyrmChatKit.gifCategories.indices, id: \.self) { at in
                            let category = WyrmChatKit.gifCategories[at]
                            let on = query.trimmingCharacters(in: .whitespaces).lowercased() == category.1
                            Button { query = category.1 } label: {
                                Text(category.0).font(.androidWyrm(12.5, .bold))
                                    .foregroundColor(on ? wyrmScopedColours.onInk : wyrmScopedColours.mute)
                                    .padding(.horizontal, 13).frame(height: 30)
                                    .background(Capsule().fill(on ? wyrmScopedColours.ink : wyrmScopedColours.well))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            if tab == 0 {
                emojiGrid
            } else {
                gifGrid
            }
        }
        .background(wyrmScopedColours.paper.ignoresSafeArea())
        .foregroundColor(wyrmScopedColours.ink)
        .task(id: "\(tab)|\(query)") {
            guard tab != 0 else { return }
            loading = true
            // A pause while typing, so a search is asked once, not per letter.
            if !query.isEmpty { try? await Task.sleep(nanoseconds: 380_000_000) }
            if Task.isCancelled { return }
            let found = await gifs(tab == 2, query.trimmingCharacters(in: .whitespaces))
            if Task.isCancelled { return }
            items = found
            loading = false
            loaded = true
        }
    }

    private var emojiGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(WyrmChatKit.emoji.indices, id: \.self) { at in
                    let group = WyrmChatKit.emoji[at]
                    Text(group.0.uppercased()).font(.androidWyrm(10.5, .bold)).tracking(1.2).foregroundColor(wyrmScopedColours.quiet)
                        .padding(.top, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                        ForEach(group.1, id: \.self) { emoji in
                            Button { UISelectionFeedbackGenerator().selectionChanged(); onEmoji(emoji) } label: {
                                Text(emoji).font(.system(size: 28)).frame(maxWidth: .infinity).frame(height: 42)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 24)
        }
    }

    private var gifGrid: some View {
        ScrollView {
            if items.isEmpty {
                VStack(spacing: 8) {
                    if loading || !loaded { ProgressView().padding(.top, 40) }
                    else {
                        Text(query.isEmpty ? "GIFs are not available right now." : "Nothing found.")
                            .font(.androidWyrm(13.5, .semibold)).foregroundColor(wyrmScopedColours.quiet).padding(.top, 40)
                    }
                }.frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(items) { item in
                        Button { onGif(item.url) } label: {
                            WyrmGifView(url: item.preview, fill: tab == 1)
                                .frame(height: 120).frame(maxWidth: .infinity)
                                .background(tab == 1 ? wyrmScopedColours.well : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            Text("Powered by KLIPY").font(.androidWyrm(10.5, .semibold)).foregroundColor(wyrmScopedColours.quiet).padding(.vertical, 14)
        }
    }
}

// MARK: Who reacted

/// One tab per emoji with its count, then the players in the order they reacted (OM, 2026-10-31).
private struct WyrmWhoReacted: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let message: WyrmChatItem
    let first: String
    let load: (WyrmChatItem) async -> [(String, [WyrmReactionPerson])]
    let onPlayer: (String) -> Void
    @State private var groups: [(String, [WyrmReactionPerson])]? = nil
    @State private var tab = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reactions").font(.wyrmDisplay(21)).padding(.horizontal, 18).padding(.top, 20)
            if let groups {
                if groups.isEmpty {
                    Text("No reactions any more.").font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.quiet).padding(.horizontal, 18)
                    Spacer()
                } else {
                    let shown = groups.first(where: { $0.0 == tab }) ?? groups[0]
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(groups.indices, id: \.self) { at in
                                let group = groups[at]
                                let on = group.0 == shown.0
                                Button { tab = group.0 } label: {
                                    HStack(spacing: 6) {
                                        Text(group.0).font(.system(size: 16))
                                        Text("\(group.1.count)").font(.androidWyrm(13, .bold)).foregroundColor(on ? wyrmScopedColours.onInk : wyrmScopedColours.mute)
                                    }
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? wyrmScopedColours.ink : wyrmScopedColours.well))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(shown.1) { person in
                                Button { onPlayer(person.id) } label: {
                                    HStack(spacing: 12) {
                                        WyrmAvatar(initials: WyrmChatKit.initials(person.name), size: 38, url: person.avatarURL)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(person.name).font(.androidWyrm(15, .bold)).foregroundColor(wyrmScopedColours.ink).lineLimit(1)
                                            if !person.username.isEmpty {
                                                Text("@" + person.username).font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Text(shown.0).font(.system(size: 18))
                                    }
                                    .padding(.horizontal, 18).padding(.vertical, 9).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 30)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(wyrmScopedColours.paper.ignoresSafeArea())
        .foregroundColor(wyrmScopedColours.ink)
        .task {
            tab = first
            groups = await load(message)
        }
    }
}

// MARK: Search and pins

private struct WyrmChatSearch: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let direct: Bool
    let search: (String) async -> [WyrmChatItem]
    let peer: WyrmServicePlayer?
    let close: () -> Void
    @State private var query = ""
    @State private var found: [WyrmChatItem] = []
    @State private var searched = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(wyrmScopedColours.quiet)
                TextField(direct ? "Search this conversation" : "Search global chat", text: $query, prompt: wyrmPrompt(direct ? "Search this conversation" : "Search global chat"))
                    .font(.androidWyrm(14.5)).focused($focused).disableAutocorrection(true).textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(wyrmScopedColours.quiet) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(wyrmScopedColours.well))
            .padding(.horizontal, 16).padding(.top, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if found.isEmpty {
                        Text(query.count < 2 ? "Type at least 2 letters." : (searched ? "Nothing found in the last 7 days." : ""))
                            .font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.quiet).frame(maxWidth: .infinity).padding(.top, 30)
                    }
                    ForEach(found) { message in WyrmChatCompactLine(message: message, peer: peer, direct: direct) }
                }
                .padding(.bottom, 24)
            }
        }
        .background(wyrmScopedColours.paper.ignoresSafeArea())
        .foregroundColor(wyrmScopedColours.ink)
        .onAppear { focused = true }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { found = []; searched = false; return }
            try? await Task.sleep(nanoseconds: 380_000_000)
            if Task.isCancelled { return }
            let rows = await search(q)
            if Task.isCancelled { return }
            found = rows.reversed()
            searched = true
        }
    }
}

private struct WyrmChatPins: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let pins: [WyrmChatItem]
    let canPin: Bool
    let onUnpin: (WyrmChatItem) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill").foregroundColor(WyrmChatKit.pink)
                Text("Pinned messages").font(.androidWyrm(16, .bold))
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if pins.isEmpty {
                        Text("Nothing pinned yet.").font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.quiet)
                            .frame(maxWidth: .infinity).padding(.top, 30)
                    }
                    ForEach(pins) { message in
                        HStack(alignment: .top, spacing: 0) {
                            WyrmChatCompactLine(message: message, peer: nil, direct: false)
                            if canPin {
                                Button { onUnpin(message) } label: {
                                    Image(systemName: "pin.slash").font(.system(size: 14, weight: .semibold)).foregroundColor(WyrmChatKit.pink)
                                        .frame(width: 44, height: 44)
                                }.buttonStyle(.plain).accessibilityLabel("Unpin")
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(wyrmScopedColours.paper.ignoresSafeArea())
        .foregroundColor(wyrmScopedColours.ink)
    }
}

/// A message in a list (search, pins): face, name, time, body.
private struct WyrmChatCompactLine: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let message: WyrmChatItem
    let peer: WyrmServicePlayer?
    let direct: Bool

    var body: some View {
        let name = direct ? (message.authorID == peer?.id ? peer?.displayName ?? "Player" : "You") : message.authorName
        HStack(alignment: .top, spacing: 10) {
            WyrmAvatar(initials: WyrmChatKit.initials(name), size: 32,
                       url: direct ? (message.authorID == peer?.id ? peer?.avatarURL ?? "" : "") : message.authorAvatarURL)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.androidWyrm(13.5, .bold)).lineLimit(1)
                    Text(WyrmChatKit.time(message.createdAt)).font(.androidWyrm(10)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                }
                if WyrmChatKit.isGif(message.body) {
                    WyrmGifView(url: message.body, fill: false).frame(width: 140, height: 100, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    WyrmChatMentionText(body: message.body).font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

// MARK: Moving pictures

/// GIF and animated WebP, decoded off the main thread and kept (24 MB) for the session.
enum WyrmGifCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func cached(_ url: String) -> UIImage? { cache.object(forKey: url as NSString) }

    static func load(_ url: String) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard let remote = URL(string: url), remote.scheme == "https",
              let answer = try? await URLSession.shared.data(from: remote), answer.0.count < 12_000_000 else { return nil }
        let data = answer.0
        let image = await Task.detached(priority: .utility) { WyrmGifCache.decode(data) }.value
        if let image {
            let frames = image.images?.count ?? 1
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4) * frames
            cache.setObject(image, forKey: url as NSString, cost: cost)
        }
        return image
    }

    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        // Long ones keep every other frame, so memory stays small.
        let step = count > 80 ? 2 : 1
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        var frames: [UIImage] = []
        var duration = 0.0
        var index = 0
        while index < count {
            if let frame = CGImageSourceCreateImageAtIndex(source, index, options) {
                frames.append(UIImage(cgImage: frame))
                duration += delay(source, index) * Double(step)
            }
            index += step
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: max(0.1, duration))
    }

    private static func delay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        var value: Double?
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            value = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
        } else if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            value = (webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double) ?? (webp[kCGImagePropertyWebPDelayTime] as? Double)
        }
        guard let value, value >= 0.02 else { return 0.1 }
        return value
    }
}

struct WyrmGifView: UIViewRepresentable {
    let url: String
    /// Fill the frame (GIF tiles) or fit inside it (messages, stickers).
    let fill: Bool

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.backgroundColor = UIColor(ATheme.well)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = fill ? .scaleAspectFill : .scaleAspectFit
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        context.coordinator.task?.cancel()
        if let hit = WyrmGifCache.cached(url) { view.image = hit; view.backgroundColor = .clear; return }
        view.image = nil
        let wanted = url
        let coordinator = context.coordinator
        coordinator.task = Task { @MainActor in
            let image = await WyrmGifCache.load(wanted)
            guard !Task.isCancelled, coordinator.url == wanted else { return }
            view.image = image
            if image != nil { view.backgroundColor = .clear }
        }
    }

    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        coordinator.task?.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var url = ""
        var task: Task<Void, Never>?
    }
}

/// "{n} active" (OM, 2026-11-07): who has Wyrm open right now; a tap opens the profile.
struct WyrmActivePeople: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }
    let title: String
    let people: [WyrmChatPerson]
    let open: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.isEmpty ? "Active" : title.prefix(1).uppercased() + title.dropFirst()).font(.wyrmDisplay(22))
                .foregroundColor(wyrmScopedColours.ink).padding(.horizontal, 18).padding(.top, 22)
            Text("On Wyrm right now. Players who hide their activity are counted, not listed.")
                .font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 18).padding(.top, 4)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if people.isEmpty {
                        Text("Nobody to show yet.").font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.quiet)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }
                    ForEach(people) { person in
                        Button { open(person.id) } label: {
                            HStack(spacing: 12) {
                                Circle().fill(wyrmScopedColours.live).frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name.isEmpty ? "Player" : person.name).font(.androidWyrm(15, .bold))
                                        .foregroundColor(wyrmScopedColours.ink).lineLimit(1)
                                    if !person.username.isEmpty {
                                        Text("@" + person.username).font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if !person.arena.isEmpty {
                                    Text("In an arena").font(.androidWyrm(12, .semibold)).foregroundColor(wyrmScopedColours.live)
                                }
                            }
                            .padding(.horizontal, 18).frame(minHeight: 52).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
        .background(wyrmScopedColours.paper.ignoresSafeArea())
    }
}
