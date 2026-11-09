import SwiftUI
import UserNotifications
import ImageIO

/*
 * Events (OM, 2026-10-30), the same as Android (data/WyrmEvents.kt,
 * ui/EventsScreens.kt, ui/EventArt.kt): the event servers' tournaments as
 * Wyrm's backend serves them (`/v1/events`, `/v1/events/:id`,
 * backend/src/events.mjs). The backend keeps the organisers' feed in memory
 * only and adds the Wyrm players of each event, the arena's live board and,
 * signed in, friends. The look of each card comes from the feed's own type
 * words, so a new wording still lands on the right card; a type Wyrm has no
 * card for keeps its own name on the universal card.
 */

enum WyrmEventKind {
    case lastOneStanding, teamLastStanding, lastDuoStanding, paintball, battledome, other

    static func of(_ type: String?) -> WyrmEventKind {
        let t = (type ?? "").uppercased()
        if t.contains("DUO") { return .lastDuoStanding }
        if t.contains("PAINT") { return .paintball }
        if t.contains("TEAM") { return .teamLastStanding }
        if t.contains("BATTLEDOME") || t.contains("DOME") { return .battledome }
        if t.contains("STANDING") || t.contains("KICKOUT") { return .lastOneStanding }
        return .other
    }

    /// The type in words: our name for the five we know, the feed's own otherwise.
    func name(_ type: String?) -> String {
        switch self {
        case .lastOneStanding: return "Last One Standing"
        case .teamLastStanding: return "Last Team Standing"
        case .lastDuoStanding: return "Last Duo Standing"
        case .paintball: return "Paintball"
        case .battledome: return "Battledome"
        case .other:
            let raw = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, raw.lowercased() != "unknown" else { return "Community Event" }
            var out = ""
            var start = true
            for ch in raw.lowercased() {
                out.append(start ? Character(String(ch).uppercased()) : ch)
                start = ch == " " || ch == "(" || ch == "-" || ch == "/"
            }
            return out
        }
    }

    var blurb: String {
        switch self {
        case .lastOneStanding: return "Every snake for itself. Players are knocked out until one is left."
        case .teamLastStanding: return "Play with your team. The last team with a snake alive wins."
        case .lastDuoStanding: return "Play in pairs. The last duo with a snake alive wins."
        case .paintball: return "A paint fight in the arena. The organisers' message has the rules."
        case .battledome: return "A closed dome that shrinks. Stay inside and outlast everyone."
        case .other: return "A community event on this server. The organisers' message has the details."
        }
    }
}

/* ---------------------------------------------------------------- JSON */

