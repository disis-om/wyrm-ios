import SwiftUI

struct WyrmDesignMain: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    @ObservedObject private var theme = WyrmThemeStore.shared
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

    init(engine: WyrmShellStore, account: WyrmAccountStore, services: WyrmServiceStore,
         initialTab: WyrmDesignTab, initialRoute: WyrmDesignRoute? = nil) {
        self.engine = engine
        self.account = account
        self.services = services
        _tab = State(initialValue: initialTab)
        _routes = State(initialValue: initialRoute.map { [$0] }?.filter { WyrmTrailsFeature.shows($0) } ?? [])
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
                        (route == .about ? WyrmNight.sky : ATheme.paper).ignoresSafeArea()
                        WyrmDetailHost(route: route, engine: engine, account: account, services: services, close: { pop(route) }, open: open)
                            .padding(.top, proxy.safeAreaInsets.top)
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background((route == .about ? WyrmNight.sky : ATheme.paper).ignoresSafeArea())
                        // Only the container edges: the keyboard's safe area must
                        // still lift composers and input boxes above the keys.
                        .ignoresSafeArea(.container)
                        .zIndex(Double(30 + index))
                        .transition(.wyrmCinematicPush)
                        .allowsHitTesting(index == routes.count - 1)
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
                if !engine.toast.isEmpty {
                    Text(engine.toast)
                        .font(.androidWyrm(11.5, .semibold)).foregroundColor(ATheme.onInk).lineLimit(2)
                        .padding(.horizontal, 14).padding(.vertical, 10).background(ATheme.ink).cornerRadius(12)
                        .padding(.horizontal, 20).padding(.bottom, routes.isEmpty ? 84 : 18).zIndex(50)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }.ignoresSafeArea(.container)
            // A theme change redraws every screen with the new palette. Tab and
            // route state live on this view, so the page the player is on stays open.
            .id(theme.identity)
        }
        .foregroundColor(ATheme.ink)
        .background(ATheme.paper.ignoresSafeArea())
        // The About page is a night page: light status bar over it.
        .preferredColorScheme(theme.palette.dark || routes.last == .about ? .dark : .light)
        // Checked once a launch; a newer build raises the prompt above.
        .task { await updates.check() }
        // The live inbox (OM, 2026-10-01): new alerts, DMs and replies land at once.
        // A quiet look stays as a fallback: every 15 s on Alerts, every 45 s elsewhere.
        .task {
            WyrmLiveInbox.shared.onInbox = { kind in Task { await handleInbox(kind) } }
            WyrmLiveInbox.shared.start(token: account.sessionToken)
            var quiet = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                quiet += 1
                if routes.last == .alerts || quiet % 3 == 0 { await pollAlerts() }
            }
        }
        .onDisappear { WyrmLiveInbox.shared.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            WyrmLiveInbox.shared.start(token: account.sessionToken)
            Task {
                await pollAlerts()
                // Back in the foreground: a reply may have come while away.
                await support.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            WyrmLiveInbox.shared.stop()
        }
        // Where the player is, for a crash or problem report.
        .onChange(of: routes) { value in WyrmCrashWatch.shared.screen = value.last?.id ?? tab.rawValue }
        .onChange(of: tab) { value in
            if routes.isEmpty { WyrmCrashWatch.shared.screen = value.rawValue }
            // Leaving the Skin tab without Wear drops a tried skin.
            if value != .skin { trial.end() }
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
        let kinds: Set<String> = ["voice_invite", "follow"]
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
            case .skin: WyrmSkinRoot(engine: engine)
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
            .tint(ATheme.ink)
            .tabBarMinimizeBehavior(.onScrollDown)
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

    private func open(_ value: WyrmDesignRoute) {
        // Trails are paused for the beta: no way into the feed, a trail or the studio.
        guard WyrmTrailsFeature.shows(value) else { return }
        guard routes.last != value else { return }
        withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.84, blendDuration: 0.12)) { routes.append(value) }
    }

    private func pop(_ value: WyrmDesignRoute) {
        guard let index = routes.lastIndex(of: value) else { return }
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.1)) {
            routes.removeSubrange(index..<routes.endIndex)
        }
    }
}

