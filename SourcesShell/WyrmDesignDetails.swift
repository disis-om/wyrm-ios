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
        case .messages: WyrmMessagesDetail(account: account, services: services, close: close, open: open)
        case .thread(let id): WyrmThreadDetail(playerID: id, account: account, services: services, close: close)
        case .people(let kind): WyrmPeopleDetail(kind: kind, account: account, services: services, close: close, open: open)
        case .profile(let id): WyrmProfileDetail(playerID: id, account: account, services: services, close: close, open: open)
        case .editProfile: WyrmEditProfileDetail(account: account, close: close)
        case .voice: WyrmVoiceDetail(services: services, close: close, open: open)
        case .voiceVerification: WyrmVoiceVerificationDetail(services: services, close: close)
        case .room(let id): WyrmRoomDetail(roomID: id, services: services, close: close, open: open)
        case .call(let id): WyrmCallDetail(roomID: id, services: services, close: close)
        case .lobby: WyrmLobbyDetail(engine: engine, account: account, services: services, close: close)
        case .team, .teamChat, .teamConnect: WyrmTeamDetail(route: route, engine: engine, close: close, open: open)
        case .display: WyrmDisplayPage(engine: engine, close: close)
        case .controls: WyrmControlsPage(engine: engine, close: close)
        case .buttons: WyrmButtonsPage(engine: engine, close: close)
        case .modes: WyrmModesPage(engine: engine, close: close)
        case .bot: WyrmBotPage(engine: engine, close: close)
        case .food: WyrmFoodPage(engine: engine, close: close)
        case .playControls: WyrmControlsWorkspace(engine: engine, close: close)
        case .playModes: WyrmModesPage(engine: engine, parent: "Play", close: close)
        case .playFood: WyrmFoodPage(engine: engine, parent: "Play", close: close)
        case .notificationSettings: WyrmNotificationSettingsPage(close: close)
        case .privacy: WyrmPrivacyPage(close: close)
        case .themes: WyrmAccessibilityPage(close: close)
        case .backup: WyrmBackupPage(engine: engine, close: close, open: open)
        case .buildNotes: WyrmBuildNotesPage(close: close)
        case .globalChat: WyrmGlobalChatDetail(account: account, services: services, close: close, open: open)
        case .developer: WyrmDeveloperDetail(close: close)
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
                                    WyrmAvatar(initials: player.initials, size: 35, url: player.avatarURL)
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
    @ObservedObject var account: WyrmAccountStore
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
                    if !services.messageCandidates.isEmpty {
                        WyrmSectionLabel("People you can message")
                        WyrmPaperCard {
                            ForEach(services.messageCandidates) { person in
                                Button { open(.thread(person.id)) } label: {
                                    HStack(spacing: 12) {
                                        WyrmAvatar(initials: person.initials, size: 35, url: person.avatarURL)
                                        VStack(alignment: .leading, spacing: 2) { Text(person.displayName).font(.androidWyrm(14.5, .semibold)); Text(person.handle).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) }
                                        Spacer(); Image(systemName: "message.fill").foregroundColor(ATheme.link)
                                    }.foregroundColor(ATheme.ink).padding(.horizontal, 14).frame(minHeight: 56)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer().frame(height: 24)
                }
            }
            .task { if let id = account.player?.id { await services.loadConnectionLists(playerID: id) } }
            .refreshable { await services.refreshConversations(); if let id = account.player?.id { await services.loadConnectionLists(playerID: id) } }
        }
    }
}

