import SwiftUI

struct WyrmDesignMain: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    @ObservedObject private var theme = WyrmThemeStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var notificationPrefs = WyrmNotificationPrefs.shared
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    @ObservedObject private var updates = WyrmUpdateStore.shared
    /// Replies from Wyrm the player has not opened: the Settings tab's badge.
    @ObservedObject private var support = WyrmSupportStore.shared
    /// Try this skin opens the Skin tab; a Share run post opens the feed.
    @ObservedObject private var trial = WyrmSkinTrial.shared
    @ObservedObject private var shareRun = WyrmShareRun.shared
    @State private var tab: WyrmDesignTab
    @State private var routes: [WyrmDesignRoute]
    /// iOS has no push for Wyrm yet, so likes, replies and answers arrive as
    /// an in-app banner while Wyrm is open (OM, 2026-09-29).
    @State private var banner: WyrmServiceAlert?
    @State private var bannerWork: DispatchWorkItem?
    /// The app tour (OM, 2026-10-05): each step opens its place here.
    @ObservedObject private var tour = WyrmTour.shared
    @State private var tourWasActive = false
    /// The one-time "Choose your language" sheet is up (OM, 2026-10-31).
    @State private var languagePromptOpen = false
    /// The page moves for the current tour step, one after the other.
    @State private var tourMove: Task<Void, Never>?

    init(engine: WyrmShellStore, account: WyrmAccountStore, services: WyrmServiceStore,
         initialTab: WyrmDesignTab, initialRoute: WyrmDesignRoute? = nil) {
        self.engine = engine
        self.account = account
        self.services = services
        let arguments = ProcessInfo.processInfo.arguments
        let page = arguments.firstIndex(of: "--smoke-theme-page").flatMap { arguments.indices.contains($0+1) ? arguments[$0+1] : nil }
        let testing = arguments.contains("--smoke-theme")
        let selectedTab: WyrmDesignTab = testing ? (["play": .play, "trails": .trails, "social": .social, "skin": .skin, "settings": .settings][page ?? ""] ?? initialTab) : initialTab
        let selectedRoute: WyrmDesignRoute? = testing ? (["themes": .themes, "controls": .playControls][page ?? ""] ?? initialRoute) : initialRoute
        _tab = State(initialValue: selectedTab)
        _routes = State(initialValue: selectedRoute.map { [$0] }?.filter { WyrmTrailsFeature.shows($0) } ?? [])
    }

    var body: some View {
        GeometryReader { proxy in
            let tabBarBottomInset = max(14, min(18, proxy.safeAreaInsets.bottom * 0.48))
            ZStack(alignment: .bottom) {
                WyrmPaperBackground()
                if WyrmGlass.native {
                    // iOS 26: the system tab bar itself, so its Liquid Glass is
                    // Apple's — the pill that morphs between tabs, the lens that
                    // magnifies under a dragging finger, the bounce, and the bar
                    // that shrinks while a page scrolls down.
                    nativeTabs(proxy)
                } else {
                    tabPage(tab, proxy)
                        .id(tab)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))

                    WyrmRootTabBar(selection: $tab, unread: trailsBadge, settingsBadge: support.unseenReplies, socialBadge: socialBadge)
                        .frame(width: proxy.size.width)
                        .padding(.bottom, tabBarBottomInset)
                        // Typing hides the bar, as system tab bars sit under the keyboard.
                        .opacity(keyboard.focused ? 0 : 1)
                        .allowsHitTesting(!keyboard.focused)
                        .animation(.easeOut(duration: 0.18), value: keyboard.focused)
                        .zIndex(10)
                }

                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    ZStack {
                        // About follows the theme too (WyrmNight reads it), up under the status bar.
                        (route == .about ? WyrmNight.sky : wyrmScopedColours.paper).ignoresSafeArea()
                        WyrmDetailHost(route: route, engine: engine, account: account, services: services, close: { pop(route) }, open: open)
                            .padding(.top, proxy.safeAreaInsets.top)
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background((route == .about ? WyrmNight.sky : wyrmScopedColours.paper).ignoresSafeArea())
                        // Only the container edges: the keyboard's safe area must
                        // still lift composers and input boxes above the keys.
                        .ignoresSafeArea(.container)
                        // The phone's own way back (OM, 2026-10-13): a swipe in from the
                        // left edge closes the page, as its Back does.
                        .overlay(alignment: .leading) {
                            if index == routes.count - 1 {
                                // Starts under the page's top bar (OM, 2026-10-31): over it,
                                // this strip ate taps on the left half of every Back button.
                                Color.clear
                                    .frame(width: 22)
                                    .frame(maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 12, coordinateSpace: .global)
                                        .onEnded { drag in
                                            if drag.translation.width > 70,
                                               abs(drag.translation.height) < drag.translation.width {
                                                pop(route)
                                            }
                                        })
                                    // Empty padding is not hit: the strip begins below the bar.
                                    .padding(.top, proxy.safeAreaInsets.top + 64)
                            }
                        }
                        .zIndex(Double(30 + index))
                        .transition(.wyrmCinematicPush)
                        .allowsHitTesting(index == routes.count - 1)
                }
                if languagePromptOpen {
                    WyrmLanguagePrompt { languagePromptOpen = false }
                        .zIndex(200)
                }
                if let alert = banner {
                    WyrmInAppBanner(alert: alert, onOpen: { openBanner(alert) }, onDismiss: dismissBanner)
                        .padding(.horizontal, 10)
                        .padding(.top, proxy.safeAreaInsets.top + 6)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(70)
                }
                if let next = updates.promptable {
                    WyrmUpdatePrompt(info: next,
                                     onLater: { withAnimation(.easeOut(duration: 0.2)) { updates.answerPrompt() } },
                                     onUpdate: { openUpdateSettings(highlightBeta: false) },
                                     onBetaSettings: { openUpdateSettings(highlightBeta: true) })
                        .zIndex(60)
                        .transition(.opacity)
                }
                // The app tour (OM, 2026-10-05), over everything on this page.
                if tour.active {
                    WyrmTourOverlay(safeTop: proxy.safeAreaInsets.top, safeBottom: proxy.safeAreaInsets.bottom)
                        .zIndex(95)
                        .transition(.opacity)
                }
                if !engine.toast.isEmpty {
                    Text(engine.toast)
                        .font(.androidWyrm(11.5, .semibold)).foregroundColor(wyrmScopedColours.onInk).lineLimit(2)
                        .padding(.horizontal, 14).padding(.vertical, 10).background(wyrmScopedColours.ink).cornerRadius(12)
                        .padding(.horizontal, 20).padding(.bottom, routes.isEmpty ? 84 : 18).zIndex(50)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }.ignoresSafeArea(.container)
            // A theme change redraws every screen with the new palette. Tab and
            // route state live on this view, so the page the player is on stays open.
            .id(theme.identity)
        }
        .foregroundColor(wyrmScopedColours.ink)
        .background(wyrmScopedColours.paper.ignoresSafeArea())
        // The About page is a night page: light status bar over it.
        .preferredColorScheme(theme.preferredScheme)
        .onAppear {
            guard routes.last != .about else { return }
            theme.noteSystemDark(colorScheme == .dark)
        }
        .onChange(of: colorScheme) { scheme in
            guard routes.last != .about else { return }
            theme.noteSystemDark(scheme == .dark)
        }
        // Checked once a launch; a newer build raises the prompt above.
        .task { await updates.check() }
        // The app tour: once after an install or an update, on the first quiet Home.
        .task { await startTourWhenQuiet() }
        // Choose your language (OM, 2026-10-31): once, on a quiet Home after the tour.
        .task { await showLanguagePromptWhenQuiet() }
        .onReceive(tour.$step) { _ in DispatchQueue.main.async { applyTourPlace() } }
        // The live inbox (OM, 2026-10-01): new alerts, DMs and replies land at once.
        // A quiet look stays as a fallback: every 15 s on Alerts, every 45 s elsewhere.
        .task {
            WyrmLiveInbox.shared.onInbox = { kind in Task { await handleInbox(kind) } }
            WyrmLiveInbox.shared.onChatEvent = { event in services.applyChatEvent(event) }
            WyrmLiveInbox.shared.onMessageDeleted = { id in
                services.dropChatMessage(id)
                Task { await services.refreshConversations() }
            }
            startPresence()
            WyrmFriendMarks.shared.playing = { WyrmPresence.shared.inOnlineMatch }
            WyrmFriendMarks.shared.start()
            // Music and sounds removed from iOS (OM, 2026-11-08): the frame
            // drops came with every bite's sound. Nothing starts WyrmSound now.
            WyrmLiveInbox.shared.start(token: account.sessionToken)
            var quiet = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                quiet += 1
                if routes.last == .alerts || quiet % 3 == 0 { await pollAlerts() }
            }
        }
        .onDisappear { WyrmLiveInbox.shared.stop(); WyrmPresence.shared.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            startPresence()
            WyrmLiveInbox.shared.start(token: account.sessionToken)
            Task {
                await pollAlerts()
                // Back in the foreground: a reply may have come while away.
                await support.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            WyrmLiveInbox.shared.stop()
            WyrmPresence.shared.stop()
        }
        // Where the player is, for a crash or problem report.
        .onChange(of: routes) { value in
            WyrmCrashWatch.shared.screen = value.last?.id ?? tab.rawValue
            // A new page closes the keyboard (OM, 2026-11-08): it opens again only
            // where that page has a composer and the player taps it.
            WyrmKeyboardController.shared.dismiss()
        }
        .onChange(of: tab) { value in
            WyrmKeyboardController.shared.dismiss()
            if routes.isEmpty { WyrmCrashWatch.shared.screen = value.rawValue }
            // Leaving the Skin tab without Wear drops a tried skin, and the tab
            // opens on the classic Skin page again (OM, 2026-10-13).
            if value != .skin {
                trial.end()
                WyrmStudio.shared.classicOpen = !ProcessInfo.processInfo.arguments.contains("--smoke-skin-studio")
            }
        }
        .onChange(of: trial.request) { _ in
            withAnimation(.easeOut(duration: 0.2)) { routes.removeAll() }
            tab = .skin
        }
        .onChange(of: shareRun.trailsRequest) { _ in
            // Posted from Share run: the Trails tab, where the new trail is landing.
            routes.removeAll()
            tab = .trails
        }
        .onChange(of: engine.toast) { value in
            guard !value.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeOut(duration: 0.2)) { if engine.toast == value { engine.toast = "" } }
            }
        }
    }

    private var unreadAlerts: Int {
        services.alerts.filter { !$0.read && notificationPrefs.allows($0.kind) }.count
    }

    /// The Social trail: unread DMs, voice invites, new followers, new global chat.
    private var socialBadge: Int {
        let dms = services.conversations.reduce(0) { $0 + $1.unreadCount }
        let kinds: Set<String> = WyrmVoiceFeature.enabled ? ["voice_invite", "follow"] : ["follow"]
        return dms + services.alerts.filter { !$0.read && kinds.contains($0.kind) }.count + services.globalUnread
    }

    /// Unread likes and replies on your trails: the Trails tab's count.
    private var trailsBadge: Int {
        guard WyrmTrailsFeature.enabled else { return 0 }
        let kinds: Set<String> = ["trail_like", "trail_reply"]
        return services.alerts.filter { !$0.read && kinds.contains($0.kind) }.count
    }

    private static let tabIcons: [WyrmDesignTab: String] = [
        .social: "person.2", .play: "play.circle",
        .skin: "circle.hexagongrid", .settings: "slider.horizontal.3",
    ]

    /// The system tab bar's glyph: Trails is Wyrm's own (the `TrailsTab`
    /// asset, same paths as `WyrmTrailsIcon`), the rest are system symbols.
    private static func tabImage(_ value: WyrmDesignTab) -> Image {
        value == .trails ? Image("TrailsTab") : Image(systemName: tabIcons[value] ?? "circle")
    }

    @ViewBuilder
    private func tabPage(_ value: WyrmDesignTab, _ proxy: GeometryProxy, padTop: Bool = true) -> some View {
        Group {
            switch value {
            case .trails:
                if WyrmTrailsFeature.enabled { WyrmTrailsFeed(account: account, open: open) }
                else { WyrmTrailsComingSoon() }
            case .social: WyrmSocialRoot(account: account, services: services, open: open)
            case .play: WyrmPlayRoot(engine: engine, account: account, services: services, open: open)
            // Skin Studio first; the classic page behind "Default skin editor" (OM, 2026-10-12).
            case .skin: WyrmSkinTab(engine: engine)
            case .settings: WyrmSettingsHub(engine: engine, account: account, open: open)
            }
        }
        .frame(width: proxy.size.width)
        // The system TabView already keeps its pages clear of the camera
        // cut-out; adding the inset again pushed every tab page down.
        .padding(.top, padTop ? proxy.safeAreaInsets.top : 0)
    }

    @ViewBuilder
    private func nativeTabs(_ proxy: GeometryProxy) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // The chosen tab takes the theme's ink (`.tint` below); the rest
            // take its faded tab colour instead of the system grey. iOS 26
            // ignores `unselectedItemTintColor` on the glass bar, so the item
            // colours go through UITabBarAppearance, set before the bar is
            // built and rebuilt with it on every theme change.
            let _ = Self.styleTabBar()
            TabView(selection: $tab) {
                ForEach(WyrmDesignTab.allCases, id: \.self) { value in
                    Tab(value: value) {
                        tabPage(value, proxy, padTop: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(WyrmPaperBackground())
                    } label: {
                        Label { Text(value.rawValue) } icon: { Self.tabImage(value) }
                    }
                    .badge(value == .trails ? trailsBadge : value == .settings ? support.unseenReplies : value == .social ? socialBadge : 0)
                }
            }
            .tint(wyrmScopedColours.ink)
            .tabBarMinimizeBehavior(tab == .skin ? .never : .onScrollDown)
        }