private struct WyrmPlayRoot: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let open: (WyrmDesignRoute) -> Void
    @State private var nickname = ""
    @FocusState private var nameFocused: Bool
    @State private var arena = ""
    @State private var userSelectedArena = false
    @State private var showArenas = false
    @State private var lastHandledRefusal: UInt64 = 0
    @AppStorage("wyrm.ios.arena.recent") private var recentArenaEndpoints = ""
    @AppStorage("wyrm.ios.arena.saved") private var savedArenaEndpoints = ""

    private var nearest: WyrmArena? {
        if userSelectedArena,
           let selected = services.arenas.first(where: { $0.endpoint == arena }) { return selected }
        if userSelectedArena, savedArenaEndpoints.split(separator: ";").contains(Substring(arena)),
           let selected = WyrmArena.custom(arena) { return selected }
        return services.recommendedArena
    }
    /// Android's `playControlsLabel`: steering style and hand, e.g. "Joystick · Right".
    private var controls: String {
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Wyrm").font(.androidWyrm(10.5, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                        TextField("Wyrm Player", text: $nickname).font(.androidWyrm(29, .bold)).textInputAutocapitalization(.never).disableAutocorrection(true)
                            .focused($nameFocused).submitLabel(.done).onSubmit(commitName)
                            .onChange(of: nameFocused) { focused in if !focused { commitName() } }
                        Text("Tap to rename in-game name").font(.androidWyrm(9.5)).foregroundColor(ATheme.quiet.opacity(0.55))
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

                WyrmPaperCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) { Circle().fill(nearest == nil ? ATheme.quiet : ATheme.live).frame(width: 6, height: 6); Text(nearest == nil ? "ARENA DIRECTORY" : "LIVE ARENA").font(.androidWyrm(10.5, .bold)).tracking(0.8).foregroundColor(nearest == nil ? ATheme.quiet : ATheme.live) }
                        HStack(alignment: .bottom) {
                            Text(nearest.map { $0.number == 0 ? "Custom arena" : "Arena \($0.code)" } ?? "Pick a server").font(.androidWyrm(21, .bold)).lineLimit(1)
                            Spacer()
                            Text(nearest == nil ? "" : "\(nearest!.players) players").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
                        }.padding(.top, 11)
                        Text(nearest?.endpoint ?? "Choose a live arena or enter an address.").font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).padding(.top, 3)
                        GeometryReader { geometry in ZStack(alignment: .leading) { Capsule().fill(ATheme.track); Capsule().fill(ATheme.ink).frame(width: geometry.size.width * min(1, CGFloat(nearest?.players ?? 0) / 2000)) } }.frame(height: 4).padding(.top, 13)
                        HStack(spacing: 9) {
                            Button { enterOriginalLobby() } label: { Text("Enter lobby").font(.androidWyrm(15, .bold)).foregroundColor(ATheme.onInk).frame(maxWidth: .infinity).frame(height: 46).background(WyrmGlass.native ? Color.clear : (nearest == nil ? ATheme.ink.opacity(0.35) : ATheme.ink)).cornerRadius(11) }.modifier(WyrmGlassButtonModifier(prominent: true, radius: 11, fallback: WSPressStyle())).disabled(nearest == nil)
                            Button { showArenas = true } label: { Image(systemName: "globe.asia.australia.fill").foregroundColor(ATheme.mute).frame(width: 46, height: 46).overlay(RoundedRectangle(cornerRadius: 11).stroke(ATheme.rule, lineWidth: WyrmGlass.native ? 0 : 1)) }.modifier(WyrmGlassButtonModifier(radius: 11, fallback: WSPressStyle()))
                        }.padding(.top, 16)
                    }.padding(18)
                    Rectangle().fill(ATheme.rule).frame(height: 1)
                    HStack(spacing: 0) {
                        WyrmMetric(label: "BEST SCORE", value: (account.player?.highestScore ?? Int64(engine.score)).wyrmFormatted)
                        Rectangle().fill(ATheme.rule).frame(width: 1, height: 51)
                        WyrmMetric(label: "TOTAL KILLS", value: (account.player?.kills ?? Int64(engine.kills)).wyrmFormatted)
                    }
                }

                WyrmSectionLabel("Loadout")
                WyrmPaperCard {
                    WyrmLoadoutRow(title: "Food", value: food, first: true, leading: AnyView(WyrmFoodWell())) { open(.playFood) }
                    WyrmLoadoutRow(title: "Controls", value: controls, leading: AnyView(WyrmLoadoutIcon(symbol: "gamecontroller"))) { open(.playControls) }
                    WyrmLoadoutRow(title: "Mode", value: "", leading: AnyView(WyrmLoadoutIcon(symbol: "scope"))) { open(.playModes) }
                    WyrmNearOriginalRow()
                }

                WyrmSectionLabel("Rooms & team")
                WyrmPaperCard {
                    WyrmListRow(title: "Voice rooms", detail: services.liveRooms.first?.name ?? "Own and community rooms", value: "\(services.liveRooms.count) live", icon: "mic.fill", tint: ATheme.live) { open(.voice) }
                    WyrmListRow(title: "Team mode", detail: "Original engine team layer", value: "Open", icon: "person.3.fill", tint: ATheme.live) { open(.team) }
                }
                Spacer().frame(height: 102)
            }
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
                get: { userSelectedArena ? arena : services.recommendedArena?.endpoint ?? "" },
                set: { arena = $0; userSelectedArena = true }))
        }
    }

    private func enterOriginalLobby() {
        guard let selected = nearest else { return }
        arena = selected.endpoint
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
        let clean = String(nickname.prefix(24))
        nickname = clean
        guard clean != engine.nickname else { return }
        engine.setNickname(clean)
        if !clean.isEmpty, clean != account.player?.ingameName { WyrmGameSync.shared.syncIngameName(clean) }
    }
}

