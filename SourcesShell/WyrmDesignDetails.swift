import SwiftUI

struct WyrmDetailHost: View {
    let route: WyrmDesignRoute
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void

    var body: some View {
        switch route {
        case .leaderboard: WyrmLeaderboardDetail(services: services, close: close, open: open)
        case .messages: WyrmMessagesDetail(services: services, close: close, open: open)
        case .thread(let id): WyrmThreadDetail(playerID: id, account: account, services: services, close: close)
        case .people(let kind): WyrmPeopleDetail(kind: kind, account: account, services: services, close: close, open: open)
        case .profile(let id): WyrmProfileDetail(playerID: id, account: account, services: services, close: close, open: open)
        case .editProfile: WyrmEditProfileDetail(account: account, close: close)
        case .voice: WyrmVoiceDetail(services: services, close: close, open: open)
        case .room(let id): WyrmRoomDetail(roomID: id, services: services, close: close, open: open)
        case .call(let id): WyrmCallDetail(roomID: id, services: services, close: close)
        case .lobby: WyrmLobbyDetail(engine: engine, account: account, services: services, close: close)
        case .team, .teamChat, .teamConnect: WyrmTeamDetail(route: route, close: close, open: open)
        case .display, .controls, .buttons, .modes, .bot, .food: WyrmEngineSettingsDetail(route: route, engine: engine, close: close)
        case .notificationSettings: WyrmNotificationSettingsDetail(close: close)
        case .privacy: WyrmPrivacyDetail(close: close)
        case .themes: WyrmThemesDetail(close: close)
        case .backup: WyrmBackupDetail(engine: engine, close: close)
        case .developer: WyrmDeveloperDetail(close: close)
        case .presets, .pattern, .accessory, .tag, .background: WyrmSkinDetail(route: route, close: close)
        }
    }
}

private struct WyrmLeaderboardDetail: View {
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State private var sort = 0
    private var rows: [WyrmServicePlayer] { sort == 0 ? services.scoreLeaders : services.killLeaders }
    var body: some View {
        WyrmDetailChrome(title: "Leaderboard", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Picker("Rank by", selection: $sort) { Text("Score").tag(0); Text("Kills").tag(1) }.pickerStyle(.segmented).padding(16)
                    WyrmPaperCard {
                        if rows.isEmpty { WyrmEmptyPanel(title: "No ranked players yet", note: "Finished runs will appear here.") }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, player in
                            Button { open(.profile(player.id)) } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.androidWyrm(13, .bold)).foregroundColor(ATheme.quiet).frame(width: 24)
                                    WyrmAvatar(initials: player.initials, size: 35)
                                    VStack(alignment: .leading, spacing: 2) { Text(player.displayName).font(.androidWyrm(14.5, .semibold)); Text(player.handle).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) }
                                    Spacer()
                                    Text((sort == 0 ? player.highestScore : player.kills).wyrmFormatted).font(.androidWyrm(14, .bold))
                                }.foregroundColor(ATheme.ink).padding(.horizontal, 14).frame(minHeight: 56)
                            }.buttonStyle(.plain).overlay(Rectangle().fill(ATheme.rowRule).frame(height: 1).padding(.leading, 58), alignment: .bottom)
                        }
                    }
                    Spacer().frame(height: 24)
                }
            }.refreshable { await services.refreshLeaderboards() }
        }
    }
}

private struct WyrmMessagesDetail: View {
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    var body: some View {
        WyrmDetailChrome(title: "Messages", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WyrmSectionLabel("Conversations")
                    WyrmPaperCard {
                        if services.conversations.isEmpty { WyrmEmptyPanel(title: "No messages yet", note: "Mutual follows can start a private conversation.") }
                        ForEach(services.conversations) { row in
                            WyrmListRow(title: row.player.displayName, detail: row.lastMessage.isEmpty ? "No messages yet" : row.lastMessage, value: row.unreadCount > 0 ? "\(row.unreadCount)" : "", icon: "person.crop.circle.fill", tint: ATheme.link) { open(.thread(row.player.id)) }
                        }
                    }
                    WyrmOutlineAction(title: "Message someone new") { open(.people("search")) }.padding(16)
                }
            }.refreshable { await services.refreshConversations() }
        }
    }
}

