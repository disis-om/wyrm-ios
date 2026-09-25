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
    case playControls
    case playModes
    case playFood
    case buildNotes
    case globalChat

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
        case .playControls: return "play-controls"
        case .playModes: return "play-modes"
        case .playFood: return "play-food"
        case .buildNotes: return "build-notes"
        case .globalChat: return "global-chat"
        }
    }
}

struct WyrmPaperBackground: View {
    var body: some View {
        ATheme.paper.ignoresSafeArea()
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
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 14)
        .background(ATheme.paper)
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
            .background(ATheme.card.opacity(0.92))
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
            Text(initials).font(.androidWyrm(max(10, size * 0.28), .bold)).foregroundColor(ATheme.onInk)
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
            }.padding(.horizontal, 17).frame(height: 52).background(disabled ? ATheme.ink.opacity(0.35) : ATheme.ink).foregroundColor(ATheme.onInk)
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
                }.padding(.horizontal, 18).frame(height: 52).background(ATheme.paper)
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

    @State private var dragLocationX: CGFloat?
    @State private var lastPreview: WyrmDesignTab?
    /// The lens rises off the bar while a finger holds it, like the system
    /// segmented control on iOS 26, and settles back with a soft overshoot.
    @State private var lifted = false
    @State private var stretch: CGFloat = 0
    @State private var lastSample: (x: CGFloat, time: Date)?
    @State private var dropWork: DispatchWorkItem?

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 5
            let width = max(1, proxy.size.width - inset * 2)
            let itemWidth = width / CGFloat(WyrmDesignTab.allCases.count)
            let selectedIndex = CGFloat(WyrmDesignTab.allCases.firstIndex(of: selection) ?? 0)
            let selectedOrigin = inset + selectedIndex * itemWidth
            let draggedOrigin = dragLocationX.map {
                min(max($0 - itemWidth * 0.5, inset), inset + width - itemWidth)
            }
            // As large as the app's other segmented thumbs: nearly the bar's
            // full height and a touch wider than one slot.
            let pillWidth = itemWidth + 2
            let pillOrigin = (draggedOrigin ?? selectedOrigin) - 1
            ZStack(alignment: .leading) {
                WyrmTabGlassSurface().zIndex(0)
                // At rest: a plain thumb beneath the icons.
                Capsule(style: .continuous)
                    .fill(ATheme.ink.opacity(ATheme.dark ? 0.16 : 0.085))
                    .modifier(WyrmTabPillMotion(width: pillWidth, origin: pillOrigin, lifted: lifted,
                                                stretch: stretch, selection: selection, dragLocationX: dragLocationX))
                    .opacity(lifted ? 0 : 1)
                    .zIndex(1)
                HStack(spacing: 0) {
                    ForEach(WyrmDesignTab.allCases, id: \.self) { tab in
                        Button { select(tab) } label: {
                            tabLabel(tab).frame(width: itemWidth, height: 48)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, inset)
                .compositingGroup()
                .zIndex(3)
                // Held, dragged or tapped: the lens rises above the icons so the
                // glass has something to bend — the icons swell and warp through
                // its edge exactly as they do under the system tab bar's lens.
                WyrmTabSelectionGlass(lifted: true)
                    .modifier(WyrmTabPillMotion(width: pillWidth, origin: pillOrigin, lifted: lifted,
                                                stretch: stretch, selection: selection, dragLocationX: dragLocationX))
                    .shadow(color: ATheme.ink.opacity(lifted ? 0.22 : 0), radius: lifted ? 16 : 0, y: lifted ? 7 : 0)
                    .opacity(lifted ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .local)
                .onChanged { value in
                    if !lifted { lift() }
                    trackStretch(value.location.x)
                    dragLocationX = min(max(value.location.x, inset + itemWidth * 0.5), inset + width - itemWidth * 0.5)
                    preview(at: value.location.x - inset, itemWidth: itemWidth)
                }
                .onEnded { value in
                    // Absolute finger location is the authority. Predicted
                    // velocity used to compound against a changing selection,
                    // causing the lens to vibrate and shoot across several tabs.
                    let index = nearestIndex(at: value.location.x - inset, itemWidth: itemWidth)
                    let target = WyrmDesignTab.allCases[index]
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.7, blendDuration: 0.12)) {
                        selection = target
                        dragLocationX = nil
                    }
                    lastPreview = nil
                    lastSample = nil
                    drop(after: 0.04)
                })
        }
        .frame(height: 56)
        // A soft contact shadow only; a heavy one makes clear glass read as a slab.
        .shadow(color: ATheme.ink.opacity(0.07), radius: 14, y: 6)
        .padding(.horizontal, 18)
    }

    private func tabLabel(_ tab: WyrmDesignTab) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icons[tab]!).font(.system(size: tab == .play ? 21 : 18, weight: selection == tab ? .semibold : .medium))
                if tab == .alerts && unread > 0 {
                    Text("\(min(unread, 99))").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 14).background(ATheme.live).clipShape(Capsule()).offset(x: 11, y: -7)
                }
            }
            Text(tab.rawValue).font(.androidWyrm(8.5, selection == tab ? .bold : .semibold)).lineLimit(1)
        }
        // Clear glass shows whatever scrolls beneath it, so the glyphs carry a
        // paper halo in every theme and idle tabs keep the theme's tab colour.
        .foregroundColor(selection == tab ? ATheme.ink : ATheme.tabIdle)
        .shadow(color: ATheme.paper.opacity(0.7), radius: 1.4)
        .animation(.easeOut(duration: 0.16), value: selection)
    }

    private func select(_ tab: WyrmDesignTab) {
        guard selection != tab else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        lift()
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.72, blendDuration: 0.14)) { selection = tab }
        drop(after: 0.24)
    }

    private func lift() {
        dropWork?.cancel()
        // Under-damped: the lens overshoots as it rises, like a drop pulled up.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.48)) { lifted = true }
    }

    /// Low damping gives the settle its bubble: a small overshoot below rest
    /// and back, the way the system glass lands.
    private func drop(after delay: Double) {
        dropWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.interpolatingSpring(stiffness: 240, damping: 10)) {
                lifted = false
                stretch = 0
            }
        }
        dropWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func trackStretch(_ x: CGFloat) {
        let now = Date()
        defer { lastSample = (x, now) }
        guard let last = lastSample else { return }
        let dt = max(now.timeIntervalSince(last.time), 1.0 / 240)
        let speed = abs(x - last.x) / CGFloat(dt)
        stretch = min(speed / 3600, 0.2)
    }

    private func preview(at x: CGFloat, itemWidth: CGFloat) {
        let index = nearestIndex(at: x, itemWidth: itemWidth)
        let tab = WyrmDesignTab.allCases[index]
        guard tab != lastPreview else { return }
        lastPreview = tab
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func nearestIndex(at x: CGFloat, itemWidth: CGFloat) -> Int {
        min(max(Int((x / itemWidth).rounded(.down)), 0), WyrmDesignTab.allCases.count - 1)
    }
}

