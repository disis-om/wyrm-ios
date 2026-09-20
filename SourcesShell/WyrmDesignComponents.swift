import SwiftUI
import UIKit

enum WyrmDesignTab: String, CaseIterable {
    case alerts = "Alerts"
    case social = "Social"
    case play = "Play"
    case skin = "Skin"
    case settings = "Settings"
}

enum WyrmDesignRoute: Identifiable, Equatable {
    case leaderboard
    case messages
    case thread(String)
    case people(String)
    case profile(String)
    case editProfile
    case voice
    case voiceVerification
    case room(String)
    case call(String)
    case lobby
    case team
    case teamChat
    case teamConnect
    case display
    case controls
    case buttons
    case modes
    case bot
    case food
    case notificationSettings
    case privacy
    case themes
    case backup
    case developer
    case presets
    case pattern
    case accessory
    case tag
    case background

    var id: String {
        switch self {
        case .leaderboard: return "leaderboard"
        case .messages: return "messages"
        case .thread(let id): return "thread-\(id)"
        case .people(let kind): return "people-\(kind)"
        case .profile(let id): return "profile-\(id)"
        case .editProfile: return "edit-profile"
        case .voice: return "voice"
        case .voiceVerification: return "voice-verification"
        case .room(let id): return "room-\(id)"
        case .call(let id): return "call-\(id)"
        case .lobby: return "lobby"
        case .team: return "team"
        case .teamChat: return "team-chat"
        case .teamConnect: return "team-connect"
        case .display: return "display"
        case .controls: return "controls"
        case .buttons: return "buttons"
        case .modes: return "modes"
        case .bot: return "bot"
        case .food: return "food"
        case .notificationSettings: return "notification-settings"
        case .privacy: return "privacy"
        case .themes: return "themes"
        case .backup: return "backup"
        case .developer: return "developer"
        case .presets: return "presets"
        case .pattern: return "pattern"
        case .accessory: return "accessory"
        case .tag: return "tag"
        case .background: return "background"
        }
    }
}

struct WyrmPaperBackground: View {
    var body: some View {
        ZStack {
            ATheme.paper
            LinearGradient(colors: [ATheme.live.opacity(0.035), .clear, ATheme.link.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
    }
}

struct WyrmScreenHeader: View {
    let kicker: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker.uppercased()).font(.androidWyrm(10.5, .bold)).tracking(1.15).foregroundColor(ATheme.quiet)
                Text(title).font(.androidWyrm(28, .bold)).tracking(-0.55)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 14)
        .background(ATheme.paper.opacity(0.94))
    }
}

struct WyrmSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.androidWyrm(10.5, .semibold)).tracking(0.9).foregroundColor(ATheme.quiet)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
    }
}

struct WyrmPaperCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(ATheme.rule))
            .shadow(color: ATheme.ink.opacity(0.035), radius: 18, y: 8)
            .padding(.horizontal, 16)
    }
}

struct WyrmListRow: View {
    let title: String
    var detail = ""
    var value = ""
    var icon: String? = nil
    var tint = ATheme.mute
    var destructive = false
    var showsChevron = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundColor(tint)
                        .frame(width: 30, height: 30).background(tint.opacity(0.09)).cornerRadius(8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.androidWyrm(15.5, .regular)).foregroundColor(destructive ? .red : ATheme.ink)
                    if !detail.isEmpty { Text(detail).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineLimit(2) }
                }
                Spacer(minLength: 8)
                if !value.isEmpty { Text(value).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).multilineTextAlignment(.trailing).lineLimit(2) }
                if showsChevron && action != nil { Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.chevron) }
            }
            .padding(.horizontal, 14).frame(minHeight: detail.isEmpty ? 52 : 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(action == nil)
        .overlay(Rectangle().fill(ATheme.rowRule).frame(height: 1).padding(.leading, icon == nil ? 14 : 56), alignment: .bottom)
    }
}

struct WyrmAvatar: View {
    let initials: String
    var size: CGFloat = 38
    var url = ""
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(ATheme.ink)
            Text(initials).font(.androidWyrm(max(10, size * 0.28), .bold)).foregroundColor(.white)
            if let remote = URL(string: url), !url.isEmpty {
                AsyncImage(url: remote) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityLabel("Player avatar")
    }
}

struct WyrmPrimaryAction: View {
    let title: String
    var icon: String? = nil
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.androidWyrm(15, .bold))
                Spacer()
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
            }.padding(.horizontal, 17).frame(height: 52).background(disabled ? ATheme.ink.opacity(0.35) : ATheme.ink).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }.buttonStyle(.plain).disabled(disabled)
    }
}

struct WyrmOutlineAction: View {
    let title: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.androidWyrm(14, .semibold)).foregroundColor(destructive ? .red : ATheme.ink)
                .frame(maxWidth: .infinity).frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(destructive ? Color.red.opacity(0.3) : ATheme.rule))
        }.buttonStyle(.plain)
    }
}

struct WyrmEmptyPanel: View {
    let title: String
    let note: String
    var body: some View {
        VStack(spacing: 7) {
            Text(title).font(.androidWyrm(17, .semibold))
            Text(note).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 24)
    }
}

struct WyrmDetailChrome<Content: View>: View {
    let title: String
    var actionTitle = ""
    let onBack: () -> Void
    var action: (() -> Void)? = nil
    let content: Content