private struct WyrmThreadDetail: View {
    let playerID: String
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    @State private var message = ""
    private var person: WyrmServicePlayer? { services.conversations.first(where: { $0.player.id == playerID })?.player ?? services.people.first(where: { $0.id == playerID }) }
    var body: some View {
        WyrmDetailChrome(title: person?.displayName ?? "Message", onBack: close) {
            VStack(spacing: 0) {
                ScrollViewReader { _ in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 9) {
                            if services.messages.isEmpty { WyrmEmptyPanel(title: "Quiet so far", note: "Say hello when you are ready.") }
                            ForEach(services.messages) { row in
                                HStack { if row.authorID == account.player?.id { Spacer(minLength: 50) }; Text(row.body).font(.androidWyrm(13)).padding(.horizontal, 14).padding(.vertical, 10).background(row.authorID == account.player?.id ? ATheme.ink : Color.white).foregroundColor(row.authorID == account.player?.id ? .white : ATheme.ink).cornerRadius(15); if row.authorID != account.player?.id { Spacer(minLength: 50) } }.padding(.horizontal, 16)
                            }
                        }.padding(.vertical, 14)
                    }
                }
                HStack(spacing: 9) {
                    TextField("Message", text: $message).font(.androidWyrm(14)).padding(.horizontal, 14).frame(height: 44).background(Color.white).cornerRadius(14)
                    Button { send() } label: { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundColor(.white).frame(width: 44, height: 44).background(ATheme.ink).clipShape(Circle()) }.buttonStyle(.plain).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(12).background(.ultraThinMaterial)
            }.task { await services.loadThread(playerID: playerID) }
        }
    }
    private func send() { let body = message.trimmingCharacters(in: .whitespacesAndNewlines); guard !body.isEmpty else { return }; message = ""; Task { await services.sendDirect(playerID: playerID, body: body) } }
}

private struct WyrmPeopleDetail: View {
    let kind: String
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State private var query = ""
    var body: some View {
        WyrmDetailChrome(title: kind == "following" ? "Following" : kind == "search" ? "People" : "Followers", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack { Image(systemName: "magnifyingglass").foregroundColor(ATheme.quiet); TextField("Search players", text: $query).font(.androidWyrm(14)); if !query.isEmpty { Button { Task { await services.searchPeople(query) } } label: { Image(systemName: "arrow.right.circle.fill").foregroundColor(ATheme.ink) } } }.padding(.horizontal, 14).frame(height: 46).background(Color.white).cornerRadius(14).padding(16)
                    WyrmPaperCard {
                        if services.people.isEmpty { WyrmEmptyPanel(title: "No people to show", note: query.isEmpty ? "This list updates from your real Wyrm connections." : "Try another name or username.") }
                        ForEach(services.people) { person in WyrmListRow(title: person.displayName, detail: person.handle, value: person.isFollowing ? "Following" : "", icon: "person.crop.circle.fill") { open(.profile(person.id)) } }
                    }
                    Spacer().frame(height: 24)
                }
            }.task { if kind != "search", let id = account.player?.id { await services.loadConnections(playerID: id, kind: kind) } }
        }
    }
}

private struct WyrmProfileDetail: View {
    let playerID: String
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    private var own: Bool { playerID.isEmpty || playerID == account.player?.id }
    private var servicePlayer: WyrmServicePlayer? { services.people.first(where: { $0.id == playerID }) ?? services.scoreLeaders.first(where: { $0.id == playerID }) ?? services.killLeaders.first(where: { $0.id == playerID }) }
    var body: some View {
        WyrmDetailChrome(title: "Profile", actionTitle: own ? "Edit" : "", onBack: close, action: { if own { open(.editProfile) } }) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WyrmAvatar(initials: own ? (account.player?.initials ?? "W") : (servicePlayer?.initials ?? "W"), size: 76).padding(.top, 28)
                    Text(own ? (account.player?.displayName ?? "Wyrm") : (servicePlayer?.displayName ?? "Player")).font(.androidWyrm(27, .bold)).padding(.top, 14)
                    Text(own ? (account.player?.handle ?? "") : (servicePlayer?.handle ?? "")).font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
                    Text(profileBio).font(.androidWyrm(13)).foregroundColor(ATheme.mute).multilineTextAlignment(.center).padding(.horizontal, 34).padding(.top, 10)
                    HStack(spacing: 0) { WyrmMetric(label: "BEST", value: score.wyrmFormatted); Rectangle().fill(ATheme.rule).frame(width: 1, height: 48); WyrmMetric(label: "KILLS", value: kills.wyrmFormatted) }.background(Color.white).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(ATheme.rule)).padding(16)
                    WyrmPaperCard {
                        WyrmListRow(title: "Followers", value: "\(followers)") { open(.people("followers")) }
                        WyrmListRow(title: "Following", value: "\(following)") { open(.people("following")) }
                        if own { WyrmListRow(title: "Sign out", destructive: true, showsChevron: false) { account.signOut() } }
                        else { WyrmListRow(title: servicePlayer?.isFollowing == true ? "Unfollow" : "Follow", value: servicePlayer?.followsYou == true ? "Follows you" : "", showsChevron: false) { if let person = servicePlayer { Task { await services.follow(person) } } } }
                    }
                    Spacer().frame(height: 24)
                }
            }
        }
    }
    private var profileBio: String { own ? ((account.player?.bio.isEmpty == false ? account.player?.bio : "Nothing yet. Add a line about how you play.") ?? "") : (servicePlayer?.bio.isEmpty == false ? servicePlayer!.bio : "Nothing here yet.") }
    private var score: Int64 { own ? (account.player?.highestScore ?? 0) : (servicePlayer?.highestScore ?? 0) }
    private var kills: Int64 { own ? (account.player?.kills ?? 0) : (servicePlayer?.kills ?? 0) }
    private var followers: Int64 { own ? (account.player?.followerCount ?? 0) : (servicePlayer?.followerCount ?? 0) }
    private var following: Int64 { own ? (account.player?.followingCount ?? 0) : (servicePlayer?.followingCount ?? 0) }
}