#endif
    }

    /// The update prompt's buttons: Settings › Updates, where the update starts.
    private func openUpdateSettings(highlightBeta: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { updates.answerPrompt() }
        tab = .settings
        routes.removeAll { $0 == .backup }
        // The shortcut lands on the Beta updates switch the way a search result does.
        if highlightBeta { WyrmSettingsFocus.shared.reveal("app.beta-updates") }
        open(.backup)
    }

    /// Active tab: the theme's ink. The rest: its faded tab colour, in every
    /// theme (OM, 2026-09-28: a dark label on the resting pill was lost in the
    /// dark themes). As `FloatingTabLabel` on Android.
    private static func styleTabBar() {
        let active = UIColor(ATheme.ink)
        let idle = UIColor(ATheme.tabIdle)
        let bar = UITabBar.appearance()
        bar.tintColor = active
        bar.unselectedItemTintColor = idle
        let appearance = UITabBarAppearance()
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = idle
            item.normal.titleTextAttributes = [.foregroundColor: idle]
            item.selected.iconColor = active
            item.selected.titleTextAttributes = [.foregroundColor: active]
        }
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
    }

    /// Something new for this player: refetch what it touches ("" = everything, after a reconnect).
    private func handleInbox(_ kind: String) async {
        switch kind {
        case "dm":
            await services.refreshConversations()
        case "support":
            await pollAlerts()
            await support.refresh()
        case "":
            await pollAlerts()
            await services.refreshConversations()
            await support.refresh()
        default:
            await pollAlerts()
        }
    }

    /// Presence (2026-10-09): the session, arena names and flags, Join, then the
    /// state on the live socket. Android twin: WyrmOverlay.startLiveInbox.
    private func startPresence() {
        let presence = WyrmPresence.shared
        presence.token = account.sessionToken
        presence.arenaName = { endpoint in services.arenas.first(where: { $0.endpoint == endpoint })?.title ?? endpoint }
        WyrmPresenceCountries.shared.directory = { address in services.countryCode(for: address) }
        presence.onJoin = { address in engine.enterLobby(name: engine.nickname, address: address) }
        guard !account.sessionToken.isEmpty else { return }
        presence.start()
    }

    private func pollAlerts() async {
        guard UIApplication.shared.applicationState == .active, engine.engineScreen == 0 else { return }
        if routes.last != .globalChat { await services.refreshGlobalUnread() }
        let fresh = await services.pollAlerts()
        // A reply from Wyrm: fetch it now so the Settings badge counts it.
        if fresh.contains(where: { $0.kind == "support" }) { await support.refresh() }
        guard let newest = fresh.first(where: { WyrmAlertRouting.banners.contains($0.kind) && notificationPrefs.allows($0.kind) }) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) { banner = newest }
        bannerWork?.cancel()
        let work = DispatchWorkItem { dismissBanner() }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    private func dismissBanner() {
        bannerWork?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { banner = nil }
    }

    private func openBanner(_ alert: WyrmServiceAlert) {
        dismissBanner()
        services.markRead(alert)
        if let route = WyrmAlertRouting.route(for: alert) { open(route) } else { open(.alerts) }
    }

    /// Waits for a quiet Home (signed in, no prompt, no match, nothing open),
    /// then starts the tour if this phone has not seen it.
    /// The one-time "Choose your language" sheet: marked shown as it opens, so it
    /// never comes back on this phone.
    private func showLanguagePromptWhenQuiet() async {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--smoke") }) else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        while !Task.isCancelled && WyrmLanguage.shared.promptOwed {
            let quiet = account.phase == .signedIn && routes.isEmpty && tab == .play
                && !tour.pending && !tour.active
                && updates.promptable == nil && WyrmCrashWatch.shared.prompt == nil
                && WyrmDropWatch.shared.prompt == nil && engine.engineScreen == 0
                && !engine.layoutEditorActive && !shareRun.isOpen && !WyrmAccountSync.shared.askingLogOut
            if quiet {
                WyrmLanguage.shared.promptShown()
                languagePromptOpen = true
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func startTourWhenQuiet() async {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--smoke") }) else { return }
        try? await Task.sleep(nanoseconds: 900_000_000)
        while !Task.isCancelled && tour.pending && !tour.active {
            let quiet = account.phase == .signedIn && routes.isEmpty && tab == .play
                && updates.promptable == nil && WyrmCrashWatch.shared.prompt == nil
                && WyrmDropWatch.shared.prompt == nil && engine.engineScreen == 0
                && !engine.layoutEditorActive && !shareRun.isOpen && !WyrmAccountSync.shared.askingLogOut
            if quiet {
                withAnimation(.easeOut(duration: 0.25)) { tour.start() }
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Opens the current tour step's place with the app's own page
    /// animations, one after the other (OM, 2026-10-06: smooth, no jumps): an
    /// open page slides back first, then the tab changes, then a page slides
    /// in. Home, Play › Controls (the workspace picks its own tab) or the
    /// Settings tab. When the tour ends, back to Home.
    private func applyTourPlace() {
        tourMove?.cancel()
        let pop = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.1)
        let push = Animation.interactiveSpring(response: 0.44, dampingFraction: 0.84, blendDuration: 0.12)
        let tabSwap = Animation.spring(response: 0.34, dampingFraction: 0.86)
        let pageTime: UInt64 = 430_000_000
        guard let place = tour.current?.place else {
            if tourWasActive {
                tourWasActive = false
                tourMove = Task { @MainActor in
                    if !routes.isEmpty {
                        withAnimation(pop) { routes.removeAll() }
                        try? await Task.sleep(nanoseconds: pageTime)
                    }
                    if tab != .play { withAnimation(tabSwap) { tab = .play } }
                }
            }
            return
        }
        tourWasActive = true
        tourMove = Task { @MainActor in
            switch place {
            case .home:
                if !routes.isEmpty {
                    withAnimation(pop) { routes.removeAll() }
                    try? await Task.sleep(nanoseconds: pageTime)
                }
                if Task.isCancelled { return }
                if tab != .play { withAnimation(tabSwap) { tab = .play } }
            case .controls, .buttons, .arenaUI:
                // Already there: the workspace slides to the step's tab by itself.
                if tab == .play && routes == [.playControls] { return }
                if !routes.isEmpty {
                    withAnimation(pop) { routes.removeAll() }
                    try? await Task.sleep(nanoseconds: pageTime)
                }
                if Task.isCancelled { return }
                if tab != .play {
                    withAnimation(tabSwap) { tab = .play }
                    try? await Task.sleep(nanoseconds: pageTime)
                }
                if Task.isCancelled { return }
                withAnimation(push) { routes = [.playControls] }
            case .settings:
                WyrmSettingsFocus.shared.query = ""
                if !routes.isEmpty {
                    withAnimation(pop) { routes.removeAll() }
                    try? await Task.sleep(nanoseconds: pageTime)
                }
                if Task.isCancelled { return }
                if tab != .settings { withAnimation(tabSwap) { tab = .settings } }
            }
        }
    }

    private func open(_ value: WyrmDesignRoute) {
        // Trails are paused for the beta: no way into the feed, a trail or the studio.
        guard WyrmTrailsFeature.shows(value) else { return }
        guard routes.last != value else { return }
        WyrmKeyboardController.shared.dismiss()
        withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.84, blendDuration: 0.12)) { routes.append(value) }
    }

    private func pop(_ value: WyrmDesignRoute) {
        guard let index = routes.lastIndex(of: value) else { return }
        WyrmKeyboardController.shared.dismiss()
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.1)) {
            routes.removeSubrange(index..<routes.endIndex)
        }
    }
}