private extension Dictionary where Key == String, Value == Any {
    func evString(_ key: String) -> String? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        let text = value as? String ?? String(describing: value)
        return text.isEmpty || text == "null" ? nil : text
    }
    func evInt(_ key: String) -> Int? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        return (value as? String).flatMap { Int($0) }
    }
    func evInt64(_ key: String) -> Int64? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        return (value as? String).flatMap { Int64($0) }
    }
    func evDouble(_ key: String) -> Double? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        return (value as? String).flatMap { Double($0) }
    }
    func evBool(_ key: String) -> Bool? {
        guard let value = self[key], !(value is NSNull) else { return nil }
        if let flag = value as? Bool { return flag }
        return (value as? NSNumber)?.boolValue
    }
    func evObject(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func evArray(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
}

private func wyrmEventDate(_ iso: String?) -> Date? {
    guard let iso, !iso.isEmpty else { return nil }
    let full = ISO8601DateFormatter()
    full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return full.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
}

/* ---------------------------------------------------------------- models */

struct WyrmEventRegistration: Equatable {
    /// true = sign up on Discord first, false = no sign-up, nil = the feed does not say.
    let discord: Bool?
    /// "channels" (sign up in their channel) or "verified" (verified players are in), or nil.
    let mode: String?
    let autoAccept: Bool?
    let url: String?
}

struct WyrmEvent: Identifiable, Equatable {
    let id: String
    let eventNumber: Int?
    /// "upcoming", "live" or "finished".
    let status: String
    let type: String?
    let kind: WyrmEventKind
    let serverCode: String
    let flag: String
    let region: String
    /// "ip:port", never with http.
    let address: String
    let startsAt: Date?
    let startedAt: Date?
    let endedAt: Date?
    let durationSeconds: Int64?
    let players: Int?
    let prizeUsd: Double?
    let roundMinutes: Int?
    let teamNames: Bool?
    let reconstructed: Bool
    let registration: WyrmEventRegistration
    let title: String?
    let prizeText: String?
    let markdown: String?
    let rules: [String]
    /// Wyrm players in it; nil before it starts.
    let wyrmPlayers: Int?

    var name: String { kind.name(type) }
    /// The organisers' server code without its port suffix ("AE_443" -> "AE").
    var serverLabel: String { String(serverCode.split(separator: "_", maxSplits: 1).first ?? Substring(serverCode)) }
    var needsSignUp: Bool { registration.discord == true }
    /// When it began (or was planned to), for a live event's clock.
    var began: Date? { startedAt ?? startsAt }

    init?(_ json: [String: Any]) {
        let server = json.evObject("server") ?? [:]
        let prize = json.evObject("prize")
        let reg = json.evObject("registration") ?? [:]
        let description = json.evObject("description")
        let raw = json.evObject("raw")
        guard let id = json.evString("id"), let address = server.evString("address") else { return nil }
        self.id = id
        eventNumber = json.evInt("eventNumber")
        status = json.evString("status") ?? "finished"
        type = json.evString("type")
        kind = WyrmEventKind.of(type)
        serverCode = server.evString("code") ?? ""
        flag = server.evString("flag") ?? ""
        region = server.evString("region") ?? ""
        self.address = address
        startsAt = wyrmEventDate(json.evString("startsAt"))
        startedAt = wyrmEventDate(json.evString("startedAt"))
        endedAt = wyrmEventDate(json.evString("endedAt"))
        durationSeconds = json.evInt64("durationSeconds")
        players = json.evInt("players")
        // The server sends the prize in dollars too (OM: show it in dollars).
        prizeUsd = raw?.evDouble("prize_usd") ?? prize?.evDouble("usd")
            ?? (prize?.evString("currency") == "USD" ? prize?.evDouble("amount") : nil)
        roundMinutes = json.evInt("roundMinutes") ?? raw?.evInt("round_min")
        teamNames = json.evBool("teamNames")
        reconstructed = json.evBool("reconstructed") ?? false
        registration = WyrmEventRegistration(discord: reg.evBool("discord"), mode: reg.evString("mode"),
                                             autoAccept: reg.evBool("autoAccept"), url: reg.evString("url"))
        title = description?.evString("title")
        prizeText = description?.evString("prizeText")
        markdown = description?.evString("markdown")
        rules = ((description?["rules"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        wyrmPlayers = json.evInt("wyrmPlayers")
    }

    static func == (a: WyrmEvent, b: WyrmEvent) -> Bool {
        a.id == b.id && a.status == b.status && a.players == b.players && a.wyrmPlayers == b.wyrmPlayers
            && a.startsAt == b.startsAt && a.startedAt == b.startedAt && a.endedAt == b.endedAt
    }
}

struct WyrmEventPlayer: Identifiable {
    let playerId: String
    let name: String
    let avatarUrl: String
    let bestScore: Int64?
    let kills: Int64?
    let runs: Int
    let playingNow: Bool
    var id: String { playerId }

    init(_ json: [String: Any]) {
        playerId = json.evString("playerId") ?? UUID().uuidString
        name = json.evString("name") ?? json.evString("username") ?? "Player"
        avatarUrl = WyrmTrailsClient.absolute(json.evString("avatarUrl") ?? "")
        bestScore = json.evInt64("bestScore")
        kills = json.evInt64("kills")
        runs = json.evInt("runs") ?? 0
        playingNow = json.evBool("playingNow") ?? false
    }
}

struct WyrmLeaderboardLine: Identifiable {
    let rank: Int
    let name: String
    let score: Int64
    var id: Int { rank }
}

/**
 * The monitor's minimap (backend arena-status.mjs `mapSvgDataUrl`): an SVG of
 * `size` x `size` cells, each lit cell a small square in one of three tones.
 * Read straight into cells so the app draws it itself, no SVG library.
 */
struct WyrmArenaMinimapCells {
    let size: Int
    let cells: [[Int]]
    /// Most arenas now send a PNG (white dots on clear, 2026-10-31): drawn as it is.
    var image: CGImage? = nil

    static func parse(_ dataUrl: String?) -> WyrmArenaMinimapCells? {
        guard let dataUrl, !dataUrl.isEmpty else { return nil }
        if dataUrl.hasPrefix("data:image/"), !dataUrl.hasPrefix("data:image/svg"), let range = dataUrl.range(of: "base64,") {
            guard let data = Data(base64Encoded: String(dataUrl[range.upperBound...]), options: .ignoreUnknownCharacters),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return WyrmArenaMinimapCells(size: picture.width, cells: [], image: picture)
        }
        var svg = dataUrl
        if dataUrl.hasPrefix("data:"), let range = dataUrl.range(of: "base64,") {
            guard let data = Data(base64Encoded: String(dataUrl[range.upperBound...]), options: .ignoreUnknownCharacters),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            svg = text
        }
        guard let view = try? NSRegularExpression(pattern: "viewBox=\"0 0 (\\d+) (\\d+)\""),
              let path = try? NSRegularExpression(pattern: "<path d=\"([^\"]*)\""),
              let cell = try? NSRegularExpression(pattern: "M([\\d.]+) ([\\d.]+)h") else { return nil }
        let ns = svg as NSString
        guard let viewMatch = view.firstMatch(in: svg, range: NSRange(location: 0, length: ns.length)),
              let size = Int(ns.substring(with: viewMatch.range(at: 1))), size > 0 else { return nil }
        var tones: [[Int]] = []
        for match in path.matches(in: svg, range: NSRange(location: 0, length: ns.length)).prefix(3) {
            let d = ns.substring(with: match.range(at: 1))
            let dn = d as NSString
            tones.append(cell.matches(in: d, range: NSRange(location: 0, length: dn.length)).compactMap { m in
                guard let x = Double(dn.substring(with: m.range(at: 1))), let y = Double(dn.substring(with: m.range(at: 2))) else { return nil }
                return Int(y) * size + Int(x)
            })
        }
        return WyrmArenaMinimapCells(size: size, cells: tones)
    }
}

/// What the monitor knows about one arena right now.
struct WyrmArenaLive {
    let players: Int?
    let country: String
    let top: [WyrmLeaderboardLine]
    let minimap: WyrmArenaMinimapCells?
    let updated: String
    /// "ip:port" (IPv4 when it has one), the arena code (nil for a custom
    /// arena) and NTL's custom flag (2026-11-07: the picker lists the arenas
    /// NTL knows that slither's directory does not).
    var endpoint = ""
    var code: Int? = nil
    var custom = false
}

struct WyrmEventLiveBoard {
    let players: Int?
    let leaderboard: [WyrmLeaderboardLine]
    let minimap: WyrmArenaMinimapCells?
}

struct WyrmEventDetail {
    let event: WyrmEvent
    let live: WyrmEventLiveBoard?
    let wyrmCount: Int
    let wyrm: [WyrmEventPlayer]
    let friends: [WyrmEventPlayer]
}

struct WyrmEventsPage {
    var upcoming: [WyrmEvent] = []
    var live: [WyrmEvent] = []
    var finished: [WyrmEvent] = []
    var nextCursor: Int? = nil
    var totalFinished = 0
    /// The one event Home shows: live first, then the next to start.
    var featured: WyrmEvent? { live.first ?? upcoming.first }
}

private func wyrmBoard(_ rows: [[String: Any]]) -> [WyrmLeaderboardLine] {
    rows.enumerated().map { WyrmLeaderboardLine(rank: $0.offset + 1, name: $0.element.evString("name") ?? "", score: $0.element.evInt64("score") ?? 0) }
}

/* ---------------------------------------------------------------- client */

enum WyrmEventsClient {
    static func get(_ path: String, token: String = "") async throws -> [String: Any] {
        let data = try await raw(path, token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WyrmServiceError.message("Could not load the events.")
        }
        return json
    }

    static func raw(_ path: String, token: String = "") async throws -> Data {
        guard let url = URL(string: WyrmTrailsClient.base + path) else { throw WyrmServiceError.message("Invalid Wyrm address.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw WyrmServiceError.message("Could not load the events.")
        }
        return data
    }
}

/**
 * The game's beads for the event pictures (OM, 2026-10-30): decoded once at app
 * start and kept for the app's life. The Skin tab's library is freed with its
 * last screen and loads backgrounds, tags and skins too, so the event pictures
 * came in late and blinked on every page change.
 */
final class WyrmEventBeads: ObservableObject {
    static let shared = WyrmEventBeads()
    @Published private(set) var beads: [Int: CGImage] = [:]
    private var loading = false

    func preload() {
        guard beads.isEmpty, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [Int: CGImage] = [:]
            if let url = Bundle.main.resourceURL?.appendingPathComponent("res/textures/tex_atlas_8k.png"),
               let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               let atlas = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceCreateThumbnailWithTransform: true,
                   kCGImageSourceThumbnailMaxPixelSize: 2016,
                   kCGImageSourceShouldCacheImmediately: true,
               ] as CFDictionary) {
                let cw = Double(atlas.width) / 7, ch = Double(atlas.height) / 9
                for id in 0..<42 {
                    let rect = CGRect(x: (Double(id % 7) * cw).rounded(.down), y: (Double(id / 7) * ch).rounded(.down),
                                      width: cw.rounded(.down), height: ch.rounded(.down))
                    out[id] = atlas.cropping(to: rect)
                }
            }
            DispatchQueue.main.async {
                self.beads = out
                self.loading = false
            }
        }
    }
}

/* ---------------------------------------------------------------- store */

@MainActor
final class WyrmEventsStore: ObservableObject {
    static let shared = WyrmEventsStore()

    @Published private(set) var page = WyrmEventsPage()
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var details: [String: WyrmEventDetail] = [:]
    @Published private(set) var reminders: Set<String> = []
    /// The arena monitor (wyrmarenas) per "ip:port": minimap, top 10, players.
    @Published private(set) var monitor: [String: WyrmArenaLive] = [:]
    /// The join question and the wait for the start (WyrmEventOverlays).
    @Published var joinSheet: WyrmEvent? = nil
    @Published var countdown: WyrmEvent? = nil
    @Published var toast = ""

    var token: () -> String = { "" }
    private var loadedAt = Date.distantPast
    private var monitorAt = Date.distantPast
    /// Which events have a reminder: this phone only, wiped on log out
    /// (WyrmAccountSync `wyrm.ios.event-reminders` wipe).
    private static let remindersKey = "wyrm.ios.event-reminders"

    /// The last first page this phone saw (public data, no account), so the
    /// next start paints Home's event card at once (OM, 2026-10-30).
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("wyrm-events.json")
    }

    private init() {
        reminders = Set(UserDefaults.standard.stringArray(forKey: Self.remindersKey) ?? [])
        if let url = Self.cacheURL, let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            page = Self.parse(json)
        }
    }

    private static func parse(_ json: [String: Any]) -> WyrmEventsPage {
        var next = WyrmEventsPage()
        next.upcoming = json.evArray("upcoming").compactMap(WyrmEvent.init)
        next.live = json.evArray("live").compactMap(WyrmEvent.init)
        next.finished = json.evArray("finished").compactMap(WyrmEvent.init)
        next.nextCursor = json.evInt("nextCursor")
        next.totalFinished = json.evInt("totalFinished") ?? next.finished.count
        return next
    }

    /// Every list; quiet when it was loaded in the last `maxAge` seconds.
    /// False only when the server could not be reached (so the caller retries soon).
    @discardableResult
    func refresh(maxAge: TimeInterval = 0) async -> Bool {
        guard !loading, Date().timeIntervalSince(loadedAt) >= maxAge else { return true }
        loading = true
        defer { loading = false }
        guard let data = try? await WyrmEventsClient.raw("/v1/events?status=all&cursor=0&limit=30"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let url = Self.cacheURL { try? data.write(to: url, options: .atomic) }
        let next = Self.parse(json)
        page = next
        loaded = true
        loadedAt = Date()
        return true
    }

    /// At every app start and every return to the app (OM, 2026-10-31): the events
    /// are asked for at once, and again after 3, 6 and 12 s if the network was not
    /// ready yet, so Home's event card never waits a minute to show.
    func refreshNow() {
        Task { @MainActor in
            var wait: UInt64 = 3
            for _ in 0..<4 {
                if await self.refresh(maxAge: 0) { return }
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                wait *= 2
            }
        }
    }

    func loadMore() async {
        guard let cursor = page.nextCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let json = try? await WyrmEventsClient.get("/v1/events?status=finished&cursor=\(cursor)&limit=30") else { return }
        let more = json.evArray("finished").compactMap(WyrmEvent.init)
        let known = Set(page.finished.map(\.id))
        page.finished += more.filter { !known.contains($0.id) }
        page.nextCursor = json.evInt("nextCursor")
    }

    func event(_ id: String) -> WyrmEvent? {
        details[id]?.event ?? (page.live + page.upcoming + page.finished).first { $0.id == id }
    }

    /// One event with its Wyrm players and live board; signed in, also friends.
    func loadDetail(_ id: String) async {
        let path = "/v1/events/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)
        guard let json = try? await WyrmEventsClient.get(path, token: token()),
              let eventJSON = json.evObject("event"), let event = WyrmEvent(eventJSON) else { return }
        let wyrm = json.evObject("wyrm")
        let live = json.evObject("live").map { board in
            WyrmEventLiveBoard(players: board.evInt("players"), leaderboard: wyrmBoard(board.evArray("leaderboard")),
                               minimap: WyrmArenaMinimapCells.parse(board.evString("minimap")))
        }
        details[id] = WyrmEventDetail(event: event, live: live, wyrmCount: wyrm?.evInt("count") ?? 0,
                                      wyrm: (wyrm?.evArray("players") ?? []).map(WyrmEventPlayer.init),
                                      friends: json.evArray("friends").map(WyrmEventPlayer.init))
    }

    /// The arena monitor, at most every `maxAge` seconds.
    func refreshMonitor(maxAge: TimeInterval = 20) async {
        guard Date().timeIntervalSince(monitorAt) >= maxAge else { return }
        monitorAt = Date()
        guard let json = try? await WyrmEventsClient.get("/v1/arena/status") else { monitorAt = .distantPast; return }
        var out: [String: WyrmArenaLive] = [:]
        for server in json.evArray("servers") {
            let live = WyrmArenaLive(players: server.evInt("playerCount"), country: server.evString("country") ?? "",
                                     top: Array(wyrmBoard(server.evArray("leaderboard")).prefix(10)),
                                     minimap: WyrmArenaMinimapCells.parse(server.evObject("preview")?.evString("dataUrl")),
                                     updated: server.evString("updatedLabel") ?? "",
                                     endpoint: server.evString("ipv4Address") ?? server.evString("address") ?? "",
                                     code: server.evInt("id"),
                                     custom: (server["custom"] as? Bool) ?? false)
            if let key = server.evString("ipv4Address") { out[key] = live }
            if let key = server.evString("address") { out[key] = live }
        }
        monitor = out
    }

    /* ------------------------------------------------------------ joining */

    /// A sign-up or a start still to come: say so first.
    func join(_ event: WyrmEvent, engine: WyrmShellStore) {
        if event.needsSignUp || event.status == "upcoming" { joinSheet = event } else { enter(event, engine: engine) }
    }

    /// Now, or after a countdown to the start.
    func enter(_ event: WyrmEvent, engine: WyrmShellStore, now: Bool = false) {
        joinSheet = nil
        if !now, event.status == "upcoming", let start = event.startsAt, start > Date() {
            countdown = event
        } else {
            countdown = nil
            engine.enterLobby(name: engine.nickname, address: event.address)
        }
    }

    /* ------------------------------------------------------------ reminders */

    /**
     * "Remind me" on an upcoming event: the phone itself posts an alert 30 and
     * 10 minutes before the start. Nothing goes to the server.
     */
    func toggleReminder(_ event: WyrmEvent) {
        let center = UNUserNotificationCenter.current()
        let ids = [30, 10].map { "wyrm-event-\(event.id)-\($0)" }
        if reminders.contains(event.id) {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            reminders.remove(event.id)
            toast = "Reminder off"
        } else {
            guard let start = event.startsAt, start > Date() else { return }
            reminders.insert(event.id)
            toast = "I'll remind you 30 and 10 minutes before"
            let prize = event.prizeUsd.flatMap(wyrmDollars)
            let server = event.region.isEmpty ? event.serverLabel : event.region
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                for lead in [30, 10] {
                    let at = start.addingTimeInterval(TimeInterval(-lead * 60))
                    let wait = at.timeIntervalSinceNow
                    guard wait > 1 else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = event.name
                    var body = "\(event.name) starts in \(lead) minutes"
                    if !server.isEmpty { body += " on the \(server) server" }
                    if let prize { body += " · \(prize) prize" }
                    content.body = body + ". Tap to join."
                    content.sound = .default
                    content.userInfo = ["kind": "wyrm_event", "id": event.id]
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
                    center.add(UNNotificationRequest(identifier: "wyrm-event-\(event.id)-\(lead)", content: content, trigger: trigger))
                }
            }
        }
        UserDefaults.standard.set(Array(reminders), forKey: Self.remindersKey)
    }

    /// Log out: every reminder goes with the account.
    func clearAll() {
        let ids = reminders.flatMap { id in [30, 10].map { "wyrm-event-\(id)-\($0)" } }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        reminders = []
        UserDefaults.standard.removeObject(forKey: Self.remindersKey)
        details = [:]
        joinSheet = nil
        countdown = nil
    }
}

