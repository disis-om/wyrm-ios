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
        case .thread(let id): WyrmThreadDetail(playerID: id, account: account, services: services, close: close, open: open)
        case .people(let kind): WyrmPeopleDetail(kind: kind, account: account, services: services, close: close, open: open)
            // The end of the new-follower trail: your connections, seen.
            .onAppear { if kind == "connections" { services.markKindsRead(["follow"]) } }
        case .profile(let id): WyrmProfilePage(playerID: id, account: account, services: services, close: close, open: open)
        case .alerts: WyrmAlertsPage(services: services, engine: engine, open: open, close: close)
        case .editProfile: WyrmEditProfileDetail(account: account, close: close)
        case .voice: WyrmVoiceDetail(services: services, close: close, open: open)
            // The end of the voice-invite trail: seen once the rooms are open.
            .onAppear { services.markKindsRead(["voice_invite"]) }
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
        case .performance: WyrmPerformancePage(close: close)
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
        case .about: WyrmAboutPage(close: close)
        case .trails:
            // Switched off: the Social card opens the "in development" page.
            if WyrmTrailsFeature.enabled { WyrmTrailsFeed(account: account, close: close, open: open) }
            else { WyrmTrailsComingSoon(close: close) }
        case .trail(let id): WyrmTrailDetail(trailID: id, account: account, close: close, open: open)
            // The end of the trail-reply trail: this trail's likes and replies, seen.
            .onAppear { services.markTrailRead(id) }
        case .trailCompose: WyrmTrailStudio(account: account, close: close)
        case .help: WyrmHelpCenterPage(account: account, close: close, open: open)
        case .supportCompose(let kind): WyrmSupportComposePage(account: account, initialKind: kind, close: close, open: open)
        case .supportReports: WyrmSupportReportsPage(account: account, close: close, open: open)
        }
    }
}

/// Leaderboard search (same rules as Android `leaderboardMatches`): every word
/// must hit one of name, @username, in-game name, score or kills. A number is
/// matched against the digits of score and kills, so "1,500" finds 1500.
func wyrmLeaderboardMatches(_ player: WyrmServicePlayer, _ query: String) -> Bool {
    let words = query.lowercased().split(separator: " ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if words.isEmpty { return true }
    let names = [player.displayName, player.username, player.ingameName].map { $0.lowercased() }
    let numbers = [String(player.highestScore), String(player.kills)]
    return words.allSatisfy { word in
        let bare = word.hasPrefix("@") ? String(word.dropFirst()) : word
        let digits = word.filter { $0.isASCII && $0.isNumber }
        let numeric = !digits.isEmpty && word.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "," || $0 == "." }
        return (!bare.isEmpty && names.contains { $0.contains(bare) }) || (numeric && numbers.contains { $0.contains(digits) })
    }
}