private struct WyrmEditProfileDetail: View {
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    @State private var displayName = ""
    @State private var ingameName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var avatar = "mono-ink"
    var body: some View {
        WyrmDetailChrome(title: "Edit profile", actionTitle: "Save", onBack: close, action: save) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 13) {
                    WyrmDesignEditField(label: "Display name", value: $displayName)
                    WyrmDesignEditField(label: "Arena name", value: $ingameName)
                    WyrmDesignEditField(label: "Username", value: $username)
                    WyrmDesignEditField(label: "Bio", value: $bio)
                    if !account.errorMessage.isEmpty { Text(account.errorMessage).font(.androidWyrm(12)).foregroundColor(.red) }
                    WyrmOutlineAction(title: "Delete account", destructive: true) { Task { await account.deleteAccount() } }
                }.padding(16)
            }.onAppear { displayName = account.player?.displayName ?? ""; ingameName = account.player?.ingameName ?? ""; username = account.player?.username ?? ""; bio = account.player?.bio ?? ""; avatar = account.player?.avatarKey ?? "mono-ink" }
        }
    }
    private func save() { Task { if await account.update(displayName: displayName, ingameName: ingameName, username: username, bio: bio, avatarKey: avatar) { close() } } }
}

private struct WyrmDesignEditField: View {
    let label: String
    @Binding var value: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(label.uppercased()).font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(ATheme.quiet); TextField(label, text: $value).font(.androidWyrm(15)).padding(.horizontal, 14).frame(height: 50).background(Color.white).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)) } }
}

private struct WyrmVoiceDetail: View {
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    var body: some View {
        WyrmDetailChrome(title: "Voice rooms", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WyrmSectionLabel("Live now")
                    WyrmPaperCard {
                        if services.liveRooms.isEmpty { WyrmEmptyPanel(title: "No live rooms", note: "Verified rooms appear here when a call starts.") }
                        ForEach(services.liveRooms) { room in WyrmListRow(title: room.name, detail: "Hosted by \(room.creator.displayName)", value: "\(room.activeCount)/\(room.capacity)", icon: "waveform", tint: ATheme.live) { open(.room(room.id)) } }
                    }
                    WyrmSectionLabel("All rooms · \(services.voiceRooms.count)")
                    WyrmPaperCard {
                        ForEach(services.voiceRooms.filter { !$0.active }) { room in WyrmListRow(title: room.name, detail: room.gate.capitalized, value: room.mine ? "Yours" : "", icon: "mic") { open(.room(room.id)) } }
                    }
                    Spacer().frame(height: 24)
                }
            }.refreshable { await services.refreshVoice() }
        }
    }
}

private struct WyrmRoomDetail: View {
    let roomID: String
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    private var room: WyrmVoiceRoom? { services.voiceRooms.first(where: { $0.id == roomID }) }
    var body: some View {
        WyrmDetailChrome(title: room?.name ?? "Room", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 9) { Image(systemName: "waveform.circle.fill").font(.system(size: 62, weight: .light)).foregroundColor(room?.active == true ? ATheme.live : ATheme.quiet); Text(room?.active == true ? "Room is live" : "Room is quiet").font(.androidWyrm(24, .bold)); Text("\(room?.activeCount ?? 0) of \(room?.capacity ?? 10) people").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet) }.padding(.vertical, 34)
                    WyrmPaperCard {
                        WyrmListRow(title: "Created by", value: room?.creator.displayName ?? "", showsChevron: false)
                        WyrmListRow(title: "Access", value: room?.gate.capitalized ?? "Open", showsChevron: false)
                        WyrmListRow(title: "Status", value: room?.suspended == true ? "Suspended" : "Available", showsChevron: false)
                    }
                    if let room {
                        WyrmPrimaryAction(title: room.member ? "Open call" : "Join room", icon: "mic.fill") { if room.member { open(.call(room.id)) } else { Task { await services.joinVoice(room); open(.call(room.id)) } } }.padding(16)
                        if room.member { WyrmOutlineAction(title: "Leave room", destructive: true) { Task { await services.leaveVoice(room); close() } }.padding(.horizontal, 16) }
                    }
                }
            }
        }
    }
}