/* ---------------------------------------------------------------- words */

private let wyrmEventClock: DateFormatter = {
    let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
}()

private func wyrmClock(_ date: Date?) -> String { date.map { wyrmEventClock.string(from: $0) } ?? "—" }

private func wyrmDay(_ date: Date?) -> String {
    guard let date else { return "—" }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    if calendar.isDateInTomorrow(date) { return "Tomorrow" }
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE d MMM")
    return f.string(from: date)
}

func wyrmEventCountdown(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600, m = (s % 3600) / 60, x = s % 60
    return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%02d:%02d", m, x)
}

private func wyrmMinutes(_ seconds: Int64?) -> String {
    guard let seconds else { return "—" }
    return seconds < 60 ? "\(seconds) s" : "\((seconds + 30) / 60) min"
}

private func wyrmGrouped(_ n: Int64?) -> String {
    guard let n else { return "—" }
    return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
}

private func wyrmDollars(_ usd: Double) -> String? {
    guard usd > 0 else { return nil }
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = usd.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    f.maximumFractionDigits = f.minimumFractionDigits
    return "$" + (f.string(from: NSNumber(value: usd)) ?? String(usd))
}

/// Discord's timestamps (<t:1793359800:t>) in the reader's own time, as Discord shows them.
func wyrmDiscordTimes(_ text: String, now: Date = Date()) -> String {
    guard let regex = try? NSRegularExpression(pattern: "<t:(\\d+)(?::([tTdDfFR]))?>") else { return text }
    let ns = text as NSString
    var out = ""
    var last = 0
    for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
        last = match.range.location + match.range.length
        guard let seconds = Double(ns.substring(with: match.range(at: 1))) else { continue }
        let at = Date(timeIntervalSince1970: seconds)
        let style = match.range(at: 2).location == NSNotFound ? "f" : ns.substring(with: match.range(at: 2))
        let f = DateFormatter()
        switch style {
        case "R":
            let minutes = Int((at.timeIntervalSince(now)) / 60)
            let a = abs(minutes)
            let t = a < 60 ? "\(a) min" : a < 2880 ? "\((a + 30) / 60) h" : "\((a + 720) / 1440) days"
            out += minutes >= 0 ? "in \(t)" : "\(t) ago"
        case "t": out += wyrmClock(at)
        case "T": f.timeStyle = .medium; out += f.string(from: at)
        case "d": f.dateStyle = .short; out += f.string(from: at)
        case "D": f.dateStyle = .long; out += f.string(from: at)
        case "F": f.setLocalizedDateFormatFromTemplate("EEEE d MMMM yyyy"); out += f.string(from: at) + ", " + wyrmClock(at)
        default: f.dateStyle = .long; out += f.string(from: at) + ", " + wyrmClock(at)
        }
    }
    out += ns.substring(from: last)
    return out
}

private func registrationLine(_ e: WyrmEvent) -> String? {
    if e.registration.discord == false { return "No sign-up" }
    if e.registration.mode == "verified" { return "Verified Discord" }
    if e.registration.discord == true || e.registration.url != nil { return "Register on Discord" }
    return nil
}

/* ---------------------------------------------------------------- art */

private func evColor(_ argb: UInt32) -> Color {
    Color(.sRGB, red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
          blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
}

struct WyrmEventLook {
    let bg: [Color]
    let skin: String
    var skin2 = ""

    static func of(_ kind: WyrmEventKind) -> WyrmEventLook {
        switch kind {
        case .lastOneStanding: return WyrmEventLook(bg: [evColor(0xFFF2B544), evColor(0xFFD9601F), evColor(0xFF6E2310)], skin: "ggwwyy")
        case .teamLastStanding: return WyrmEventLook(bg: [evColor(0xFF5B9BFF), evColor(0xFF3D55D6), evColor(0xFF1A2366)], skin: "ll00ss")
        case .lastDuoStanding: return WyrmEventLook(bg: [evColor(0xFF22C1B8), evColor(0xFF6D5BD0), evColor(0xFF3A1F6E)], skin: "uuccss", skin2: "mmaass")
        case .paintball: return WyrmEventLook(bg: [evColor(0xFF3A3F4B), evColor(0xFF22252D), evColor(0xFF111317)], skin: ",,nnwwppuuzz")
        case .battledome: return WyrmEventLook(bg: [evColor(0xFF46C893), evColor(0xFF15805A), evColor(0xFF0A3527)], skin: "ppoohh")
        case .other: return WyrmEventLook(bg: [evColor(0xFF6E5BFF), evColor(0xFF3B2A9E), evColor(0xFF150F3D)], skin: "zzxxuuppwwnnmm")
        }
    }
}

/// Official bead characters -> colour group (SkinCatalog groupCodes), as Android `beadGroup`.
private let wyrmBeadChars = Array("zxcvbnm,asdfghjklqwertyuiop1234567890-")
func wyrmEventBeadGroup(_ c: Character) -> Int {
    guard let i = wyrmBeadChars.firstIndex(of: c) else { return 9 }
    if i < 36 { return i }
    return c == "0" ? 37 : 39
}
private let wyrmEyeBead = 40

/// A small stable random (the art must look the same on every draw and phone).
private struct WyrmArtRandom {
    var state: UInt64
    init(_ seed: String) {
        var h: UInt64 = 1469598103934665603
        for byte in seed.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        state = h == 0 ? 0x9E3779B97F4A7C15 : h
    }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 1_000_000) / 1_000_000
    }
    mutating func int(_ bound: Int) -> Int { min(bound - 1, Int(next() * CGFloat(bound))) }
}

private struct WyrmArtPainter {
    let context: GraphicsContext
    let size: CGSize
    let beads: [Int: CGImage]
    var w: CGFloat { size.width }
    var h: CGFloat { size.height }

