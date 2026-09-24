import SwiftUI

struct WyrmDesignMain: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    @State private var tab: WyrmDesignTab
    @State private var routes: [WyrmDesignRoute]

    init(engine: WyrmShellStore, account: WyrmAccountStore, services: WyrmServiceStore,
         initialTab: WyrmDesignTab, initialRoute: WyrmDesignRoute? = nil) {
        self.engine = engine
        self.account = account
        self.services = services
        _tab = State(initialValue: initialTab)
        _routes = State(initialValue: initialRoute.map { [$0] } ?? [])
    }

    var body: some View {
        GeometryReader { proxy in
            let tabBarBottomInset = max(14, min(18, proxy.safeAreaInsets.bottom * 0.48))
            ZStack(alignment: .bottom) {
                WyrmPaperBackground()
                Group {
                    switch tab {
                    case .alerts: WyrmAlertsRoot(services: services)
                    case .social: WyrmSocialRoot(account: account, services: services, open: open)
                    case .play: WyrmPlayRoot(engine: engine, account: account, services: services, open: open)
                    case .skin: WyrmSkinRoot(engine: engine)
                    case .settings: WyrmSettingsRoot(engine: engine, account: account, open: open)
                    }
                }
                .id(tab)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .frame(width: proxy.size.width)
                .padding(.top, proxy.safeAreaInsets.top)

                WyrmRootTabBar(selection: $tab, unread: services.unreadCount)
                    .frame(width: proxy.size.width)
                    .padding(.bottom, tabBarBottomInset)
                    .zIndex(10)

                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    ZStack {
                        ATheme.paper.ignoresSafeArea()
                        WyrmDetailHost(route: route, engine: engine, account: account, services: services, close: { pop(route) }, open: open)
                            .padding(.top, proxy.safeAreaInsets.top)
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(ATheme.paper.ignoresSafeArea())
                        .ignoresSafeArea()
                        .zIndex(Double(30 + index))
                        .transition(.wyrmCinematicPush)
                        .allowsHitTesting(index == routes.count - 1)
                }
                if !engine.toast.isEmpty {
                    Text(engine.toast)
                        .font(.androidWyrm(11.5, .semibold)).foregroundColor(.white).lineLimit(2)
                        .padding(.horizontal, 14).padding(.vertical, 10).background(ATheme.ink).cornerRadius(12)
                        .padding(.horizontal, 20).padding(.bottom, routes.isEmpty ? 84 : 18).zIndex(50)
                }
            }.ignoresSafeArea()
        }
        .foregroundColor(ATheme.ink)
        .background(ATheme.paper.ignoresSafeArea())
    }

    private func open(_ value: WyrmDesignRoute) {
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
    @State private var arena = ""
    @State private var userSelectedArena = false
    @State private var showArenas = false
    @State private var lastPlayedName = "Wyrm Player"
    @State private var lastHandledRefusal: UInt64 = 0
    @AppStorage("wyrm.ios.arena.recent") private var recentArenaEndpoints = ""
    @AppStorage("wyrm.ios.arena.saved") private var savedArenaEndpoints = ""

    private var nearest: WyrmArena? {
        if userSelectedArena,
           let selected = services.arenas.first(where: { $0.endpoint == arena }),
           !services.isArenaTainted(selected.endpoint) { return selected }
        if userSelectedArena, savedArenaEndpoints.split(separator: ";").contains(Substring(arena)),
           let selected = WyrmArena.custom(arena), !services.isArenaTainted(selected.endpoint) { return selected }
        return services.recommendedArena
    }
    private var controls: String { engine.settings.first(where: { $0.id == "controls.joystick_mode" })?.displayValue ?? "Joystick" }
    private var food: String { engine.settings.first(where: { $0.id.contains("food_type") })?.displayValue ?? "Original" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Wyrm").font(.androidWyrm(10.5, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                        TextField("Wyrm Player", text: $nickname).font(.androidWyrm(29, .bold)).textInputAutocapitalization(.never).disableAutocorrection(true)
                        Text("Tap to rename in-game name").font(.androidWyrm(9.5)).foregroundColor(ATheme.quiet.opacity(0.55))
                    }
                    Spacer()
                    Button { open(.profile("")) } label: {
                        HStack(spacing: 9) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(account.player?.displayName ?? "Wyrm").font(.androidWyrm(12, .bold))
                                Text(account.player?.handle ?? "").font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet)
                            }
                            WyrmAvatar(initials: account.player?.initials ?? "W", size: 36, url: account.player?.avatarURL ?? "")
                        }.foregroundColor(ATheme.ink)
                    }.buttonStyle(.plain)
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
                            Button { enterOriginalLobby() } label: { Text("Enter lobby").font(.androidWyrm(15, .bold)).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 46).background(nearest == nil ? ATheme.ink.opacity(0.35) : ATheme.ink).cornerRadius(11) }.buttonStyle(.plain).disabled(nearest == nil)
                            Button { showArenas = true } label: { Image(systemName: "globe.asia.australia.fill").foregroundColor(ATheme.mute).frame(width: 46, height: 46).overlay(RoundedRectangle(cornerRadius: 11).stroke(ATheme.rule)) }.buttonStyle(.plain)
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
                    WyrmListRow(title: "Food", value: food, icon: "circle.grid.2x2.fill", tint: ATheme.live) { open(.food) }
                    WyrmListRow(title: "Controls", value: controls, icon: "scope") { open(.controls) }
                    WyrmListRow(title: "Mode", icon: "plus") { open(.modes) }
                }

                WyrmSectionLabel("Rooms & team")
                WyrmPaperCard {
                    WyrmListRow(title: "Voice rooms", detail: services.liveRooms.first?.name ?? "Own and community rooms", value: "\(services.liveRooms.count) live", icon: "mic.fill", tint: ATheme.live) { open(.voice) }
                    WyrmListRow(title: "Team mode", detail: "Original engine team layer", value: "Open", icon: "person.3.fill", tint: ATheme.live) { open(.team) }
                }
                Spacer().frame(height: 102)
            }
        }
        .onAppear { if nickname.isEmpty { nickname = account.player?.arenaName ?? engine.nickname }; if arena.isEmpty { arena = engine.arena } }
        .onChange(of: nearest?.endpoint) { value in if arena.isEmpty, let value { arena = value } }
        .onChange(of: engine.arenaRefusalSequence) { sequence in
            guard sequence > lastHandledRefusal, !engine.refusedArena.isEmpty else { return }
            lastHandledRefusal = sequence
            let refused = engine.refusedArena
            guard let alternate = services.failoverArena(refused: refused) else {
                WyrmDiagnostics.record("arena failover unavailable refused=\(refused)", category: "NETWORK")
                return
            }
            arena = alternate.endpoint
            WyrmDiagnostics.record("arena failover refused=\(refused) alternate=\(alternate.endpoint)", category: "NETWORK")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                engine.playOnline(name: lastPlayedName, address: alternate.endpoint)
            }
        }
        .task {
            while !Task.isCancelled {
                await services.refreshArenasLive()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
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
        lastPlayedName = nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Wyrm Player" : nickname
        engine.enterLobby(name: lastPlayedName, address: selected.endpoint)
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
    private var recentRows: [WyrmArena] {
        recent.compactMap { endpoint in
            services.arenas.first(where: { $0.endpoint == endpoint && $0.active })
                ?? (saved.contains(endpoint) ? WyrmArena.custom(endpoint) : nil)
        }.filter { search.isEmpty || $0.endpoint.contains(search) || $0.title.localizedCaseInsensitiveContains(search) }
    }
    private var ranked: [WyrmArena] { filtered.filter { row in !recent.contains(row.endpoint) } }

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) { Text("LIVE DIRECTORY").font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.live); Text("Pick a server").font(.androidWyrm(27, .bold)) }
                    Spacer()
                    Button { showAdd.toggle() } label: { Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).frame(width: 36, height: 36).background(Color.white).clipShape(Circle()) }
                        .buttonStyle(.plain).accessibilityLabel("Add custom arena IP")
                    Button("Close") { presentation.wrappedValue.dismiss() }.font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.link)
                }.padding(20)
                HStack { Image(systemName: "magnifyingglass"); TextField("Arena code or IP", text: $search).textInputAutocapitalization(.never).disableAutocorrection(true) }
                    .font(.androidWyrm(13)).padding(.horizontal, 14).frame(height: 44).background(Color.white.opacity(0.82)).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)).padding(.horizontal, 16)
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 9, pinnedViews: []) {
                        if showAdd {
                            HStack(spacing: 8) {
                                TextField("IPv4 address:port", text: $customAddress)
                                    .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).disableAutocorrection(true)
                                Button("Save") { saveCustom() }.fontWeight(.bold)
                            }.font(.androidWyrm(13)).padding(14).background(Color.white).cornerRadius(14)
                            if addressError { Text("Enter a valid IPv4 address and port (1–65535).")
                                .font(.androidWyrm(11)).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        if !recentRows.isEmpty {
                            sectionLabel("RECENTLY JOINED")
                            ForEach(recentRows) { arena in arenaRow(arena) }
                        }
                        sectionLabel(search.isEmpty ? "LOWEST PING" : "SEARCH RESULTS")
                        ForEach(showAll || !search.isEmpty ? ranked : Array(ranked.prefix(10))) { arena in arenaRow(arena) }
                        if search.isEmpty && ranked.count > 10 {
                            Button(showAll ? "Show top 10" : "See all \(ranked.count) arenas") { withAnimation { showAll.toggle() } }
                                .font(.androidWyrm(13, .bold)).frame(maxWidth: .infinity).padding(14)
                        }
                        if !saved.isEmpty {
                            DisclosureGroup(isExpanded: $showSaved) {
                                ForEach(saved, id: \.self) { endpoint in
                                    if let arena = WyrmArena.custom(endpoint) { arenaRow(arena) }
                                }
                            } label: { sectionLabel("SAVED ARENAS · \(saved.count)") }
                                .tint(ATheme.ink).padding(14).background(Color.white.opacity(0.9)).cornerRadius(15)
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
            while !Task.isCancelled {
                await services.refreshArenasLive()
                for endpoint in saved {
                    guard !Task.isCancelled else { return }
                    customLatencies[endpoint] = await services.measureCustomArena(endpoint) ?? -1
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.androidWyrm(10, .bold)).tracking(0.8).foregroundColor(ATheme.quiet)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12).padding(.bottom, 3)
    }
    private func arenaRow(_ arena: WyrmArena) -> some View {
        Button { selection = arena.endpoint; presentation.wrappedValue.dismiss() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(arena.number == 0 ? "Custom arena" : "Arena \(arena.code)").font(.androidWyrm(15, .bold))
                    Text(arena.endpoint).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet)
                }
                Spacer()
                Text(latencyText(arena)).font(.androidWyrm(12, .bold)).foregroundColor(latencyColor(arena))
            }.foregroundColor(ATheme.ink).padding(14).background(Color.white.opacity(0.9)).cornerRadius(15)
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
        guard let value = arena.number == 0 ? customLatencies[arena.endpoint] : services.arenaLatencies[arena.id] else { return "Measuring…" }
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
                WyrmPaperCard {
                    WyrmListRow(title: "Leaderboard", detail: leaderboardDetail, icon: "trophy.fill") { open(.leaderboard) }
                    WyrmListRow(title: "Messages", detail: messageDetail, icon: "message.fill", tint: ATheme.link) { open(.messages) }
                    WyrmListRow(title: "Voice rooms", detail: "\(services.liveRooms.count) live", icon: "mic.fill", tint: ATheme.live) { open(.voice) }
                    WyrmListRow(title: "Connections", detail: "\(account.player?.followerCount ?? 0) followers · \(account.player?.followingCount ?? 0) following", icon: "person.2") { open(.people("connections")) }
                    WyrmListRow(title: "Your profile", detail: account.player?.handle ?? "", icon: "person.crop.circle.fill") { open(.profile("")) }
                }
                WyrmSectionLabel("Recently played with")
                WyrmPaperCard { WyrmEmptyPanel(title: "Your arena circle starts here", note: "Players from real conversations and follows appear here.") }
                Spacer().frame(height: 102)
            }
        }.refreshable { await services.refreshSocial() }
    }
    private var messageDetail: String { let unread = services.conversations.reduce(0) { $0 + $1.unreadCount }; return unread == 0 ? "No unread messages" : "\(unread) unread" }
    private var leaderboardDetail: String { guard let id = account.player?.id, let rank = services.killLeaders.firstIndex(where: { $0.id == id }) else { return "Score and kills" }; return "You are \(rank + 1) by kills" }
}

