import SwiftUI
import UIKit

/*
 * The chat surfaces shared by Global chat and direct messages: a transcript of
 * grouped bubbles that spring in as they arrive, and a Liquid Glass composer
 * whose send button swells out of the field when there is something to send
 * and launches its arrow when pressed. Both sit on the keyboard, not behind it.
 */

/// A Liquid Glass surface on iOS 26, paper card with a hairline before it.
private struct WyrmGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive(), in: shape)
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }
    private func fallback(_ content: Content) -> some View {
        content
            .background(shape.fill(tint ?? ATheme.card))
            .overlay(shape.stroke(ATheme.rule, lineWidth: tint == nil ? 1 : 0))
    }
}

struct WyrmChatComposer: View {
    @Binding var text: String
    let placeholder: String
    let limit: Int
    let sending: Bool
    let onSend: () -> Void
    @FocusState private var focused: Bool
    @State private var launched = false
    @ObservedObject private var keyboard = WyrmKeyboardController.shared

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !sending && text.count <= limit }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if text.count > limit - 40 {
                Text("\(max(0, limit - text.count))")
                    .font(.androidWyrm(10.5, .bold)).monospacedDigit()
                    .foregroundColor(text.count > limit ? ATheme.badge : ATheme.quiet)
                    .padding(.trailing, 64)
                    .transition(.opacity)
            }
            container {
                HStack(alignment: .bottom, spacing: 10) {
                    field
                        .modifier(WyrmGlassSurface(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
                    if canSend || sending {
                        sendButton
                            .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.62), value: canSend || sending)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
        // Sits on the keys, not under them: iOS 26 grows the input view past
        // what the page rises for, so the overlap is measured and added back.
        .modifier(WyrmAboveKeys())
        .background(bar)
        .animation(.easeOut(duration: 0.15), value: text.count > limit - 40)
        .onAppear {
            // CI screenshot of the composer seated on the keyboard.
            if ProcessInfo.processInfo.arguments.contains("--smoke-chat-keyboard") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { focused = true }
            }
        }
    }

    @ViewBuilder
    private func container<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Glass shapes this close melt together: the send button grows out
            // of the field like a drop leaving it, and melts back in on send.
            GlassEffectContainer(spacing: 14) { content() }
        } else {
            content()
        }
#else
        content()
#endif
    }

    @ViewBuilder
    private var field: some View {
        if #available(iOS 16.0, *) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .modifier(FieldStyle(focused: $focused, onSubmit: send))
        } else {
            TextField(placeholder, text: $text)
                .modifier(FieldStyle(focused: $focused, onSubmit: send))
        }
    }

    private struct FieldStyle: ViewModifier {
        var focused: FocusState<Bool>.Binding
        let onSubmit: () -> Void
        func body(content: Content) -> some View {
            content
                .font(.androidWyrm(15))
                .foregroundColor(ATheme.ink)
                .focused(focused)
                .submitLabel(.send)
                .onSubmit(onSubmit)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 46)
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            ZStack {
                if sending {
                    ProgressView().tint(ATheme.onInk).scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(ATheme.onInk)
                        .offset(y: launched ? -30 : 0)
                        .opacity(launched ? 0 : 1)
                        .scaleEffect(launched ? 0.6 : 1)
                }
            }
            .frame(width: 46, height: 46)
            .modifier(WyrmGlassSurface(shape: Circle(), tint: ATheme.ink))
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(WSPressStyle())
        .disabled(!canSend)
        .accessibilityLabel("Send")
    }

    private var bar: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial)
            ATheme.paper.opacity(0.35)
            Rectangle().fill(ATheme.rule).frame(height: 1)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func send() {
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.22)) { launched = true }
        onSend()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { launched = false }
        }
    }
}