private struct WyrmPlayRoot: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let open: (WyrmDesignRoute) -> Void
    @State private var nickname = ""
    @FocusState private var nameFocused: Bool
    @State private var arena = ""
    @State private var userSelectedArena = false
    @State private var showArenas = ProcessInfo.processInfo.arguments.contains("--smoke-theme-arenas")
    @State private var lastHandledRefusal: UInt64 = 0
    @AppStorage("wyrm.ios.arena.recent") private var recentArenaEndpoints = ""
    @AppStorage("wyrm.ios.arena.saved") private var savedArenaEndpoints = ""
    /// The arena the player chose (OM, 2026-10-09: Home showed the lowest-ping
    /// arena on every launch instead). Only the picker and a Play on what Home
    /// shows change it; an event, invite or friend's Join does not. Synced with
    /// the account (`wyrm.ios.arena.`).
    @AppStorage("wyrm.ios.arena.chosen") private var chosenArena = ""

    private var nearest: WyrmArena? {
        let pick = userSelectedArena ? arena : chosenArena
        if !pick.isEmpty {
            if let selected = services.arenas.first(where: { $0.endpoint == pick }) { return selected }
            if let selected = WyrmArena.custom(pick) { return selected }
        }
        return services.recommendedArena
    }
    /// Android's `playControlsLabel`: steering style and hand, e.g. "Joystick · Right".
    private var controls: String {
        if engine.setting("controls.joystick_mode")?.index == 3 { return "Classic" }
        let steering = engine.setting("controls.joystick_mode")?.index == 2 ? "Arrow" : "Joystick"
        guard let hand = engine.setting("controls.handedness"), hand.options.indices.contains(hand.index) else { return "\(steering) · Right" }
        return "\(steering) · \(hand.options[hand.index].prefix(1).uppercased() + hand.options[hand.index].dropFirst())"
    }
    private var food: String { WyrmFoodPage.label(engine) }
    /// Unread alerts the player allows: the count on the bell.
    private var unreadAlerts: Int {
        services.alerts.filter { !$0.read && WyrmNotificationPrefs.shared.allows($0.kind) }.count
    }

    var body: some View {
        ScrollViewReader { tourProxy in
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Wyrm").font(.androidWyrm(10.5, .bold)).tracking(1).foregroundColor(wyrmScopedColours.quiet)
                        TextField("Wyrm Player", text: $nickname, prompt: wyrmPrompt("Wyrm Player")).font(.androidWyrm(29, .bold)).textInputAutocapitalization(.never).disableAutocorrection(true)
                            .focused($nameFocused).submitLabel(.done).onSubmit(commitName)
                            .onChange(of: nameFocused) { focused in if !focused { commitName() } }
                        Text("Tap to rename in-game name").font(.androidWyrm(9.5)).foregroundColor(wyrmScopedColours.quiet)
                    }
                    Spacer()
                    // Top right (OM, 2026-10-04): Alerts as a button, then your
                    // avatar, which opens your profile. No name or @username here.
                    HStack(spacing: 10) {
                        WyrmAlertsBellButton(unread: unreadAlerts) { open(.alerts) }
                        Button { open(.profile("")) } label: {
                            WyrmAvatar(initials: account.player?.initials ?? "W", size: 36, url: account.player?.avatarURL ?? "")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Your profile")
                    }
                }.padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 15)

                // Events (OM, 2026-10-30): the live or next event above the arena card.
                WyrmHomeEvents(engine: engine, open: open)

                WyrmHeroCard(slot: 1) { wyrmScopedColours in
WyrmPaperCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) { Circle().fill(nearest == nil ? wyrmScopedColours.quiet : wyrmScopedColours.live).frame(width: 6, height: 6); Text(nearest == nil ? "ARENA DIRECTORY" : "LIVE ARENA").font(.androidWyrm(10.5, .bold)).tracking(0.8).foregroundColor(nearest == nil ? wyrmScopedColours.quiet : wyrmScopedColours.live) }
                        HStack(alignment: .bottom) {
                            Text(nearest.map { $0.number == 0 ? "Custom arena" : "Arena \($0.code)" } ?? "Pick a server").font(.androidWyrm(21, .bold)).lineLimit(1)
                            if let nearest, nearest.number > 0 {
                                WyrmArenaCountryBadge(country: services.countryCode(for: nearest.address)).padding(.bottom, 4)
                            }
                            Spacer()
                            Text(nearest == nil ? "" : "\(nearest!.players) players").font(.androidWyrm(11.5)).foregroundColor(wyrmScopedColours.quiet)
                        }.padding(.top, 11)
                        Text(nearest?.endpoint ?? "Choose a live arena or enter an address.").font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.mute).padding(.top, 3)
                        GeometryReader { geometry in ZStack(alignment: .leading) { Capsule().fill(wyrmScopedColours.track); Capsule().fill(wyrmScopedColours.ink).frame(width: geometry.size.width * min(1, CGFloat(nearest?.players ?? 0) / 2000)) } }.frame(height: 4).padding(.top, 13)
                        HStack(spacing: 9) {
                            Button { enterOriginalLobby() } label: { Text("Enter lobby").font(.androidWyrm(15, .bold)).foregroundColor(wyrmScopedColours.onInk).frame(maxWidth: .infinity).frame(height: 46).background(WyrmGlass.native ? Color.clear : (nearest == nil ? wyrmScopedColours.ink : wyrmScopedColours.ink)).cornerRadius(11) }.modifier(WyrmGlassButtonModifier(prominent: true, radius: 11, fallback: WSPressStyle())).disabled(nearest == nil)
                            Button { showArenas = true } label: { Image(systemName: "globe.asia.australia.fill").foregroundColor(wyrmScopedColours.mute).frame(width: 46, height: 46).overlay(RoundedRectangle(cornerRadius: 11).stroke(wyrmScopedColours.rule, lineWidth: WyrmGlass.native ? 0 : 1)) }.modifier(WyrmGlassButtonModifier(radius: 11, fallback: WSPressStyle()))
                        }.padding(.top, 16)
                    }.padding(18)
                    Rectangle().fill(wyrmScopedColours.rule).frame(height: 1)
                    HStack(spacing: 0) {
                        WyrmMetric(label: "BEST SCORE", value: (account.player?.highestScore ?? Int64(engine.score)).wyrmFormatted)
                        Rectangle().fill(wyrmScopedColours.rule).frame(width: 1, height: 51)
                        WyrmMetric(label: "TOTAL KILLS", value: (account.player?.kills ?? Int64(engine.kills)).wyrmFormatted)
                    }
                }
}

                WyrmSectionLabel("Loadout")
                WyrmPaperCard {
                    WyrmLoadoutRow(title: "Food", value: food, first: true, leading: AnyView(WyrmFoodWell())) { open(.playFood) }
                    WyrmLoadoutRow(title: "Controls", value: controls, leading: AnyView(WyrmLoadoutIcon(symbol: "gamecontroller"))) { open(.playControls) }
                        .wyrmTourAnchor("home.controls")
                    WyrmLoadoutRow(title: "Mode", value: "", leading: AnyView(WyrmLoadoutIcon(symbol: "scope"))) { open(.playModes) }
                    WyrmLoadoutRow(title: "Snakey Rain", value: WyrmRain.shared.enabled ? "On" : "Off", leading: AnyView(WyrmLoadoutIcon(symbol: "cloud.rain"))) { open(.snakeyRain) }
                    WyrmNearOriginalRow()
                        .wyrmTourAnchor("home.near")
                }

                // Shed (OM, 2026-10-15): between Loadout and Rooms & team, as on Android.
                WyrmSectionLabel("Shed")
                WyrmHeroCard(slot: 2) { wyrmScopedColours in
WyrmPaperCard {
                    WyrmShedHomeCard { open(.shed) }
                }
}

                WyrmSectionLabel("Rooms & team")
                WyrmPaperCard {
                    if WyrmVoiceFeature.enabled {
                        WyrmListRow(title: "Voice rooms", detail: services.liveRooms.first?.name ?? "Own and community rooms", value: "\(services.liveRooms.count) live", icon: "mic.fill", tint: wyrmScopedColours.live) { open(.voice) }
                    }
                    WyrmListRow(title: "Team mode", detail: "Original engine team layer", value: "Open", icon: "person.3.fill", tint: wyrmScopedColours.live) { open(.team) }
                        .wyrmTourAnchor("home.team")
                }

                // Events (OM, 2026-10-30): a button of its own under Team, so every
                // event (live, coming, done) is one tap away.
                WyrmSectionLabel("Events")
                WyrmPaperCard {
                    WyrmEventsHomeRow { open(.events) }
                }
                Spacer().frame(height: 102)
            }
        }
        .wyrmTourScroll(tourProxy)
        }
        .onAppear { adoptEngineName(); if arena.isEmpty { arena = engine.arena } }
        .onChange(of: engine.nickname) { _ in if !nameFocused { adoptEngineName() } }
        .onChange(of: engine.nicknameLoaded) { _ in adoptEngineName() }
        .onChange(of: nearest?.endpoint) { value in if arena.isEmpty, let value { arena = value } }
        .onChange(of: engine.arenaRefusalSequence) { sequence in
            guard sequence > lastHandledRefusal, !engine.refusedArena.isEmpty else { return }
            lastHandledRefusal = sequence
            WyrmDiagnostics.record("arena join ended; returning to lobby endpoint=\(engine.refusedArena)", category: "NETWORK")
        }
        // One directory read for the recommendation. It used to repeat every
        // two seconds for as long as this page existed — which is also under
        // the lobby and the match. The picker keeps its own refresh while open.
        .task { await services.refreshArenasLive() }
        .fullScreenCover(isPresented: $showArenas) {
            WyrmArenaPicker(services: services, selection: Binding(
                get: { userSelectedArena ? arena : (chosenArena.isEmpty ? services.recommendedArena?.endpoint ?? "" : chosenArena) },
                set: { arena = $0; userSelectedArena = true; chosenArena = $0 }))
        }
    }

    private func enterOriginalLobby() {
        guard let selected = nearest else { return }
        arena = selected.endpoint
        chosenArena = selected.endpoint
        var recent = recentArenaEndpoints.split(separator: ";").map(String.init)
        recent.removeAll { $0 == selected.endpoint }
        recent.insert(selected.endpoint, at: 0)
        recentArenaEndpoints = recent.prefix(5).joined(separator: ";")
        commitName()
        engine.enterLobby(name: engine.nickname, address: selected.endpoint)
    }

    /// The engine's saved name wins, so a restart never swaps it. Only when
    /// the engine has never had one does the account's arena name seed it.
    private func adoptEngineName() {
        guard engine.nicknameLoaded else { return }
        if engine.nickname.isEmpty, !engine.nicknameChosen, let seed = account.player?.ingameName, !seed.isEmpty {
            engine.setNickname(seed)
            nickname = seed
        } else {
            nickname = engine.nickname
        }
    }

    private func commitName() {
        // As typed (at most 24), blank included: the arena shows it as is (OM).
        let clean = WyrmShellStore.arenaNickname(nickname)
        nickname = clean
        guard clean != engine.nickname else { return }
        engine.setNickname(clean)
        // Blank too (OM, 2026-10-14): the account then forgets the old name.
        let trimmed = clean.trimmingCharacters(in: .whitespaces)
        if trimmed != (account.player?.ingameName ?? "") { WyrmGameSync.shared.syncIngameName(clean) }
    }
}