private struct WyrmAlertsRoot: View {
    @ObservedObject var services: WyrmServiceStore
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                WyrmScreenHeader(kicker: "Inbox", title: "Alerts", trailing: AnyView(Button("Read all") { Task { await services.markAllRead() } }.font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.link)))
                if services.alerts.isEmpty {
                    WyrmPaperCard { WyrmEmptyPanel(title: services.loading ? "Checking Wyrm…" : "All caught up", note: services.loading ? "Looking for real invites and notices." : "Nothing new right now.") }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(services.alerts) { alert in WyrmAlertCard(alert: alert, services: services) }
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
    @State private var showingMenu = false
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack { Circle().fill(alert.read ? Color.clear : ATheme.live).frame(width: 7, height: 7); Text(alert.kind.replacingOccurrences(of: "_", with: " ").uppercased()).font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(ATheme.live); Spacer(); Text(relative(alert.createdAt)).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet); Button { showingMenu = true } label: { Image(systemName: "ellipsis").foregroundColor(ATheme.quiet).frame(width: 28, height: 28) }.buttonStyle(.plain) }
            Text(alert.title).font(.androidWyrm(18, .bold))
            Text((try? AttributedString(markdown: alert.body,
                                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)))
                ?? AttributedString(alert.body))
                .font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).lineSpacing(3)
            if !alert.meta.isEmpty { ForEach(alert.meta.sorted(by: { $0.key < $1.key }), id: \.key) { pair in HStack { Text(pair.key.capitalized).foregroundColor(ATheme.quiet); Spacer(); Text(pair.value).fontWeight(.semibold) }.font(.androidWyrm(11.5)) } }
        }.padding(16).background(Color.white.opacity(0.92)).cornerRadius(17).overlay(RoundedRectangle(cornerRadius: 17).stroke(ATheme.rule)).padding(.horizontal, 16)
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
}