    func cell(_ group: Int, _ cx: CGFloat, _ cy: CGFloat, _ side: CGFloat, alpha: Double = 1, tint: Color? = nil) {
        guard let image = beads[group], side > 0.5 else { return }
        var g = context
        g.opacity = alpha
        var resolved = g.resolve(Image(decorative: image, scale: 1))
        if let tint { resolved.shading = .color(tint) }
        g.draw(resolved, in: CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side))
    }

    /// A cubic in fractions of the card, sampled into 161 points.
    func cubic(_ f: [CGFloat]) -> [CGPoint] {
        let p = (0..<8).map { $0 % 2 == 0 ? f[$0] * w : f[$0] * h }
        return (0...160).map { i in
            let t = CGFloat(i) / 160, u = 1 - t
            return CGPoint(x: u * u * u * p[0] + 3 * u * u * t * p[2] + 3 * u * t * t * p[4] + t * t * t * p[6],
                           y: u * u * u * p[1] + 3 * u * u * t * p[3] + 3 * u * t * t * p[5] + t * t * t * p[7])
        }
    }

    /// Points every `step` along the line, from its end (the head) back.
    func walk(_ pts: [CGPoint], _ step: CGFloat) -> [CGPoint] {
        guard pts.count > 1 else { return pts }
        var cum = [CGFloat](repeating: 0, count: pts.count)
        for i in 1..<pts.count { cum[i] = cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        var out: [CGPoint] = []
        var d = cum[pts.count - 1]
        var j = pts.count - 1
        while d >= 0 {
            while j > 0 && cum[j - 1] > d { j -= 1 }
            let a = j == 0 ? 0 : j - 1
            let span = cum[j] - cum[a] > 0 ? cum[j] - cum[a] : 1
            let k = min(1, max(0, (d - cum[a]) / span))
            out.append(CGPoint(x: pts[a].x + (pts[j].x - pts[a].x) * k, y: pts[a].y + (pts[j].y - pts[a].y) * k))
            d -= step
        }
        return out
    }

    /// The game's beads close together like the arena's body points, from a
    /// thin far tail to a full head, with the game's eye bead and a black pupil.
    func snake(_ line: [CGPoint], _ code: String, _ r: CGFloat, alpha: Double = 1, eyes: Bool = true, look: CGFloat = 0, tail: CGFloat = 0.42) {
        guard !code.isEmpty, !beads.isEmpty else { return }
        let points = walk(line, r * 0.42)
        let n = points.count
        guard n > 0 else { return }
        let groups = code.map(wyrmEventBeadGroup)
        for i in stride(from: n - 1, through: 0, by: -1) {
            let grow = tail + (1 - tail) * (1 - CGFloat(i) / CGFloat(max(1, n - 1)))
            cell(groups[(i / 3) % groups.count], points[i].x, points[i].y, 2 * r * grow, alpha: alpha)
        }
        guard eyes, n >= 2 else { return }
        let head = points[0], back = points[min(2, n - 1)]
        let ang = atan2(head.y - back.y, head.x - back.x)
        let u = r / 14.5
        for side: CGFloat in [-1, 1] {
            let px = cos(ang + side * .pi / 2), py = sin(ang + side * .pi / 2)
            let ex = head.x + cos(ang) * 6 * u + px * 6.5 * u
            let ey = head.y + sin(ang) * 6 * u + py * 6.5 * u
            cell(wyrmEyeBead, ex, ey, 12 * u, alpha: alpha)
            cell(wyrmEyeBead, ex + cos(ang + look) * 2 * u, ey + sin(ang + look) * 2 * u, 7 * u, alpha: alpha, tint: evColor(0xFF0A0A0D))
        }
    }

    func sparkle(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y - s)); p.addLine(to: CGPoint(x: x + s * 0.3, y: y - s * 0.3))
        p.addLine(to: CGPoint(x: x + s, y: y)); p.addLine(to: CGPoint(x: x + s * 0.3, y: y + s * 0.3))
        p.addLine(to: CGPoint(x: x, y: y + s)); p.addLine(to: CGPoint(x: x - s * 0.3, y: y + s * 0.3))
        p.addLine(to: CGPoint(x: x - s, y: y)); p.addLine(to: CGPoint(x: x - s * 0.3, y: y - s * 0.3)); p.closeSubpath()
        context.fill(p, with: .color(.white.opacity(0.85)))
    }

    func circle(_ c: CGPoint, _ r: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    func ring(_ c: CGPoint, _ r: CGFloat, _ color: Color, _ style: StrokeStyle) {
        context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color), style: style)
    }

    func splat(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: Color, _ rand: inout WyrmArtRandom) {
        let n = 11
        var pts: [CGPoint] = []
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi
            let rr = radius * (i % 2 == 1 ? 0.62 + rand.next() * 0.2 : 0.9 + rand.next() * 0.45)
            pts.append(CGPoint(x: x + cos(a) * rr, y: y + sin(a) * rr))
        }
        var path = Path()
        for i in 0..<n {
            let p = pts[i], q = pts[(i + 1) % n]
            let m = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            if i == 0 { path.move(to: m) } else { path.addQuadCurve(to: m, control: p) }
        }
        let m0 = CGPoint(x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2)
        path.addQuadCurve(to: m0, control: pts[0])
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(0.8)))
        for _ in 0..<5 {
            let a = rand.next() * 2 * .pi, d = radius * (1.4 + rand.next() * 1.1)
            circle(CGPoint(x: x + cos(a) * d, y: y + sin(a) * d), radius * (0.08 + rand.next() * 0.14), color.opacity(0.8))
        }
    }

    func draw(kind: WyrmEventKind, seed: String, big: Bool) {
        let look = WyrmEventLook.of(kind)
        var rand = WyrmArtRandom(seed)
        let unit = w / 390
        let r = (big ? 17 : 14) * unit
        // Ground: the type's gradient, a dot grid, a soft light top right.
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: look.bg), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
        let step = 14 * unit
        var gy = 2 * unit
        while gy < h {
            var gx = 2 * unit
            while gx < w { circle(CGPoint(x: gx, y: gy), 1.1 * unit, .white.opacity(0.12)); gx += step }
            gy += step
        }
        let hx: CGFloat = 0.64, hy: CGFloat = 0.36
        let main = cubic([1.06, 0.98, 0.82, 0.94, 0.94, 0.52, hx, hy])
        let ex = w * hx, ey = h * hy - r * 2.8
        let ghost = "ii33", enemy = "55,,"
        switch kind {
        case .lastOneStanding:
            var beam = Path()
            beam.move(to: CGPoint(x: w * 0.5, y: 0)); beam.addLine(to: CGPoint(x: w * 0.78, y: 0))
            beam.addLine(to: CGPoint(x: w * 1.06, y: h)); beam.addLine(to: CGPoint(x: w * 0.56, y: h)); beam.closeSubpath()
            context.fill(beam, with: .linearGradient(Gradient(colors: [.white.opacity(0.3), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            for _ in 0..<24 {
                let a = 0.1 + rand.next() * 0.3, rr = (1 + rand.next() * 2.6) * unit
                circle(CGPoint(x: w * (0.56 + rand.next() * 0.44), y: h * (0.3 + rand.next() * 0.6)), rr, .white.opacity(Double(a)))
            }
            snake(cubic([0.56, 0.94, 0.58, 0.88, 0.62, 0.9, 0.64, 0.82]), ghost, r * 0.6, alpha: 0.3, eyes: false)
            snake(cubic([1.04, 0.44, 1, 0.4, 0.98, 0.46, 0.95, 0.4]), ghost, r * 0.55, alpha: 0.25, eyes: false)
            snake(main, look.skin, r, look: -0.5)
            var g = context
            g.translateBy(x: ex, y: ey)
            g.rotate(by: .degrees(-6))
            g.scaleBy(x: 0.85 * unit, y: 0.85 * unit)
            var crown = Path()
            crown.move(to: CGPoint(x: -20, y: 10)); crown.addLine(to: CGPoint(x: -24, y: -9)); crown.addLine(to: CGPoint(x: -11, y: 0))
            crown.addLine(to: CGPoint(x: 0, y: -16)); crown.addLine(to: CGPoint(x: 11, y: 0)); crown.addLine(to: CGPoint(x: 24, y: -9))
            crown.addLine(to: CGPoint(x: 20, y: 10)); crown.closeSubpath()
            g.fill(crown, with: .color(evColor(0xFFFDE68A)))
            g.stroke(crown, with: .color(.white), style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))
            g.fill(Path(roundedRect: CGRect(x: -20, y: 10, width: 40, height: 6), cornerRadius: 2), with: .color(evColor(0xFFF59E0B)))
            for o in [CGPoint(x: -24, y: -9), CGPoint(x: 0, y: -16), CGPoint(x: 24, y: -9)] {
                g.fill(Path(ellipseIn: CGRect(x: o.x - 3.2, y: o.y - 3.2, width: 6.4, height: 6.4)), with: .color(.white))
            }
            sparkle(ex - 34 * unit, ey + 8 * unit, 5 * unit); sparkle(ex + 30 * unit, ey - 2 * unit, 4 * unit)
        case .teamLastStanding:
            // A squad in three lanes: the leader in front, two behind it on either side.
            func lane(_ side: CGFloat) -> [CGPoint] {
                let ox = (0.95 * 30 + 0.31 * 27 * side) * unit / w, oy = (0.31 * 30 - 0.95 * 27 * side) * unit / h
                return cubic([1.06 + ox, 0.98 + oy, 0.82 + ox, 0.94 + oy, 0.94 + ox, 0.52 + oy, hx + ox, hy + oy])
            }
            snake(cubic([0.58, 0.94, 0.6, 0.88, 0.62, 0.9, 0.64, 0.84]), enemy, r * 0.55, alpha: 0.4)
            snake(lane(1), look.skin, r * 0.74, look: -0.5)
            snake(lane(-1), look.skin, r * 0.74, look: -0.5)
            snake(main, look.skin, r * 0.86, look: -0.5)
            var g = context
            g.translateBy(x: ex, y: ey)
            g.scaleBy(x: 0.85 * unit, y: 0.85 * unit)
            var shield = Path()
            shield.move(to: CGPoint(x: 0, y: -20)); shield.addLine(to: CGPoint(x: 18, y: -13)); shield.addLine(to: CGPoint(x: 18, y: 3))
            shield.addCurve(to: CGPoint(x: 0, y: 26), control1: CGPoint(x: 18, y: 15), control2: CGPoint(x: 9, y: 22))
            shield.addCurve(to: CGPoint(x: -18, y: 3), control1: CGPoint(x: -9, y: 22), control2: CGPoint(x: -18, y: 15))
            shield.addLine(to: CGPoint(x: -18, y: -13)); shield.closeSubpath()
            g.fill(shield, with: .color(.white.opacity(0.2)))
            g.stroke(shield, with: .color(.white), lineWidth: 2.4)
            for o in [CGPoint(x: -6, y: 0), CGPoint(x: 6, y: 0), CGPoint(x: 0, y: 9)] {
                g.fill(Path(ellipseIn: CGRect(x: o.x - 3.6, y: o.y - 3.6, width: 7.2, height: 7.2)), with: .color(.white))
            }
        case .lastDuoStanding:
            var shade = Path()
            shade.move(to: CGPoint(x: w * 0.55, y: 0)); shade.addLine(to: CGPoint(x: w, y: 0))
            shade.addLine(to: CGPoint(x: w, y: h)); shade.addLine(to: CGPoint(x: w * 0.4, y: h)); shade.closeSubpath()
            context.fill(shade, with: .color(.white.opacity(0.06)))
            let x0 = w * 1.04, y0 = h * 0.98, x1 = w * hx, y1 = h * hy
            let len = hypot(x1 - x0, y1 - y0)
            let px = -(y1 - y0) / len, py = (x1 - x0) / len
            func wave(_ phase: CGFloat, _ side: CGFloat) -> [CGPoint] {
                (0...40).map { i in
                    let s = CGFloat(i) / 40
                    let off = sin(s * .pi * 1.6 + phase) * r * 0.7 + side * r * 0.62
                    return CGPoint(x: x0 + (x1 - x0) * s + px * off, y: y0 + (y1 - y0) * s + py * off)
                }
            }
            snake(wave(0, -1), look.skin, r * 0.84, look: -0.5)
            snake(wave(.pi, 1), look.skin2, r * 0.84, look: -0.5)
            ring(CGPoint(x: ex - 7 * unit, y: ey), 9 * unit, .white, StrokeStyle(lineWidth: 2.6 * unit))
            ring(CGPoint(x: ex + 7 * unit, y: ey), 9 * unit, .white, StrokeStyle(lineWidth: 2.6 * unit))
        case .paintball:
            let colors = [evColor(0xFFFB7185), evColor(0xFFFDE047), evColor(0xFF22D3EE), evColor(0xFFA3E635), evColor(0xFFC084FC), evColor(0xFFFB923C)]
            for i in 0..<7 {
                let sx = w * (0.56 + rand.next() * 0.44), sy = h * (0.25 + rand.next() * 0.7), sr = h * (0.06 + rand.next() * 0.09)
                splat(sx, sy, sr, colors[i % colors.count], &rand)
            }
            for i in 0..<3 {
                let x = w * (0.74 + rand.next() * 0.22), top = h * (0.22 + rand.next() * 0.2), dl = h * (0.12 + rand.next() * 0.16)
                let col = colors[(i + 2) % colors.count].opacity(0.7)
                var drip = Path(); drip.move(to: CGPoint(x: x, y: top)); drip.addLine(to: CGPoint(x: x, y: top + dl))
                context.stroke(drip, with: .color(col), style: StrokeStyle(lineWidth: (2 + rand.next() * 2.5) * unit, lineCap: .round))
                circle(CGPoint(x: x, y: top + dl + 4 * unit), 3 * unit, col)
            }
            snake(main, look.skin, r, look: -0.5)
            circle(CGPoint(x: ex, y: ey), 11 * unit, .white)
            circle(CGPoint(x: ex, y: ey), 4.5 * unit, evColor(0xFFFB7185))
            for (a, b) in [(CGPoint(x: -18, y: 0), CGPoint(x: -13, y: 0)), (CGPoint(x: 13, y: 0), CGPoint(x: 18, y: 0)),
                           (CGPoint(x: 0, y: -18), CGPoint(x: 0, y: -13)), (CGPoint(x: 0, y: 13), CGPoint(x: 0, y: 18))] {
                var tick = Path()
                tick.move(to: CGPoint(x: ex + a.x * unit, y: ey + a.y * unit)); tick.addLine(to: CGPoint(x: ex + b.x * unit, y: ey + b.y * unit))
                context.stroke(tick, with: .color(.white), style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
            }
        case .battledome:
            let c = CGPoint(x: w * 0.8, y: h * (big ? 0.4 : 0.5)), rad = h * (big ? 0.27 : 0.3)
            ring(c, rad, .white.opacity(0.55), StrokeStyle(lineWidth: 2.5 * unit, lineCap: .round, dash: [2 * unit, 9 * unit]))
            circle(c, rad * 0.78, .white.opacity(0.09))
            ring(c, rad * 0.78, .white.opacity(0.34), StrokeStyle(lineWidth: 1.6 * unit))
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2 + .pi / 4
                let o = CGPoint(x: c.x + cos(a) * rad * 1.16, y: c.y + sin(a) * rad * 1.16)
                let t = CGPoint(x: c.x + cos(a) * rad * 1.03, y: c.y + sin(a) * rad * 1.03)
                var arrow = Path(); arrow.move(to: o); arrow.addLine(to: t)
                context.stroke(arrow, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
                let dir = atan2(t.y - o.y, t.x - o.x), s = 4.5 * unit
                var head = Path()
                head.move(to: CGPoint(x: t.x + cos(dir) * s, y: t.y + sin(dir) * s))
                head.addLine(to: CGPoint(x: t.x + cos(dir + 2.4) * s, y: t.y + sin(dir + 2.4) * s))
                head.addLine(to: CGPoint(x: t.x + cos(dir - 2.4) * s, y: t.y + sin(dir - 2.4) * s)); head.closeSubpath()
                context.fill(head, with: .color(.white.opacity(0.8)))
            }
            let coil = (0...60).map { i -> CGPoint in
                let a = -CGFloat.pi * 0.1 + CGFloat(i) / 60 * .pi * 1.9
                let rr = rad * (0.64 - CGFloat(i) / 60 * 0.36)
                return CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            }
            snake(coil, look.skin, r * 0.86)
            snake(cubic([0.56, 0.94, 0.58, 0.88, 0.62, 0.9, 0.64, 0.84]), enemy, r * 0.55, alpha: 0.55)
        case .other:
            // Northern lights, bead confetti, one bright snake and a star.
            for i in 0..<3 {
                let y = h * (0.12 + CGFloat(i) * 0.16), amp = h * (0.08 + CGFloat(i) * 0.03)
                var band = Path()
                band.move(to: CGPoint(x: w * 0.3, y: y + amp))
                band.addCurve(to: CGPoint(x: w * 1.05, y: y - amp * 0.4), control1: CGPoint(x: w * 0.5, y: y - amp), control2: CGPoint(x: w * 0.7, y: y + amp * 1.6))
                var g = context
                g.opacity = 0.9 - Double(i) * 0.25
                g.stroke(band, with: .linearGradient(Gradient(colors: [evColor(0x005EEAD4), evColor(0x615EEAD4), evColor(0x57C084FC), evColor(0x00F472B6)]),
                                                    startPoint: CGPoint(x: w * 0.3, y: 0), endPoint: CGPoint(x: w * 1.05, y: 0)),
                         style: StrokeStyle(lineWidth: h * (0.09 - CGFloat(i) * 0.02), lineCap: .round))
            }
            for _ in 0..<40 {
                let a = 0.2 + rand.next() * 0.6, rr = (0.6 + rand.next() * 1.3) * unit
                circle(CGPoint(x: w * (0.3 + rand.next() * 0.7), y: h * rand.next()), rr, .white.opacity(Double(a)))
            }
            let confetti = Array("zxcvbnm,wpu")
            for _ in 0..<9 {
                let s = r * (0.5 + rand.next() * 0.55)
                let ch = confetti[rand.int(confetti.count)]
                let cx = w * (0.6 + rand.next() * 0.38), cy = h * (0.18 + rand.next() * 0.62)
                cell(wyrmEventBeadGroup(ch), cx, cy, s, alpha: Double(0.55 + rand.next() * 0.4))
            }
            snake(main, look.skin, r, look: -0.5)
            var g = context
            g.translateBy(x: ex, y: ey)
            g.scaleBy(x: unit, y: unit)
            let pts: [CGFloat] = [0, -15, 4.4, -4.6, 15.6, -4.4, 6.8, 2.6, 9.8, 13.6, 0, 7.2, -9.8, 13.6, -6.8, 2.6, -15.6, -4.4, -4.4, -4.6]
            var star = Path()
            star.move(to: CGPoint(x: pts[0], y: pts[1]))
            for i in stride(from: 2, to: pts.count, by: 2) { star.addLine(to: CGPoint(x: pts[i], y: pts[i + 1])) }
            star.closeSubpath()
            g.fill(star, with: .color(evColor(0xFFFDE68A)))
            g.stroke(star, with: .color(.white), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            sparkle(ex - 30 * unit, ey + 2 * unit, 4.5 * unit); sparkle(ex + 26 * unit, ey + 10 * unit, 3.5 * unit)
        }
        // Shade for the text on the left and the buttons along the bottom.
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .clear, .black.opacity(0.25)]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
    }
}

/// One look per event type: the game's own beads and eye bead, the body
/// rising from the bottom-right corner towards the top centre, each type's
/// emblem just above the head, on the small and the big card alike.
struct WyrmEventArt: View {
    let kind: WyrmEventKind
    let seed: String
    var big = false
    @ObservedObject private var store = WyrmEventBeads.shared

    var body: some View {
        // Read here so the art redraws once when the beads land, never on a tick.
        let beads = store.beads
        Canvas { context, size in
            WyrmArtPainter(context: context, size: size, beads: beads).draw(kind: kind, seed: seed, big: big)
        }
        .onAppear { store.preload() }
    }
}

/// A row of the type's beads (the Event pass's foot).
private struct WyrmEventBeadStrip: View {
    let skin: String
    @ObservedObject private var store = WyrmEventBeads.shared
    var body: some View {
        let beads = store.beads
        Canvas { context, size in
            let painter = WyrmArtPainter(context: context, size: size, beads: beads)
            for (i, ch) in skin.enumerated() {
                painter.cell(wyrmEventBeadGroup(ch), CGFloat(i) * 11 + 8, size.height / 2, 16)
            }
        }
        .frame(width: CGFloat(skin.count * 11 + 6), height: 16)
        .onAppear { store.preload() }
    }
}

/// The minimap of an arena, drawn from the monitor's cells (three tones).
struct WyrmArenaMinimapView: View {
    let map: WyrmArenaMinimapCells?
    var body: some View {
        Canvas { context, size in
            let d = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(evColor(0xFF101713)))
            let rr = d / 2 * 0.98
            context.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)), with: .color(evColor(0xFF78B998)), lineWidth: 1)
            guard let map, map.size > 0 else { return }
            let cell = d / CGFloat(map.size)
            let ox = (size.width - d) / 2, oy = (size.height - d) / 2
            if let picture = map.image {
                context.draw(Image(decorative: picture, scale: 1), in: CGRect(x: ox, y: oy, width: d, height: d))
                return
            }
            let tones = [evColor(0xF5F4F6F2), evColor(0xE69BD9BA), evColor(0xBFD8EADF)]
            for (tone, cells) in map.cells.enumerated() {
                var path = Path()
                for index in cells {
                    let x = index % map.size, y = index / map.size
                    path.addRect(CGRect(x: ox + (CGFloat(x) + 0.2) * cell, y: oy + (CGFloat(y) + 0.2) * cell, width: cell * 0.6 + 0.6, height: cell * 0.6 + 0.6))
                }
                context.fill(path, with: .color(tones[tone % tones.count]))
            }
        }
    }
}