/// Android's `LoadoutRow`: a 26 pt well, the title, its value and a chevron.
struct WyrmLoadoutRow: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let title: String
    let value: String
    var first = false
    var leading: AnyView? = nil
    let onOpen: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(wyrmScopedColours.rowRule).frame(height: 1) }
            Button(action: onOpen) {
                HStack(spacing: 0) {
                    if let leading { leading; Spacer().frame(width: 12) }
                    Text(title).font(.androidWyrm(15.5)).foregroundColor(wyrmScopedColours.ink).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !value.isEmpty {
                        Text(value).font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                        Spacer().frame(width: 6)
                    }
                    Text("›").font(.androidWyrm(17)).foregroundColor(wyrmScopedColours.chevron)
                }
                .padding(.horizontal, 14).frame(height: 52).contentShape(Rectangle())
            }.buttonStyle(WSPressStyle())
        }
    }
}

struct WyrmLoadoutIcon: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(wyrmScopedColours.mute)
            .frame(width: 26, height: 26).background(wyrmScopedColours.well)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WyrmMetric: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let label: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 2) { Text(label).font(.androidWyrm(9.5, .bold)).tracking(0.8).foregroundColor(wyrmScopedColours.quiet); Text(value).font(.androidWyrm(17, .bold)) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 12) }
}