private struct WyrmThreadDetail: View {
    let playerID: String
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    @State private var message = ""
    private var person: WyrmServicePlayer? { services.conversations.first(where: { $0.player.id == playerID })?.player ?? services.people.first(where: { $0.id == playerID }) ?? services.followers.first(where: { $0.id == playerID }) ?? services.following.first(where: { $0.id == playerID }) }
    var body: some View {
        WyrmDetailChrome(title: person?.displayName ?? "Message", onBack: close) {
            VStack(spacing: 0) {
                ScrollViewReader { _ in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 9) {
                            if services.messages.isEmpty { WyrmEmptyPanel(title: "Quiet so far", note: "Say hello when you are ready.") }
                            ForEach(services.messages) { row in
                                HStack { if row.authorID == account.player?.id { Spacer(minLength: 50) }; Text(row.body).font(.androidWyrm(13)).padding(.horizontal, 14).padding(.vertical, 10).background(row.authorID == account.player?.id ? ATheme.ink : ATheme.card).foregroundColor(row.authorID == account.player?.id ? ATheme.onInk : ATheme.ink).cornerRadius(15); if row.authorID != account.player?.id { Spacer(minLength: 50) } }.padding(.horizontal, 16)
                            }
                        }.padding(.vertical, 14)
                    }
                }
                HStack(spacing: 9) {
                    TextField("Message", text: $message).font(.androidWyrm(14)).padding(.horizontal, 14).frame(height: 44).background(ATheme.card).cornerRadius(14)
                    Button { send() } label: { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundColor(ATheme.onInk).frame(width: 44, height: 44).background(ATheme.ink).clipShape(Circle()) }.buttonStyle(.plain).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        if kind == "connections" {
            WyrmConnectionsDetail(account: account, services: services, close: close, open: open)
        } else {
        WyrmDetailChrome(title: kind == "following" ? "Following" : kind == "search" ? "People" : "Followers", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack { Image(systemName: "magnifyingglass").foregroundColor(ATheme.quiet); TextField("Search players", text: $query).font(.androidWyrm(14)); if !query.isEmpty { Button { Task { await services.searchPeople(query) } } label: { Image(systemName: "arrow.right.circle.fill").foregroundColor(ATheme.ink) } } }.padding(.horizontal, 14).frame(height: 46).background(ATheme.card).cornerRadius(14).padding(16)
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
}

private struct WyrmConnectionsDetail: View {
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State private var page = 0
    var body: some View {
        WyrmDetailChrome(title: "Connections", onBack: close) {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    segment("Followers", index: 0, count: services.followers.count)
                    segment("Following", index: 1, count: services.following.count)
                }.padding(6).background(ATheme.card.opacity(0.72)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(ATheme.rule)).padding(16)
                TabView(selection: $page) {
                    connectionList(services.followers, empty: "No followers yet").tag(0)
                    connectionList(services.following, empty: "Not following anyone yet").tag(1)
                }.tabViewStyle(.page(indexDisplayMode: .never))
            }
            .task { if let id = account.player?.id { await services.loadConnectionLists(playerID: id) } }
        }
    }
    private func segment(_ title: String, index: Int, count: Int) -> some View {
        Button { withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.8)) { page = index } } label: {
            HStack(spacing: 5) { Text(title); Text("\(count)").foregroundColor(ATheme.quiet) }.font(.androidWyrm(12.5, page == index ? .bold : .medium)).foregroundColor(ATheme.ink).frame(maxWidth: .infinity).frame(height: 38).background(page == index ? Color.white : .clear).cornerRadius(12)
        }.buttonStyle(.plain)
    }
    private func connectionList(_ rows: [WyrmServicePlayer], empty: String) -> some View {
        ScrollView(showsIndicators: false) { VStack(spacing: 0) { WyrmPaperCard {
            if rows.isEmpty { WyrmEmptyPanel(title: empty, note: "Connections update from your Wyrm account.") }
            ForEach(rows) { person in Button { open(.profile(person.id)) } label: { HStack(spacing: 12) { WyrmAvatar(initials: person.initials, size: 36, url: person.avatarURL); VStack(alignment: .leading, spacing: 2) { Text(person.displayName).font(.androidWyrm(14.5, .semibold)); Text(person.handle).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.chevron) }.foregroundColor(ATheme.ink).padding(.horizontal, 14).frame(minHeight: 58) }.buttonStyle(.plain) }
        }; Spacer().frame(height: 24) } }
    }
}

