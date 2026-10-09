import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A mutual follow's activity (OM, 2026-10-09; backend `presence.mjs`):
/// online (Wyrm open on screen), the arena they play in, or the last one they
/// played in and when. Android twin: `FriendActivity` in WyrmRepository.kt.
struct WyrmFriendActivity: Equatable {
    let playerID: String
    let online: Bool
    /// "playing", "online", "idle" or "offline".
    let state: String
    let arena: String?
    let sinceMs: Double?
    let lastArena: String?
    let lastPlayedAt: Date?
    let fetchedAt: Date

    var playing: Bool { online && state == "playing" && !(arena ?? "").isEmpty }

    /// "12 min" keeps counting between fetches.
    func since(_ now: Date) -> Double? { sinceMs.map { $0 + now.timeIntervalSince(fetchedAt) * 1000 } }
}

/// Presence (OM, 2026-10-09): what this player is doing, said on the live
/// socket when it changes (home, lobby, playing + arena, practice, idle after
/// two quiet minutes outside a match), and friends' activity for the social
/// pages. Android twin: `FriendPresence` + the presence part of WyrmOverlay.
@MainActor
final class WyrmPresence: ObservableObject {
    static let shared = WyrmPresence()
    private static let base = "https://wyrm-api.77-245-76-86.sslip.io"
    private static let idleAfter: TimeInterval = 120

    @Published private(set) var friends: [String: WyrmFriendActivity] = [:]
    /// "Show my activity to friends" as the account has it.
    @Published private(set) var sharing = true

    /// The session the friends list is fetched with (set with the live socket).
    var token = ""
    /// "Arena 4817" for a directory arena, else the address (set by the shell).
    var arenaName: (String) -> String = { $0 }
    /// Join from a friend's activity: the shell opens the lobby on that arena.
    var onJoin: (String) -> Void = { _ in }

    private var screen = 0
    private var practice = false
    private var arena = ""
    private var lastTouch = Date()
    private var idle = false
    private var lastRefresh = Date.distantPast
    private var ticker: Task<Void, Never>?

    func of(_ playerID: String?) -> WyrmFriendActivity? { playerID.flatMap { friends[$0] } }

    /// The arena a finished run was played in; nil for Play with AI.
    var runArena: String? { practice || arena.isEmpty ? nil : arena }

    // MARK: - This player

    /// A Play: online (with the arena) or with AI.
    func willPlay(online address: String?) {
        practice = address == nil
        if let address { arena = address }
    }

    func engineScreen(_ value: Int) {
        screen = value
        lastTouch = Date()
        idle = false
        push()
    }

    func touched() {
        lastTouch = Date()
        if idle { idle = false; push() }
    }