private struct WyrmArenaPicker: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var services: WyrmServiceStore
    @Binding var selection: String
    @Environment(\.presentationMode) private var presentation
    @State private var search = ""
    @State private var showAll = false
    @State private var showSaved = false
    @State private var showAdd = false
    @State private var customAddress = ""
    @State private var addressError = false
    @State private var customLatencies: [String: Int] = [:]
    @AppStorage("wyrm.ios.arena.recent") private var recentArenaEndpoints = ""
    @AppStorage("wyrm.ios.arena.saved") private var savedArenaEndpoints = ""
    /// Picker style (OM, 2026-10-30): 0 Classic (the list), 1 Details (cards
    /// with the monitor's minimap and top 10). Synced with `wyrm.ios.arena.`.
    @AppStorage("wyrm.ios.arena.picker-style") private var pickerStyle = 0
    @ObservedObject private var events = WyrmEventsStore.shared

    /// Saved arenas picked by a long press (OM, 2026-11-07); non-empty = selecting.
    @State private var savedPicked: Set<String> = []

    private var saved: [String] { savedArenaEndpoints.split(separator: ";").map(String.init) }
    private var recent: [String] { recentArenaEndpoints.split(separator: ";").map(String.init) }

    /// Every arena NTL lists (OM, 2026-11-07): the monitor (/v1/arena/status)
    /// is slither's arenas plus the ones NTL knows, custom arenas included.
    /// Those missing from slither's directory join the list in both styles,
    /// so search finds them and a tap plays them, saved or not. Not pinged
    /// (custom servers have no /ptc); their players come from the feed.
    private var extraArenas: [WyrmArena] {
        let known = Set(services.arenas.map { $0.endpoint.lowercased() })
        var seen = Set<String>()
        var out: [WyrmArena] = []
        for live in events.monitor.values {
            let key = live.endpoint.lowercased()
            guard !live.endpoint.isEmpty, !known.contains(key), seen.insert(key).inserted,
                  let base = WyrmArena.custom(live.endpoint) else { continue }
            out.append(WyrmArena(active: true, address: base.address, port: base.port,
                                 players: live.players ?? 0,
                                 number: live.custom ? 0 : (live.code ?? 0), cluster: 0))
        }
        return out
    }

    private var filtered: [WyrmArena] {
        // Every listed arena (OM, 2026-10-09: 108 of 144, e.g. 4817, were
        // hidden behind the directory's "active" byte, which the web client
        // only uses to weight its automatic pick).
        let live = services.arenas + extraArenas
        let matching = search.isEmpty ? live : live.filter {
            $0.endpoint.contains(search) || $0.title.localizedCaseInsensitiveContains(search)
        }
        return matching.sorted { left, right in
            let leftPing = services.arenaLatencies[left.id].flatMap { $0 > 0 ? $0 : nil } ?? .max
            let rightPing = services.arenaLatencies[right.id].flatMap { $0 > 0 ? $0 : nil } ?? .max
            if leftPing != rightPing { return leftPing < rightPing }
            return left.code < right.code
        }
    }
    // Phase 3 I (OM, 2026-10-01): Recent is ranked by ping too (unmeasured
    // last, joined order kept between equals). Uses only the pings the picker
    // already measured; no new probes.
    private var recentRows: [WyrmArena] {
        let rows = recent.compactMap { endpoint in
            services.arenas.first(where: { $0.endpoint == endpoint })
                ?? extraArenas.first(where: { $0.endpoint == endpoint })
                ?? (saved.contains(endpoint) ? WyrmArena.custom(endpoint) : nil)
        }.filter { search.isEmpty || $0.endpoint.contains(search) || $0.title.localizedCaseInsensitiveContains(search) }
        return rows.enumerated().sorted { left, right in
            let leftPing = measured(left.element) ?? .max
            let rightPing = measured(right.element) ?? .max
            if leftPing != rightPing { return leftPing < rightPing }
            return left.offset < right.offset
        }.map(\.element)
    }
    private func measured(_ arena: WyrmArena) -> Int? {
        let value = arena.number == 0 ? customLatencies[arena.endpoint] : services.arenaLatencies[arena.id]
        return value.flatMap { $0 > 0 ? $0 : nil }
    }
    /// "Best for you": the live arena with the lowest measured ping (never a
    /// custom address). Selecting it is a plain tap; nothing auto-joins.
    private var bestArena: WyrmArena? {
        guard search.isEmpty else { return nil }
        return services.arenas
            .compactMap { arena -> (WyrmArena, Int)? in
                guard let ping = services.arenaLatencies[arena.id], ping > 0 else { return nil }
                return (arena, ping)
            }
            .min { $0.1 < $1.1 }?.0
    }
    private var ranked: [WyrmArena] { filtered.filter { row in !recent.contains(row.endpoint) } }

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) { Text("LIVE DIRECTORY").font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(wyrmScopedColours.live); Text("Pick a server").font(.androidWyrm(27, .bold)) }
                    Spacer()
                    // "Add IP" (OM, 2026-11-07: a bare + confused players): opens a popup.
                    Button { addressError = false; withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { showAdd = true } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                            Text("Add IP").font(.androidWyrm(13, .bold))
                        }
                        .foregroundColor(wyrmScopedColours.ink).padding(.horizontal, 12).frame(height: 36)
                        .background(Capsule().fill(wyrmScopedColours.card))
                        .overlay(Capsule().stroke(wyrmScopedColours.rule))
                    }.buttonStyle(WSPressStyle()).accessibilityLabel("Add an arena IP")
                    Button { presentation.wrappedValue.dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundColor(wyrmScopedColours.ink)
                            .frame(width: 36, height: 36).background(WyrmGlass.native ? Color.clear : wyrmScopedColours.card).clipShape(Circle())
                    }.modifier(WyrmGlassCircleButton()).accessibilityLabel("Close")
                }.padding(20)
                WSSegmented(options: ["Classic", "Details"], selected: pickerStyle) { pickerStyle = $0 }
                    .padding(.horizontal, 16).padding(.bottom, 10)
                HStack { Image(systemName: "magnifyingglass"); TextField("Arena code or IP", text: $search, prompt: wyrmPrompt("Arena code or IP")).textInputAutocapitalization(.never).disableAutocorrection(true) }
                    .font(.androidWyrm(13)).padding(.horizontal, 14).frame(height: 44).background(wyrmScopedColours.card.opacity(0.82)).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(wyrmScopedColours.rule)).padding(.horizontal, 16)
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 9, pinnedViews: []) {
                        if let best = bestArena {
                            sectionLabel("BEST FOR YOU")
                            WyrmHeroCard { _ in pickRow(best, tag: "Lowest ping") }
                        }
                        if !recentRows.isEmpty {
                            sectionLabel("RECENTLY JOINED")
                            ForEach(recentRows) { arena in pickRow(arena) }
                        }
                        sectionLabel(search.isEmpty ? "ARENAS" : "SEARCH RESULTS")
                        ForEach(showAll || !search.isEmpty ? ranked : Array(ranked.prefix(10))) { arena in pickRow(arena) }
                        if search.isEmpty && ranked.count > 10 {
                            Button(showAll ? "Show less" : "See all") { withAnimation { showAll.toggle() } }
                                .font(.androidWyrm(13, .bold)).frame(maxWidth: .infinity).padding(14)
                        }
                        if !saved.isEmpty { savedSection }
                        if filtered.isEmpty && recentRows.isEmpty && saved.isEmpty {
                            Text("No active arenas right now. Try refreshing or add a custom IP.")
                                .font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.quiet).padding(20)
                        }
                    }.padding(16)
                }
            }
            if showAdd { addIPPopup.transition(.opacity) }
        }
        .task {
            await services.refreshArenasLive()
            await services.measurePickerArenas(preferredEndpoints: [selection] + recent)
            if let selected = WyrmArena.custom(selection),
               !services.arenas.contains(where: { $0.endpoint == selected.endpoint }) {
                customLatencies[selected.endpoint] = await services.measureCustomArena(selected.endpoint) ?? -1
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await services.refreshArenasLive()
            }
        }
        .task {
            // The arena monitor (wyrmarenas) for Details: every 20 s while open.
            while !Task.isCancelled {
                await events.refreshMonitor(maxAge: 20)
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
        .onDisappear { WyrmArenaProbeGate.shared.cancelProbes() }
    }

    /// Add IP (OM, 2026-11-07): a centred popup over the page, kept above the
    /// keyboard (SwiftUI's keyboard-safe layout, plus WyrmAboveKeys for any
    /// measured residual overlap).
    private var addIPPopup: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
                .onTapGesture { WyrmKeyboardController.shared.dismiss(); withAnimation { showAdd = false } }
            VStack(alignment: .leading, spacing: 14) {
                Text("Add an arena").font(.androidWyrm(22, .bold)).foregroundColor(wyrmScopedColours.ink)
                Text("Type the arena's IP and port, for example 141.164.36.225:446. It is saved under Saved arenas.")
                    .font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.quiet).fixedSize(horizontal: false, vertical: true)
                WyrmFocusedField(placeholder: "IP address:port", text: $customAddress, onDone: saveCustom)
                    .frame(height: 48).padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(wyrmScopedColours.card))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(addressError ? ATheme.badge : wyrmScopedColours.rule))
                if addressError {
                    Text("Enter an IPv4 address or [IPv6] address and a port (1–65535).")
                        .font(.androidWyrm(11.5)).foregroundColor(ATheme.badge)
                }
                HStack(spacing: 10) {
                    Button { WyrmKeyboardController.shared.dismiss(); withAnimation { showAdd = false } } label: {
                        Text("Cancel").font(.androidWyrm(15)).foregroundColor(wyrmScopedColours.mute)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(wyrmScopedColours.rule))
                    }.buttonStyle(WSPressStyle())
                    Button { saveCustom() } label: {
                        Text("Save").font(.androidWyrm(15.5, .semibold)).foregroundColor(wyrmScopedColours.onInk)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(wyrmScopedColours.ink))
                    }.buttonStyle(WSPressStyle()).disabled(customAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(22)
            .frame(maxWidth: 440)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(wyrmScopedColours.paper))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(wyrmScopedColours.rule))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
            .padding(24)
            .modifier(WyrmAboveKeys())
        }
    }

    /// Saved arenas (OM, 2026-11-07): tap plays; touch and hold selects, then
    /// tap adds or drops; Delete removes every selected one.
    private var savedSection: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                if savedPicked.isEmpty {
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { showSaved.toggle() } } label: {
                        HStack {
                            sectionLabel("SAVED ARENAS · \(saved.count)")
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .rotationEffect(.degrees(showSaved ? 90 : 0)).foregroundColor(wyrmScopedColours.ink)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else {
                    Text("\(savedPicked.count) selected").font(.androidWyrm(14, .bold)).foregroundColor(wyrmScopedColours.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(savedPicked.count == saved.count ? "None" : "All") {
                        savedPicked = savedPicked.count == saved.count ? [] : Set(saved)
                    }.font(.androidWyrm(13, .semibold)).foregroundColor(wyrmScopedColours.link)
                    Button("Cancel") { savedPicked = [] }.font(.androidWyrm(13, .semibold)).foregroundColor(wyrmScopedColours.link)
                    Button {
                        let drop = savedPicked
                        savedArenaEndpoints = saved.filter { !drop.contains($0) }.joined(separator: ";")
                        savedPicked = []
                    } label: {
                        Text("Delete").font(.androidWyrm(13, .bold)).foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(ATheme.badge))
                    }.buttonStyle(WSPressStyle())
                }
            }
            if showSaved {
                if savedPicked.isEmpty {
                    Text("Touch and hold an arena to select it.").font(.androidWyrm(11.5)).foregroundColor(wyrmScopedColours.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(saved, id: \.self) { endpoint in
                    if let arena = WyrmArena.custom(endpoint) { savedRow(arena) }
                }
            }
        }
        .padding(14).background(wyrmScopedColours.card.opacity(0.9)).cornerRadius(15)
    }

    private func savedRow(_ arena: WyrmArena) -> some View {
        let picked = savedPicked.contains(arena.endpoint)
        let chosen = selection == arena.endpoint
        return HStack(spacing: 12) {
            if !savedPicked.isEmpty {
                ZStack {
                    Circle().fill(picked ? ATheme.badge : Color.clear)
                    Circle().stroke(picked ? ATheme.badge : wyrmScopedColours.quiet, lineWidth: 1.5)
                    if picked { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.white) }
                }.frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Custom arena").font(.androidWyrm(15, .bold)).foregroundColor(wyrmScopedColours.ink)
                Text(arena.endpoint).font(.androidWyrm(10.5)).foregroundColor(wyrmScopedColours.quiet)
            }
            Spacer()
            Text(latencyText(arena)).font(.androidWyrm(12, .bold)).foregroundColor(latencyColor(arena))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(picked ? wyrmScopedColours.ink.opacity(0.08) : wyrmScopedColours.card.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(picked ? ATheme.badge : (chosen ? wyrmScopedColours.ink : wyrmScopedColours.rule), lineWidth: picked || chosen ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onTapGesture {
            if savedPicked.isEmpty { selection = arena.endpoint; presentation.wrappedValue.dismiss() }
            else if picked { savedPicked.remove(arena.endpoint) } else { savedPicked.insert(arena.endpoint) }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            savedPicked.insert(arena.endpoint)
        }
    }

    @ViewBuilder
    private func pickRow(_ arena: WyrmArena, tag: String? = nil) -> some View {
        if pickerStyle == 1 { detailCard(arena, tag: tag) } else { arenaRow(arena, tag: tag) }
    }

    /* Details (OM, 2026-10-30): one card per arena with its live minimap, the
       top 10, its address and players, from the arena monitor. Arenas come
       from slither's directory only; the monitor adds to them. */
    private func detailCard(_ arena: WyrmArena, tag: String? = nil) -> some View {
        let wyrmScopedColours = WyrmThemeColours(palette: tag == nil ? WyrmThemeStore.shared.palette : WyrmThemeStore.shared.palette.heroView(slot: 1))
        let chosen = (selection.isEmpty ? services.recommendedArena?.endpoint : selection) == arena.endpoint
        let live = events.monitor[arena.endpoint]
        let top = live?.top ?? []
        let directoryCountry = services.countryCode(for: arena.address)
        let country = directoryCountry.isEmpty ? (live?.country ?? "").uppercased() : directoryCountry
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                WyrmArenaMinimapView(map: live?.minimap).frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(arena.number == 0 ? "Custom arena" : "Arena \(arena.code)").font(.androidWyrm(17, .heavy)).foregroundColor(wyrmScopedColours.ink)
                        if arena.number > 0 { WyrmArenaCountryBadge(country: country) }
                    }
                    if let tag {
                        Text(tag).font(.androidWyrm(10, .bold)).foregroundColor(wyrmScopedColours.live)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(wyrmScopedColours.live.opacity(0.12)).clipShape(Capsule())
                    }
                    Text(arena.endpoint).font(.system(size: 12, design: .monospaced)).foregroundColor(wyrmScopedColours.mute).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(wyrmScopedColours.well))
                    HStack(spacing: 0) {
                        Text(Int64(live?.players ?? arena.players).wyrmFormatted).font(.androidWyrm(15, .heavy)).foregroundColor(wyrmScopedColours.ink)
                        Text(" playing").font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                        Spacer(minLength: 6)
                        Text(latencyText(arena)).font(.androidWyrm(12, .bold)).foregroundColor(latencyColor(arena))
                    }
                    Button { selection = arena.endpoint; presentation.wrappedValue.dismiss() } label: {
                        Text(chosen ? "Selected" : "Choose").font(.androidWyrm(13, .heavy))
                            .foregroundColor(chosen ? .white : wyrmScopedColours.onInk)
                            .padding(.horizontal, 16).frame(height: 34)
                            .background(Capsule().fill(chosen ? wyrmScopedColours.live : wyrmScopedColours.ink))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            Rectangle().fill(wyrmScopedColours.rule).frame(height: 1)
            if top.isEmpty {
                Text("The live board is not watched for this arena yet.").font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOP 10").font(.androidWyrm(10, .bold)).tracking(0.8).foregroundColor(wyrmScopedColours.quiet)
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<2, id: \.self) { column in
                            VStack(spacing: 3) {
                                ForEach(top.filter { $0.rank > column * 5 && $0.rank <= column * 5 + 5 }) { line in
                                    HStack(spacing: 0) {
                                        Text("\(line.rank)").font(.androidWyrm(12, .heavy)).foregroundColor(wyrmScopedColours.quiet).frame(width: 18, alignment: .leading)
                                        Text(line.name.isEmpty ? "—" : line.name).font(.androidWyrm(12.5, .semibold)).foregroundColor(wyrmScopedColours.ink).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(line.score.wyrmFormatted).font(.androidWyrm(12.5, .heavy)).foregroundColor(wyrmScopedColours.ink)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .background(wyrmScopedColours.card.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(chosen ? wyrmScopedColours.live : wyrmScopedColours.rule, lineWidth: chosen ? 2 : 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.androidWyrm(10, .bold)).tracking(0.8).foregroundColor(wyrmScopedColours.quiet)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12).padding(.bottom, 3)
    }
    private func arenaRow(_ arena: WyrmArena, tag: String? = nil) -> some View {
        let wyrmScopedColours = WyrmThemeColours(palette: tag == nil ? WyrmThemeStore.shared.palette : WyrmThemeStore.shared.palette.heroView(slot: 1))
        return Button { selection = arena.endpoint; presentation.wrappedValue.dismiss() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(arena.number == 0 ? "Custom arena" : "Arena \(arena.code)").font(.androidWyrm(15, .bold))
                        if arena.number > 0 { WyrmArenaCountryBadge(country: services.countryCode(for: arena.address)) }
                        if let tag {
                            Text(tag).font(.androidWyrm(10, .bold)).foregroundColor(wyrmScopedColours.live)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(wyrmScopedColours.live.opacity(0.12)).clipShape(Capsule())
                        }
                    }
                    Text(arena.endpoint).font(.androidWyrm(10.5)).foregroundColor(wyrmScopedColours.quiet)
                }
                Spacer()
                Text(latencyText(arena)).font(.androidWyrm(12, .bold)).foregroundColor(latencyColor(arena))
            }.foregroundColor(wyrmScopedColours.ink).padding(14).background(wyrmScopedColours.card.opacity(0.9)).cornerRadius(15)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke((selection.isEmpty ? services.recommendedArena?.endpoint : selection) == arena.endpoint ? wyrmScopedColours.ink : wyrmScopedColours.rule, lineWidth: (selection.isEmpty ? services.recommendedArena?.endpoint : selection) == arena.endpoint ? 2 : 1))
        }.buttonStyle(.plain)
    }
    private func saveCustom() {
        guard let arena = WyrmArena.custom(customAddress) else { addressError = true; return }
        addressError = false
        var entries = saved
        entries.removeAll { $0 == arena.endpoint }
        entries.insert(arena.endpoint, at: 0)
        savedArenaEndpoints = entries.prefix(20).joined(separator: ";")
        showSaved = true
        WyrmKeyboardController.shared.dismiss()
        withAnimation { showAdd = false }
        customAddress = ""
        selection = arena.endpoint
        Task { customLatencies[arena.endpoint] = await services.measureCustomArena(arena.endpoint) ?? -1 }
    }

    private func latencyText(_ arena: WyrmArena) -> String {
        guard let value = arena.number == 0 ? customLatencies[arena.endpoint] : services.arenaLatencies[arena.id] else {
            return arena.players > 0 ? "\(arena.players) playing" : "—"
        }
        return value > 0 ? "\(value)ms" : "Unavailable"
    }
    private func latencyColor(_ arena: WyrmArena) -> Color {
        guard let value = arena.number == 0 ? customLatencies[arena.endpoint] : services.arenaLatencies[arena.id] else { return wyrmScopedColours.quiet }
        if value <= 0 { return Color(red: 0.75, green: 0.25, blue: 0.22) }
        let values = services.arenaLatencies.values.filter { $0 > 0 }
        let low = values.min() ?? value, high = values.max() ?? value
        let ratio = high == low ? 0 : Double(value - low) / Double(high - low)
        return Color(red: 0.18 + 0.68 * ratio, green: 0.68 - 0.45 * ratio, blue: 0.27 - 0.08 * ratio)
    }
}

private struct WyrmSocialRoot: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let open: (WyrmDesignRoute) -> Void
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                WyrmScreenHeader(kicker: "Arena", title: "Social")
                // Trails is a tab of its own now (OM, 2026-10-04): no card here.
                WyrmPaperCard {
                    WyrmListRow(title: "Leaderboard", detail: leaderboardDetail, icon: "trophy.fill") { open(.leaderboard) }
                    WyrmListRow(title: "Messages", detail: messageDetail, icon: "message.fill", tint: wyrmScopedColours.link,
                                badge: services.conversations.reduce(0) { $0 + $1.unreadCount }) { open(.messages) }
                    WyrmListRow(title: "Global chat",
                                detail: services.globalUnread > 0 ? "\(services.globalUnread) new · last 24 hours" : "Everyone in Wyrm · last 24 hours",
                                icon: "bubble.left.and.bubble.right.fill", tint: wyrmScopedColours.link,
                                badge: services.globalUnread) { open(.globalChat) }
                    if WyrmVoiceFeature.enabled {
                        WyrmListRow(title: "Voice rooms", detail: unread(["voice_invite"]) > 0 ? "\(unread(["voice_invite"])) invitation(s) · \(services.liveRooms.count) live" : "\(services.liveRooms.count) live",
                                    icon: "mic.fill", tint: wyrmScopedColours.live, badge: unread(["voice_invite"])) { open(.voice) }
                    }
                    WyrmListRow(title: "Connections", detail: unread(["follow"]) > 0 ? "\(unread(["follow"])) new · \(account.player?.followerCount ?? 0) followers" : "\(account.player?.followerCount ?? 0) followers · \(account.player?.followingCount ?? 0) following",
                                icon: "person.2", badge: unread(["follow"])) { open(.people("connections")) }
                    WyrmListRow(title: "Your profile", detail: account.player?.handle ?? "", icon: "person.crop.circle.fill") { open(.profile("")) }
                }
                WyrmSectionLabel("Recently played with")
                WyrmHeroCard(slot: 2) { wyrmScopedColours in
WyrmPaperCard { WyrmEmptyPanel(title: "Your arena circle starts here", note: "Players from real conversations and follows appear here.") }
}
                Spacer().frame(height: 102)
            }
        }.refreshable {
            await services.refreshSocial()
            if WyrmTrailsFeature.enabled { await WyrmTrailsStore.shared.refresh() }
        }
    }
    private var messageDetail: String { let unread = services.conversations.reduce(0) { $0 + $1.unreadCount }; return unread == 0 ? "No unread messages" : "\(unread) unread" }
    private func unread(_ kinds: Set<String>) -> Int { services.alerts.filter { !$0.read && kinds.contains($0.kind) }.count }
    private var leaderboardDetail: String { guard let id = account.player?.id, let rank = services.killLeaders.firstIndex(where: { $0.id == id }) else { return "Score and kills" }; return "You are \(rank + 1) by kills" }
}