private struct WyrmProfileDetail: View {
    let playerID: String
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    private var own: Bool { playerID.isEmpty || playerID == account.player?.id }
    private var servicePlayer: WyrmServicePlayer? { services.profiles[playerID] ?? services.people.first(where: { $0.id == playerID }) ?? services.followers.first(where: { $0.id == playerID }) ?? services.following.first(where: { $0.id == playerID }) ?? services.conversations.first(where: { $0.player.id == playerID })?.player ?? services.scoreLeaders.first(where: { $0.id == playerID }) ?? services.killLeaders.first(where: { $0.id == playerID }) }
    var body: some View {
        WyrmDetailChrome(title: "Profile", actionTitle: own ? "Edit" : "", onBack: close, action: { if own { open(.editProfile) } }) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WyrmAvatar(initials: own ? (account.player?.initials ?? "W") : (servicePlayer?.initials ?? "W"), size: 76, url: own ? (account.player?.avatarURL ?? "") : (servicePlayer?.avatarURL ?? "")).padding(.top, 28)
                    Text(own ? (account.player?.displayName ?? "Wyrm") : (servicePlayer?.displayName ?? "Player")).font(.androidWyrm(27, .bold)).padding(.top, 14)
                    Text(own ? (account.player?.handle ?? "") : (servicePlayer?.handle ?? "")).font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
                    Text(profileBio).font(.androidWyrm(13)).foregroundColor(ATheme.mute).multilineTextAlignment(.center).padding(.horizontal, 34).padding(.top, 10)
                    HStack(spacing: 0) { WyrmMetric(label: "BEST", value: score.wyrmFormatted); Rectangle().fill(ATheme.rule).frame(width: 1, height: 48); WyrmMetric(label: "KILLS", value: kills.wyrmFormatted) }.background(ATheme.card).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(ATheme.rule)).padding(16)
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
        .task(id: playerID) { if !own { await services.loadPlayer(playerID) } }
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
    @State private var choosingPhoto = false
    var body: some View {
        WyrmDetailChrome(title: "Edit profile", actionTitle: "Save", onBack: close, action: save) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 13) {
                    VStack(spacing: 10) {
                        WyrmAvatar(initials: account.player?.initials ?? "W", size: 76, url: account.player?.avatarURL ?? "")
                        HStack(spacing: 18) {
                            Button(account.player?.avatarURL.isEmpty == false ? "Change photo" : "Add photo") { choosingPhoto = true }
                                .font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.link)
                            if account.player?.avatarURL.isEmpty == false {
                                Button("Remove") { Task { await account.removeAvatar() } }
                                    .font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.badge)
                            }
                        }
                        if account.busy { ProgressView().tint(ATheme.quiet) }
                    }.padding(.vertical, 8)
                    WyrmDesignEditField(label: "Display name", value: $displayName)
                    WyrmDesignEditField(label: "Arena name", value: $ingameName)
                    WyrmDesignEditField(label: "Username", value: $username)
                    WyrmDesignEditField(label: "Bio", value: $bio)
                    if let renames = account.renames {
                        Text("Renames left this month: display name \(renames.displayName) · username \(renames.username)")
                            .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !account.errorMessage.isEmpty { Text(account.errorMessage).font(.androidWyrm(12)).foregroundColor(.red) }
                    WyrmOutlineAction(title: "Delete account", destructive: true) { Task { await account.deleteAccount() } }
                }.padding(16)
            }.onAppear { displayName = account.player?.displayName ?? ""; ingameName = account.player?.ingameName ?? ""; username = account.player?.username ?? ""; bio = account.player?.bio ?? ""; avatar = account.player?.avatarKey ?? "mono-ink" }
        }
        .task { await account.loadRenames() }
        .sheet(isPresented: $choosingPhoto) {
            WyrmPhotoPicker { image in
                choosingPhoto = false
                guard let image, let jpeg = WyrmPhotoPicker.jpeg(image) else { return }
                Task { await account.uploadAvatar(jpeg) }
            }
        }
    }
    private func save() { Task { if await account.update(displayName: displayName, ingameName: ingameName, username: username, bio: bio, avatarKey: avatar) { close() } } }
}

private struct WyrmDesignEditField: View {
    let label: String
    @Binding var value: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(label.uppercased()).font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(ATheme.quiet); TextField(label, text: $value).font(.androidWyrm(15)).padding(.horizontal, 14).frame(height: 50).background(ATheme.card).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)) } }
}