private struct WyrmCallDetail: View {
    let roomID: String
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    @State private var muted = true
    @State private var deafened = false
    private var room: WyrmVoiceRoom? { services.voiceRooms.first(where: { $0.id == roomID }) }
    var body: some View {
        WyrmDetailChrome(title: "Voice", onBack: close) {
            VStack(spacing: 0) {
                Spacer()
                Text(room?.name ?? "Voice room").font(.androidWyrm(28, .bold))
                Text("Control plane connected").font(.androidWyrm(12)).foregroundColor(ATheme.live).padding(.top, 6)
                Text("Live audio requires the iOS realtime media adapter and microphone permission on a physical device.").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 12)
                Spacer()
                HStack(spacing: 22) {
                    callButton(icon: muted ? "mic.slash.fill" : "mic.fill", title: muted ? "Muted" : "Live", on: !muted) { muted.toggle() }
                    callButton(icon: deafened ? "speaker.slash.fill" : "speaker.wave.2.fill", title: deafened ? "Deafened" : "Audio", on: !deafened) { deafened.toggle() }
                }
                if let room { Button { Task { await services.leaveVoice(room); close() } } label: { Image(systemName: "phone.down.fill").font(.system(size: 23)).foregroundColor(.white).frame(width: 66, height: 66).background(Color.red).clipShape(Circle()) }.padding(.top, 28).padding(.bottom, 42) }
            }
        }
    }
    private func callButton(icon: String, title: String, on: Bool, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 22)).frame(width: 58, height: 58).background(on ? ATheme.live.opacity(0.14) : ATheme.ink.opacity(0.08)).clipShape(Circle()); Text(title).font(.androidWyrm(11.5)) }.foregroundColor(on ? ATheme.live : ATheme.ink) }.buttonStyle(.plain) }
}

private struct WyrmLobbyDetail: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    @State private var name = ""
    @State private var arena = ""
    var body: some View {
        WyrmDetailChrome(title: "Lobby", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WyrmSectionLabel("Playing as")
                    WyrmPaperCard { WyrmListRow(title: name.isEmpty ? (account.player?.arenaName ?? "Wyrm Player") : name, detail: account.player?.handle ?? "", value: "Ready", showsChevron: false) }
                    WyrmSectionLabel("Arena")
                    WyrmPaperCard {
                        TextField("IP address or host", text: $arena).font(.androidWyrm(14)).textInputAutocapitalization(.never).disableAutocorrection(true).padding(.horizontal, 14).frame(height: 52)
                        WyrmListRow(title: "Live directory", value: "\(services.arenas.count) arenas", showsChevron: false)
                    }
                    VStack(spacing: 10) {
                        WyrmPrimaryAction(title: "Play", icon: "play.fill", disabled: arena.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { engine.enterLobby(name: cleanName, address: arena.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        WyrmOutlineAction(title: "Play with AI") { engine.playOffline(name: cleanName) }
                    }.padding(16)
                    Text("The button hands your name and endpoint to the original C engine. Its own landscape lobby opens inside the portrait iOS container.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(.horizontal, 20)
                }
            }.onAppear { name = account.player?.arenaName ?? engine.nickname; arena = engine.arena.isEmpty ? (services.arenas.first?.endpoint ?? "") : engine.arena }
        }
    }
    private var cleanName: String { let value = name.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? "Wyrm Player" : String(value.prefix(24)) }
}

private struct WyrmTeamDetail: View {
    let route: WyrmDesignRoute
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @AppStorage("wyrm.ios.team.id") private var teamID = ""
    @State private var key = ""
    @State private var message = ""
    var body: some View {
        WyrmDetailChrome(title: title, onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if route.id == "team-connect" {
                        WyrmSectionLabel("Team")
                        VStack(spacing: 12) { WyrmDesignEditField(label: "Team ID", value: $teamID); WyrmDesignEditField(label: "Auth key", value: $key); WyrmPrimaryAction(title: "Store on this phone", icon: "lock.fill", disabled: teamID.count < 4 || key.count < 8) { key = ""; close() } }.padding(16)
                        Text("Team credentials stay on this device. The iOS native Team transport adapter is the remaining engine boundary before it can connect.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).padding(.horizontal, 20)
                    } else if route.id == "team-chat" {
                        WyrmPaperCard { WyrmEmptyPanel(title: teamID.isEmpty ? "No team connected" : teamID, note: "Team chat becomes live when the native iOS Team adapter is available.") }.padding(.top, 18)
                        HStack { TextField("Message the team", text: $message).padding(12).background(Color.white).cornerRadius(12); Button("Send") {}.disabled(true) }.padding(16)
                    } else {
                        WyrmSectionLabel("Team mode")
                        WyrmPaperCard { WyrmListRow(title: teamID.isEmpty ? "No team connected" : teamID, detail: teamID.isEmpty ? "A team ID comes from your NTL server." : "Saved on this iPhone", value: teamID.isEmpty ? "" : "Stored", showsChevron: false) }
                        VStack(spacing: 10) { WyrmPrimaryAction(title: teamID.isEmpty ? "Add a team" : "Edit connection", icon: "person.3.fill") { open(.teamConnect) }; if !teamID.isEmpty { WyrmOutlineAction(title: "Open team chat") { open(.teamChat) } } }.padding(16)
                    }
                }
            }
        }
    }
    private var title: String { route.id == "team-chat" ? "Team chat" : route.id == "team-connect" ? "Connect" : "Team mode" }
}