/// Grouped bubbles: consecutive messages from one author share a name line and
/// tighten up; the last of a group carries its time.
struct WyrmChatTranscript: View {
    let messages: [WyrmChatItem]
    let myID: String?
    var showsAuthors = true
    var emptyTitle = "Quiet right now"
    var emptyNote = ""
    var onAuthor: ((String) -> Void)? = nil
    var onReport: ((WyrmChatItem) -> Void)? = nil
    /// A direct conversation (Instagram's layout): the other player. Their
    /// profile card heads the thread, their face sits beside the last bubble
    /// of each of their runs, and times sit between runs far apart.
    var peer: WyrmServicePlayer? = nil
    var onPeer: (() -> Void)? = nil
    private var direct: Bool { onPeer != nil }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if direct {
                        WyrmDirectIntro(peer: peer, onPeer: { onPeer?() })
                            .padding(.top, messages.isEmpty ? 44 : 12)
                            .padding(.bottom, 10)
                    } else if messages.isEmpty {
                        WyrmPaperCard { WyrmEmptyPanel(title: emptyTitle, note: emptyNote) }.padding(.top, 18)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if direct, let stamp = separator(message, previous: index > 0 ? messages[index - 1] : nil) {
                            Text(stamp).font(.androidWyrm(11, .semibold)).foregroundColor(ATheme.quiet)
                                .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 4)
                        }
                        row(message, previous: index > 0 ? messages[index - 1] : nil,
                            next: index + 1 < messages.count ? messages[index + 1] : nil)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.86, anchor: message.authorID == myID ? .bottomTrailing : .bottomLeading)
                                    .combined(with: .opacity).combined(with: .offset(y: 12)),
                                removal: .opacity))
                    }
                    Color.clear.frame(height: 8).id("wyrm-chat-bottom")
                }
                .padding(.top, 10)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: messages.map(\.id))
            }
            .modifier(DismissOnScroll())
            .onAppear { reader.scrollTo("wyrm-chat-bottom", anchor: .bottom) }
            .onChange(of: messages.last?.id) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { reader.scrollTo("wyrm-chat-bottom", anchor: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo("wyrm-chat-bottom", anchor: .bottom) }
            }
        }
    }

    private struct DismissOnScroll: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 16.0, *) { content.scrollDismissesKeyboard(.interactively) } else { content }
        }
    }

    private func row(_ message: WyrmChatItem, previous: WyrmChatItem?, next: WyrmChatItem?) -> some View {
        let mine = message.authorID == myID
        let startsGroup = previous?.authorID != message.authorID || farApart(previous, message)
        let endsGroup = next?.authorID != message.authorID || farApart(message, next)
        return HStack(alignment: .bottom, spacing: 8) {
            if direct && !mine {
                // Their face beside the last bubble of their run, a gap elsewhere.
                Group {
                    if endsGroup {
                        Button { onPeer?() } label: {
                            WyrmAvatar(initials: peer?.initials ?? "W", size: 28, url: peer?.avatarURL ?? "")
                        }.buttonStyle(.plain)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 28, height: 28)
            }
            bubbleColumn(message, mine: mine, startsGroup: startsGroup, endsGroup: endsGroup)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.horizontal, direct ? 10 : 14)
        .padding(.top, startsGroup ? 10 : 2)
    }

    private func bubbleColumn(_ message: WyrmChatItem, mine: Bool, startsGroup: Bool, endsGroup: Bool) -> some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if showsAuthors && !mine && startsGroup {
                Button { onAuthor?(message.authorID) } label: {
                    HStack(spacing: 6) {
                        // The app's squircle face, as everywhere else (OM, 2026-10-09).
                        WyrmAvatar(initials: initials(message.authorName), size: 18)
                        Text(message.authorUsername.isEmpty ? message.authorName : "\(message.authorName) · @\(message.authorUsername)")
                            .font(.androidWyrm(10.5, .semibold)).foregroundColor(ATheme.quiet)
                    }
                }.buttonStyle(.plain).padding(.leading, 4)
            }
            Text(message.body)
                .font(.androidWyrm(14.5))
                .foregroundColor(mine ? ATheme.onInk : ATheme.ink)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(bubble(mine: mine, startsGroup: startsGroup, endsGroup: endsGroup).fill(mine ? ATheme.ink : ATheme.card))
                .overlay(bubble(mine: mine, startsGroup: startsGroup, endsGroup: endsGroup).stroke(mine ? Color.clear : ATheme.rule, lineWidth: 1))
                .frame(maxWidth: 290, alignment: mine ? .trailing : .leading)
                .contextMenu {
                    Button { UIPasteboard.general.string = message.body } label: { Label("Copy", systemImage: "doc.on.doc") }
                    if !mine, let onReport { Button(role: .destructive) { onReport(message) } label: { Label("Report", systemImage: "flag") } }
                }
            if !direct, endsGroup, let time = time(message.createdAt) {
                Text(time).font(.androidWyrm(9.5)).foregroundColor(ATheme.quiet).padding(.horizontal, 6)
            }
        }
    }

    private func date(_ raw: String) -> Date? { Self.parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) }

    /// Runs far apart in time (an hour) are separate runs, as on Instagram.
    private func farApart(_ first: WyrmChatItem?, _ second: WyrmChatItem?) -> Bool {
        guard direct, let first, let second, let a = date(first.createdAt), let b = date(second.createdAt) else { return false }
        return b.timeIntervalSince(a) > 3600
    }

    /// "Today 3:45 PM", "Yesterday 9:10 AM", "Mon 3:45 PM" or "12 Oct 3:45 PM"
    /// above the first message and above one that comes an hour after the last.
    private func separator(_ message: WyrmChatItem, previous: WyrmChatItem?) -> String? {
        guard let when = date(message.createdAt) else { return nil }
        if let previous, let before = date(previous.createdAt), when.timeIntervalSince(before) <= 3600 { return nil }
        let calendar = Calendar.current
        let clock = Self.clock.string(from: when)
        if calendar.isDateInToday(when) { return "Today \(clock)" }
        if calendar.isDateInYesterday(when) { return "Yesterday \(clock)" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: when), to: calendar.startOfDay(for: Date())).day ?? 99
        let formatter = DateFormatter()
        formatter.dateFormat = days < 7 ? "EEE" : "d MMM"
        return "\(formatter.string(from: when)) \(clock)"
    }

    /// Rounder on the outside of a run, tighter where bubbles of one author meet.
    private func bubble(mine: Bool, startsGroup: Bool, endsGroup: Bool) -> WyrmBubbleShape {
        WyrmBubbleShape(mine: mine, tightTop: !startsGroup, tightBottom: !endsGroup)
    }

    private func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "W" : letters
    }

    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func time(_ raw: String) -> String? {
        guard let date = Self.parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return nil }
        return Self.clock.string(from: date)
    }
}