private struct WyrmLeaderboardDetail: View {
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State private var sort = 0
    @State private var query = ""
    private var rows: [WyrmServicePlayer] { sort == 0 ? services.scoreLeaders : services.killLeaders }
    /// Keeps the real rank: searching narrows the list, it does not re-rank it.
    private var shown: [(offset: Int, element: WyrmServicePlayer)] {
        rows.enumerated().filter { wyrmLeaderboardMatches($0.element, query) }.map { (offset: $0.offset, element: $0.element) }
    }
    var body: some View {
        WyrmDetailChrome(title: "Leaderboard", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Picker("Rank by", selection: $sort) { Text("Score").tag(0); Text("Kills").tag(1) }.pickerStyle(.segmented).padding(16)
                    if !rows.isEmpty { WyrmSettingsSearchField(query: $query, placeholder: "Name, @username, score or kills") }
                    WyrmPaperCard {
                        if rows.isEmpty { WyrmEmptyPanel(title: "No ranked players yet", note: "Finished runs will appear here.") }
                        else if shown.isEmpty { WyrmEmptyPanel(title: "No one found", note: "Nobody on this board matches “\(query.trimmingCharacters(in: .whitespaces))”.") }
                        ForEach(shown, id: \.element.id) { index, player in
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
    @ObservedObject private var presence = WyrmPresence.shared
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    var body: some View {
        WyrmDetailChrome(title: "Messages", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    WyrmSectionLabel("Conversations")
                    WyrmPaperCard {
                        if services.conversations.isEmpty { WyrmEmptyPanel(title: "No messages yet", note: "Mutual follows can start a private conversation.") }
                        // Instagram's inbox (2026-10-09): their face (green dot while
                        // Wyrm is open), name, the last message or the arena they play in.
                        ForEach(services.conversations) { row in
                            let activity = presence.of(row.player.id)
                            let unread = row.unreadCount > 0
                            Button { open(.thread(row.player.id)) } label: {
                                HStack(spacing: 12) {
                                    WyrmAvatar(initials: row.player.initials, size: 44, url: row.player.avatarURL, online: activity?.online == true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.player.displayName).font(.androidWyrm(15, unread ? .bold : .semibold)).lineLimit(1)
                                        if activity?.playing == true {
                                            WyrmFriendActivityLine(activity: activity)
                                        } else {
                                            Text(row.lastMessage.isEmpty ? "No messages yet" : row.lastMessage)
                                                .font(.androidWyrm(12.5, unread ? .semibold : .regular))
                                                .foregroundColor(unread ? ATheme.ink : ATheme.quiet).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 6)
                                    if unread { WyrmCountBadge(count: row.unreadCount) }
                                }.foregroundColor(ATheme.ink).padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 64)
                            }.buttonStyle(.plain)
                        }
                    }
                    if !services.messageCandidates.isEmpty {
                        WyrmSectionLabel("People you can message")
                        WyrmPaperCard {
                            ForEach(services.messageCandidates) { person in
                                Button { open(.thread(person.id)) } label: {
                                    HStack(spacing: 12) {
                                        let activity = presence.of(person.id)
                                        WyrmAvatar(initials: person.initials, size: 35, url: person.avatarURL, online: activity?.online == true)
                                        WyrmPersonText(name: person.displayName, handle: person.handle, activity: activity)
                                        Spacer(); Image(systemName: "message.fill").foregroundColor(ATheme.link)
                                    }.foregroundColor(ATheme.ink).padding(.horizontal, 14).frame(minHeight: 56)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer().frame(height: 24)
                }
            }
            .task {
                await presence.refresh()
                if let id = account.player?.id { await services.loadConnectionLists(playerID: id) }
            }
            .refreshable {
                await services.refreshConversations()
                await presence.refresh(force: true)
                if let id = account.player?.id { await services.loadConnectionLists(playerID: id) }
            }
        }
    }
}

/// A direct conversation laid out like Instagram's (OM, 2026-10-09): the
/// other player's face and name in the bar, their profile card at the top of
/// the thread (alone when nothing has been said yet), their face beside the
/// last bubble of each of their runs, and the time between runs that are far
/// apart. Wyrm's colours, not Instagram's.
private struct WyrmThreadDetail: View {
    let playerID: String
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    @ObservedObject private var presence = WyrmPresence.shared
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State private var message = ""
    @State private var sending = false
    private var person: WyrmServicePlayer? { services.profiles[playerID] ?? services.conversations.first(where: { $0.player.id == playerID })?.player ?? services.people.first(where: { $0.id == playerID }) ?? services.followers.first(where: { $0.id == playerID }) ?? services.following.first(where: { $0.id == playerID }) }
    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 0) {
                header
                Rectangle().fill(ATheme.rule).frame(height: 1)
                WyrmChatTranscript(messages: services.messages, myID: account.player?.id, showsAuthors: false,
                                   peer: person, onPeer: { open(.profile(playerID)) })
                WyrmChatComposer(text: $message, placeholder: "Message…", limit: 1000,
                                 sending: sending, onSend: send)
            }
        }
        .foregroundColor(ATheme.ink)
        // A thread is live while it is open, like Global chat.
        .task {
            await services.loadPlayer(playerID)
            var beat = 0
            while !Task.isCancelled {
                await services.loadThread(playerID: playerID)
                // The other player's activity, every ~30 s while the thread is open.
                if beat % 8 == 0 { await presence.refresh() }
                beat += 1
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    /// Back, then the other player's face, name and handle (opens their profile).
    private var header: some View {
        HStack(spacing: 6) {
            Button(action: close) {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                    .foregroundColor(ATheme.ink).frame(width: 36, height: 44)
            }.buttonStyle(.plain)
            Button { open(.profile(playerID)) } label: {
                HStack(spacing: 10) {
                    let activity = presence.of(playerID)
                    WyrmAvatar(initials: person?.initials ?? "W", size: 34, url: person?.avatarURL ?? "", online: activity?.online == true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person?.displayName ?? "Message").font(.androidWyrm(15.5, .bold)).lineLimit(1)
                        if let activity, activity.online || activity.lastArena != nil {
                            WyrmFriendActivityLine(activity: activity)
                        } else if let handle = person?.handle, !handle.isEmpty {
                            Text(handle).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineLimit(1)
                        }
                    }
                }
            }.buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 10).frame(height: 58).background(ATheme.paper)
    }
    private func send() {
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        message = ""
        sending = true
        Task { await services.sendDirect(playerID: playerID, body: String(body.prefix(1000))); sending = false }
    }
}

/// A name, then a friend's activity when there is one, else the handle (2026-10-09).
private struct WyrmPersonText: View {
    let name: String
    let handle: String
    let activity: WyrmFriendActivity?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.androidWyrm(14.5, .semibold)).lineLimit(1)
            if let activity, activity.online || activity.lastArena != nil {
                WyrmFriendActivityLine(activity: activity, size: 11)
            } else if !handle.isEmpty {
                Text(handle).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet).lineLimit(1)
            }
        }
    }
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
        // "followers" / "following" are yours; "followers:<id>" another player's.
        let parts = kind.split(separator: ":", maxSplits: 1).map(String.init)
        let list = parts.first ?? kind
        WyrmDetailChrome(title: list == "following" ? "Following" : list == "search" ? "People" : "Followers", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack { Image(systemName: "magnifyingglass").foregroundColor(ATheme.quiet); TextField("Search players", text: $query).font(.androidWyrm(14)); if !query.isEmpty { Button { Task { await services.searchPeople(query) } } label: { Image(systemName: "arrow.right.circle.fill").foregroundColor(ATheme.ink) } } }.padding(.horizontal, 14).frame(height: 46).background(ATheme.card).cornerRadius(14).padding(16)
                    WyrmPaperCard {
                        if services.people.isEmpty { WyrmEmptyPanel(title: "No people to show", note: query.isEmpty ? "This list updates from your real Wyrm connections." : "Try another name or username.") }
                        ForEach(services.people) { person in WyrmListRow(title: person.displayName, detail: person.handle, value: person.isFollowing ? "Following" : "", icon: "person.crop.circle.fill") { open(.profile(person.id)) } }
                    }
                    Spacer().frame(height: 24)
                }
            }.task {
                guard list != "search", let id = parts.count > 1 ? parts[1] : account.player?.id else { return }
                await services.loadConnections(playerID: id, kind: list)
            }
        }
        }
    }
}