private struct WyrmEngineSettingsDetail: View {
    let route: WyrmDesignRoute
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    private var rows: [EngineSetting] { engine.settings.filter(matches) }
    private var title: String { ["display":"Display", "controls":"Controls", "buttons":"On-screen buttons", "modes":"Modes", "bot":"Bot", "food":"Food style"][route.id] ?? "Settings" }
    var body: some View {
        WyrmDetailChrome(title: title, onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if route.id == "buttons" { ForEach(engine.hotkeys) { hotkey in WyrmHotkeyDesignRow(engine: engine, hotkey: hotkey) } }
                    ForEach(rows) { row in WyrmEngineSettingDesignRow(engine: engine, row: row).id(row.id + row.displayValue) }
                    if rows.isEmpty && route.id != "buttons" { WyrmPaperCard { WyrmEmptyPanel(title: "Engine is starting", note: "These controls appear as soon as the native settings mailbox is ready.") } }
                }.padding(.vertical, 16)
            }
        }
    }
    private func matches(_ row: EngineSetting) -> Bool {
        guard !row.label.isEmpty else { return false }
        switch route {
        case .display: return row.group.hasPrefix("general") && !row.group.contains("bot")
        case .controls: return row.group.hasPrefix("controls")
        case .buttons: return row.group == "keys"
        case .modes: return row.group == "normal" || row.group == "assist"
        case .bot: return row.group.contains("bot")
        case .food: return row.id.contains("food")
        default: return false
        }
    }
}

private struct WyrmEngineSettingDesignRow: View {
    @ObservedObject var engine: WyrmShellStore
    let row: EngineSetting
    @State private var value: Double
    init(engine: WyrmShellStore, row: EngineSetting) { self.engine = engine; self.row = row; _value = State(initialValue: row.values.first ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { VStack(alignment: .leading, spacing: 2) { Text(row.label).font(.androidWyrm(14.5, .semibold)); if !row.hint.isEmpty { Text(row.hint).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) } }; Spacer(); control }
            if row.type == "float" || row.type == "int" { Slider(value: Binding(get: { value }, set: { value = $0; engine.write(row, values: [$0]) }), in: row.minimum...max(row.minimum, row.maximum), step: row.type == "int" ? 1 : max(0.001, (row.maximum-row.minimum)/100)).tint(ATheme.ink) }
        }.padding(15).background(Color.white).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(ATheme.rule)).padding(.horizontal, 16)
    }
    @ViewBuilder private var control: some View {
        switch row.type {
        case "bool": Toggle("", isOn: Binding(get: { value != 0 }, set: { value = $0 ? 1 : 0; engine.write(row, values: [value]) })).labelsHidden().tint(ATheme.live)
        case "enum": Picker("", selection: Binding(get: { Int(value) }, set: { value = Double($0); engine.write(row, values: [value]) })) { ForEach(row.options.indices, id: \.self) { Text(row.options[$0]).tag($0) } }.pickerStyle(.menu).tint(ATheme.ink)
        default: Text(row.displayValue).font(.androidWyrm(12, .bold)).foregroundColor(ATheme.quiet)
        }
    }
}

private struct WyrmHotkeyDesignRow: View {
    @ObservedObject var engine: WyrmShellStore
    let hotkey: EngineHotkey
    var body: some View { Toggle(isOn: Binding(get: { hotkey.visible }, set: { engine.setHotkey(hotkey, visible: $0) })) { VStack(alignment: .leading, spacing: 2) { Text(hotkey.name).font(.androidWyrm(14.5, .semibold)); Text("\(hotkey.keyName) · \(hotkey.mode == 1 ? "Hold" : "Toggle")").font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) } }.tint(ATheme.live).padding(15).background(Color.white).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(ATheme.rule)).padding(.horizontal, 16) }
}