/// The other player at the head of a direct thread (Instagram's empty chat):
/// face, name, handle, followers, whether you follow each other, View profile.
struct WyrmDirectIntro: View {
    let peer: WyrmServicePlayer?
    let onPeer: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            WyrmAvatar(initials: peer?.initials ?? "W", size: 92, url: peer?.avatarURL ?? "")
                .padding(.bottom, 6)
            Text(peer?.displayName ?? "").font(.androidWyrm(18, .bold)).lineLimit(1)
            if let handle = peer?.handle, !handle.isEmpty {
                Text(handle).font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
            }
            if let peer {
                Text("\(Self.count(peer.followerCount)) followers · Wyrm").font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                if peer.isFollowing && peer.followsYou {
                    Text("You follow each other on Wyrm").font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                } else if peer.followsYou {
                    Text("Follows you").font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                }
            }
            Button(action: onPeer) {
                Text("View profile").font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.ink)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(Capsule().fill(ATheme.well))
            }
            .buttonStyle(.plain)
            .padding(.top, 9)
        }
        .frame(maxWidth: .infinity)
    }

    static func count(_ value: Int64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0M", with: "M") }
        if value >= 10_000 { return "\(value / 1000)K" }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000).replacingOccurrences(of: ".0K", with: "K") }
        return "\(value)"
    }
}

/// A message bubble whose corners on the author's side tighten inside a run.
struct WyrmBubbleShape: Shape {
    let mine: Bool
    let tightTop: Bool
    let tightBottom: Bool

    func path(in rect: CGRect) -> Path {
        let big = min(19, rect.height / 2)
        let small: CGFloat = 6
        let topLeading = !mine && tightTop ? small : big
        let bottomLeading = !mine && tightBottom ? small : (!mine ? small : big)
        let topTrailing = mine && tightTop ? small : big
        let bottomTrailing = mine && tightBottom ? small : (mine ? small : big)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeading, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - topTrailing, y: rect.minY + topTrailing), radius: topTrailing,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomTrailing))
        path.addArc(center: CGPoint(x: rect.maxX - bottomTrailing, y: rect.maxY - bottomTrailing), radius: bottomTrailing,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY - bottomLeading), radius: bottomLeading,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeading))
        path.addArc(center: CGPoint(x: rect.minX + topLeading, y: rect.minY + topLeading), radius: topLeading,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