/// Shared geometry for the resting thumb and the lens, so they travel as one:
/// a springy trail behind the finger that wobbles when it stops, and a lift
/// that swells the lens out of the bar and squashes it along fast drags.
private struct WyrmTabPillMotion: ViewModifier {
    let width: CGFloat
    let origin: CGFloat
    let lifted: Bool
    let stretch: CGFloat
    let selection: WyrmDesignTab
    let dragLocationX: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: 50)
            .scaleEffect(x: lifted ? 1.14 + stretch : 1, y: lifted ? 1.24 - stretch * 0.6 : 1)
            .offset(x: origin, y: lifted ? -2 : 0)
            .animation(.interactiveSpring(response: 0.36, dampingFraction: 0.6, blendDuration: 0.1), value: selection)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.62, blendDuration: 0.04), value: dragLocationX)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.5), value: stretch)
    }
}

private struct WyrmTabGlassSurface: View {
    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                Color.clear
                    .contentShape(Capsule())
                    // Clear glass: the page refracts through the bar instead of
                    // being frosted out. A breath of paper keeps edges readable.
                    .glassEffect(Glass.clear.tint(ATheme.paper.opacity(0.08)).interactive(), in: .capsule)
                    .overlay(Capsule().stroke(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                    .overlay(Capsule().stroke(ATheme.ink.opacity(0.06), lineWidth: 0.45))
            }
        } else {
            fallback
        }
#else
        fallback
#endif
    }
    private var fallback: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(Capsule(style: .continuous).fill(ATheme.paper.opacity(0.06)))
            .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.4), lineWidth: 0.8))
            .overlay(Capsule(style: .continuous).stroke(ATheme.ink.opacity(0.08), lineWidth: 0.5))
    }
}

/// At rest a plain tinted capsule, as the system segmented thumb is; only
/// while a finger holds, drags or taps it does it become a clear lens.
private struct WyrmTabSelectionGlass: View {
    var lifted = false
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(ATheme.ink.opacity(ATheme.dark ? 0.16 : 0.085))
                .opacity(lifted ? 0 : 1)
            lens.opacity(lifted ? 1 : 0)
        }
    }

    @ViewBuilder
    private var lens: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                Color.clear
                    .contentShape(Capsule())
                    .glassEffect(Glass.clear.interactive(), in: .capsule)
                    .overlay(prismEdge)
            }
        } else {
            fallback
        }
#else
        fallback
#endif
    }

    /// A bright rim along the top that fades round the sides: the edge light
    /// that makes the lens read as a raised drop rather than a flat disc.
    private var prismEdge: some View {
        Capsule(style: .continuous)
            .stroke(LinearGradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.25), Color.white.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1.1)
    }

    private var fallback: some View {
        Capsule(style: .continuous)
            .fill(Material.ultraThinMaterial)
            .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(prismEdge)
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