private struct WyrmConnectionsDetail: View {
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    @ObservedObject private var presence = WyrmPresence.shared
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
            .task {
                await presence.refresh()
                if let id = account.player?.id { await services.loadConnectionLists(playerID: id) }
            }
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
            ForEach(rows) { person in Button { open(.profile(person.id)) } label: { HStack(spacing: 12) { WyrmAvatar(initials: person.initials, size: 36, url: person.avatarURL, online: presence.of(person.id)?.online == true); WyrmPersonText(name: person.displayName, handle: person.handle, activity: presence.of(person.id)); Spacer(); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.chevron) }.foregroundColor(ATheme.ink).padding(.horizontal, 14).frame(minHeight: 58) }.buttonStyle(.plain) }
        }; Spacer().frame(height: 24) } }
    }
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

/// Voice rooms, redesigned (OM, 2026-09-30): one card per room like a
/// modern audio app, as Android draws it (`IosVoiceDirectory`). Who is
/// talking now; a verify card until verified; official Wyrm rooms (the real
/// Wyrm mark); the player's own room; live rooms; quiet rooms.
private struct WyrmVoiceDetail: View {
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    private var official: [WyrmVoiceRoom] { services.voiceRooms.filter(\.managedPublic) }
    private var mine: [WyrmVoiceRoom] { services.voiceRooms.filter { $0.mine && !$0.managedPublic } }
    private var live: [WyrmVoiceRoom] { services.voiceRooms.filter { !$0.managedPublic && !$0.mine && $0.active } }
    private var quiet: [WyrmVoiceRoom] { services.voiceRooms.filter { !$0.managedPublic && !$0.mine && !$0.active } }
    private var talking: Int { services.voiceRooms.filter(\.active).reduce(0) { $0 + $1.activeCount } }
    var body: some View {
        WyrmDetailChrome(title: "Voice rooms", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        WyrmVoiceLiveBars(colour: talking > 0 ? ATheme.live : ATheme.quiet, playing: talking > 0, height: 13)
                        Text(talking > 0 ? "\(talking) \(talking == 1 ? "person" : "people") talking now" : "No one is talking yet")
                            .font(.androidWyrm(13, .semibold)).foregroundColor(talking > 0 ? ATheme.live : ATheme.quiet)
                        Spacer()
                    }
                    .padding(.horizontal, 22).padding(.top, 14)
                    if !services.voiceVerification.verified {
                        Button { open(.voiceVerification) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "checkmark.shield.fill").font(.system(size: 22)).foregroundColor(ATheme.onInk)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Verify once, talk anywhere").font(.androidWyrm(14.5, .bold)).foregroundColor(ATheme.onInk)
                                    Text("One email code unlocks player rooms. Official rooms are open now.")
                                        .font(.androidWyrm(11.5)).foregroundColor(ATheme.onInk.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 6)
                                Text("Verify").font(.androidWyrm(12.5, .bold)).foregroundColor(ATheme.ink)
                                    .padding(.horizontal, 13).padding(.vertical, 7).background(Capsule().fill(ATheme.onInk))
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.ink))
                        }
                        .buttonStyle(WSPressStyle()).padding(.horizontal, 16).padding(.top, 14)
                    }
                    WyrmVoiceSectionTitle(title: "Official Wyrm rooms", note: "Open to everyone")
                    if official.isEmpty { WyrmPaperCard { WyrmEmptyPanel(title: "Official rooms are quiet", note: "Wyrm-managed public rooms appear here first.") } }
                    ForEach(official) { room in WyrmVoiceRoomCard(room: room) { open(.room(room.id)) } }
                    if !mine.isEmpty {
                        WyrmVoiceSectionTitle(title: "Your room")
                        ForEach(mine) { room in WyrmVoiceRoomCard(room: room) { open(.room(room.id)) } }
                    }
                    WyrmVoiceSectionTitle(title: "Live now", note: live.isEmpty ? "" : "\(live.count)")
                    if live.isEmpty {
                        Text(quiet.isEmpty ? "No player rooms yet." : "No player room is live right now.")
                            .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.vertical, 4)
                    }
                    ForEach(live) { room in WyrmVoiceRoomCard(room: room) { open(.room(room.id)) } }
                    if !quiet.isEmpty {
                        WyrmVoiceSectionTitle(title: "Quiet rooms", note: "\(quiet.count)")
                        ForEach(quiet) { room in WyrmVoiceRoomCard(room: room) { open(.room(room.id)) } }
                    }
                    Spacer().frame(height: 24)
                }
            }.task { await services.refreshVoiceVerification() }.refreshable { await services.refreshVoice(); await services.refreshVoiceVerification() }
        }
    }
}