/* ---------------------------------------------------------------- small pieces */

struct WyrmEventFlag: View {
    let country: String
    var width: CGFloat = 18
    var height: CGFloat = 13
    var body: some View {
        if country.count == 2, let url = URL(string: "https://flagcdn.com/w160/\(country.lowercased()).png") {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Color.white.opacity(0.25) }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color.black.opacity(0.14), lineWidth: 0.5))
        }
    }
}

private struct WyrmGlassPill<Content: View>: View {
    @Environment(\.wyrmPaletteOverride) private var palette
    var solid: Color? = nil
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(palette?.well.color ?? solid ?? Color.white.opacity(0.2)))
            .overlay(Capsule().stroke(palette?.rule.color ?? (solid == nil ? Color.white.opacity(0.24) : .clear), lineWidth: 1))
    }
}

private struct WyrmPillText: View {
    @Environment(\.wyrmPaletteOverride) private var palette
    let text: String
    var color: Color? = nil
    init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }
    var body: some View { Text(text).font(.androidWyrm(12, .heavy)).foregroundColor(palette?.ink.color ?? color ?? .white).lineLimit(1) }
}

private struct WyrmEventStatusPill: View {
    let event: WyrmEvent
    var body: some View {
        // Only this pill ticks; the card and its picture stay still.
        if event.status == "upcoming" {
            TimelineView(.periodic(from: .now, by: 1)) { context in pill(context.date) }
        } else {
            pill(Date())
        }
    }

    @ViewBuilder
    private func pill(_ now: Date) -> some View {
        switch event.status {
        case "live":
            WyrmGlassPill(solid: evColor(0xFFE5484D)) { Circle().fill(Color.white).frame(width: 7, height: 7); WyrmPillText("LIVE") }
        case "upcoming":
            WyrmGlassPill { WyrmPillText("IN " + wyrmEventCountdown((event.startsAt ?? now).timeIntervalSince(now))) }
        default:
            WyrmGlassPill { WyrmPillText("Ended " + wyrmDay(event.startedAt)) }
        }
    }
}

private struct WyrmEventBell: View {
    @Environment(\.wyrmPaletteOverride) private var palette
    let on: Bool
    var size: CGFloat = 46
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "bell.fill" : "bell").font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(on ? (palette?.onInk.color ?? evColor(0xFF1D1C19)) : (palette?.ink.color ?? .white))
                .frame(width: size, height: size)
                .background(Circle().fill(on ? (palette?.ink.color ?? .white) : (palette?.well.color ?? Color.white.opacity(0.2))))
                .overlay(Circle().stroke(palette?.rule.color ?? Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Reminder on" : "Remind me")
    }
}