/// Android's `LoadoutRow`: a 26 pt well, the title, its value and a chevron.
struct WyrmLoadoutRow: View {
    let title: String
    let value: String
    var first = false
    var leading: AnyView? = nil
    let onOpen: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(ATheme.rowRule).frame(height: 1) }
            Button(action: onOpen) {
                HStack(spacing: 0) {
                    if let leading { leading; Spacer().frame(width: 12) }
                    Text(title).font(.androidWyrm(15.5)).foregroundColor(ATheme.ink).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !value.isEmpty {
                        Text(value).font(.androidWyrm(14)).foregroundColor(ATheme.quiet).lineLimit(1)
                        Spacer().frame(width: 6)
                    }
                    Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron)
                }
                .padding(.horizontal, 14).frame(height: 52).contentShape(Rectangle())
            }.buttonStyle(WSPressStyle())
        }
    }
}

struct WyrmLoadoutIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundColor(ATheme.mute)
            .frame(width: 26, height: 26).background(ATheme.well)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WyrmMetric: View {
    let label: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 2) { Text(label).font(.androidWyrm(9.5, .bold)).tracking(0.8).foregroundColor(ATheme.quiet); Text(value).font(.androidWyrm(17, .bold)) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 12) }
}

private struct WyrmArenaPicker: View {
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

    private var saved: [String] { savedArenaEndpoints.split(separator: ";").map(String.init) }
    private var recent: [String] { recentArenaEndpoints.split(separator: ";").map(String.init) }