private struct WyrmNotificationSettingsDetail: View {
    let close: () -> Void
    @AppStorage("wyrm.notify.invites") private var invites = true
    @AppStorage("wyrm.notify.direct") private var direct = true
    @AppStorage("wyrm.notify.voice") private var voice = true
    @AppStorage("wyrm.notify.follows") private var follows = true
    @AppStorage("wyrm.notify.notices") private var notices = true
    @AppStorage("wyrm.notify.events") private var events = true
    @AppStorage("wyrm.notify.achievements") private var achievements = true
    var body: some View {
        WyrmDetailChrome(title: "Notifications", onBack: close) {
            ScrollView(showsIndicators: false) { VStack(spacing: 0) {
                WyrmSectionLabel("People"); toggles([("Arena invites", "Someone sends you a server and key.", $invites), ("Direct messages", "New thread or reply.", $direct), ("Voice invitations", "Private room invitations.", $voice), ("New followers", "Another player starts following you.", $follows)])
                WyrmSectionLabel("Wyrm"); toggles([("Notices", "Maintenance and important alerts.", $notices), ("Battledome events", "Scheduled events and arena addresses.", $events), ("Achievements", "Personal bests and milestones.", $achievements)])
                Text("These preferences filter the real Wyrm feed in-app. APNs delivery still needs an Apple push entitlement and physical-device token.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(20)
            } }
        }
    }
    private func toggles(_ rows: [(String, String, Binding<Bool>)]) -> some View { WyrmPaperCard { ForEach(rows.indices, id: \.self) { index in Toggle(isOn: rows[index].2) { VStack(alignment: .leading, spacing: 2) { Text(rows[index].0).font(.androidWyrm(14.5)); Text(rows[index].1).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) } }.tint(ATheme.live).padding(.horizontal, 14).frame(minHeight: 58).overlay(Rectangle().fill(ATheme.rowRule).frame(height: 1).padding(.leading, 14), alignment: .bottom) } } }
}

