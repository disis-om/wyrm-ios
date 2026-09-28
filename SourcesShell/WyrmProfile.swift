import SwiftUI
import UIKit

/*
 * The profile (OM, 2026-09-29): laid out the way people already read a social
 * profile, in Wyrm's own paper look.
 *
 * - A header with the squircle avatar beside Trails, Followers and Following.
 * - Name, "follows you", bio, then the arena numbers as chips (Best, Kills).
 * - Edit profile + Share on your own profile; Follow + Message on another's.
 * - Ten badges (`backend/src/badges.mjs`), each with its progress ring.
 * - The player's trails as a three-column grid, paged as it scrolls.
 * - Tapping the avatar grows it into the middle of the screen. On your own
 *   profile a pill rises from the bottom and opens into Change photo, Remove
 *   this photo and Edit profile.
 *
 * Every part paints from the last visit at once (WyrmCache) and refreshes in
 * place; placeholders have the final sizes, so nothing jumps when data lands.
 * Android: `ProfileScreen.kt` (`IosProfileScreen`).
 */

// MARK: - Badges

struct WyrmBadge: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let earned: Bool
    let progress: Int
    let goal: Int

    var fraction: Double { goal > 0 ? min(1, Double(progress) / Double(goal)) : 0 }

    var icon: String {
        switch id {
        case "first-blood": return "drop.fill"
        case "hunter": return "scope"
        case "slayer": return "bolt.fill"
        case "big-snake": return "arrow.up.forward"
        case "giant": return "flame.fill"
        case "legend": return "crown.fill"
        case "trailblazer": return "sparkles"
        case "crowd-favourite": return "circle.hexagongrid.fill"
        case "social": return "person.3.fill"
        case "veteran": return "calendar"
        default: return "star.fill"
        }
    }
}

struct WyrmBadgeBook: Codable, Equatable {
    let badges: [WyrmBadge]
    let trailCount: Int
    let beads: Int
}

@MainActor
final class WyrmBadgeStore: ObservableObject {
    static let shared = WyrmBadgeStore()
    @Published private(set) var books: [String: WyrmBadgeBook] = [:]
    var token: () -> String = { "" }
    private var loading: Set<String> = []

    func load(_ id: String) async {
        guard !id.isEmpty else { return }
        if books[id] == nil, let cached = WyrmCache.load("badges-\(id)", as: WyrmBadgeBook.self) { books[id] = cached }
        guard !loading.contains(id) else { return }
        loading.insert(id)
        defer { loading.remove(id) }
        let token = token()
        guard let fresh = try? await Task(operation: { try await Self.fetch(id, token: token) }).value else { return }
        if books[id] != fresh { withAnimation(.easeOut(duration: 0.25)) { books[id] = fresh } }
        WyrmCache.save("badges-\(id)", fresh)
    }

    /// Sign-out: nothing of one account is shown to the next.
    func reset() { books = [:]; loading = [] }

    private static func fetch(_ id: String, token: String) async throws -> WyrmBadgeBook {
        guard let url = URL(string: "https://wyrm-api.77-245-76-86.sslip.io/v1/players/\(id)/badges") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(WyrmBadgeBook.self, from: data)
    }
}

// MARK: - Page

struct WyrmProfilePage: View {
    let playerID: String
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var trails = WyrmTrailsStore.shared
    @ObservedObject private var badgeStore = WyrmBadgeStore.shared

    @State private var avatarFrame: CGRect = .zero
    @State private var avatarMounted = false
    @State private var avatarExpanded = false
    @State private var optionsOpen = false
    @State private var choosingPhoto = false
    @State private var followBusy = false
    @State private var badgeShown: WyrmBadge?
    @State private var sharing = false
    /// Only what went wrong with the photo, not an older error on the account.
    @State private var photoError = ""

    private static let avatarSize: CGFloat = 86