    private var filtered: [WyrmArena] {
        let live = services.arenas.filter(\.active)
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
            services.arenas.first(where: { $0.endpoint == endpoint && $0.active })
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
        return services.arenas.filter(\.active)
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
                    VStack(alignment: .leading, spacing: 2) { Text("LIVE DIRECTORY").font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.live); Text("Pick a server").font(.androidWyrm(27, .bold)) }
                    Spacer()
                    Button { showAdd.toggle() } label: { Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundColor(ATheme.ink).frame(width: 36, height: 36).background(WyrmGlass.native ? Color.clear : ATheme.card).clipShape(Circle()) }
                        .modifier(WyrmGlassCircleButton()).accessibilityLabel("Add custom arena IP")
                    Button { presentation.wrappedValue.dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundColor(ATheme.ink)
                            .frame(width: 36, height: 36).background(WyrmGlass.native ? Color.clear : ATheme.card).clipShape(Circle())
                    }.modifier(WyrmGlassCircleButton()).accessibilityLabel("Close")
                }.padding(20)
                HStack { Image(systemName: "magnifyingglass"); TextField("Arena code or IP", text: $search).textInputAutocapitalization(.never).disableAutocorrection(true) }
                    .font(.androidWyrm(13)).padding(.horizontal, 14).frame(height: 44).background(ATheme.card.opacity(0.82)).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)).padding(.horizontal, 16)
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 9, pinnedViews: []) {
                        if showAdd {
                            HStack(spacing: 8) {
                                TextField("IPv4 address:port", text: $customAddress)
                                    .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).disableAutocorrection(true)
                                Button("Save") { saveCustom() }.font(.androidWyrm(13, .bold))
                            }.font(.androidWyrm(13)).padding(14).background(ATheme.card).cornerRadius(14)
                            if addressError { Text("Enter a valid IPv4 address and port (1–65535).")
                                .font(.androidWyrm(11)).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        if let best = bestArena {
                            sectionLabel("BEST FOR YOU")
                            arenaRow(best, tag: "Lowest ping")
                        }
                        if !recentRows.isEmpty {
                            sectionLabel("RECENTLY JOINED")
                            ForEach(recentRows) { arena in arenaRow(arena) }
                        }
                        sectionLabel(search.isEmpty ? "ARENAS" : "SEARCH RESULTS")
                        ForEach(showAll || !search.isEmpty ? ranked : Array(ranked.prefix(10))) { arena in arenaRow(arena) }
                        if search.isEmpty && ranked.count > 10 {
                            Button(showAll ? "Show less" : "See all") { withAnimation { showAll.toggle() } }
                                .font(.androidWyrm(13, .bold)).frame(maxWidth: .infinity).padding(14)
                        }
                        if !saved.isEmpty {
                            DisclosureGroup(isExpanded: $showSaved) {
                                ForEach(saved, id: \.self) { endpoint in
                                    if let arena = WyrmArena.custom(endpoint) { arenaRow(arena) }
                                }
                            } label: { sectionLabel("SAVED ARENAS · \(saved.count)") }
                                .tint(ATheme.ink).padding(14).background(ATheme.card.opacity(0.9)).cornerRadius(15)
                        }
                        if filtered.isEmpty && recentRows.isEmpty && saved.isEmpty {
                            Text("No active arenas right now. Try refreshing or add a custom IP.")
                                .font(.androidWyrm(12)).foregroundColor(ATheme.quiet).padding(20)
                        }
                    }.padding(16)
                }
            }
        }
        .task {
            await services.refreshArenasLive()
            await services.measurePickerArenas(preferredEndpoints: [selection] + recent)
            if let selected = WyrmArena.custom(selection), selected.number == 0 {
                customLatencies[selected.endpoint] = await services.measureCustomArena(selected.endpoint) ?? -1
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await services.refreshArenasLive()
            }
        }
        .onDisappear { WyrmArenaProbeGate.shared.cancelProbes() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.androidWyrm(10, .bold)).tracking(0.8).foregroundColor(ATheme.quiet)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12).padding(.bottom, 3)
    }
    private func arenaRow(_ arena: WyrmArena, tag: String? = nil) -> some View {
        Button { selection = arena.endpoint; presentation.wrappedValue.dismiss() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(arena.number == 0 ? "Custom arena" : "Arena \(arena.code)").font(.androidWyrm(15, .bold))
                        if let tag {
                            Text(tag).font(.androidWyrm(10, .bold)).foregroundColor(ATheme.live)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(ATheme.live.opacity(0.12)).clipShape(Capsule())
                        }
                    }
                    Text(arena.endpoint).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet)
                }
                Spacer()
                Text(latencyText(arena)).font(.androidWyrm(12, .bold)).foregroundColor(latencyColor(arena))
            }.foregroundColor(ATheme.ink).padding(14).background(ATheme.card.opacity(0.9)).cornerRadius(15)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke((selection.isEmpty ? services.recommendedArena?.endpoint : selection) == arena.endpoint ? ATheme.ink : ATheme.rule, lineWidth: (selection.isEmpty ? services.recommendedArena?.endpoint : selection) == arena.endpoint ? 2 : 1))
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
        showAdd = false
        customAddress = ""
        selection = arena.endpoint
        Task { customLatencies[arena.endpoint] = await services.measureCustomArena(arena.endpoint) ?? -1 }
    }

    private func latencyText(_ arena: WyrmArena) -> String {
        guard let value = arena.number == 0 ? customLatencies[arena.endpoint] : services.arenaLatencies[arena.id] else { return "—" }
        return value > 0 ? "\(value)ms" : "Unavailable"
    }
    private func latencyColor(_ arena: WyrmArena) -> Color {
        guard let value = arena.number == 0 ? customLatencies[arena.endpoint] : services.arenaLatencies[arena.id] else { return ATheme.quiet }
        if value <= 0 { return Color(red: 0.75, green: 0.25, blue: 0.22) }
        let values = services.arenaLatencies.values.filter { $0 > 0 }
        let low = values.min() ?? value, high = values.max() ?? value
        let ratio = high == low ? 0 : Double(value - low) / Double(high - low)
        return Color(red: 0.18 + 0.68 * ratio, green: 0.68 - 0.45 * ratio, blue: 0.27 - 0.08 * ratio)
    }
}