private struct WyrmEventChip: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let text: String
    var tint: Color? = nil
    var body: some View {
        Text(text).font(.androidWyrm(11, .heavy)).foregroundColor(tint ?? wyrmScopedColours.mute)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill((tint ?? wyrmScopedColours.ink).opacity(tint == nil ? 0.06 : 0.15)))
    }
}

private struct WyrmEventLabel: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.androidWyrm(10.5, .heavy)).tracking(0.9).foregroundColor(wyrmScopedColours.quiet) }
}

/* ---------------------------------------------------------------- Home */

/// Home's event card: the live event, else the next one.
struct WyrmHomeEventCard: View {
    let event: WyrmEvent
    let reminded: Bool
    let onOpen: () -> Void
    let onJoin: () -> Void
    let onRemind: () -> Void

    var body: some View {
 WyrmHeroCard(slot: 1) { wyrmScopedColours in
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WyrmEventStatusPill(event: event)
                Spacer()
                WyrmGlassPill { WyrmEventFlag(country: event.flag); WyrmPillText(event.serverLabel) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.status == "live" ? "EVENT ON NOW" : "NEXT EVENT").font(.androidWyrm(10.5, .heavy)).tracking(1)
                    .foregroundColor(wyrmScopedColours.quiet)
                Text(event.name).font(.androidWyrm(24, .heavy)).foregroundColor(wyrmScopedColours.ink).lineLimit(2)
                Text(subtitle).font(.androidWyrm(13, .semibold)).foregroundColor(wyrmScopedColours.mute)
            }
            .padding(8).background(wyrmScopedColours.paper).clipShape(RoundedRectangle(cornerRadius: 12))
            if let line = registrationLine(event) { WyrmGlassPill { WyrmPillText(line) } }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(action: onJoin) {
                    Text(event.status == "live" ? "Join now" : "Join at the start").font(.androidWyrm(15, .heavy))
                        .foregroundColor(wyrmScopedColours.onInk).frame(maxWidth: .infinity).frame(height: 46)
                        .background(Capsule().fill(wyrmScopedColours.ink))
                }.buttonStyle(.plain)
                if event.status == "upcoming" { WyrmEventBell(on: reminded, action: onRemind) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .background(WyrmEventArt(kind: event.kind, seed: event.id))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
        .padding(.horizontal, 16)
    
 }
}

    private var subtitle: String {
        var text = event.status == "live"
            ? "Started " + wyrmClock(event.began)
            : wyrmDay(event.startsAt) + " · " + wyrmClock(event.startsAt)
        if let prize = event.prizeUsd.flatMap(wyrmDollars) { text += " · " + prize }
        return text
    }
}

