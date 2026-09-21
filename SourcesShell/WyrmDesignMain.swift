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
                    case .skin: WyrmSkinRoot(open: open)
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
                if !services.errorMessage.isEmpty || !engine.toast.isEmpty {
                    Text(!engine.toast.isEmpty ? engine.toast : services.errorMessage)
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
    @State private var showArenas = false
    @State private var lastPlayedName = "Wyrm Player"
    @State private var lastHandledRefusal: UInt64 = 0

    private var nearest: WyrmArena? {
        if let selected = services.arenas.first(where: { $0.endpoint == arena }), !services.isArenaTainted(selected.endpoint) { return selected }
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
                            Text(nearest.map { "Arena \($0.code)" } ?? "Pick a server").font(.androidWyrm(21, .bold)).lineLimit(1)
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
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .fullScreenCover(isPresented: $showArenas) { WyrmArenaPicker(services: services, selection: $arena) }
    }

    private func enterOriginalLobby() {
        guard let selected = nearest else { return }
        arena = selected.endpoint
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

    private var filtered: [WyrmArena] { search.isEmpty ? services.arenas : services.arenas.filter { $0.endpoint.contains(search) || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) { Text("LIVE DIRECTORY").font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.live); Text("Pick a server").font(.androidWyrm(27, .bold)) }
                    Spacer(); Button("Close") { presentation.wrappedValue.dismiss() }.font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.link)
                }.padding(20)
                HStack { Image(systemName: "magnifyingglass"); TextField("Arena code or IP", text: $search).textInputAutocapitalization(.never).disableAutocorrection(true) }
                    .font(.androidWyrm(13)).padding(.horizontal, 14).frame(height: 44).background(Color.white.opacity(0.82)).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)).padding(.horizontal, 16)
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 9) {
                        ForEach(filtered) { arena in
                            Button { selection = arena.endpoint; presentation.wrappedValue.dismiss() } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) { Text("Arena \(arena.code)").font(.androidWyrm(15, .bold)); Text(arena.endpoint).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) { Text("\(arena.players) players").font(.androidWyrm(11.5, .semibold)); Text(latencyText(arena)).font(.androidWyrm(11, .bold)).foregroundColor(latencyColor(arena)) }
                                }.foregroundColor(ATheme.ink).padding(14).background(Color.white.opacity(0.9)).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(selection == arena.endpoint ? ATheme.ink : ATheme.rule, lineWidth: selection == arena.endpoint ? 2 : 1))
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
            }
        }
        .task { while !Task.isCancelled { await services.refreshArenasLive(); try? await Task.sleep(nanoseconds: 1_000_000_000) } }
    }

    private func latencyText(_ arena: WyrmArena) -> String { services.arenaLatencies[arena.id].map { "\($0)ms" } ?? "measuring" }
    private func latencyColor(_ arena: WyrmArena) -> Color {
        guard let value = services.arenaLatencies[arena.id], !services.arenaLatencies.isEmpty else { return ATheme.quiet }
        let values = services.arenaLatencies.values
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
        }.refreshable { await services.bootstrap(token: account.sessionToken, playerID: account.player?.id) }
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
            Text(alert.body).font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).lineSpacing(3)
            if !alert.meta.isEmpty { ForEach(alert.meta.sorted(by: { $0.key < $1.key }), id: \.key) { pair in HStack { Text(pair.key.capitalized).foregroundColor(ATheme.quiet); Spacer(); Text(pair.value).fontWeight(.semibold) }.font(.androidWyrm(11.5)) } }
        }.padding(16).background(Color.white.opacity(0.92)).cornerRadius(17).overlay(RoundedRectangle(cornerRadius: 17).stroke(ATheme.rule)).padding(.horizontal, 16)
            .confirmationDialog(alert.title, isPresented: $showingMenu) {
                Button(alert.read ? "Mark unread" : "Mark as read") { Task { await services.setRead(alert, read: !alert.read) } }
                Button("Delete notification", role: .destructive) { Task { await services.delete(alert) } }
            }
    }
    private func relative(_ raw: String) -> String { raw.isEmpty ? "" : String(raw.prefix(10)) }
}

private struct WyrmSkinRoot: View {
    let open: (WyrmDesignRoute) -> Void
    private let beads = [ATheme.ink, Color(red: 0.62, green: 0.72, blue: 0.49), Color(red: 0.83, green: 0.60, blue: 0.48)]
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                WyrmScreenHeader(kicker: "WYRM", title: "Skin")
                VStack(spacing: 15) {
                    HStack(spacing: -7) { ForEach(0..<12) { index in Circle().fill(beads[index % beads.count]).frame(width: CGFloat(31 - min(index, 9)), height: CGFloat(31 - min(index, 9))).shadow(color: ATheme.ink.opacity(0.1), radius: 2, y: 1) } }
                    Text("ENGINE PREVIEW").font(.androidWyrm(9.5, .bold)).tracking(1.3).foregroundColor(ATheme.quiet)
                }.frame(maxWidth: .infinity).frame(height: 190)
                WyrmPaperCard {
                    WyrmListRow(title: "Default skins", value: "48") { open(.presets) }
                    WyrmListRow(title: "Pattern", value: "Custom") { open(.pattern) }
                    WyrmListRow(title: "Accessory", value: "None") { open(.accessory) }
                    WyrmListRow(title: "Tag", value: "None") { open(.tag) }
                    WyrmListRow(title: "Arena background", value: "Paper") { open(.background) }
                }
                Text("Skin screens preserve the design system while the native engine remains the rendering authority.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(20)
                Spacer().frame(height: 102)
            }
        }
    }
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
                section("This device", rows: [("Backup & version", "Skins, controls, settings and team keys", "0.12.1 · 38", .backup)])
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