private struct WyrmSettingsRoot: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    let open: (WyrmDesignRoute) -> Void
    @AppStorage("wyrm.ios.developer-mode") private var developerMode = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                WyrmScreenHeader(kicker: "WYRM", title: "Settings")
                section("Arena", rows: [("Display", "Scores, names, minimap, text sizes", "", WyrmDesignRoute.display), ("Controls", "Steering, boost, zoom bar", setting("controls.joystick_mode"), .controls), ("On-screen buttons", "Which buttons appear and how they fire", "\(engine.hotkeys.filter(\.visible).count) on", .buttons)])
                section("Playing help", rows: [("Modes", "Normal, Assist, helper lines and arena colours", "", .modes), ("Bot", "When it circles, how wide it swings", "", .bot)])
                section("Food", rows: [("Food style", "Original, rings and geometric shapes", engine.settings.first(where: { $0.id.contains("food_type") })?.displayValue ?? "Original", .food)])
                section("Account", rows: [("Profile", "Name, username, photo, bio", account.player?.handle ?? "", .profile("")), ("Notifications", "Invites, team pings, follows", "", .notificationSettings), ("Privacy", "Who can reach you, what is stored", "", .privacy)])
                section("Accessibility", rows: [("Themes", "Paper, dark and colour appearances", UserDefaults.standard.string(forKey: "wyrm.ios.theme") ?? "Paper", .themes)])
                section("This device", rows: [("Backup & version", "Skins, controls, settings and team keys", "0.13.1 · 40", .backup)])
                VStack(spacing: 0) {
                    WyrmSectionLabel("Developer")
                    WyrmPaperCard {
                        Toggle(isOn: $developerMode) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Developer Mode").font(.androidWyrm(14.5, .semibold))
                                Text("Local diagnostics and export tools").font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet)
                            }
                        }.tint(ATheme.live).padding(.horizontal, 14).frame(minHeight: 58)
                        if developerMode {
                            WyrmListRow(title: "Wyrm logs", detail: "App, network and original engine events", value: "7 days") { open(.developer) }
                        }
                    }
                    Text("Developer logs stay on this iPhone until you explicitly share them. They automatically expire after seven days and are capped at 2 MB.")
                        .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(20)
                }
                Spacer().frame(height: 102)
            }
        }
    }
    private func setting(_ id: String) -> String { engine.settings.first(where: { $0.id == id })?.displayValue ?? "Joystick" }
    private func section(_ title: String, rows: [(String, String, String, WyrmDesignRoute)]) -> some View {
        VStack(spacing: 0) { WyrmSectionLabel(title); WyrmPaperCard { ForEach(rows.indices, id: \.self) { index in let row = rows[index]; WyrmListRow(title: row.0, detail: row.1, value: row.2) { open(row.3) } } } }
    }
}