private struct WyrmVoiceDetail: View {
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    private var official: [WyrmVoiceRoom] { services.voiceRooms.filter(\.managedPublic) }
    private var personal: [WyrmVoiceRoom] { services.voiceRooms.filter { !$0.managedPublic } }
    var body: some View {
        WyrmDetailChrome(title: "Voice rooms", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !services.voiceVerification.verified {
                        Button { open(.voiceVerification) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "checkmark.shield.fill").font(.system(size: 22)).foregroundColor(ATheme.live)
                                VStack(alignment: .leading, spacing: 3) { Text("Your voice profile is not verified").font(.androidWyrm(14.5, .bold)); Text("Verify once to create and enter player rooms.").font(.androidWyrm(11)).foregroundColor(ATheme.quiet) }
                                Spacer(); Text("Verify").font(.androidWyrm(12.5, .bold)).foregroundColor(ATheme.link)
                            }.foregroundColor(ATheme.ink).padding(16).background(ATheme.card.opacity(0.9)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(ATheme.live.opacity(0.35)))
                        }.buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 16)
                    }
                    WyrmSectionLabel("Official Wyrm rooms")
                    WyrmPaperCard {
                        if official.isEmpty { WyrmEmptyPanel(title: "Official rooms are quiet", note: "Wyrm-managed public rooms appear here first.") }
                        ForEach(official) { room in WyrmOfficialRoomRow(room: room) { open(.room(room.id)) } }
                    }
                    WyrmSectionLabel("Player rooms · \(personal.count)")
                    WyrmPaperCard {
                        if personal.isEmpty { WyrmEmptyPanel(title: "No player rooms yet", note: "Your rooms and rooms from other players will appear here.") }
                        ForEach(personal) { room in WyrmListRow(title: room.name, detail: room.mine ? "Your room" : "by \(room.creator.displayName)", value: room.active ? "\(room.activeCount) live" : room.gate.capitalized, icon: room.active ? "waveform" : "mic", tint: room.active ? ATheme.live : ATheme.mute) { open(.room(room.id)) } }
                    }
                    Spacer().frame(height: 24)
                }
            }.task { await services.refreshVoiceVerification() }.refreshable { await services.refreshVoice(); await services.refreshVoiceVerification() }
        }
    }
}

private struct WyrmOfficialRoomRow: View {
    let room: WyrmVoiceRoom
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 9).fill(ATheme.ink.opacity(0.06)); Text("W").font(.androidWyrm(17, .bold)).foregroundColor(ATheme.ink.opacity(0.38)) }.frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) { Text(room.name).font(.androidWyrm(14.5, .semibold)); Text("Wyrm · direct entry").font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet) }
                Spacer(); Text(room.active ? "\(room.activeCount)/\(room.capacity) live" : "Public").font(.androidWyrm(11.5, .semibold)).foregroundColor(room.active ? ATheme.live : ATheme.quiet); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.chevron)
            }.foregroundColor(ATheme.ink).padding(.horizontal, 14).frame(minHeight: 58)
        }.buttonStyle(.plain).overlay(Rectangle().fill(ATheme.rowRule).frame(height: 1).padding(.leading, 64), alignment: .bottom)
    }
}

private struct WyrmVoiceVerificationDetail: View {
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    @State private var email = ""
    @State private var code = ""
    @State private var stage = 0
    @State private var working = false
    var body: some View {
        WyrmDetailChrome(title: "Voice verification", onBack: close) {
            ZStack {
                if services.voiceVerification.verified {
                    VStack(spacing: 14) { Image(systemName: "checkmark.seal.fill").font(.system(size: 66)).foregroundColor(ATheme.live); Text("Voice profile verified").font(.androidWyrm(24, .bold)); Text("You can now enter and create player voice rooms.").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet); WyrmPrimaryAction(title: "Return to rooms") { close() }.frame(maxWidth: 300).padding(.top, 12) }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    VStack(spacing: 18) {
                        Spacer()
                        ZStack { Circle().fill(ATheme.live.opacity(0.12)).frame(width: 92, height: 92); Image(systemName: stage == 0 ? "envelope.badge.shield.half.filled" : "number.square.fill").font(.system(size: 38, weight: .light)).foregroundColor(ATheme.live) }
                            .id(stage).transition(.wyrmCinematicPush)
                        Text(stage == 0 ? "Verify your email" : "Enter the six-digit code").font(.androidWyrm(24, .bold)).multilineTextAlignment(.center)
                        Text(stage == 0 ? "Wyrm sends one private code. Your email is protected by the voice control plane." : "The code expires shortly. You can resend it without restarting this flow.").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center).padding(.horizontal, 34)
                        if stage == 0 {
                            TextField("name@example.com", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).disableAutocorrection(true).font(.androidWyrm(15)).padding(.horizontal, 15).frame(height: 52).background(ATheme.card).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(ATheme.rule)).padding(.horizontal, 24)
                            WyrmPrimaryAction(title: working ? "Sending…" : "Send code", disabled: working || !email.contains("@")) { begin() }.padding(.horizontal, 24)
                        } else {
                            TextField("000000", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).font(.androidWyrm(24, .bold)).multilineTextAlignment(.center).padding(.horizontal, 15).frame(height: 56).background(ATheme.card).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(ATheme.rule)).padding(.horizontal, 24)
                            WyrmPrimaryAction(title: working ? "Checking…" : "Verify", disabled: working || code.count != 6) { confirm() }.padding(.horizontal, 24)
                            Button("Resend code") { Task { _ = await services.resendVoiceVerification(email: email) } }.font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.link)
                        }
                        if !services.errorMessage.isEmpty { Text(services.errorMessage).font(.androidWyrm(11.5)).foregroundColor(.red).padding(.horizontal, 24) }
                        Spacer()
                    }.transition(.wyrmCinematicPush)
                }
            }.animation(.interactiveSpring(response: 0.5, dampingFraction: 0.84), value: stage).animation(.easeInOut(duration: 0.36), value: services.voiceVerification.verified)
        }
    }
    private func begin() { working = true; Task { let ok = await services.startVoiceVerification(email: email.trimmingCharacters(in: .whitespacesAndNewlines)); await MainActor.run { working = false; if ok { withAnimation { stage = 1 } } } } }
    private func confirm() { working = true; Task { _ = await services.confirmVoiceVerification(code: String(code.prefix(6))); await MainActor.run { working = false } } }
}