    private var own: Bool { playerID.isEmpty || playerID == account.player?.id }
    private var targetID: String { own ? (account.player?.id ?? "") : playerID }
    private var other: WyrmServicePlayer? {
        services.profiles[playerID]
            ?? services.people.first(where: { $0.id == playerID })
            ?? services.followers.first(where: { $0.id == playerID })
            ?? services.following.first(where: { $0.id == playerID })
            ?? services.conversations.first(where: { $0.player.id == playerID })?.player
            ?? services.scoreLeaders.first(where: { $0.id == playerID })
            ?? services.killLeaders.first(where: { $0.id == playerID })
    }
    private var name: String { own ? (account.player?.displayName ?? "Wyrm") : (other?.displayName ?? "Player") }
    private var handle: String { own ? (account.player?.handle ?? "") : (other?.handle ?? "") }
    private var bio: String { own ? (account.player?.bio ?? "") : (other?.bio ?? "") }
    private var avatarURL: String { own ? (account.player?.avatarURL ?? "") : (other?.avatarURL ?? "") }
    private var initials: String { own ? (account.player?.initials ?? "W") : (other?.initials ?? "W") }
    private var score: Int64 { own ? (account.player?.highestScore ?? 0) : (other?.highestScore ?? 0) }
    private var kills: Int64 { own ? (account.player?.kills ?? 0) : (other?.kills ?? 0) }
    private var followers: Int64 { own ? (account.player?.followerCount ?? 0) : (other?.followerCount ?? 0) }
    private var following: Int64 { own ? (account.player?.followingCount ?? 0) : (other?.followingCount ?? 0) }
    private var grid: WyrmAuthorTrails? { trails.authors[targetID] }
    private var book: WyrmBadgeBook? { badgeStore.books[targetID] }
    private var trailCount: String {
        if let book { return Int64(book.trailCount).wyrmFormatted }
        if let grid, grid.loaded, grid.reachedEnd { return "\(grid.trails.count)" }
        return "–"
    }