private struct WyrmPrivacyDetail: View {
    let close: () -> Void
    var body: some View { WyrmDetailChrome(title: "Privacy", onBack: close) { ScrollView(showsIndicators: false) { VStack(spacing: 0) { WyrmSectionLabel("What Wyrm keeps"); WyrmPaperCard { WyrmListRow(title: "Stored on this phone", value: "Session, Team ID, settings", showsChevron: false); WyrmListRow(title: "Stored on the server", value: "Profile, scores, social", showsChevron: false); WyrmListRow(title: "Chat retention", value: "Global 24 h · direct history", showsChevron: false); WyrmListRow(title: "Analytics", value: "No fabricated telemetry", showsChevron: false) }; Text("The iOS session bearer is stored in Keychain. Views never log it. Team credentials are not shared with Android Keystore ciphertext.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(20) } } } }
}

private struct WyrmThemesDetail: View {
    let close: () -> Void
    @AppStorage("wyrm.ios.theme") private var theme = "Paper"
    private let themes = ["Paper", "Graphite", "Blush", "Sun", "Slate", "Lilac", "Forest", "Midnight"]
    var body: some View { WyrmDetailChrome(title: "Accessibility", onBack: close) { ScrollView(showsIndicators: false) { VStack(spacing: 0) { WyrmSectionLabel("Themes"); WyrmPaperCard { ForEach(themes, id: \.self) { name in Button { theme = name } label: { HStack { Circle().fill(colour(name)).frame(width: 28, height: 28); VStack(alignment: .leading, spacing: 2) { Text(name).font(.androidWyrm(14.5)); Text(description(name)).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) }; Spacer(); if theme == name { Image(systemName: "checkmark.circle.fill").foregroundColor(ATheme.live) } }.foregroundColor(ATheme.ink).padding(.horizontal, 14).frame(minHeight: 56) }.buttonStyle(.plain).overlay(Rectangle().fill(ATheme.rowRule).frame(height: 1).padding(.leading, 54), alignment: .bottom) } }; Text("Paper remains the production iOS 15 appearance. The saved theme choice is ready for the full token palette pass.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).padding(20) } } } }
    private func colour(_ name: String) -> Color { ["Paper":ATheme.paper, "Graphite":Color(white: 0.18), "Blush":Color(red: 0.88, green: 0.72, blue: 0.72), "Sun":Color(red: 0.92, green: 0.79, blue: 0.42), "Slate":Color(red: 0.38, green: 0.48, blue: 0.58), "Lilac":Color(red: 0.69, green: 0.56, blue: 0.72), "Forest":Color(red: 0.29, green: 0.48, blue: 0.35), "Midnight":Color(red: 0.08, green: 0.12, blue: 0.18)][name] ?? ATheme.paper }
    private func description(_ name: String) -> String { name == "Paper" ? "Original warm paper and ink" : name == "Midnight" ? "Deep blue-black with quiet highlights" : "Wyrm palette variation" }
}

private struct WyrmBackupDetail: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    @State private var confirmReset = false
    var body: some View { WyrmDetailChrome(title: "Backup", onBack: close) { ScrollView(showsIndicators: false) { VStack(spacing: 0) { WyrmSectionLabel("This device"); WyrmPaperCard { WyrmListRow(title: "Wyrm", value: "0.9.0 (31)", showsChevron: false); WyrmListRow(title: "Settings format", value: engine.settingsVersion.isEmpty ? "Starting" : engine.settingsVersion, showsChevron: false); WyrmListRow(title: "Engine controls", value: "\(engine.settings.count)", showsChevron: false); WyrmListRow(title: "On-screen actions", value: "\(engine.hotkeys.count)", showsChevron: false) }; VStack(spacing: 10) { WyrmOutlineAction(title: "Reset controls layout") { engine.reset(2, message: "Controls reset") }; WyrmOutlineAction(title: "Reset arena HUD") { engine.reset(8, message: "HUD reset") }; WyrmOutlineAction(title: confirmReset ? "Tap again to reset everything" : "Reset everything to defaults", destructive: true) { if confirmReset { engine.reset(1, message: "All engine settings reset"); confirmReset = false } else { confirmReset = true } } }.padding(16); Text("Portable backup and Files import/export remain a Phase 7 Apple service. Reset actions above are live native-engine mailboxes.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).padding(.horizontal, 20) } } } }
}

private struct WyrmDeveloperDetail: View {
    let close: () -> Void
    @ObservedObject private var diagnostics = WyrmDiagnostics.shared
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var confirmClear = false

    var body: some View {
        WyrmDetailChrome(title: "Developer Mode", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WyrmSectionLabel("Diagnostics")
                    WyrmPaperCard {
                        WyrmListRow(title: "Retention", value: "7 days", showsChevron: false)
                        WyrmListRow(title: "Storage cap", value: "2 MB total", showsChevron: false)
                        WyrmListRow(title: "Current export", value: ByteCountFormatter.string(fromByteCount: Int64(diagnostics.byteCount), countStyle: .file), showsChevron: false)
                    }
                    HStack(spacing: 10) {
                        WyrmOutlineAction(title: "Refresh") { diagnostics.refresh() }
                        WyrmOutlineAction(title: "Share logs") {
                            WyrmDiagnostics.record("share sheet requested", category: "DIAGNOSTICS")
                            shareURL = diagnostics.exportFile()
                            showingShare = shareURL != nil
                        }
                    }.padding(.horizontal, 16).padding(.top, 16)
                    WyrmOutlineAction(title: confirmClear ? "Tap again to clear logs" : "Clear stored logs", destructive: true) {
                        if confirmClear { diagnostics.clear(); confirmClear = false }
                        else { confirmClear = true }
                    }.padding(.horizontal, 16).padding(.top, 10)

                    WyrmSectionLabel("App + engine log")
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(diagnostics.text)
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundColor(ATheme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                    .background(Color.white.opacity(0.94))
                    .cornerRadius(15)
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(ATheme.rule))
                    .padding(.horizontal, 16)
                    Text("Exports include app lifecycle, safe network status and SDL3/original-engine events. Tokens, passwords and private message bodies are never written.")
                        .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(20)
                }
            }
            .onAppear { diagnostics.refresh(); WyrmDiagnostics.record("developer console opened", category: "DIAGNOSTICS") }
            .sheet(isPresented: $showingShare) {
                if let shareURL = shareURL { WyrmShareSheet(items: [shareURL]) }
            }
        }
    }
}

private struct WyrmSkinDetail: View {
    let route: WyrmDesignRoute
    let close: () -> Void
    @AppStorage("wyrm.ios.skin.preset") private var preset = 2
    @AppStorage("wyrm.ios.skin.background") private var background = "Paper"
    @State private var pattern = "b3-m1-c2-b3-m1-c2"
    @State private var tag = 0
    @State private var chain = 0.6
    @State private var swing = 0.5
    @State private var size = 0.6
    private var title: String { ["presets":"Default skins", "pattern":"Pattern", "accessory":"Accessory", "tag":"Tag", "background":"Background"][route.id] ?? "Skin" }
    var body: some View {
        WyrmDetailChrome(title: title, onBack: close) {
            ScrollView(showsIndicators: false) { VStack(spacing: 0) {
                if route.id == "presets" { presets }
                else if route.id == "pattern" { patternView }
                else if route.id == "accessory" { accessories }
                else if route.id == "tag" { tags }
                else { backgrounds }
                Text("This screen saves the design choice locally. Applying it to live snakes remains owned by the original engine skin bridge; no SwiftUI snake is substituted.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(20)
            } }
        }
    }
    private var presets: some View { VStack(spacing: 0) { WyrmSectionLabel("Presets load with the engine"); LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) { ForEach(0..<6) { index in Button { preset = index } label: { VStack(spacing: 8) { HStack(spacing: -5) { Circle().fill(presetColor(index)).frame(width: 24, height: 24); Circle().fill(presetColor(index).opacity(0.65)).frame(width: 19, height: 19) }; Text(String(format: "Preset %02d", index + 1)).font(.androidWyrm(9.5)).foregroundColor(ATheme.ink) }.frame(maxWidth: .infinity).frame(height: 82).background(Color.white).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(preset == index ? ATheme.ink : ATheme.rule, lineWidth: preset == index ? 2 : 1)) }.buttonStyle(.plain) } }.padding(.horizontal, 16) } }
    private var patternView: some View { VStack(spacing: 0) { WyrmSectionLabel("Your pattern"); WyrmPaperCard { TextField("Pattern code", text: $pattern).font(.androidWyrm(13)).textInputAutocapitalization(.never).disableAutocorrection(true).padding(14) }; HStack(spacing: 10) { WyrmOutlineAction(title: "Undo") {}; WyrmOutlineAction(title: "Clear", destructive: true) { pattern = "" } }.padding(16); WyrmSectionLabel("Original beads"); HStack { ForEach(0..<6) { index in Circle().fill(presetColor(index)).frame(width: 34, height: 34).onTapGesture { pattern += pattern.isEmpty ? "b\(index + 1)" : "-b\(index + 1)" } } }.frame(maxWidth: .infinity) } }
    private var accessories: some View { VStack(spacing: 0) { WyrmSectionLabel("Worn"); WyrmPaperCard { WyrmListRow(title: "Nothing yet", detail: "Accessories sit on the head and never affect play.", showsChevron: false) }; WyrmSectionLabel("All accessories"); LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) { ForEach(1...8, id: \.self) { value in Text(String(format: "%02d", value)).font(.androidWyrm(12, .bold)).frame(maxWidth: .infinity).frame(height: 58).background(Color.white).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)) } }.padding(.horizontal, 16) } }
    private var tags: some View { VStack(spacing: 0) { WyrmSectionLabel("Pick one"); LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) { ForEach(0..<6) { index in Button { tag = index } label: { Text(index == 0 ? "None" : "Tag \(String(format: "%02d", index))").font(.androidWyrm(11.5)).foregroundColor(ATheme.ink).frame(maxWidth: .infinity).frame(height: 56).background(Color.white).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(tag == index ? ATheme.ink : ATheme.rule, lineWidth: tag == index ? 2 : 1)) }.buttonStyle(.plain) } }.padding(.horizontal, 16); WyrmSectionLabel("How it moves"); slider("Chain", value: $chain); slider("Swing", value: $swing); slider("Size", value: $size) } }
    private var backgrounds: some View { VStack(spacing: 0) { WyrmSectionLabel("Arena floor"); HStack(spacing: 10) { ForEach(["Paper", "Graphite", "None"], id: \.self) { name in Button { background = name } label: { VStack(spacing: 8) { RoundedRectangle(cornerRadius: 10).fill(name == "Graphite" ? Color(white: 0.14) : name == "Paper" ? ATheme.paper : ATheme.track).frame(height: 56); Text(name).font(.androidWyrm(11.5)).foregroundColor(ATheme.ink) }.padding(8).background(Color.white).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(background == name ? ATheme.ink : ATheme.rule, lineWidth: background == name ? 2 : 1)) }.buttonStyle(.plain) } }.padding(.horizontal, 16) } }
    private func slider(_ title: String, value: Binding<Double>) -> some View { VStack(alignment: .leading, spacing: 6) { HStack { Text(title).font(.androidWyrm(13.5, .semibold)); Spacer(); Text("\(Int(value.wrappedValue * 100))%").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet) }; Slider(value: value).tint(ATheme.ink) }.padding(14).background(Color.white).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)).padding(.horizontal, 16).padding(.bottom, 10) }
    private func presetColor(_ index: Int) -> Color { [Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.62, green: 0.72, blue: 0.49), Color(red: 0.83, green: 0.60, blue: 0.48), ATheme.ink, Color(red: 0.56, green: 0.66, blue: 0.77), Color(red: 0.78, green: 0.64, blue: 0.79)][index % 6] }
}