/// Home when nothing is on: the last event, and a way to all of them.
struct WyrmHomeLastEventRow: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let last: WyrmEvent
    let onOpenEvents: () -> Void
    var body: some View {
        WyrmPaperCard {
            Button(action: onOpenEvents) {
                HStack(spacing: 12) {
                    WyrmEventArt(kind: last.kind, seed: last.id).frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        WyrmEventLabel("Events")
                        Text("No event right now").font(.androidWyrm(15, .bold)).foregroundColor(wyrmScopedColours.ink)
                        Text("Last: \(last.name)" + (last.players.map { " · \($0) players" } ?? "") + " · " + wyrmDay(last.startedAt))
                            .font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(wyrmScopedColours.chevron)
                }
                .padding(12).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

/// Home's event block: the card when one is on or coming, else the last one.
struct WyrmHomeEvents: View {
    @ObservedObject var engine: WyrmShellStore
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var events = WyrmEventsStore.shared

    var body: some View {
        Group {
            if let featured = events.page.featured {
                WyrmHomeEventCard(event: featured, reminded: events.reminders.contains(featured.id),
                                  onOpen: { open(.event(featured.id)) },
                                  onJoin: { events.join(featured, engine: engine) },
                                  onRemind: { events.toggleReminder(featured) })
                    .padding(.bottom, 14)
            } else if let last = events.page.finished.first {
                WyrmHomeLastEventRow(last: last) { open(.events) }.padding(.bottom, 14)
            }
        }
        .task {
            // Fresh on every Home visit, then every minute while Home is up; a
            // failed look is tried again after 5 s instead of a minute.
            while !Task.isCancelled {
                let ok = await events.refresh(maxAge: 20)
                try? await Task.sleep(nanoseconds: ok ? 60_000_000_000 : 5_000_000_000)
            }
        }
    }
}

/// Play's own Events button (OM, 2026-10-30): under Team, with what is on.
struct WyrmEventsHomeRow: View {
    let action: () -> Void
    @ObservedObject private var events = WyrmEventsStore.shared

    private var detail: String {
        let page = events.page
        var parts: [String] = []
        if !page.live.isEmpty { parts.append("\(page.live.count) live") }
        if !page.upcoming.isEmpty { parts.append("\(page.upcoming.count) coming") }
        if page.totalFinished > 0 { parts.append("\(page.totalFinished) done") }
        return parts.isEmpty ? "Live, coming and past tournaments" : parts.joined(separator: " · ")
    }

    var body: some View {
        WyrmListRow(title: "Events", detail: detail, value: events.page.live.isEmpty ? "All" : "Live now",
                    icon: "trophy.fill", tint: evColor(0xFFD9601F), action: action)
    }
}

/* ---------------------------------------------------------------- Events page */

struct WyrmEventsListPage: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var events = WyrmEventsStore.shared
    @State private var tab: Int? = nil

    private var selected: Int {
        tab ?? (events.page.live.isEmpty ? (events.page.upcoming.isEmpty ? 2 : 0) : 1)
    }

    var body: some View {
        WSScaffold(title: "Events", parent: "Play", onBack: close) {
            Text("Community tournaments on slither servers. Times are in your time zone.")
                .font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.quiet)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 6)
            WSSegmented(options: ["Upcoming \(events.page.upcoming.count)", "Live \(events.page.live.count)", "Past \(events.page.totalFinished)"],
                        selected: selected) { tab = $0 }
                .padding(.horizontal, 16).padding(.vertical, 8)
            let list = selected == 0 ? events.page.upcoming : selected == 1 ? events.page.live : events.page.finished
            if events.loading && list.isEmpty && !events.loaded {
                Text("Loading…").font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.quiet).padding(24)
            } else if list.isEmpty {
                empty
            } else if selected < 2 {
                VStack(spacing: 12) {
                    ForEach(list) { e in
                        WyrmHomeEventCard(event: e, reminded: events.reminders.contains(e.id),
                                          onOpen: { open(.event(e.id)) },
                                          onJoin: { events.join(e, engine: engine) },
                                          onRemind: { events.toggleReminder(e) })
                    }
                }.padding(.vertical, 4)
            } else {
                ForEach(pastDays(list)) { group in
                    WSSectionLabel(group.day)
                    WSCard {
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, e in
                            if index > 0 { WSHairline() }
                            pastRow(e)
                        }
                    }
                }
                if events.page.nextCursor != nil {
                    Button { Task { await events.loadMore() } } label: {
                        Text(events.loadingMore ? "Loading…" : "Show older events").font(.androidWyrm(14, .bold)).foregroundColor(wyrmScopedColours.ink)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(wyrmScopedColours.card)).overlay(Capsule().stroke(wyrmScopedColours.rule, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(events.loadingMore)
                    .frame(maxWidth: .infinity).padding(16)
                }
            }
            Spacer().frame(height: 24)
        }
        .task { await events.refresh(maxAge: 10) }
    }

    private struct Day: Identifiable { let day: String; let rows: [WyrmEvent]; var id: String { day } }

    private func pastDays(_ list: [WyrmEvent]) -> [Day] {
        var order: [String] = []
        var groups: [String: [WyrmEvent]] = [:]
        for e in list {
            let day = wyrmDay(e.startedAt ?? e.startsAt)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(e)
        }
        return order.map { Day(day: $0, rows: groups[$0] ?? []) }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text(selected == 0 ? "Nothing planned yet" : selected == 1 ? "No event is on" : "No past events")
                .font(.androidWyrm(18, .heavy)).foregroundColor(wyrmScopedColours.ink)
            Text(selected == 0 ? "When the organisers plan an event it shows here." : selected == 1 ? "A live event shows here with its board and who from Wyrm is playing." : "")
                .font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.quiet).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(28)
    }

    private func pastRow(_ e: WyrmEvent) -> some View {
        Button { open(.event(e.id)) } label: {
            HStack(spacing: 12) {
                WyrmEventArt(kind: e.kind, seed: e.id).frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.name).font(.androidWyrm(15, .heavy)).foregroundColor(wyrmScopedColours.ink)
                    HStack(spacing: 6) {
                        WyrmEventFlag(country: e.flag, width: 16, height: 11)
                        Text([e.serverLabel, wyrmClock(e.startedAt), e.durationSeconds.map { wyrmMinutes($0) }].compactMap { $0 }.joined(separator: " · "))
                            .font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                    }
                    HStack(spacing: 6) {
                        if let players = e.players { WyrmEventChip(text: "\(players) players") }
                        if let prize = e.prizeUsd.flatMap(wyrmDollars) { WyrmEventChip(text: prize, tint: evColor(0xFFC28A2C)) }
                        if let wyrm = e.wyrmPlayers, wyrm > 0 { WyrmEventChip(text: "\(wyrm) on Wyrm", tint: wyrmScopedColours.live) }
                    }.padding(.top, 2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(wyrmScopedColours.chevron)
            }
            .padding(12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/* ---------------------------------------------------------------- event page */

struct WyrmEventDetailPage: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let eventID: String
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    @ObservedObject private var events = WyrmEventsStore.shared
    @Environment(\.openURL) private var openURL
    @State private var note = ""

    var body: some View {
        Group {
            if let e = events.event(eventID) {
                page(e, detail: events.details[eventID])
            } else {
                ZStack(alignment: .topLeading) {
                    wyrmScopedColours.paper.ignoresSafeArea()
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    backButton.padding(.leading, 18).padding(.top, 10)
                }
            }
        }
        .task {
            // A live event's board moves: every 15 s while the page is open.
            while !Task.isCancelled {
                await events.loadDetail(eventID)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private var backButton: some View {
        Button(action: close) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.18)))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel("Back")
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        note = "Copied \(text)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if note == "Copied \(text)" { note = "" } }
    }

    private func page(_ e: WyrmEvent, detail: WyrmEventDetail?) -> some View {
        ZStack(alignment: .bottom) {
            wyrmScopedColours.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero(e)
                    TimelineView(.periodic(from: .now, by: 1)) { context in timer(e, now: context.date) }
                        .offset(y: -26).padding(.bottom, -26)
                    VStack(spacing: 0) {
                        if e.status != "upcoming", let friends = detail?.friends, !friends.isEmpty { friendsBar(friends, live: e.status == "live") }
                        if let board = detail?.live { liveBoard(board) }
                        if e.status != "finished" { registration(e) }
                        wyrmPlayers(e, detail)
                        if !e.rules.isEmpty {
                            WyrmSectionLabel("Rules")
                            WyrmPaperCard {
                                ForEach(Array(e.rules.enumerated()), id: \.offset) { index, rule in
                                    if index > 0 { Rectangle().fill(wyrmScopedColours.rowRule).frame(height: 1) }
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(wyrmScopedColours.live)
                                        Text(rule.replacingOccurrences(of: "**", with: "")).font(.androidWyrm(13.5)).foregroundColor(wyrmScopedColours.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                }
                            }
                        }
                        if let markdown = e.markdown {
                            WyrmSectionLabel("From the organisers")
                            WyrmPaperCard {
                                WyrmMarkdown(source: wyrmDiscordTimes(markdown), size: 14, ink: wyrmScopedColours.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            }
                        }
                        if e.status == "finished" { registration(e) }
                        TimelineView(.periodic(from: .now, by: 1)) { context in pass(e, now: context.date) }
                        people
                        Spacer().frame(height: 110)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            if e.status != "finished" {
                Button { events.join(e, engine: engine) } label: {
                    Text(e.status == "live" ? "Join now" : "Join at the start").font(.androidWyrm(17, .heavy)).foregroundColor(wyrmScopedColours.onInk)
                        .frame(maxWidth: .infinity).frame(height: 58).background(Capsule().fill(wyrmScopedColours.ink))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 18)
                .background(LinearGradient(colors: [wyrmScopedColours.paper.opacity(0), wyrmScopedColours.paper], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            }
            if !note.isEmpty {
                Text(note).font(.androidWyrm(12.5, .semibold)).foregroundColor(wyrmScopedColours.onInk)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(wyrmScopedColours.ink))
                    .padding(.bottom, e.status == "finished" ? 24 : 96)
                    .transition(.opacity)
            }
        }
    }

    /// The window's top inset: the art runs under the status bar.
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { scene in
            (scene as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top
        }.first ?? 0
    }

    private func hero(_ e: WyrmEvent) -> some View {
        let top = topInset
        return ZStack(alignment: .topLeading) {
            WyrmEventArt(kind: e.kind, seed: e.id, big: true)
            VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        backButton
                        Spacer()
                        if e.status == "upcoming" { WyrmEventBell(on: events.reminders.contains(e.id), size: 40) { events.toggleReminder(e) } }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if e.status == "live" { WyrmGlassPill(solid: evColor(0xFFE5484D)) { WyrmPillText("LIVE") } }
                        WyrmGlassPill { WyrmEventFlag(country: e.flag); WyrmPillText(e.region.isEmpty ? e.serverLabel : e.region) }
                        if let number = e.eventNumber { WyrmGlassPill { WyrmPillText("#\(number)") } }
                    }
                    let title = (e.title?.count ?? 99) < 34 ? e.title : nil
                    Text(title ?? e.name).font(.androidWyrm(30, .heavy)).foregroundColor(.white).padding(.top, 10)
                    Text((title != nil ? e.name + " · " : "") + e.kind.blurb).font(.androidWyrm(13)).foregroundColor(.white.opacity(0.88))
                        .padding(.top, 6)
                }
                .padding(.top, top + 10).padding(.horizontal, 18).padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340 + top)
    }

    private func timer(_ e: WyrmEvent, now: Date) -> some View {
        WyrmPaperCard {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    WyrmEventLabel(e.status == "upcoming" ? "Starts in" : e.status == "live" ? "On for" : "Played")
                    Text(e.status == "upcoming" ? wyrmEventCountdown((e.startsAt ?? now).timeIntervalSince(now))
                         : e.status == "live" ? wyrmEventCountdown(now.timeIntervalSince(e.began ?? now)) : wyrmDay(e.startedAt))
                        .font(.androidWyrm(26, .heavy)).foregroundColor(wyrmScopedColours.ink).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(e.status == "finished" ? wyrmClock(e.startedAt) + " – " + wyrmClock(e.endedAt) : wyrmClock(e.startsAt))
                        .font(.androidWyrm(14, .bold)).foregroundColor(wyrmScopedColours.ink)
                    Text(e.status == "finished" ? wyrmMinutes(e.durationSeconds) : wyrmDay(e.startsAt))
                        .font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    private func friendsBar(_ friends: [WyrmEventPlayer], live: Bool) -> some View {
        WyrmPaperCard {
            HStack(spacing: 4) {
                ForEach(friends.prefix(2)) { p in WyrmAvatar(initials: String(p.name.prefix(1)).uppercased(), size: 30, url: p.avatarUrl) }
                Text("\(friends.prefix(2).map(\.name).joined(separator: " and ")) \(live ? "are playing" : "played") this event")
                    .font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.ink).padding(.leading, 8)
                Spacer(minLength: 0)
            }.padding(12)
        }.padding(.top, 4)
    }

    private func liveBoard(_ board: WyrmEventLiveBoard) -> some View {
        VStack(spacing: 0) {
            WyrmSectionLabel("Live in the arena")
            WyrmPaperCard {
                HStack(spacing: 14) {
                    WyrmArenaMinimapView(map: board.minimap).frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(wyrmGrouped(board.players.map { Int64($0) })).font(.androidWyrm(30, .heavy)).foregroundColor(wyrmScopedColours.ink)
                        Text("snakes in the arena now").font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.quiet)
                    }
                    Spacer(minLength: 0)
                }.padding(16)
                ForEach(board.leaderboard) { line in boardRow(line) }
            }
        }
    }

    private func boardRow(_ line: WyrmLeaderboardLine) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(wyrmScopedColours.rowRule).frame(height: 1)
            HStack {
                Text("\(line.rank)").font(.androidWyrm(14, .heavy)).foregroundColor(wyrmScopedColours.quiet).frame(width: 24, alignment: .leading)
                Text(line.name.isEmpty ? "—" : line.name).font(.androidWyrm(14, .semibold)).foregroundColor(wyrmScopedColours.ink).lineLimit(1)
                Spacer(minLength: 6)
                Text(wyrmGrouped(line.score)).font(.androidWyrm(14, .heavy)).foregroundColor(wyrmScopedColours.ink)
            }.padding(.horizontal, 16).padding(.vertical, 9)
        }
    }

    private func registration(_ e: WyrmEvent) -> some View {
        let r = e.registration
        let title: String, lead: String, steps: [String]
        if r.discord == false {
            title = "No sign-up needed"; lead = "Join the server at the start time with your usual in-game name."; steps = []
        } else if r.mode == "verified" {
            title = "Verified Discord players are in"
            lead = "The organisers enrol players who are verified in their Discord automatically."
            steps = ["Join the organisers' Discord and verify once.", "Keep the same in-game name you verified with.", "Join this server when the event starts."]
        } else {
            title = "Register on Discord first"
            lead = "The organisers' bot runs sign-ups. Players who are not registered cannot take part."
            steps = ["Open the registration channel in their Discord.", "Sign up with your real in-game name. Their bot sends you a link.", "Join this server at the start. Do not change network or name."]
        }
        return VStack(spacing: 0) {
            WyrmSectionLabel("Registration")
            WyrmPaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.androidWyrm(16, .heavy)).foregroundColor(wyrmScopedColours.ink)
                    Text(lead).font(.androidWyrm(13.5)).foregroundColor(wyrmScopedColours.mute)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)").font(.androidWyrm(12, .heavy)).foregroundColor(wyrmScopedColours.ink)
                                .frame(width: 22, height: 22).background(Circle().fill(wyrmScopedColours.well))
                            Text(step).font(.androidWyrm(13.5)).foregroundColor(wyrmScopedColours.mute)
                        }
                    }
                    if r.discord != false, let raw = r.url, let url = URL(string: raw) {
                        Button { openURL(url) } label: {
                            Text("Open the registration channel").font(.androidWyrm(15, .heavy)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 46).background(Capsule().fill(evColor(0xFF5865F2)))
                        }.buttonStyle(.plain)
                    }
                    Text("Sign-ups are handled by the event organisers, not by Wyrm. For anything about registering, message Noah (noahvem) or Lucky (lucky_623) on Discord.")
                        .font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.quiet)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }
    }

    private func wyrmPlayers(_ e: WyrmEvent, _ detail: WyrmEventDetail?) -> some View {
        let players: [WyrmEventPlayer] = e.status == "upcoming" ? [] : (detail?.wyrm ?? [])
        return VStack(spacing: 0) {
            WyrmSectionLabel("Wyrm players")
            WyrmPaperCard {
                if detail == nil && e.status != "upcoming" {
                    Text("Loading…").font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.quiet).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                } else if players.isEmpty {
                    Text(e.status == "upcoming" ? "Players from Wyrm show here once the event starts." : "Nobody from Wyrm played this one.")
                        .font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.quiet).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                } else {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, p in
                        if index > 0 { Rectangle().fill(wyrmScopedColours.rowRule).frame(height: 1) }
                        HStack(spacing: 10) {
                            Text(p.bestScore != nil ? "\(index + 1)" : "·").font(.androidWyrm(14, .heavy)).foregroundColor(wyrmScopedColours.quiet).frame(width: 22, alignment: .leading)
                            WyrmAvatar(initials: String(p.name.prefix(1)).uppercased(), size: 30, url: p.avatarUrl, online: p.playingNow)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.androidWyrm(14, .bold)).foregroundColor(wyrmScopedColours.ink).lineLimit(1)
                                Text(p.runs > 0 ? "\(p.runs) \(p.runs == 1 ? "life" : "lives") · \(wyrmGrouped(p.kills)) kills" : p.playingNow ? "Playing now" : "Was in the arena")
                                    .font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.quiet)
                            }
                            Spacer(minLength: 4)
                            if let best = p.bestScore { Text(wyrmGrouped(best)).font(.androidWyrm(14, .heavy)).foregroundColor(wyrmScopedColours.ink) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                }
            }
        }
    }

    /**
     * The Event pass (OM, 2026-10-30): what the feed says about the event, once,
     * in plain words, and only what applies (no team line for a solo event, no
     * Discord line without a sign-up, no tiers, no raw port or http).
     */
    private func pass(_ e: WyrmEvent, now: Date) -> some View {
        let look = WyrmEventLook.of(e.kind)
        var tiles: [(String, String, String)] = []
        switch e.status {
        case "finished": tiles.append(("Played", wyrmDay(e.startedAt) + " · " + wyrmClock(e.startedAt) + "–" + wyrmClock(e.endedAt), wyrmMinutes(e.durationSeconds)))
        case "live": tiles.append(("Started", wyrmClock(e.began), wyrmEventCountdown(now.timeIntervalSince(e.began ?? now)) + " ago"))
        default: tiles.append(("Starts", wyrmDay(e.startsAt) + " · " + wyrmClock(e.startsAt), "in " + wyrmEventCountdown((e.startsAt ?? now).timeIntervalSince(now))))
        }
        if let prize = e.prizeUsd.flatMap(wyrmDollars) { tiles.append(("Prize", prize, "for the winner")) }
        if let round = e.roundMinutes, round > 0 { tiles.append(("First round", "\(round) min", "then players are knocked out")) }
        if e.status == "finished", let players = e.players { tiles.append(("Players", wyrmGrouped(Int64(players)), "took part")) }
        if (e.kind == .teamLastStanding || e.kind == .lastDuoStanding) && e.teamNames == true {
            tiles.append((e.kind == .lastDuoStanding ? "Duos" : "Teams", "Named", "each team plays under its name"))
        }
        if e.needsSignUp {
            tiles.append(("Discord sign-up", "Needed", e.registration.mode == "verified" ? "Verified players are in automatically"
                          : e.registration.autoAccept == true ? "Sign up in their channel, you are accepted at once" : "Sign up in their channel"))
        }
        if e.reconstructed { tiles.append(("Note", "Rebuilt from server logs", "some details may be missing")) }
        // The first tile and any sign-up or note take a whole row; the rest pair up.
        let wide: Set<String> = ["Starts", "Started", "Played", "Discord sign-up", "Note"]
        var rows: [[(String, String, String)]] = []
        var pending: [(String, String, String)] = []
        for tile in tiles {
            if wide.contains(tile.0) { rows.append([tile]) } else {
                pending.append(tile)
                if pending.count == 2 { rows.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { rows.append(pending) }
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(spacing: 0) {
            WyrmSectionLabel("Event pass")
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("EVENT TYPE").font(.androidWyrm(10.5, .heavy)).tracking(1).foregroundColor(.white.opacity(0.85))
                        Text(e.name).font(.androidWyrm(21, .heavy)).foregroundColor(.white)
                    }
                    Spacer()
                    if let number = e.eventNumber { WyrmGlassPill { WyrmPillText("#\(number)") } }
                }
                .padding(16)
                .background(LinearGradient(colors: look.bg, startPoint: .topLeading, endPoint: .bottomTrailing))
                HStack(spacing: 10) {
                    WyrmEventFlag(country: e.flag, width: 24, height: 17)
                    Text("\(e.serverLabel) server").font(.androidWyrm(15, .heavy)).foregroundColor(wyrmScopedColours.ink).lineLimit(1).fixedSize()
                    Text(e.address).font(.system(size: 13, design: .monospaced)).foregroundColor(wyrmScopedColours.mute).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button { copy(e.address) } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 13, weight: .semibold)).foregroundColor(wyrmScopedColours.ink)
                            .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(wyrmScopedColours.card))
                    }.buttonStyle(.plain).accessibilityLabel("Copy the address")
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(wyrmScopedColours.well))
                .padding(.horizontal, 14).padding(.top, 14)
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 10) { ForEach(Array(row.enumerated()), id: \.offset) { _, tile in passTile(tile) } }
                    }
                }.padding(14)
                HStack {
                    WyrmEventBeadStrip(skin: look.skin + look.skin2)
                    Spacer()
                    Text([e.region.isEmpty ? nil : e.region, e.eventNumber.map { "event \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.androidWyrm(12, .bold)).foregroundColor(wyrmScopedColours.quiet)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(wyrmScopedColours.card)
            .clipShape(shape)
            .overlay(shape.stroke(wyrmScopedColours.rule, lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    private func passTile(_ t: (String, String, String)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            WyrmEventLabel(t.0)
            Text(t.1).font(.androidWyrm(15.5, .heavy)).foregroundColor(wyrmScopedColours.ink)
            if !t.2.isEmpty { Text(t.2).font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(wyrmScopedColours.well))
    }

    /* The people behind the events (OM, 2026-10-30), with their Discord names.
       Registration questions go to Noah and Lucky; Wyrm's own to OM. */
    private static let people: [(name: String, role: String, discord: String, note: String)] = [
        ("Noah", "Organiser", "noahvem", "Runs the events. Ask about registration."),
        ("Lucky", "Manager", "lucky_623", "Manages the events. Ask about registration."),
        ("OM", "Wyrm developer", "disis_om", "Makes Wyrm. Ask about the app."),
    ]

    private var people: some View {
        VStack(spacing: 0) {
            WyrmSectionLabel("Run by")
            WyrmPaperCard {
                ForEach(Array(Self.people.enumerated()), id: \.offset) { index, person in
                    if index > 0 { Rectangle().fill(wyrmScopedColours.rowRule).frame(height: 1) }
                    Button { copy(person.discord) } label: {
                        HStack(spacing: 12) {
                            Text(String(person.name.prefix(1))).font(.androidWyrm(16, .heavy)).foregroundColor(evColor(0xFF5865F2))
                                .frame(width: 38, height: 38)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(evColor(0xFF5865F2).opacity(0.14)))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(person.name).font(.androidWyrm(15, .heavy)).foregroundColor(wyrmScopedColours.ink)
                                    WyrmEventChip(text: person.role, tint: person.role == "Wyrm developer" ? wyrmScopedColours.live : evColor(0xFF5865F2))
                                }
                                Text(person.note).font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Discord").font(.androidWyrm(10.5)).foregroundColor(wyrmScopedColours.quiet)
                                Text(person.discord).font(.androidWyrm(13, .bold)).foregroundColor(wyrmScopedColours.ink)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Text("Tap a name to copy it. For registration, message Noah or Lucky.").font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
    }
}

/* ---------------------------------------------------------------- joining */

/// Over the portrait app: the join question, then the wait for the start.
struct WyrmEventOverlays: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var engine: WyrmShellStore
    @ObservedObject private var events = WyrmEventsStore.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if let event = events.countdown {
                countdown(event).transition(.opacity)
            } else if let event = events.joinSheet {
                Color.black.opacity(0.32).ignoresSafeArea().onTapGesture { events.joinSheet = nil }
                VStack { Spacer(); sheet(event) }.transition(.move(edge: .bottom))
            }
            if !events.toast.isEmpty {
                VStack {
                    Spacer()
                    Text(events.toast).font(.androidWyrm(12.5, .semibold)).foregroundColor(wyrmScopedColours.onInk)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(wyrmScopedColours.ink))
                        .padding(.bottom, 110)
                }
                .allowsHitTesting(false)
                .task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    events.toast = ""
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: events.joinSheet?.id)
        .animation(.easeOut(duration: 0.22), value: events.countdown?.id)
    }

    private func sheet(_ event: WyrmEvent) -> some View {
        let needs = event.needsSignUp
        return VStack(alignment: .leading, spacing: 10) {
            Text(needs ? "Are you registered?" : "Ready to join").font(.androidWyrm(21, .heavy)).foregroundColor(wyrmScopedColours.ink)
            Text(!needs ? "No sign-up is needed for this event."
                 : event.registration.mode == "verified" ? "This event takes players verified in the organisers' Discord. Unregistered players cannot take part."
                 : "This event needs a sign-up in the organisers' Discord before it starts. Unregistered players cannot take part.")
                .font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.mute)
            ForEach(Array(event.rules.prefix(3).enumerated()), id: \.offset) { _, rule in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(wyrmScopedColours.live)
                    Text(rule.replacingOccurrences(of: "**", with: "")).font(.androidWyrm(13)).foregroundColor(wyrmScopedColours.mute)
                }
            }
            if needs {
                Text("Not sure? Message Noah (noahvem) or Lucky (lucky_623) on Discord.").font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                if let raw = event.registration.url, let url = URL(string: raw) {
                    Button { openURL(url) } label: {
                        Text("Register on Discord").font(.androidWyrm(15, .heavy)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(evColor(0xFF5865F2)))
                    }.buttonStyle(.plain)
                }
            }
            Button { events.enter(event, engine: engine) } label: {
                Text(event.status == "live" ? "Join now" : needs ? "I'm registered, join at the start" : "Join at the start")
                    .font(.androidWyrm(15, .heavy)).foregroundColor(wyrmScopedColours.onInk)
                    .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(wyrmScopedColours.ink))
            }.buttonStyle(.plain)
            Button { events.joinSheet = nil } label: {
                Text("Not now").font(.androidWyrm(15, .heavy)).foregroundColor(wyrmScopedColours.quiet).frame(maxWidth: .infinity).frame(height: 40)
            }.buttonStyle(.plain)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(wyrmScopedColours.card))
        .padding(8)
    }

    /// Waiting for the start: a countdown, then the arena.
    private func countdown(_ event: WyrmEvent) -> some View {
        countdownFace(event)
            .task(id: event.id) {
                // At the start, straight into the event's arena.
                let wait = (event.startsAt ?? Date()).timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled, events.countdown?.id == event.id else { return }
                events.enter(event, engine: engine, now: true)
            }
    }

    private func countdownFace(_ event: WyrmEvent) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = (event.startsAt ?? context.date).timeIntervalSince(context.date)
            ZStack {
                evColor(0xFF0B0F0C).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(wyrmEventCountdown(left)).font(.androidWyrm(64, .heavy)).foregroundColor(.white).monospacedDigit()
                    Text(event.name).font(.androidWyrm(20, .bold)).foregroundColor(.white)
                    Text("The event starts, then Wyrm enters \(event.address)").font(.androidWyrm(14)).foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Button { events.countdown = nil } label: {
                        Text("Cancel").font(.androidWyrm(15, .heavy)).foregroundColor(.white)
                            .frame(width: 200, height: 48).background(Capsule().fill(Color.white.opacity(0.12)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