    var body: some View {
        ZStack {
            WyrmDetailChrome(title: handle.isEmpty ? "Profile" : handle, actionTitle: own ? "Edit" : "", onBack: close,
                             action: { if own { open(.editProfile) } }) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        badgeStrip
                        gridHeader
                        gridBody
                        if own {
                            WyrmPaperCard {
                                WyrmListRow(title: "Sign out", destructive: true, showsChevron: false) { account.signOut() }
                            }
                            .padding(.top, 28)
                        }
                        Spacer().frame(height: 36)
                    }
                }
                .refreshable { await reload(pulled: true) }
            }
            if avatarMounted { avatarOverlay.zIndex(5) }
            if let badge = badgeShown { badgeOverlay(badge).zIndex(6) }
        }
        .task(id: targetID) { await reload(pulled: false) }
        .sheet(isPresented: $choosingPhoto) {
            WyrmPhotoPicker { image in
                choosingPhoto = false
                guard let image, let jpeg = WyrmPhotoPicker.jpeg(image) else { return }
                photoError = ""
                Task {
                    await account.uploadAvatar(jpeg)
                    photoError = account.errorMessage
                    if photoError.isEmpty { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            }
        }
        .sheet(isPresented: $sharing) {
            WyrmShareSheet(items: ["Find me on Wyrm: \(handle.isEmpty ? name : handle)"])
        }
    }

    /// Your own numbers come from the account, kept fresh by game sync; a pull
    /// asks the server for them too.
    private func reload(pulled: Bool) async {
        let token: () -> String = { [weak account] in account?.sessionToken ?? "" }
        trails.token = token
        badgeStore.token = token
        let id = targetID
        guard !id.isEmpty else { return }
        async let gridLoad: Void = trails.loadAuthor(id)
        async let badgeLoad: Void = badgeStore.load(id)
        if own { if pulled { await account.refreshProfile() } } else { await services.loadPlayer(playerID) }
        _ = await (gridLoad, badgeLoad)
    }

    private func connections(_ kind: String) {
        open(.people(own ? kind : "\(kind):\(playerID)"))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Button(action: expandAvatar) {
                    WyrmAvatar(initials: initials, size: Self.avatarSize, url: avatarURL)
                        .opacity(avatarMounted ? 0 : 1)
                        .background(GeometryReader { proxy in
                            let frame = proxy.frame(in: .global)
                            Color.clear
                                .onAppear { avatarFrame = frame }
                                .onChange(of: frame) { avatarFrame = $0 }
                        })
                }
                .buttonStyle(WSPressStyle())
                .accessibilityLabel(own ? "Your photo. Tap to change it." : "\(name)'s photo")
                HStack(spacing: 0) {
                    stat(trailCount, "Trails", action: nil)
                    stat(followers.wyrmFormatted, "Followers") { connections("followers") }
                    stat(following.wyrmFormatted, "Following") { connections("following") }
                }
            }
            HStack(spacing: 8) {
                Text(name).font(.androidWyrm(18, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
                if !own, other?.followsYou == true {
                    Text(other?.isFollowing == true ? "Friends" : "Follows you")
                        .font(.androidWyrm(10.5, .semibold)).foregroundColor(ATheme.live)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(ATheme.live.opacity(0.14)))
                }
            }
            .padding(.top, 14)
            if !bio.isEmpty {
                Text(bio).font(.androidWyrm(13.5)).foregroundColor(ATheme.mute).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            } else if own {
                Button { open(.editProfile) } label: {
                    Text("Add a line about how you play").font(.androidWyrm(13.5, .semibold)).foregroundColor(ATheme.link)
                }.buttonStyle(.plain).padding(.top, 4)
            }
            HStack(spacing: 8) {
                chip("trophy.fill", "Best", score.wyrmFormatted)
                chip("bolt.fill", "Kills", kills.wyrmFormatted)
                if let beads = book?.beads, beads > 0 { chip("circle.hexagongrid.fill", "Beads", Int64(beads).wyrmFormatted) }
            }
            .padding(.top, 12)
            actions.padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private func stat(_ value: String, _ label: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            VStack(spacing: 2) {
                Text(value).font(.androidWyrm(18, .bold)).foregroundColor(ATheme.ink).monospacedDigit().lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineLimit(1)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(WSPressStyle()).disabled(action == nil)
    }

    private func chip(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .bold)).foregroundColor(ATheme.quiet)
            Text(label).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
            Text(value).font(.androidWyrm(12, .bold)).foregroundColor(ATheme.ink)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(ATheme.well))
    }

    @ViewBuilder private var actions: some View {
        if own {
            HStack(spacing: 8) {
                profileButton("Edit profile", filled: false) { open(.editProfile) }
                profileButton("Share profile", filled: false) { sharing = true }
            }
        } else {
            let isFollowing = other?.isFollowing == true
            let followsYou = other?.followsYou == true
            let ready = other != nil && !followBusy
            HStack(spacing: 8) {
                profileButton(followBusy ? "…" : isFollowing ? "Following" : followsYou ? "Follow back" : "Follow",
                              filled: !isFollowing, enabled: ready, action: toggleFollow)
                profileButton("Message", filled: false, enabled: other?.canMessage == true) { open(.thread(playerID)) }
            }
            if other != nil, other?.canMessage != true {
                Text("You can message each other once you both follow.")
                    .font(.androidWyrm(11)).foregroundColor(ATheme.quiet).padding(.top, 6)
            }
        }
    }

    private func profileButton(_ title: String, filled: Bool, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.androidWyrm(14, .semibold))
                .foregroundColor(filled ? ATheme.onInk : ATheme.ink)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(filled ? ATheme.ink : ATheme.well))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(WSPressStyle()).disabled(!enabled)
        .animation(.easeOut(duration: 0.18), value: title)
    }

    private func toggleFollow() {
        guard let person = other, !followBusy else { return }
        followBusy = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await services.follow(person); followBusy = false }
    }

    // MARK: Badges

    private var badgeStrip: some View {
        let list = (book?.badges ?? []).enumerated().sorted { a, b in
            a.element.earned != b.element.earned ? a.element.earned : a.offset < b.offset
        }.map(\.element)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BADGES").font(.androidWyrm(10.5, .semibold)).tracking(0.9).foregroundColor(ATheme.quiet)
                Spacer()
                if let book {
                    Text("\(book.badges.filter(\.earned).count) of \(book.badges.count)")
                        .font(.androidWyrm(11.5, .semibold)).foregroundColor(ATheme.quiet)
                }
            }
            .padding(.horizontal, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    if list.isEmpty {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(spacing: 7) {
                                Circle().fill(ATheme.well).frame(width: 58, height: 58)
                                RoundedRectangle(cornerRadius: 4).fill(ATheme.well).frame(width: 48, height: 9)
                            }.frame(width: 70)
                        }
                    } else {
                        ForEach(list) { badge in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) { badgeShown = badge }
                            } label: { WyrmBadgeMedal(badge: badge, size: 58) }
                            .buttonStyle(WSPressStyle())
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .padding(.top, 24)
    }

    private func badgeOverlay(_ badge: WyrmBadge) -> some View {
        ZStack(alignment: .bottom) {
            ATheme.ink.opacity(0.3).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.22)) { badgeShown = nil } }
            VStack(spacing: 12) {
                WyrmBadgeMedal(badge: badge, size: 92, showsTitle: false)
                Text(badge.title).font(.androidWyrm(21, .bold)).foregroundColor(ATheme.ink)
                Text(badge.detail).font(.androidWyrm(14)).foregroundColor(ATheme.mute)
                if badge.earned {
                    Text("Earned").font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.live)
                        .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(ATheme.live.opacity(0.14)))
                } else {
                    VStack(spacing: 6) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ATheme.well)
                                Capsule().fill(ATheme.live).frame(width: max(8, proxy.size.width * badge.fraction))
                            }
                        }.frame(height: 8)
                        Text("\(Int64(badge.progress).wyrmFormatted) of \(Int64(badge.goal).wyrmFormatted)")
                            .font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.quiet)
                    }.padding(.horizontal, 30)
                }
                WSPrimaryButton(label: "Done") { withAnimation(.easeOut(duration: 0.22)) { badgeShown = nil } }
                    .padding(.horizontal, 20).padding(.top, 6)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(ATheme.rule))
            .padding(12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    // MARK: Trails grid

    private var gridHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.3x3.fill").font(.system(size: 13, weight: .semibold))
                Text("Trails").font(.androidWyrm(13.5, .semibold))
            }
            .foregroundColor(ATheme.ink)
            .frame(maxWidth: .infinity).frame(height: 44)
            .overlay(Rectangle().fill(ATheme.ink).frame(width: 90, height: 2), alignment: .bottom)
            Rectangle().fill(ATheme.rule).frame(height: 1)
        }
        .padding(.top, 20)
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    @ViewBuilder private var gridBody: some View {
        if let grid, grid.loaded, !grid.trails.isEmpty {
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(grid.trails) { trail in
                    Button { open(.trail(trail.id)) } label: { WyrmTrailTile(trail: trail) }
                        .buttonStyle(WSPressStyle())
                        .onAppear { Task { await trails.loadMoreAuthor(targetID, after: trail) } }
                }
            }
            .padding(.top, 2)
            if grid.loading, grid.cursor != nil {
                ProgressView().tint(ATheme.quiet).padding(.top, 14)
            }
        } else if let grid, grid.loaded {
            VStack(spacing: 10) {
                Image(systemName: grid.failed ? "wifi.exclamationmark" : "square.grid.3x3")
                    .font(.system(size: 26, weight: .semibold)).foregroundColor(ATheme.quiet)
                Text(grid.failed ? "Couldn't load trails" : own ? "Share your first trail" : "No trails yet")
                    .font(.androidWyrm(17, .semibold)).foregroundColor(ATheme.ink)
                Text(grid.failed ? "Pull down to try again." : own ? "A photo, a run, a few words. It shows up here and in Trails." : "When \(name) posts, it shows up here.")
                    .font(.androidWyrm(13)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center)
                if own && !grid.failed {
                    Button { open(.trailCompose) } label: {
                        Text("New trail").font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.onInk)
                            .padding(.horizontal, 22).frame(height: 40).background(Capsule().fill(ATheme.ink))
                    }.buttonStyle(WSPressStyle()).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.vertical, 40)
        } else {
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(0..<9, id: \.self) { index in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                        .background(ATheme.well.opacity(index % 2 == 0 ? 1 : 0.7))
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: Avatar

    private func expandAvatar() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        photoError = ""
        avatarMounted = true
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) { avatarExpanded = true }
            if own {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { optionsOpen = true }
                }
            }
        }
    }

    private func collapseAvatar(then next: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { optionsOpen = false }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { avatarExpanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            avatarMounted = false
            next?()
        }
    }

    private var avatarOverlay: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let big = min(proxy.size.width - 72, 300)
            let start = CGPoint(x: avatarFrame.midX - origin.x, y: avatarFrame.midY - origin.y)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * (own ? 0.38 : 0.44))
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(ATheme.paper.opacity(0.35))
                    .opacity(avatarExpanded ? 1 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { collapseAvatar() }

                VStack(spacing: 4) {
                    Text(name).font(.androidWyrm(20, .bold)).foregroundColor(ATheme.ink)
                    if !handle.isEmpty { Text(handle).font(.androidWyrm(13)).foregroundColor(ATheme.quiet) }
                    if own, !photoError.isEmpty {
                        Text(photoError).font(.androidWyrm(12)).foregroundColor(ATheme.badge)
                            .multilineTextAlignment(.center).padding(.top, 4).padding(.horizontal, 30)
                    }
                }
                .position(x: centre.x, y: centre.y + big / 2 + 44)
                .opacity(avatarExpanded ? 1 : 0)

                WyrmAvatar(initials: initials, size: big, url: avatarURL)
                    .overlay(Group {
                        if own && account.busy {
                            RoundedRectangle(cornerRadius: big * 0.3, style: .continuous).fill(Color.black.opacity(0.35))
                            ProgressView().tint(.white).scaleEffect(1.4)
                        }
                    })
                    .shadow(color: Color.black.opacity(avatarExpanded ? 0.22 : 0), radius: 30, y: 14)
                    .scaleEffect(avatarExpanded ? 1 : Self.avatarSize / big)
                    .position(avatarExpanded ? centre : start)
                    .onTapGesture { collapseAvatar() }

                if own {
                    optionsMorph(width: proxy.size.width)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - optionsHeight / 2 - max(40, proxy.safeAreaInsets.bottom + 12))
                }
            }
        }
        .ignoresSafeArea()
    }

    private var hasPhoto: Bool { !avatarURL.isEmpty }
    private var optionRows: Int { hasPhoto ? 3 : 2 }
    private var optionsHeight: CGFloat { optionsOpen ? CGFloat(optionRows) * 56 : 46 }

    /// A pill that opens into the photo options, as if the pill itself grew.
    private func optionsMorph(width: CGFloat) -> some View {
        let full = min(width - 32, 480)
        return VStack(spacing: 0) {
            if optionsOpen {
                optionRow("Change photo", icon: "photo.on.rectangle.angled", first: true) {
                    choosingPhoto = true
                }
                if hasPhoto {
                    optionRow("Remove this photo", icon: "trash", destructive: true) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        photoError = ""
                        Task {
                            await account.removeAvatar()
                            photoError = account.errorMessage
                        }
                    }
                }
                optionRow("Edit profile", icon: "pencil") {
                    collapseAvatar { open(.editProfile) }
                }
            } else {
                Capsule().fill(ATheme.quiet.opacity(0.5)).frame(width: 34, height: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: optionsOpen ? full : 120, height: optionsHeight)
        .background(RoundedRectangle(cornerRadius: optionsOpen ? 24 : 23, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: optionsOpen ? 24 : 23, style: .continuous).stroke(ATheme.rule))
        .clipShape(RoundedRectangle(cornerRadius: optionsOpen ? 24 : 23, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 10)
        .opacity(avatarExpanded ? 1 : 0)
        .scaleEffect(avatarExpanded ? 1 : 0.6, anchor: .bottom)
        .disabled(account.busy)
    }

    private func optionRow(_ title: String, icon: String, destructive: Bool = false, first: Bool = false,
                           action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(ATheme.rowRule).frame(height: 1) }
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                        .foregroundColor(destructive ? ATheme.badge : ATheme.ink).frame(width: 24)
                    Text(title).font(.androidWyrm(15.5, .semibold)).foregroundColor(destructive ? ATheme.badge : ATheme.ink)
                    Spacer()
                }
                .padding(.horizontal, 20).frame(height: 55).contentShape(Rectangle())
            }
            .buttonStyle(WSPressStyle())
        }
        .transition(.opacity)
    }
}