    init(title: String, actionTitle: String = "", onBack: @escaping () -> Void, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.actionTitle = actionTitle; self.onBack = onBack; self.action = action; self.content = content()
    }

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 0) {
                ZStack {
                    HStack {
                        Button(action: onBack) { HStack(spacing: 5) { Image(systemName: "chevron.left"); Text("Back") }.font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.link) }
                        Spacer()
                        if !actionTitle.isEmpty { Button(actionTitle) { action?() }.font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.link) }
                    }
                    Text(title).font(.androidWyrm(16, .semibold))
                }.padding(.horizontal, 18).frame(height: 52).background(ATheme.paper.opacity(0.97))
                Rectangle().fill(ATheme.rule).frame(height: 1)
                content
            }
        }.foregroundColor(ATheme.ink)
    }
}

struct WyrmRootTabBar: View {
    @Binding var selection: WyrmDesignTab
    let unread: Int
    private let icons: [WyrmDesignTab: String] = [.alerts: "bell.badge", .social: "person.2", .play: "play.circle", .skin: "circle.hexagongrid", .settings: "slider.horizontal.3"]

    @GestureState private var dragX: CGFloat = 0
    @State private var lastPreview: WyrmDesignTab?

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 6
            let width = max(1, proxy.size.width - inset * 2)
            let itemWidth = width / CGFloat(WyrmDesignTab.allCases.count)
            let selectedIndex = CGFloat(WyrmDesignTab.allCases.firstIndex(of: selection) ?? 0)
            ZStack(alignment: .leading) {
                WyrmTabGlassSurface()
                WyrmTabSelectionGlass()
                    .frame(width: itemWidth - 3, height: 56)
                    .offset(x: inset + selectedIndex * itemWidth + dragX)
                    .scaleEffect(x: dragX == 0 ? 1 : 1.08, y: dragX == 0 ? 1 : 0.94)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.72, blendDuration: 0.12), value: selection)
                HStack(spacing: 0) {
                    ForEach(WyrmDesignTab.allCases, id: \.self) { tab in
                        Button { select(tab) } label: {
                            tabLabel(tab).frame(width: itemWidth, height: 57)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, inset)
            }
            .contentShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .local)
                .updating($dragX) { value, state, _ in
                    let start = selectedIndex * itemWidth
                    state = min(max(value.translation.width, -start), width - itemWidth - start)
                    preview(at: start + state, itemWidth: itemWidth)
                }
                .onEnded { value in
                    let raw = selectedIndex + value.predictedEndTranslation.width / itemWidth
                    let index = min(max(Int(raw.rounded()), 0), WyrmDesignTab.allCases.count - 1)
                    select(WyrmDesignTab.allCases[index])
                    lastPreview = nil
                })
        }
        .frame(height: 69)
        .shadow(color: ATheme.ink.opacity(0.14), radius: 22, y: 9)
        .padding(.horizontal, 12)
    }

    private func tabLabel(_ tab: WyrmDesignTab) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icons[tab]!).font(.system(size: tab == .play ? 23 : 19, weight: selection == tab ? .semibold : .regular))
                if tab == .alerts && unread > 0 {
                    Text("\(min(unread, 99))").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 14).background(ATheme.live).clipShape(Capsule()).offset(x: 11, y: -7)
                }
            }
            Text(tab.rawValue).font(.androidWyrm(9, selection == tab ? .bold : .medium)).lineLimit(1)
        }
        .foregroundColor(selection == tab ? ATheme.ink : ATheme.tabIdle)
        .animation(.easeOut(duration: 0.16), value: selection)
    }

    private func select(_ tab: WyrmDesignTab) {
        guard selection != tab else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.72, blendDuration: 0.14)) { selection = tab }
    }

    private func preview(at x: CGFloat, itemWidth: CGFloat) {
        let index = min(max(Int((x / itemWidth).rounded()), 0), WyrmDesignTab.allCases.count - 1)
        let tab = WyrmDesignTab.allCases[index]
        guard tab != lastPreview else { return }
        lastPreview = tab
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

private struct WyrmTabGlassSurface: View {
    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 27))
                .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(Color.white.opacity(0.64), lineWidth: 0.7))
        } else {
            fallback
        }
#else
        fallback
#endif
    }
    private var fallback: some View {
        RoundedRectangle(cornerRadius: 27, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).fill(Color.white.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(Color.white.opacity(0.82), lineWidth: 0.8))
    }
}

private struct WyrmTabSelectionGlass: View {
    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(.white.opacity(0.18)).interactive(), in: .rect(cornerRadius: 21))
        } else {
            fallback
        }
#else
        fallback
#endif
    }
    private var fallback: some View {
        RoundedRectangle(cornerRadius: 21, style: .continuous)
            .fill(.thinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(Color.white.opacity(0.42)))
            .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.white.opacity(0.92)))
            .shadow(color: ATheme.ink.opacity(0.08), radius: 8, y: 3)
    }
}

extension AnyTransition {
    static var wyrmCinematicPush: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: WyrmCinematicModifier(offset: 52, blur: 16, opacity: 0), identity: WyrmCinematicModifier(offset: 0, blur: 0, opacity: 1)),
            removal: .modifier(active: WyrmCinematicModifier(offset: 38, blur: 12, opacity: 0), identity: WyrmCinematicModifier(offset: 0, blur: 0, opacity: 1))
        )
    }
}

private struct WyrmCinematicModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.offset(x: offset).blur(radius: blur).opacity(opacity) }
}

extension Int64 {
    var wyrmFormatted: String { NumberFormatter.localizedString(from: NSNumber(value: self), number: .decimal) }
}
