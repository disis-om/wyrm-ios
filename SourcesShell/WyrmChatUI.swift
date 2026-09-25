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
        .background(bar)
        .animation(.easeOut(duration: 0.15), value: text.count > limit - 40)
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

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if messages.isEmpty {
                        WyrmPaperCard { WyrmEmptyPanel(title: emptyTitle, note: emptyNote) }.padding(.top, 18)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
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
        let startsGroup = previous?.authorID != message.authorID
        let endsGroup = next?.authorID != message.authorID
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if showsAuthors && !mine && startsGroup {
                Button { onAuthor?(message.authorID) } label: {
                    HStack(spacing: 6) {
                        Text(initials(message.authorName)).font(.androidWyrm(8.5, .bold)).foregroundColor(ATheme.onInk)
                            .frame(width: 18, height: 18).background(Circle().fill(ATheme.ink.opacity(0.8)))
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
            if endsGroup, let time = time(message.createdAt) {
                Text(time).font(.androidWyrm(9.5)).foregroundColor(ATheme.quiet).padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.horizontal, 14)
        .padding(.top, startsGroup ? 10 : 2)
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