private struct WyrmRoomDetail: View {
    let roomID: String
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State private var password = ""
    private var room: WyrmVoiceRoom? { services.voiceRooms.first(where: { $0.id == roomID }) }
    var body: some View {
        WyrmDetailChrome(title: room?.name ?? "Room", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 9) { Image(systemName: "waveform.circle.fill").font(.system(size: 62, weight: .light)).foregroundColor(room?.active == true ? ATheme.live : ATheme.quiet); Text(room?.active == true ? "Room is live" : "Room is quiet").font(.androidWyrm(24, .bold)); Text("\(room?.activeCount ?? 0) of \(room?.capacity ?? 10) people").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet) }.padding(.vertical, 34)
                    WyrmPaperCard {
                        WyrmListRow(title: room?.managedPublic == true ? "Managed by" : "Created by", value: room?.managedPublic == true ? "Wyrm" : (room?.creator.displayName ?? ""), showsChevron: false)
                        WyrmListRow(title: "Access", value: room?.gate.capitalized ?? "Open", showsChevron: false)
                        WyrmListRow(title: "Status", value: room?.suspended == true ? "Suspended" : "Available", showsChevron: false)
                    }
                    if let room {
                        if !room.managedPublic && !room.member && services.voiceVerification.verified {
                            SecureField("8-character room key", text: $password).textInputAutocapitalization(.never).disableAutocorrection(true).font(.androidWyrm(14)).padding(.horizontal, 14).frame(height: 50).background(ATheme.card).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)).padding(.horizontal, 16).padding(.top, 16)
                        }
                        WyrmPrimaryAction(title: room.member ? "Open call" : room.managedPublic ? "Enter public room" : services.voiceVerification.verified ? "Join room" : "Verify to join", icon: "mic.fill", disabled: !room.managedPublic && !room.member && services.voiceVerification.verified && password.count != 8) { if room.member { open(.call(room.id)) } else if !room.managedPublic && !services.voiceVerification.verified { open(.voiceVerification) } else { Task { await services.joinVoice(room, password: password); if services.errorMessage.isEmpty { open(.call(room.id)) } } } }.padding(16)
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
            }.onAppear { name = engine.nickname.isEmpty ? (account.player?.arenaName ?? "") : engine.nickname; arena = engine.arena.isEmpty ? (services.arenas.first?.endpoint ?? "") : engine.arena }
        }
    }
    private var cleanName: String { let value = name.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? "Wyrm Player" : String(value.prefix(24)) }
}