private struct WyrmSocialRoot: View {
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
                    WyrmListRow(title: "Messages", detail: messageDetail, icon: "message.fill", tint: ATheme.link,
                                badge: services.conversations.reduce(0) { $0 + $1.unreadCount }) { open(.messages) }
                    WyrmListRow(title: "Global chat",
                                detail: services.globalUnread > 0 ? "\(services.globalUnread) new · last 24 hours" : "Everyone in Wyrm · last 24 hours",
                                icon: "bubble.left.and.bubble.right.fill", tint: ATheme.link,
                                badge: services.globalUnread) { open(.globalChat) }
                    WyrmListRow(title: "Voice rooms", detail: unread(["voice_invite"]) > 0 ? "\(unread(["voice_invite"])) invitation(s) · \(services.liveRooms.count) live" : "\(services.liveRooms.count) live",
                                icon: "mic.fill", tint: ATheme.live, badge: unread(["voice_invite"])) { open(.voice) }
                    WyrmListRow(title: "Connections", detail: unread(["follow"]) > 0 ? "\(unread(["follow"])) new · \(account.player?.followerCount ?? 0) followers" : "\(account.player?.followerCount ?? 0) followers · \(account.player?.followingCount ?? 0) following",
                                icon: "person.2", badge: unread(["follow"])) { open(.people("connections")) }
                    WyrmListRow(title: "Your profile", detail: account.player?.handle ?? "", icon: "person.crop.circle.fill") { open(.profile("")) }
                }
                WyrmSectionLabel("Recently played with")
                WyrmPaperCard { WyrmEmptyPanel(title: "Your arena circle starts here", note: "Players from real conversations and follows appear here.") }
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
    let unread: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(ATheme.ink)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 36 * 0.3, style: .continuous).fill(ATheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 36 * 0.3, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(ATheme.onInk)
                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                        .background(ATheme.badge).clipShape(Capsule())
                        .offset(x: 5, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unread > 0 ? "Alerts, \(unread) new" : "Alerts")
    }
}

private struct WyrmAlertsRoot: View {
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
                                .font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.link)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(height: 52)
                }
                WyrmScreenHeader(kicker: "Inbox", title: "Alerts", trailing: AnyView(Button("Read all") { Task { await services.markAllRead() } }.font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.link)))
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
        VStack(alignment: .leading, spacing: 11) {
            HStack { Circle().fill(alert.read ? Color.clear : ATheme.live).frame(width: 7, height: 7); Text(WyrmAlertRouting.label(alert.kind)).font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(ATheme.live); Spacer(); Text(relative(alert.createdAt)).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet); Button { showingMenu = true } label: { Image(systemName: "ellipsis").foregroundColor(ATheme.quiet).frame(width: 28, height: 28) }.buttonStyle(.plain) }
            Text(alert.title).font(.androidWyrm(18, .bold))
            // Full Markdown, block by block: Enters, spaces, lists, tables…
            if !alert.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                WyrmMarkdown(source: alert.body, size: 12.5)
            }
            ForEach(shownMeta, id: \.key) { pair in HStack { Text(pair.key).foregroundColor(ATheme.quiet); Spacer(); Text(pair.value).fontWeight(.semibold) }.font(.androidWyrm(11.5)) }
            if let action = WyrmAlertRouting.actionTitle(alert.kind), WyrmAlertRouting.route(for: alert) != nil {
                Text("\(action) ›").font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.link)
            }
            if alert.kind == "event", let address = eventAddress { eventActions(address) }
        }.padding(16).background(ATheme.card.opacity(0.92)).cornerRadius(17).overlay(RoundedRectangle(cornerRadius: 17).stroke(ATheme.rule)).padding(.horizontal, 16)
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
                    Text(copied ? "Copied" : "Copy IP").font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().stroke(ATheme.rule, lineWidth: 1.2))
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
                    .foregroundColor(waiting == nil ? ATheme.onInk : ATheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().fill(waiting == nil ? ATheme.ink : ATheme.well))
                }.buttonStyle(.plain)
                .layoutPriority(1.2)
            }
        }
    }
}