// MARK: - Pieces

struct WyrmBadgeMedal: View {
    let badge: WyrmBadge
    var size: CGFloat = 58
    var showsTitle = true

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(badge.earned ? ATheme.ink : ATheme.well)
                if badge.earned {
                    Circle().stroke(ATheme.live, lineWidth: max(2, size * 0.04)).padding(-size * 0.06)
                } else if badge.fraction > 0 {
                    Circle().trim(from: 0, to: badge.fraction)
                        .stroke(ATheme.live, style: StrokeStyle(lineWidth: max(2.5, size * 0.05), lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(size * 0.04)
                }
                Image(systemName: badge.icon).font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundColor(badge.earned ? ATheme.onInk : ATheme.quiet)
            }
            .frame(width: size, height: size)
            .padding(size * 0.06)
            if showsTitle {
                Text(badge.title).font(.androidWyrm(10.5, .semibold))
                    .foregroundColor(badge.earned ? ATheme.ink : ATheme.quiet).lineLimit(1)
                    .frame(width: size + 14)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title), \(badge.earned ? "earned" : "\(badge.progress) of \(badge.goal)")")
    }
}

/// One square in a profile's grid: the thumbnail filling the square, or the
/// words of a text trail on ink. Beads show when there are any.
struct WyrmTrailTile: View {
    let trail: WyrmTrail
    @State private var image: UIImage?

    init(trail: WyrmTrail) {
        self.trail = trail
        let address = trail.thumbUrl ?? trail.photo?.url
        _image = State(initialValue: address.flatMap { URL(string: WyrmTrailsClient.absolute($0)) }.flatMap { WyrmTrailImages.shared.cached($0) })
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(trail.photo == nil ? ATheme.ink : ATheme.well)
            .overlay(content)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if trail.likeCount > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(ATheme.live).frame(width: 7, height: 7)
                        Text("\(trail.likeCount)").font(.androidWyrm(11, .bold))
                    }
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.5), radius: 3)
                    .padding(7)
                }
            }
            .contentShape(Rectangle())
            .task(id: trail.id) { await loadImage() }
    }

    @ViewBuilder private var content: some View {
        if trail.photo != nil {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
            }
        } else {
            Text(trail.caption)
                .font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.onInk)
                .lineLimit(5).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(9)
        }
    }

    private func loadImage() async {
        guard image == nil, let address = trail.thumbUrl ?? trail.photo?.url,
              let url = URL(string: WyrmTrailsClient.absolute(address)) else { return }
        if let loaded = await WyrmTrailImages.shared.image(url) {
            withAnimation(.easeOut(duration: 0.18)) { image = loaded }
        }
    }
}