private struct WyrmTeamDetail: View {
    let route: WyrmDesignRoute
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @EnvironmentObject private var team: WyrmTeamStore
    @State private var teamID = ""
    @State private var auth = ""
    @State private var message = ""
    @State private var error = ""
    var body: some View {
        WyrmDetailChrome(title: title, onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if route.id == "team-connect" {
                        WyrmSectionLabel("NTL Team")
                        VStack(spacing: 12) {
                            WyrmDesignEditField(label: "Team ID", value: $teamID)
                            SecureField("Auth key", text: $auth)
                                .font(.androidWyrm(14)).textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true).padding(14)
                                .background(ATheme.card).cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ATheme.rule))
                            if !error.isEmpty { Text(error).font(.androidWyrm(11.5, .semibold)).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading) }
                            WyrmPrimaryAction(title: "Connect Team", icon: "lock.shield.fill",
                                              disabled: teamID.count < 16 || auth.count < 16) {
                                do { try team.connect(auth: auth, teamID: teamID); auth = ""; close() }
                                catch { self.error = error.localizedDescription }
                            }
                        }.padding(16)
                        Text("Auth and Team ID remain in this iPhone's Keychain. Diagnostics never include either value. Presence follows NTL 9.68 every four seconds.")
                            .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(.horizontal, 20)
                    } else if route.id == "team-chat" {
                        if team.chat.isEmpty {
                            WyrmPaperCard { WyrmEmptyPanel(title: "No Team messages yet", note: "Messages from your connected NTL Team appear here.") }.padding(.top, 18)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(team.chat) { line in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(line.author.uppercased()).font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(ATheme.live)
                                        Text(line.body).font(.androidWyrm(13)).frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(14).background(ATheme.card).cornerRadius(14)
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ATheme.rule))
                                }
                            }.padding(16)
                        }
                        HStack(spacing: 10) {
                            TextField("Message the team", text: $message).font(.androidWyrm(13)).padding(12).background(ATheme.card).cornerRadius(12)
                            Button("Send") { team.send(message); message = "" }
                                .font(.androidWyrm(12, .bold)).disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(16)
                    } else {
                        WyrmSectionLabel("Team mode")
                        WyrmPaperCard {
                            WyrmListRow(title: team.teamID.isEmpty ? "No team connected" : maskedTeamID,
                                        detail: statusDetail, value: statusValue, showsChevron: false)
                        }
                        if !team.members.isEmpty {
                            WyrmSectionLabel("Live roster")
                            WyrmPaperCard {
                                ForEach(team.members) { member in
                                    Button {
                                        guard member.arena != "_GAME_MENU_" else { return }
                                        engine.enterLobby(name: engine.nickname.isEmpty ? "Wyrm Player" : engine.nickname, address: member.arena)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Circle().fill(member.arena == engine.arena ? ATheme.live : ATheme.quiet.opacity(0.3)).frame(width: 8, height: 8)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(member.name).font(.androidWyrm(14.5, .semibold))
                                                Text(member.arena == "_GAME_MENU_" ? "In menu" : member.arena)
                                                    .font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("#\(member.rank)").font(.androidWyrm(11, .bold))
                                                Text("tag \(member.tag)").font(.androidWyrm(9.5)).foregroundColor(ATheme.quiet)
                                            }
                                            if member.arena != "_GAME_MENU_" { Image(systemName: "arrow.up.right").foregroundColor(ATheme.quiet) }
                                        }.padding(.horizontal, 15).frame(minHeight: 62).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        VStack(spacing: 10) {
                            WyrmPrimaryAction(title: team.teamID.isEmpty ? "Add a team" : "Edit connection", icon: "person.3.fill") { open(.teamConnect) }
                            if !team.teamID.isEmpty {
                                WyrmOutlineAction(title: "Open team chat") { open(.teamChat) }
                                Button("Disconnect Team") { team.disconnect() }.font(.androidWyrm(11.5, .semibold)).foregroundColor(.red).padding(.top, 4)
                            }
                        }.padding(16)
                    }
                }
            }
        }
        .onAppear { teamID = team.teamID; NSLog("Wyrm SwiftUI NTL Team presented state=%@", statusValue) }
    }
    private var title: String { route.id == "team-chat" ? "Team chat" : route.id == "team-connect" ? "Connect" : "Team mode" }
    private var maskedTeamID: String { "•••• \(team.teamID.suffix(4))" }
    private var statusValue: String {
        switch team.state { case .connected: return "Live"; case .connecting: return "Joining"; case .failed: return "Offline"; case .disconnected: return "" }
    }
    private var statusDetail: String {
        switch team.state {
        case .connected: return "\(team.members.count) members · NTL 9.68 compatible"
        case .connecting: return "Publishing selected tag and arena presence"
        case .failed(let text): return text
        case .disconnected: return "Use the Auth and Team ID from your NTL Team."
        }
    }
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
                    .background(ATheme.card.opacity(0.94))
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