/// Alerts, opened from Play's bell (OM, 2026-10-04): a page with Back.
struct WyrmAlertsPage: View {
    @ObservedObject var services: WyrmServiceStore
    let engine: WyrmShellStore
    let open: (WyrmDesignRoute) -> Void
    let close: () -> Void
    var body: some View {
        WyrmAlertsRoot(services: services, engine: engine, open: open, close: close)
    }
}

/// The bell on Play: a card squircle (the avatar's own shape, size x 0.3
/// continuous corners; OM, 2026-10-04) with the unread count.
struct WyrmAlertsBellButton: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let unread: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(wyrmScopedColours.ink)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 36 * 0.3, style: .continuous).fill(wyrmScopedColours.card))
                    .overlay(RoundedRectangle(cornerRadius: 36 * 0.3, style: .continuous).stroke(wyrmScopedColours.rule, lineWidth: 1))
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(wyrmScopedColours.onInk)
                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                        .background(wyrmScopedColours.badge).clipShape(Capsule())
                        .offset(x: 5, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unread > 0 ? "Alerts, \(unread) new" : "Alerts")
    }
}

private struct WyrmAlertsRoot: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var services: WyrmServiceStore
    let engine: WyrmShellStore
    let open: (WyrmDesignRoute) -> Void
    var close: (() -> Void)? = nil
    @ObservedObject private var prefs = WyrmNotificationPrefs.shared
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if let close = close {
                    HStack {
                        Button(action: close) {
                            HStack(spacing: 5) { Image(systemName: "chevron.left"); Text("Back") }
                                .font(.androidWyrm(14, .semibold)).foregroundColor(wyrmScopedColours.link)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(height: 52)
                }
                WyrmScreenHeader(kicker: "Inbox", title: "Alerts", trailing: AnyView(Button("Read all") { Task { await services.markAllRead() } }.font(.androidWyrm(12, .semibold)).foregroundColor(wyrmScopedColours.link)))
                if services.alerts.isEmpty {
                    WyrmPaperCard { WyrmEmptyPanel(title: services.loading ? "Checking Wyrm…" : "All caught up", note: services.loading ? "Looking for real invites and notices." : "Nothing new right now.") }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(services.alerts.filter { prefs.allows($0.kind) }) { alert in WyrmAlertCard(alert: alert, services: services, engine: engine, open: open) }
                    }
                }
                Spacer().frame(height: 102)
            }
        }.refreshable { await services.refreshAlerts() }
    }
}