/// The server's voice codes in plain words, as Android says them (`voiceMessage`).
private func wyrmVoiceText(_ raw: String) -> String {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "": return ""
    case "VOICE_VERIFICATION_REQUIRED": return "Verify your profile once to use player rooms."
    case "ROOM_PASSWORD_INCORRECT": return "That code didn't work. Check it with the room's creator."
    case "ROOM_PASSWORD_REQUIRED": return "Enter the room code to join."
    case "ROOM_CODE_CHANGED": return "The creator changed the code. Ask them for the new one."
    case "ROOM_CLOSED": return "This room is closed right now. Try again when its creator opens it."
    case "ROOM_FULL": return "This room already has 10 people."
    case "ROOM_BANNED": return "You can't join this room."
    case "ROOM_SUSPENDED": return "This room is paused by Wyrm."
    case "ROOM_NOT_FOUND": return "This room is gone."
    case "VOICE_DISABLED": return "Voice rooms aren't available yet."
    case "VOICE_JOIN_PAUSED": return "New joins are paused for a moment."
    default: return raw
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

/// A room before joining (OM, 2026-09-30): art, name, maker, a live line,
/// facts and one action. A private room asks for its code in eight boxes and
/// says how to get one ("Don't have a code? Ask <creator> for it.").
private struct WyrmRoomDetail: View {
    let roomID: String
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State private var code = ""
    @State private var joining = false
    private var room: WyrmVoiceRoom? { services.voiceRooms.first(where: { $0.id == roomID }) }
    var body: some View {
        WyrmDetailChrome(title: "Voice room", onBack: close) {
            ScrollView(showsIndicators: false) {
                if let room {
                    content(room)
                } else {
                    WyrmPaperCard { WyrmEmptyPanel(title: "This room is gone", note: "Pull to refresh the rooms.") }.padding(.top, 20)
                }
            }
        }
    }

    private func content(_ room: WyrmVoiceRoom) -> some View {
        let verified = services.voiceVerification.verified
        let error = wyrmVoiceText(services.errorMessage)
        let needsCode = verified && !room.managedPublic && !room.mine && (!room.member || !error.isEmpty)
        let needsVerify = !verified && !room.managedPublic
        let canJoin = !joining && (!needsCode || code.count == 8)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                WyrmVoiceRoomArt(room: room, size: 88)
                Text(room.name).font(.androidWyrm(28, .bold)).foregroundColor(ATheme.ink).multilineTextAlignment(.center).padding(.top, 14)
                if room.managedPublic {
                    Text("Official Wyrm room").font(.androidWyrm(13)).foregroundColor(ATheme.quiet).padding(.top, 6)
                } else {
                    Button { open(.profile(room.creator.id)) } label: {
                        HStack(spacing: 7) {
                            WyrmAvatar(initials: String(room.creator.displayName.prefix(2)).uppercased(), size: 20, url: room.creator.avatarURL)
                            Text("by \(room.creator.displayName)").font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.mute)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }.buttonStyle(.plain).padding(.top, 6)
                }
                HStack(spacing: 7) {
                    WyrmVoiceLiveBars(colour: room.active ? ATheme.live : ATheme.quiet, playing: room.active, height: 11)
                    Text(room.active ? "Live · \(room.activeCount) of \(room.capacity) inside"
                         : (room.gate != "open" && !room.managedPublic) ? "Closed right now" : "Quiet · be the first one in")
                        .font(.androidWyrm(12.5, .semibold)).foregroundColor(room.active ? ATheme.live : ATheme.mute)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(room.active ? ATheme.live.opacity(0.13) : ATheme.well))
                .padding(.top, 12)
            }
            .padding(.horizontal, 24).padding(.top, 26)
            WyrmVoiceFacts(room: room).padding(.top, 20)
            if needsCode {
                WyrmVoiceRoomCodeField(code: $code, creator: room.creator.displayName, error: error,
                                       askCreator: { open(.profile(room.creator.id)) }, done: { if canJoin { join(room) } })
                    .padding(.horizontal, 20).padding(.top, 24)
            } else if !error.isEmpty {
                Text(error).font(.androidWyrm(12.5)).foregroundColor(.red).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 16)
            }
            Button {
                if room.member { open(.call(room.id)) }
                else if needsVerify { open(.voiceVerification) }
                else { join(room) }
            } label: {
                HStack(spacing: 9) {
                    if joining { ProgressView().tint(.white) } else { Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)) }
                    Text(joining ? "Joining…" : needsVerify ? "Verify to join" : room.member ? "Open call" : room.mine ? "Join your room" : "Join room")
                        .font(.androidWyrm(16, .bold))
                }
                .foregroundColor(canJoin ? .white : ATheme.quiet)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Capsule().fill(canJoin ? ATheme.live : ATheme.well))
            }
            .buttonStyle(WSPressStyle()).disabled(!canJoin)
            .padding(.horizontal, 20).padding(.top, needsCode ? 20 : 24)
            Text("You join muted. Tap the mic when you want to talk.")
                .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).padding(.top, 10)
            if room.member {
                WyrmOutlineAction(title: "Leave room", destructive: true) { Task { await services.leaveVoice(room); close() } }
                    .padding(.horizontal, 20).padding(.top, 18)
            }
            Spacer().frame(height: 32)
        }
    }

    /// One tap, straight in: no separate checks first (the server makes them).
    private func join(_ room: WyrmVoiceRoom) {
        guard !joining else { return }
        joining = true
        Task {
            await services.joinVoice(room, password: code)
            await MainActor.run {
                joining = false
                if services.errorMessage.isEmpty { open(.call(room.id)) }
            }
        }
    }
}