    func start() {
        WyrmTouchWatch.install { [weak self] in self?.touched() }
        lastTouch = Date()
        idle = false
        push()
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let quiet = self.screen != 2 && Date().timeIntervalSince(self.lastTouch) > Self.idleAfter
                if quiet != self.idle { self.idle = quiet; self.push() }
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    private func push() {
        let state: String
        if screen == 2 { state = practice ? "practice" : "playing" }
        else if idle { state = "idle" }
        else if screen == WyrmShellStore.lobbyScreen { state = "lobby" }
        else { state = "home" }
        WyrmLiveInbox.shared.setPresence(state: state, arena: state == "playing" && !arena.isEmpty ? arena : nil)
    }

    // MARK: - Friends

    /// At most every 15 s unless `force`; the social pages call it as they open.
    func refresh(force: Bool = false) async {
        guard !token.isEmpty, force || Date().timeIntervalSince(lastRefresh) >= 15 else { return }
        lastRefresh = Date()
        guard let json = await call("/v1/friends/presence", method: "GET", body: nil) else { return }
        sharing = json["sharing"] as? Bool ?? true
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var next: [String: WyrmFriendActivity] = [:]
        for row in json["friends"] as? [[String: Any]] ?? [] {
            guard let id = row["playerId"] as? String, !id.isEmpty else { continue }
            func text(_ key: String) -> String? { (row[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            next[id] = WyrmFriendActivity(
                playerID: id,
                online: row["online"] as? Bool ?? false,
                state: row["state"] as? String ?? "offline",
                arena: text("arena"),
                sinceMs: (row["sinceMs"] as? NSNumber)?.doubleValue,
                lastArena: text("lastArena"),
                lastPlayedAt: text("lastPlayedAt").flatMap { iso.date(from: $0) },
                fetchedAt: now)
        }
        friends = next
    }

    /// Settings › Privacy: on or off for the account; undone if the server says no.
    func setSharing(_ share: Bool) {
        let before = sharing
        sharing = share
        Task {
            if let json = await call("/v1/me/activity-sharing", method: "PUT", body: ["share": share]) {
                sharing = json["shareActivity"] as? Bool ?? share
                await refresh(force: true)
            } else {
                sharing = before
            }
        }
    }

    /// Sign-out: nothing of one account is shown to the next.
    func reset() {
        friends = [:]
        sharing = true
        token = ""
        lastRefresh = .distantPast
        arena = ""
        practice = false
    }

    private func call(_ path: String, method: String, body: [String: Any]?) async -> [String: Any]? {
        guard let url = URL(string: Self.base + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else { return nil }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Any touch on the window, without taking it (idle detection).
private final class WyrmTouchWatch: UIGestureRecognizer {
    private static var installed = false
    private var onTouch: () -> Void = {}

    static func install(_ onTouch: @escaping () -> Void) {
        guard !installed else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let watch = WyrmTouchWatch(target: nil, action: nil)
        watch.onTouch = onTouch
        watch.cancelsTouchesInView = false
        watch.delaysTouchesBegan = false
        watch.delaysTouchesEnded = false
        window.addGestureRecognizer(watch)
        installed = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// 45s, 12m, 3h 5m, 2d.
func wyrmShortSpan(_ ms: Double) -> String {
    let seconds = max(0, Int(ms / 1000))
    let minutes = seconds / 60
    let hours = minutes / 60
    if minutes < 1 { return "\(max(1, seconds))s" }
    if hours < 1 { return "\(minutes)m" }
    if hours < 24 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d"
}

/// A friend's activity in one line: "Playing in Arena 4817" + flag + how
/// long + Join; "Active now"; "Played in Arena 4817 · 2h ago". Same words as
/// Android's `FriendActivityLine`.
struct WyrmFriendActivityLine: View {
    let activity: WyrmFriendActivity?
    var size: CGFloat = 11.5
    var showsJoin = true
    @ObservedObject private var services = WyrmPresenceCountries.shared

    var body: some View {
        if let activity {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                line(activity, now: context.date)
            }
        }
    }

    @ViewBuilder private func line(_ activity: WyrmFriendActivity, now: Date) -> some View {
        if activity.playing, let arena = activity.arena {
            HStack(spacing: 6) {
                Text("Playing in \(WyrmPresence.shared.arenaName(arena))")
                    .font(.androidWyrm(size, .semibold)).foregroundColor(ATheme.live).lineLimit(1)
                WyrmArenaCountryBadge(country: services.country(arena))
                if let since = activity.since(now) {
                    Text(wyrmShortSpan(since)).font(.androidWyrm(size)).foregroundColor(ATheme.quiet).lineLimit(1)
                }
                if showsJoin {
                    Button { WyrmPresence.shared.onJoin(arena) } label: {
                        Text("Join").font(.androidWyrm(size, .bold)).foregroundColor(ATheme.onInk)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill(ATheme.ink))
                    }.buttonStyle(.plain)
                }
            }
        } else if activity.online {
            Text("Active now").font(.androidWyrm(size, .semibold)).foregroundColor(ATheme.live).lineLimit(1)
        } else if let last = activity.lastArena, let at = activity.lastPlayedAt {
            Text("Played in \(WyrmPresence.shared.arenaName(last)) · \(wyrmShortSpan(now.timeIntervalSince(at) * 1000)) ago")
                .font(.androidWyrm(size)).foregroundColor(ATheme.quiet).lineLimit(1)
        }
    }
}

/// Countries for friends' arenas (the directory's own list covers most).
@MainActor
final class WyrmPresenceCountries: ObservableObject {
    static let shared = WyrmPresenceCountries()
    @Published private var known: [String: String] = [:]
    private var asked: Set<String> = []
    /// Set by the shell: the directory's countries, when it has them.
    var directory: (String) -> String = { _ in "" }

    func country(_ endpoint: String) -> String {
        let address = String(endpoint.split(separator: ":").first ?? "")
        let fromDirectory = directory(address)
        if !fromDirectory.isEmpty { return fromDirectory }
        if let found = known[address] { return found }
        if !address.isEmpty, asked.insert(address).inserted {
            Task {
                let found = await WyrmServiceStore.lookupCountries([address])
                if let code = found[address] { known[address] = code.uppercased() }
            }
        }
        return ""
    }
}