private struct WyrmAlertCard: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let alert: WyrmServiceAlert
    @ObservedObject var services: WyrmServiceStore
    let engine: WyrmShellStore
    let open: (WyrmDesignRoute) -> Void
    @State private var showingMenu = false
    @State private var copied = false
    /// Only the facts a player reads, named as Android names them
    /// (`alertMeta`); ids, "previous" values and other raw fields never show (OM).
    private var shownMeta: [(key: String, value: String)] {
        func value(_ key: String) -> String? {
            guard let raw = alert.meta[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "null" else { return nil }
            return raw
        }
        var rows: [(key: String, value: String)] = []
        // Trail and support alerts already say who in their own words.
        if !["trail_like", "trail_reply", "support"].contains(alert.kind), let from = value("actorName") { rows.append(("From", from)) }
        if let organizer = value("organizer") { rows.append(("Organizer", organizer)) }
        if let starts = value("startsAt") { rows.append(("Starts", String(starts.replacingOccurrences(of: "T", with: " ").prefix(16)))) }
        if let address = value("address") { rows.append(("Server", address)) }
        if let version = value("version") { rows.append(("Version", version)) }
        if let number = value("value") ?? value("rank"), Int64(number) != nil { rows.append(("Value", number)) }
        return rows.sorted { $0.key < $1.key }
    }
    var body: some View {
 WyrmHeroCard(slot: 2, enabled: alert.kind == "event") { wyrmScopedColours in
        VStack(alignment: .leading, spacing: 11) {
            HStack { Circle().fill(alert.read ? Color.clear : wyrmScopedColours.live).frame(width: 7, height: 7); Text(WyrmAlertRouting.label(alert.kind)).font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(wyrmScopedColours.live); Spacer(); Text(relative(alert.createdAt)).font(.androidWyrm(10.5)).foregroundColor(wyrmScopedColours.quiet); Button { showingMenu = true } label: { Image(systemName: "ellipsis").foregroundColor(wyrmScopedColours.quiet).frame(width: 28, height: 28) }.buttonStyle(.plain) }
            Text(alert.title).font(.androidWyrm(18, .bold))
            // Full Markdown, block by block: Enters, spaces, lists, tables…
            if !alert.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                WyrmMarkdown(source: alert.body, size: 12.5)
            }
            ForEach(shownMeta, id: \.key) { pair in HStack { Text(pair.key).foregroundColor(wyrmScopedColours.quiet); Spacer(); Text(pair.value).fontWeight(.semibold) }.font(.androidWyrm(11.5)) }
            if let action = WyrmAlertRouting.actionTitle(alert.kind), WyrmAlertRouting.route(for: alert) != nil {
                Text("\(action) ›").font(.androidWyrm(12.5, .semibold)).foregroundColor(wyrmScopedColours.link)
            }
            if alert.kind == "event", let address = eventAddress { eventActions(address) }
        }.padding(16).background(wyrmScopedColours.card.opacity(0.92)).cornerRadius(17).overlay(RoundedRectangle(cornerRadius: 17).stroke(wyrmScopedColours.rule)).padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                services.markRead(alert)
                if let route = WyrmAlertRouting.route(for: alert) { open(route) }
            }
            .contextMenu {
                Button(alert.read ? "Mark as unread" : "Mark as read") { Task { await services.setRead(alert, read: !alert.read) } }
                Button("Delete notification", role: .destructive) { Task { await services.delete(alert) } }
            }
            .confirmationDialog(alert.title, isPresented: $showingMenu) {
                Button(alert.read ? "Mark unread" : "Mark as read") { Task { await services.setRead(alert, read: !alert.read) } }
                Button("Delete notification", role: .destructive) { Task { await services.delete(alert) } }
            }
    
 }
}
    private func relative(_ raw: String) -> String { raw.isEmpty ? "" : String(raw.prefix(10)) }

    // MARK: Battledome (OM, 2026-10-01)

    private var eventAddress: String? {
        guard let raw = alert.meta["address"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "null" else { return nil }
        return raw
    }

    private var eventStart: Date? {
        guard let raw = alert.meta["startsAt"], !raw.isEmpty else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return full.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// "Starts in 04:12", from the start time every second; nil once it has begun.
    private func countdown(_ now: Date) -> String? {
        guard let start = eventStart, start > now else { return nil }
        let left = Int(ceil(start.timeIntervalSince(now)))
        let days = left / 86_400, hours = (left % 86_400) / 3_600, minutes = (left % 3_600) / 60, seconds = left % 60
        if days > 0 { return "Starts in \(days)d \(hours)h" }
        if hours > 0 { return String(format: "Starts in %d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "Starts in %02d:%02d", minutes, seconds)
    }

    /// Copy IP and Play. Play enters this event's arena (not the lobby's
    /// selection); until the start it is a live countdown.
    private func eventActions(_ address: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let waiting = countdown(context.date)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = address
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Text(copied ? "Copied" : "Copy IP").font(.androidWyrm(14, .semibold)).foregroundColor(wyrmScopedColours.ink)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().stroke(wyrmScopedColours.rule, lineWidth: 1.2))
                }.buttonStyle(.plain)
                Button {
                    if let waiting {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        engine.toast = "The event \(waiting.lowercased())"
                    } else {
                        services.markRead(alert)
                        engine.enterLobby(name: engine.nickname, address: address)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: waiting == nil ? "play.fill" : "timer").font(.system(size: 13, weight: .bold))
                        Text(waiting ?? "Play").font(.androidWyrm(14, .bold)).monospacedDigit()
                    }
                    .foregroundColor(waiting == nil ? wyrmScopedColours.onInk : wyrmScopedColours.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(waiting == nil ? wyrmScopedColours.ink : wyrmScopedColours.well))
                }.buttonStyle(.plain)
                .layoutPriority(1.2)
            }
        }
    }
}