/// In the room (OM, 2026-09-30): the room's art and name, a live line, and a
/// dock of round controls. Talking on iPhone needs the realtime audio adapter,
/// which is not built yet; the page says so plainly.
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
                if let room { WyrmVoiceRoomArt(room: room, size: 96) }
                Text(room?.name ?? "Voice room").font(.androidWyrm(28, .bold)).multilineTextAlignment(.center).padding(.top, 16).padding(.horizontal, 24)
                HStack(spacing: 7) {
                    WyrmVoiceLiveBars(colour: ATheme.live, playing: true, height: 11)
                    Text("You're in · \(room?.activeCount ?? 1) in the room").font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.live)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(ATheme.live.opacity(0.13))).padding(.top, 12)
                Text("Talking and listening on iPhone come in a later build. Android players can already talk here.")
                    .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 14)
                Spacer()
                HStack(spacing: 0) {
                    WyrmVoiceDockButton(symbol: muted ? "mic.slash.fill" : "mic.fill", label: muted ? "Unmute" : "Mute", on: !muted) { muted.toggle() }
                        .frame(maxWidth: .infinity)
                    WyrmVoiceDockButton(symbol: deafened ? "speaker.slash.fill" : "speaker.wave.2.fill", label: deafened ? "Sound off" : "Sound") { deafened.toggle() }
                        .frame(maxWidth: .infinity)
                    if let room {
                        WyrmVoiceDockButton(symbol: "phone.down.fill", label: "Leave", danger: true) { Task { await services.leaveVoice(room); close() } }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .padding(.horizontal, 12).padding(.bottom, 24)
            }
        }
    }
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
    @State private var teamName = ""
    @State private var teamID = ""
    @State private var auth = ""
    @State private var message = ""
    @State private var error = ""
    @State private var confirmRemove = false

    var body: some View {
        WyrmDetailChrome(title: title, onBack: close) {
            if route.id == "team-chat" {
                chatPage
            } else if route.id == "team-connect" {
                ScrollView(showsIndicators: false) { connectPage }
            } else {
                ScrollView(showsIndicators: false) { overviewPage }
            }
        }
        // Team settings live behind the gear, top right, as on the other pages.
        .overlay(alignment: .topTrailing) {
            if route.id == "team" { settingsMenu.padding(.trailing, 14).frame(height: 52) }
        }
        .onAppear {
            let editing = team.connectEditing.flatMap { id in team.saved.first { $0.id == id } }
            teamName = editing?.name ?? ""
            teamID = editing?.teamID ?? ""
            NSLog("Wyrm SwiftUI NTL Team presented state=%@", statusValue)
        }
    }

    // MARK: Chat

    /// The transcript scrolls; the composer stays on the bottom edge, on the
    /// keys when typing, exactly like Global chat.
    private var chatPage: some View {
        VStack(spacing: 0) {
            WyrmChatTranscript(messages: chatItems, myID: engine.nickname, showsAuthors: true,
                               emptyTitle: "No Team messages yet",
                               emptyNote: "Messages from your connected NTL Team appear here.")
            WyrmChatComposer(text: $message, placeholder: "Message the team", limit: 280, sending: false) {
                team.send(message)
                message = ""
            }
        }
    }

    private var chatItems: [WyrmChatItem] {
        let stamp = ISO8601DateFormatter()
        return team.chat.map {
            WyrmChatItem(id: $0.id, body: $0.body, createdAt: stamp.string(from: $0.at),
                         authorID: $0.author, authorName: $0.author, authorUsername: "")
        }
    }

    // MARK: Connect

    private var editingTeam: WyrmSavedTeam? { team.connectEditing.flatMap { id in team.saved.first { $0.id == id } } }

    private var connectPage: some View {
        VStack(spacing: 0) {
            WyrmSectionLabel(editingTeam == nil ? "Add an NTL Team" : "Edit \(editingTeam?.name ?? "team")")
            VStack(spacing: 12) {
                WyrmDesignEditField(label: "Name (optional)", value: $teamName)
                WyrmDesignEditField(label: "Team ID", value: $teamID)
                SecureField(editingTeam == nil ? "Auth key" : "Auth key (enter it again)", text: $auth)
                    .font(.androidWyrm(14)).textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true).padding(14)
                    .background(ATheme.card).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(ATheme.rule))
                if !error.isEmpty { Text(error).font(.androidWyrm(11.5, .semibold)).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading) }
                WyrmPrimaryAction(title: editingTeam == nil ? "Save and connect" : "Save changes", icon: "lock.shield.fill",
                                  disabled: teamID.count < 16 || auth.count < 16) {
                    do {
                        try team.connect(auth: auth, teamID: teamID, name: teamName, editing: team.connectEditing)
                        auth = ""
                        close()
                    } catch { self.error = error.localizedDescription }
                }
            }.padding(16)
            Text("Auth and Team ID remain in this iPhone's Keychain. Diagnostics never include either value. You can keep several teams; only the one you pick runs.")
                .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(.horizontal, 20)
        }
    }

    // MARK: Overview

    private var overviewPage: some View {
        VStack(spacing: 0) {
            if WyrmTeamStore.ntlServicesDisabled {
                WyrmSectionLabel("Paused")
                WyrmPaperCard {
                    WyrmListRow(title: "Team mode is paused",
                                detail: "NTL services are switched off in this build: nothing is sent to or received from NTL while arena drops are being fixed. Your saved teams stay on this iPhone.",
                                showsChevron: false)
                }
            }
            WyrmSectionLabel("Team mode")
            WyrmPaperCard {
                WyrmListRow(title: team.selected?.name ?? "No team connected",
                            detail: statusDetail, value: statusValue, showsChevron: false)
            }
            if !team.members.isEmpty {
                WyrmSectionLabel("Live roster")
                WyrmPaperCard {
                    ForEach(team.members) { member in rosterRow(member) }
                }
            }
            VStack(spacing: 10) {
                if team.selected == nil {
                    if team.saved.isEmpty {
                        WyrmPrimaryAction(title: "Add a team", icon: "person.3.fill") { addTeam() }
                    } else {
                        teamsMenu {
                            Label("Pick a saved team", systemImage: "person.3.fill")
                                .font(.androidWyrm(15, .semibold)).foregroundColor(ATheme.onInk)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.ink))
                        }
                    }
                } else if !WyrmTeamStore.ntlServicesDisabled {
                    WyrmPrimaryAction(title: "Open team chat", icon: "bubble.left.and.bubble.right.fill") { open(.teamChat) }
                }
            }.padding(16)
        }
    }

    /// Name, key owner and arena on the left; FPS, ping and leaderboard place on the right.
    private func rosterRow(_ member: WyrmTeamMember) -> some View {
        Button {
            guard member.arena != "_GAME_MENU_" else { return }
            engine.enterLobby(name: engine.nickname, address: member.arena)
        } label: {
            HStack(spacing: 12) {
                Circle().fill(member.arena == engine.arena ? ATheme.live : ATheme.quiet.opacity(0.3)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(.androidWyrm(14.5, .semibold)).lineLimit(1)
                    Text([member.owner.isEmpty ? nil : "Key \(member.owner)",
                          member.arena == "_GAME_MENU_" ? "In menu" : member.arena].compactMap { $0 }.joined(separator: " · "))
                        .font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet).lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    if let fps = member.fps { stat("\(fps) fps") }
                    if let ping = member.ping { stat("\(ping) ms") }
                    if member.rank > 0 { stat("LB #\(member.rank)", strong: true) }
                }
                if member.arena != "_GAME_MENU_" { Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundColor(ATheme.quiet) }
            }.padding(.horizontal, 15).frame(minHeight: 62).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func stat(_ text: String, strong: Bool = false) -> some View {
        Text(text).font(.androidWyrm(10, .bold)).monospacedDigit()
            .foregroundColor(strong ? ATheme.onInk : ATheme.ink)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(strong ? ATheme.ink : ATheme.well))
    }

    // MARK: Settings menu

    private func addTeam() {
        team.connectEditing = nil
        open(.teamConnect)
    }

    private func teamsMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu(content: {
            Section("Saved teams") {
                ForEach(team.saved) { saved in
                    Button { team.select(saved.id) } label: {
                        if saved.id == team.selectedTeam { Label(saved.name, systemImage: "checkmark") } else { Text(saved.name) }
                    }
                }
            }
        }, label: label)
    }

    private var settingsMenu: some View {
        Menu {
            if !team.saved.isEmpty {
                Section("Saved teams") {
                    ForEach(team.saved) { saved in
                        Button { team.select(saved.id) } label: {
                            if saved.id == team.selectedTeam { Label(saved.name, systemImage: "checkmark") } else { Text(saved.name) }
                        }
                    }
                }
            }
            Section {
                Button { addTeam() } label: { Label("Add another team", systemImage: "plus") }
                if let current = team.selected {
                    Button {
                        team.connectEditing = current.id
                        open(.teamConnect)
                    } label: { Label("Edit connection", systemImage: "pencil") }
                }
            }
            if let current = team.selected {
                Section {
                    Button(role: .destructive) { team.disconnect() } label: { Label("Disconnect team", systemImage: "wifi.slash") }
                    Button(role: .destructive) { team.remove(current.id) } label: { Label("Remove this team", systemImage: "trash") }
                }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ATheme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(WyrmGlass.native ? Color.clear : ATheme.card))
                .contentShape(Circle())
        }
        .modifier(WyrmGlassCircleButton())
        .accessibilityLabel("Team settings")
    }

    private var title: String { route.id == "team-chat" ? "Team chat" : route.id == "team-connect" ? "Connect" : "Team mode" }
    private var statusValue: String {
        switch team.state { case .connected: return "Live"; case .connecting: return "Joining"; case .failed: return "Offline"; case .disconnected: return "" }
    }
    private var statusDetail: String {
        switch team.state {
        case .connected: return "\(team.members.count) members · NTL 9.68 compatible"
        case .connecting: return "Joining your team"
        case .failed(let text): return text
        case .disconnected: return team.saved.isEmpty ? "Use the Auth and Team ID from your NTL Team." : "Pick a saved team from the gear."
        }
    }
}

private struct WyrmDeveloperDetail: View {
    let close: () -> Void
    @ObservedObject private var diagnostics = WyrmDiagnostics.shared
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var confirmClear = false
    // The log opens folded: it is thousands of lines. Drawn as separate lazy
    // lines, because one 2 MB Text is more than SwiftUI will lay out and the
    // block came up empty white.
    @State private var logOpen = false
    @State private var lines: [String] = []
    private static let shownLines = 2000

    private func reloadLines() {
        let all = diagnostics.text.split(separator: "\n", omittingEmptySubsequences: true)
        lines = all.suffix(Self.shownLines).map(String.init)
    }

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
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { logOpen.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "text.alignleft").font(.system(size: 14, weight: .semibold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(logOpen ? "Hide log" : "Show log").font(.androidWyrm(15, .semibold))
                                Text(lines.count >= Self.shownLines ? "Latest \(lines.count) lines" : "\(lines.count) lines")
                                    .font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                            }
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                                .rotationEffect(.degrees(logOpen ? 180 : 0))
                        }
                        .foregroundColor(ATheme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(ATheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(ATheme.rule))
                        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(WSPressStyle())
                    .padding(.horizontal, 16)
                    .accessibilityLabel(logOpen ? "Hide log" : "Show log")

                    if logOpen {
                        ScrollViewReader { proxy in
                            ZStack(alignment: .bottomTrailing) {
                                ScrollView(.vertical, showsIndicators: true) {
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        ForEach(lines.indices, id: \.self) { index in
                                            Text(lines[index])
                                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                                .foregroundColor(ATheme.ink)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        Color.clear.frame(height: 44).id("log-end")
                                    }
                                    .padding(12)
                                }
                                .frame(height: 440)
                                // To the newest line as the log opens.
                                .onAppear { DispatchQueue.main.async { proxy.scrollTo("log-end", anchor: .bottom) } }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("log-end", anchor: .bottom) }
                                } label: {
                                    Image(systemName: "arrow.down").font(.system(size: 15, weight: .bold))
                                        .foregroundColor(ATheme.onInk)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(WyrmGlass.native ? Color.clear : ATheme.ink))
                                        .contentShape(Circle())
                                }
                                .modifier(WyrmGlassCircleButton(tint: ATheme.ink))
                                .padding(12)
                                .accessibilityLabel("Scroll to the latest log line")
                            }
                        }
                        .background(ATheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(ATheme.rule))
                        .padding(.horizontal, 16).padding(.top, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Text("Exports include app lifecycle, safe network status and SDL3/original-engine events. Tokens, passwords and private message bodies are never written.")
                        .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(3).padding(20)
                }
            }
            .onAppear { diagnostics.refresh(); reloadLines(); WyrmDiagnostics.record("developer console opened", category: "DIAGNOSTICS") }
            .onReceive(diagnostics.$text) { _ in reloadLines() }
            .sheet(isPresented: $showingShare) {
                if let shareURL = shareURL { WyrmShareSheet(items: [shareURL]) }
            }
        }
    }
}
