import Foundation
import Network
import SwiftUI

struct WyrmServicePlayer: Identifiable, Equatable {
    let id: String
    let ingameName: String
    let username: String
    let displayName: String
    let avatarKey: String
    let avatarURL: String
    let bio: String
    let highestScore: Int64
    let kills: Int64
    let followerCount: Int64
    let followingCount: Int64
    let createdAt: String
    let isFollowing: Bool
    let followsYou: Bool
    let canMessage: Bool

    var handle: String { username.isEmpty ? "" : "@\(username)" }
    var initials: String {
        let value = displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return value.isEmpty ? "W" : value
    }

    init(_ json: [String: Any]) {
        id = json.string("id")
        ingameName = json.string("ingameName")
        username = json.string("username")
        displayName = json.string("displayName", fallback: "Unnamed")
        avatarKey = json.string("avatarKey", fallback: "mono-ink")
        let rawAvatar = json.string("avatarUrl")
        avatarURL = rawAvatar.hasPrefix("/") ? "https://wyrm-api.77-245-76-86.sslip.io\(rawAvatar)" : rawAvatar
        bio = json.string("bio")
        highestScore = json.int64("highestScore")
        kills = json.int64("kills")
        followerCount = json.int64("followerCount")
        followingCount = json.int64("followingCount")
        createdAt = json.string("createdAt")
        isFollowing = json.bool("isFollowing")
        followsYou = json.bool("followsYou")
        canMessage = json.bool("canMessage")
    }
}

struct WyrmServiceAlert: Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let meta: [String: String]
    let createdAt: String
    private(set) var read: Bool

    func markedRead() -> WyrmServiceAlert {
        var copy = self
        copy.read = true
        return copy
    }

    init(_ json: [String: Any]) {
        id = json.string("id")
        kind = json.string("kind", fallback: "broadcast")
        title = json.string("title")
        body = json.string("body")
        createdAt = json.string("createdAt")
        read = json.bool("read")
        let raw = json["meta"] as? [String: Any] ?? [:]
        meta = raw.reduce(into: [:]) { result, pair in
            if let value = pair.value as? String { result[pair.key] = value }
            else if let data = try? JSONSerialization.data(withJSONObject: pair.value, options: [.fragmentsAllowed, .sortedKeys]),
                    let string = String(data: data, encoding: .utf8) { result[pair.key] = string }
        }
    }
}

struct WyrmChatItem: Identifiable, Equatable {
    let id: String
    let body: String
    let createdAt: String
    let authorID: String
    let authorName: String
    let authorUsername: String

    /// For lines that do not come from the Wyrm API, such as NTL Team chat.
    init(id: String, body: String, createdAt: String, authorID: String, authorName: String, authorUsername: String) {
        self.id = id; self.body = body; self.createdAt = createdAt
        self.authorID = authorID; self.authorName = authorName; self.authorUsername = authorUsername
    }

    init(_ json: [String: Any], direct: Bool = false) {
        id = json.string("id")
        body = json.string("body")
        createdAt = json.string("createdAt")
        authorID = json.string(direct ? "senderId" : "playerId")
        authorName = json.string("displayName", fallback: "Player")
        authorUsername = json.string("username")
    }
}

struct WyrmConversation: Identifiable, Equatable {
    let player: WyrmServicePlayer
    let lastMessage: String
    let lastAt: String
    let unreadCount: Int
    var id: String { player.id }

    init?(_ json: [String: Any]) {
        guard let raw = json["player"] as? [String: Any] else { return nil }
        player = WyrmServicePlayer(raw)
        lastMessage = json.string("lastMessage")
        lastAt = json.string("lastAt")
        unreadCount = json.int("unreadCount")
    }
}

struct WyrmVoiceRoom: Identifiable, Equatable {
    let id: String
    let name: String
    let creator: WyrmServicePlayer
    let gate: String
    let active: Bool
    let activeCount: Int
    let revision: Int
    let mine: Bool
    let member: Bool
    let managedPublic: Bool
    let capacity: Int
    let suspended: Bool
    let createdAt: String

    init?(_ json: [String: Any]) {
        guard let owner = json["creator"] as? [String: Any] else { return nil }
        id = json.string("id")
        name = json.string("name", fallback: "Voice room")
        creator = WyrmServicePlayer(owner)
        gate = json.string("gate", fallback: "open")
        active = json.bool("active")
        activeCount = json.int("activeCount")
        revision = json.int("revision", fallback: 1)
        mine = json.bool("mine")
        member = json.bool("member")
        managedPublic = json.bool("managedPublic")
        capacity = json.int("capacity", fallback: 10)
        suspended = json.bool("suspended")
        createdAt = json.string("createdAt")
    }
}

struct WyrmArena: Identifiable, Equatable {
    let active: Bool
    let address: String
    let port: Int
    let players: Int
    let number: Int
    let cluster: Int
    var id: String { endpoint }
    var endpoint: String { "\(address):\(port)" }
    var code: String { String(format: "%04d", number % 10_000) }
    var title: String { "Arena \(code)" }

    static func custom(_ raw: String) -> WyrmArena? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }),
              let first = UInt8(octets[0]), (1...223).contains(first) else { return nil }
        let port = parts.count == 2 ? Int(parts[1]) : 444
        guard let port, (1...65535).contains(port) else { return nil }
        return WyrmArena(active: true, address: octets.joined(separator: "."), port: port,
                         players: 0, number: 0, cluster: 0)
    }
}

struct WyrmVoiceVerification: Equatable {
    let verified: Bool
    let verifiedAt: String
    init(_ json: [String: Any]) {
        verified = json.bool("verified")
        verifiedAt = json.string("verifiedAt")
    }
}

struct WyrmVoiceChallenge: Equatable {
    let id: String
    let expiresAt: String
    let resendAt: String
    init(_ json: [String: Any]) {
        id = json.string("challengeId")
        expiresAt = json.string("expiresAt")
        resendAt = json.string("resendAt")
    }
}

enum WyrmServiceError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, fallback: String = "") -> String {
        guard let value = self[key], !(value is NSNull) else { return fallback }
        let text = value as? String ?? String(describing: value)
        return text == "null" ? fallback : text
    }
    func bool(_ key: String) -> Bool { (self[key] as? Bool) ?? ((self[key] as? NSNumber)?.boolValue ?? false) }
    func int(_ key: String, fallback: Int = 0) -> Int { (self[key] as? NSNumber)?.intValue ?? Int(string(key)) ?? fallback }
    func int64(_ key: String) -> Int64 { (self[key] as? NSNumber)?.int64Value ?? Int64(string(key)) ?? 0 }
}

/// The arena machine's country (OM, 2026-10-09): a real flag picture (flagcdn,
/// 160 px PNG) with rounded corners and a hairline edge, then its code. Draws
/// nothing while the country is unknown; a quiet plate until the picture lands.
struct WyrmArenaCountryBadge: View {
    let country: String

    var body: some View {
        if country.count == 2, let url = URL(string: "https://flagcdn.com/w160/\(country.lowercased()).png") {
            HStack(spacing: 5) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { ATheme.well }
                }
                .frame(width: 20, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(ATheme.ink.opacity(0.14), lineWidth: 0.5))
                Text(country).font(.androidWyrm(10.5, .bold)).tracking(0.6).foregroundColor(ATheme.quiet)
            }
        }
    }
}

/// Set by any 429 from the rate limiter (it sends Retry-After). Until then the
/// background refreshes (after a run) stay quiet and screens keep what they
/// show; a player's own action still goes through (2026-10-08).
@MainActor
enum WyrmRateLimit {
    private(set) static var quietUntil = Date.distantPast
    static var quiet: Bool { Date() < quietUntil }
    static func note(seconds: Int) {
        guard seconds > 0 else { return }
        quietUntil = max(quietUntil, Date().addingTimeInterval(TimeInterval(min(seconds, 600))))
    }
}

private actor WyrmServiceClient {
    static let shared = WyrmServiceClient()
    private let base = "https://wyrm-api.77-245-76-86.sslip.io"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func notifications(token: String) async throws -> [WyrmServiceAlert] {
        try await request("/v1/notifications", token: token).array("notifications").map(WyrmServiceAlert.init)
    }

    func markAllRead(token: String) async throws { _ = try await request("/v1/notifications/read", method: "POST", token: token) }
    func setRead(_ id: String, read: Bool, token: String) async throws {
        _ = try await request("/v1/notifications/\(id)/read", method: "PUT", body: ["read": read], token: token)
    }
    func deleteAlert(_ id: String, token: String) async throws {
        _ = try await request("/v1/notifications/\(id)", method: "DELETE", token: token)
    }

    func player(_ id: String, token: String) async throws -> WyrmServicePlayer {
        WyrmServicePlayer(try await request("/v1/players/\(id)", token: token))
    }

    /// The same answer as JSON, so it can be kept for the next open (WyrmCache).
    func playerObject(_ id: String, token: String) async throws -> [String: Any] {
        try await request("/v1/players/\(id)", token: token)
    }

    func setFollowObject(playerID: String, following: Bool, token: String) async throws -> [String: Any] {
        try await request("/v1/players/\(playerID)/follow", method: following ? "PUT" : "DELETE", token: token)
    }

    func leaderboard(sort: String, token: String) async throws -> [WyrmServicePlayer] {
        try await request("/v1/leaderboard?sort=\(sort)", token: token).array("players").map(WyrmServicePlayer.init)
    }

    func search(_ query: String, token: String) async throws -> [WyrmServicePlayer] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await request("/v1/players?q=\(encoded)", token: token).array("players").map(WyrmServicePlayer.init)
    }

    func connections(playerID: String, kind: String, token: String) async throws -> [WyrmServicePlayer] {
        try await request("/v1/players/\(playerID)/connections?kind=\(kind)", token: token).array("players").map(WyrmServicePlayer.init)
    }

    func setFollow(playerID: String, following: Bool, token: String) async throws -> WyrmServicePlayer {
        WyrmServicePlayer(try await request("/v1/players/\(playerID)/follow", method: following ? "PUT" : "DELETE", token: token))
    }

    func globalMessages(token: String) async throws -> [WyrmChatItem] {
        try await request("/v1/chat/messages", token: token).array("messages").map { WyrmChatItem($0) }
    }

    func sendGlobal(body: String, token: String) async throws {
        _ = try await request("/v1/chat/messages", method: "POST", body: ["body": body, "channel": "global"], token: token)
    }

    func report(messageID: String, reason: String, token: String) async throws {
        _ = try await request("/v1/chat/messages/\(messageID)/report", method: "POST", body: ["reason": reason], token: token)
    }

    func conversations(token: String) async throws -> [WyrmConversation] {
        try await request("/v1/direct", token: token).array("conversations").compactMap(WyrmConversation.init)
    }

    func directMessages(playerID: String, token: String) async throws -> [WyrmChatItem] {
        try await request("/v1/direct/\(playerID)/messages", token: token).array("messages").map { WyrmChatItem($0, direct: true) }
    }

    func sendDirect(playerID: String, body: String, token: String) async throws {
        _ = try await request("/v1/direct/\(playerID)/messages", method: "POST", body: ["body": body], token: token)
    }

    func voiceRooms(token: String) async throws -> [WyrmVoiceRoom] {
        try await request("/v1/voice/rooms", token: token).array("rooms").compactMap(WyrmVoiceRoom.init)
    }

    func voiceVerification(token: String) async throws -> WyrmVoiceVerification {
        WyrmVoiceVerification(try await request("/v1/voice/verification/status", token: token))
    }

    func startVoiceVerification(email: String, token: String) async throws -> WyrmVoiceChallenge {
        WyrmVoiceChallenge(try await request("/v1/voice/verification/start", method: "POST", body: ["email": email], token: token))
    }

    func resendVoiceVerification(challengeID: String, email: String, token: String) async throws -> WyrmVoiceChallenge {
        WyrmVoiceChallenge(try await request("/v1/voice/verification/resend", method: "POST", body: ["challengeId": challengeID, "email": email], token: token))
    }

    func confirmVoiceVerification(challengeID: String, code: String, token: String) async throws -> WyrmVoiceVerification {
        WyrmVoiceVerification(try await request("/v1/voice/verification/confirm", method: "POST", body: ["challengeId": challengeID, "code": code], token: token))
    }

    func joinVoice(roomID: String, password: String?, token: String) async throws {
        var body: [String: Any] = [:]
        if let password, !password.isEmpty { body["password"] = password }
        _ = try await request("/v1/voice/rooms/\(roomID)/join", method: "POST", body: body, token: token)
    }

    func leaveVoice(roomID: String, token: String) async throws {
        _ = try await request("/v1/voice/rooms/\(roomID)/leave", method: "POST", token: token)
    }

    /// Each machine's country the way NTL asks for it (OM, 2026-10-09):
    /// `https://ntl-slither.com/ss/flags.php?ips=a,b,...` (60 a call) answers
    /// `{"ok":true,"flags":{"ip":"in"}}`; NTL also accepts "in.png" or a path
    /// ending in it. Keyed by IPv4, lower-case two letters.
    func arenaCountries(_ addresses: [String]) async -> [String: String] {
        var found: [String: String] = [:]
        var start = 0
        while start < addresses.count {
            let chunk = addresses[start..<min(start + 60, addresses.count)]
            start += 60
            var components = URLComponents(string: "https://ntl-slither.com/ss/flags.php")!
            components.queryItems = [URLQueryItem(name: "ips", value: chunk.joined(separator: ","))]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  json["ok"] as? Bool == true,
                  let flags = json["flags"] as? [String: Any] else { continue }
            for (ip, value) in flags {
                guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased(),
                      let match = text.range(of: "(?:^|/)([a-z]{2})(?:\\.png)?$", options: .regularExpression) else { continue }
                let piece = text[match].replacingOccurrences(of: "/", with: "").replacingOccurrences(of: ".png", with: "")
                if piece.count == 2 { found[ip] = piece }
            }
        }
        return found
    }

    func arenas() async throws -> [WyrmArena] {
        var request = URLRequest(url: URL(string: "https://slither.io/i80124.txt")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            WyrmDiagnostics.record("GET slither arena directory failed", category: "NETWORK")
            throw WyrmServiceError.message("Arena directory is unavailable.")
        }
        let result = try Self.decodeArenaDirectory(data)
        WyrmDiagnostics.record("GET slither arena directory status=200 arenas=\(result.count)", category: "NETWORK")
        return result
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, token: String) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw WyrmServiceError.message("Invalid Wyrm endpoint.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WyrmServiceError.message("Wyrm returned an invalid response.") }
            guard 200..<300 ~= http.statusCode else {
                WyrmDiagnostics.record("\(method) \(path) status=\(http.statusCode)", category: "NETWORK")
                let payload = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                // The rate limiter (and only it) sends Retry-After: note the
                // pause and say it in words instead of "Too Many Requests".
                if http.statusCode == 429, let seconds = Int(http.value(forHTTPHeaderField: "Retry-After") ?? ""), seconds > 0 {
                    await MainActor.run { WyrmRateLimit.note(seconds: seconds) }
                    throw WyrmServiceError.message("Slow down a little and try again in a moment.")
                }
                throw WyrmServiceError.message(payload.string("error", fallback: "HTTP_\(http.statusCode)"))
            }
            WyrmDiagnostics.record("\(method) \(path) status=\(http.statusCode)", category: "NETWORK")
            guard !data.isEmpty else { return [:] }
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch let error as WyrmServiceError { throw error }
        catch {
            WyrmDiagnostics.record("\(method) \(path) transport failure=\(error.localizedDescription)", category: "NETWORK")
            throw WyrmServiceError.message("Could not reach Wyrm. Check your connection and try again.")
        }
    }

    private static func decodeArenaDirectory(_ source: Data) throws -> [WyrmArena] {
        var payload = Array(source)
        while let last = payload.last, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(Int(last))!) { payload.removeLast() }
        guard payload.count >= 3, (payload.count - 1) % 2 == 0 else { throw WyrmServiceError.message("Arena directory is truncated.") }
        var bytes = Array(repeating: UInt8(0), count: (payload.count - 1) / 2)
        var shift = 0
        for index in 0..<(payload.count - 1) {
            var nibble = (Int(payload[index + 1]) - Int(Character("a").asciiValue!) - shift) % 26
            if nibble < 0 { nibble += 26 }
            guard nibble <= 15 else { throw WyrmServiceError.message("Arena directory could not be decoded.") }
            if index % 2 == 0 { bytes[index / 2] = UInt8(nibble << 4) }
            else { bytes[index / 2] |= UInt8(nibble) }
            shift = (shift + 7) % 26
        }
        let modern = !bytes.isEmpty && bytes.count % 28 == 0
        let width = modern ? 28 : 11
        guard bytes.count % width == 0 else { throw WyrmServiceError.message("Arena directory format is unsupported.") }
        var result: [WyrmArena] = []
        for offset in stride(from: 0, to: bytes.count, by: width) {
            let ip = modern ? offset + 1 : offset
            let port = modern ? (Int(bytes[offset + 21]) << 8) | Int(bytes[offset + 22]) : (Int(bytes[offset + 4]) << 16) | (Int(bytes[offset + 5]) << 8) | Int(bytes[offset + 6])
            let players = modern ? (Int(bytes[offset + 23]) << 8) | Int(bytes[offset + 24]) : (Int(bytes[offset + 7]) << 16) | (Int(bytes[offset + 8]) << 8) | Int(bytes[offset + 9])
            let cluster = modern ? Int(bytes[offset + 25]) : Int(bytes[offset + 10])
            let number = modern ? (Int(bytes[offset + 26]) << 8) | Int(bytes[offset + 27]) : offset / width + 1
            let address = (0..<4).map { String(bytes[ip + $0]) }.joined(separator: ".")
            let active = modern ? bytes[offset] <= 26 : true
            if (1...65535).contains(port) { result.append(WyrmArena(active: active, address: address, port: port, players: min(65535, players), number: number, cluster: cluster)) }
        }
        guard !result.isEmpty else { throw WyrmServiceError.message("No playable arenas were returned.") }
        return result
    }
}

/// A TCP latency probe and the arena WebSocket must never own the game port at
/// the same time. Closing the picker cancels its task, but an NWConnection
/// already in flight can outlive that task until its 1.5-second deadline.
final class WyrmArenaProbeGate {
    static let shared = WyrmArenaProbeGate()

    private let lock = NSLock()
    private var playActive = false
    private var sessions: [ObjectIdentifier: WyrmArenaProbeSession] = [:]

    /// Measured on 2026-09-25: thirty bare TCP connects to one arena, one every
    /// two seconds, and that arena reset every connection from the same public
    /// IP for about a minute afterwards — the WebSocket never upgraded, so every
    /// Play in that minute failed. So a
    /// round trip is remembered for a minute and an arena is never re-dialled
    /// inside it, however often the picker is opened.
    private static let reuseSeconds: TimeInterval = 60
    private var measured: [String: (at: Date, value: Int?)] = [:]

    fileprivate func recent(_ endpoint: String) -> (hit: Bool, value: Int?) {
        lock.lock()
        defer { lock.unlock() }
        guard let last = measured[endpoint],
              Date().timeIntervalSince(last.at) < Self.reuseSeconds else { return (false, nil) }
        return (true, last.value)
    }

    fileprivate func remember(_ endpoint: String, _ value: Int?) {
        lock.lock()
        // A probe cut short by Play measured nothing.
        if !playActive { measured[endpoint] = (Date(), value) }
        lock.unlock()
    }

    private init() {}

    fileprivate func register(_ session: WyrmArenaProbeSession) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !playActive else { return false }
        sessions[ObjectIdentifier(session)] = session
        return true
    }

    fileprivate func unregister(_ session: WyrmArenaProbeSession) {
        lock.lock()
        sessions.removeValue(forKey: ObjectIdentifier(session))
        lock.unlock()
    }

    func beginPlay() {
        lock.lock()
        playActive = true
        let pending = Array(sessions.values)
        lock.unlock()
        pending.forEach { $0.cancel() }
    }

    func endPlay() {
        lock.lock()
        playActive = false
        lock.unlock()
    }

    /// The picker closed: a dial still in flight is closed now rather than
    /// being left to run out its 1.5-second deadline behind the lobby.
    func cancelProbes() {
        lock.lock()
        let pending = Array(sessions.values)
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}

/// The web client's own ping (OM, 2026-10-09): `ws://ip:80/ptc`, one byte
/// 112 ('p') out, the same byte back, three round trips, the fastest kept
/// (`game1107241958.js`, the `/ptc` sockets after `loadSos`). The server wants
/// the page's Origin. Port 80, never the arena's game port, so a ping no
/// longer counts towards the game port's per-IP connect limit, and arenas
/// whose game port ignores a bare TCP dial still get a number. Network
/// framework (not URLSession): App Transport Security would refuse a plain
/// `ws://`. A custom address with no `/ptc` falls back to a TCP dial of its
/// own port, the probe used before.
fileprivate final class WyrmArenaProbeSession {
    private let arena: WyrmArena
    private let queue: DispatchQueue
    private let stateLock = NSLock()
    private var connection: NWConnection?
    private var completion: ((Int?) -> Void)?
    private var probeStarted: UInt64 = 0
    private var times: [Int] = []
    private var finished = false
    private static let rounds = 3
    private static let deadline = 2.5

    init(arena: WyrmArena, completion: @escaping (Int?) -> Void) {
        self.arena = arena
        self.completion = completion
        self.queue = DispatchQueue(label: "com.omrajput.wyrmios.ptc.\(arena.id)")
    }

    func start() {
        guard WyrmArenaProbeGate.shared.register(self) else { finish(nil); return }
        guard let url = URL(string: "ws://\(arena.address):80/ptc") else { fallback(); return }
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.setAdditionalHeaders([("Origin", "https://slither.io")])
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        let connection = NWConnection(to: .url(url), using: parameters)
        guard install(connection) else { return }
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready: sendPing(on: connection)
            case .failed, .cancelled: ptcEnded()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.deadline) { [self] in finish(best) }
    }

    func cancel() { finish(nil) }

    private var best: Int? { times.min().map { max(1, $0) } }

    private func install(_ connection: NWConnection) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !finished else { return false }
        self.connection = connection
        return true
    }

    private func sendPing(on connection: NWConnection) {
        probeStarted = DispatchTime.now().uptimeNanoseconds
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "ptc", metadata: [metadata])
        connection.send(content: Data([112]), contentContext: context, isComplete: true,
                        completion: .contentProcessed { [self] error in
            if error != nil { ptcEnded(); return }
            connection.receiveMessage { [self] data, _, _, error in
                guard error == nil, let data, data.count == 1, data.first == 112 else { ptcEnded(); return }
                let elapsed = DispatchTime.now().uptimeNanoseconds - probeStarted
                times.append(Int(elapsed / 1_000_000))
                if times.count < Self.rounds { sendPing(on: connection) } else { finish(best) }
            }
        })
    }

    /// The ptc socket closed or failed: what it measured, else (custom only) a TCP dial.
    private func ptcEnded() {
        if let value = best { finish(value); return }
        if arena.number == 0 { fallback() } else { finish(nil) }
    }

    private func fallback() {
        guard let port = NWEndpoint.Port(rawValue: UInt16(arena.port)) else { finish(nil); return }
        stateLock.lock()
        let previous = connection
        connection = nil
        stateLock.unlock()
        previous?.stateUpdateHandler = nil
        previous?.cancel()
        let connection = NWConnection(host: NWEndpoint.Host(arena.address), port: port, using: .tcp)
        guard install(connection) else { return }
        probeStarted = DispatchTime.now().uptimeNanoseconds
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                let elapsed = DispatchTime.now().uptimeNanoseconds - probeStarted
                finish(max(1, Int(elapsed / 1_000_000)))
            case .failed, .cancelled: finish(nil)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func finish(_ result: Int?) {
        stateLock.lock()
        guard !finished else { stateLock.unlock(); return }
        finished = true
        let active = connection
        connection = nil
        let callback = completion
        completion = nil
        stateLock.unlock()
        active?.stateUpdateHandler = nil
        active?.cancel()
        WyrmArenaProbeGate.shared.unregister(self)
        callback?(result)
    }
}

private enum WyrmArenaProbe {
    static func latency(to arena: WyrmArena) async -> Int? {
        // One machine answers for every arena on it; a custom address for itself.
        let key = arena.number == 0 ? arena.endpoint : arena.address
        let recent = WyrmArenaProbeGate.shared.recent(key)
        if recent.hit { return recent.value }
        let value: Int? = await withCheckedContinuation { continuation in
            WyrmArenaProbeSession(arena: arena) { continuation.resume(returning: $0) }.start()
        }
        WyrmArenaProbeGate.shared.remember(key, value)
        return value
    }
}

private extension Dictionary where Key == String, Value == Any {
    func array(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
}

@MainActor
final class WyrmServiceStore: ObservableObject {
    @Published private(set) var alerts: [WyrmServiceAlert] = []
    @Published private(set) var scoreLeaders: [WyrmServicePlayer] = []
    @Published private(set) var killLeaders: [WyrmServicePlayer] = []
    @Published private(set) var conversations: [WyrmConversation] = []
    @Published private(set) var voiceRooms: [WyrmVoiceRoom] = []
    @Published private(set) var arenas: [WyrmArena] = []
    @Published private(set) var arenaLatencies: [String: Int] = [:]
    @Published private(set) var recommendedArena: WyrmArena?
    @Published private(set) var people: [WyrmServicePlayer] = []
    /// Players opened by id (a profile reached from a message, a room or a
    /// leaderboard row), fetched fresh from /v1/players/:id.
    @Published private(set) var profiles: [String: WyrmServicePlayer] = [:]
    /// The global channel, last 24 hours, oldest first.
    @Published private(set) var globalChat: [WyrmChatItem] = []
    /// New global messages from others since the room was last read (OM, 2026-10-04).
    @Published private(set) var globalUnread = 0
    private var syncObservers: [NSObjectProtocol] = []
    @Published private(set) var followers: [WyrmServicePlayer] = []
    @Published private(set) var following: [WyrmServicePlayer] = []
    @Published private(set) var messages: [WyrmChatItem] = []
    @Published private(set) var voiceVerification = WyrmVoiceVerification([:])
    @Published private(set) var voiceChallenge: WyrmVoiceChallenge?
    @Published var loading = false
    @Published var errorMessage = ""
    @Published var lastRefresh: Date?
    @Published private(set) var preparedPlayerID: String?
    private var token = ""
    private var sessionRevision = UUID()
    private var arenaRefreshInFlight = false
    /// IPv4 -> lower-case country code, from NTL's service (see arenaCountries).
    @Published private(set) var arenaCountries: [String: String] = [:]
    private var arenaCountriesAt = Date.distantPast

    /// The upper-case country of the machine at `address`, or "".
    func countryCode(for address: String) -> String { arenaCountries[address]?.uppercased() ?? "" }

    private func refreshArenaCountries() async {
        let missing = Array(Set(arenas.map(\.address)).filter { arenaCountries[$0] == nil })
        guard !missing.isEmpty, Date().timeIntervalSince(arenaCountriesAt) >= 300 else { return }
        arenaCountriesAt = Date()
        let found = await WyrmServiceClient.shared.arenaCountries(missing)
        if found.isEmpty { arenaCountriesAt = .distantPast; return }
        arenaCountries.merge(found) { _, new in new }
    }

    var unreadCount: Int { alerts.filter { !$0.read }.count }
    var liveRooms: [WyrmVoiceRoom] { voiceRooms.filter { $0.active && !$0.suspended } }
    var messageCandidates: [WyrmServicePlayer] {
        var seen = Set<String>()
        return (followers + following).filter { $0.canMessage && seen.insert($0.id).inserted }
    }

    func isPrepared(for playerID: String?) -> Bool {
        guard let playerID, !playerID.isEmpty else { return false }
        return preparedPlayerID == playerID && !token.isEmpty
    }

    /// Invalidates every in-flight account request before removing all
    /// account-scoped data. This is deliberately exhaustive: switching users
    /// must never show the previous player's alerts, messages or connections.
    func resetSession() {
        sessionRevision = UUID()
        token = ""
        clearPublishedSession()
        loading = false
        WyrmDiagnostics.record("service session cleared", category: "ACCOUNT")
    }

    func bootstrap(token: String, playerID: String? = nil) async {
        guard !token.isEmpty else { return }
        let revision = UUID()
        sessionRevision = revision
        self.token = token
        clearPublishedSession()
        loading = true
        errorMessage = ""
        WyrmDiagnostics.record("service bootstrap started player=\(playerID ?? "none")", category: "ACCOUNT")

        // Each endpoint is isolated so one unavailable surface cannot discard
        // six successful responses. Results are published together only after
        // this exact account session is still current.
        async let alertRows: [WyrmServiceAlert]? = try? await WyrmServiceClient.shared.notifications(token: token)
        async let scoreRows: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.leaderboard(sort: "score", token: token)
        async let killRows: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.leaderboard(sort: "kills", token: token)
        async let conversationRows: [WyrmConversation]? = try? await WyrmServiceClient.shared.conversations(token: token)
        async let roomRows: [WyrmVoiceRoom]? = try? await WyrmServiceClient.shared.voiceRooms(token: token)
        async let verification: WyrmVoiceVerification? = try? await WyrmServiceClient.shared.voiceVerification(token: token)
        async let arenaRows: [WyrmArena]? = try? await WyrmServiceClient.shared.arenas()
        let values = await (alertRows, scoreRows, killRows, conversationRows, roomRows, verification, arenaRows)

        var followerRows: [WyrmServicePlayer]? = []
        var followingRows: [WyrmServicePlayer]? = []
        if let playerID, !Task.isCancelled {
            async let fetchedFollowers: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.connections(playerID: playerID, kind: "followers", token: token)
            async let fetchedFollowing: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.connections(playerID: playerID, kind: "following", token: token)
            (followerRows, followingRows) = await (fetchedFollowers, fetchedFollowing)
        }

        guard !Task.isCancelled, sessionRevision == revision else { return }
        alerts = WyrmTrailsFeature.visible(values.0 ?? [])
        scoreLeaders = values.1 ?? []
        killLeaders = values.2 ?? []
        conversations = values.3 ?? []
        voiceRooms = values.4 ?? []
        voiceVerification = values.5 ?? WyrmVoiceVerification([:])
        installArenaDirectory(values.6 ?? [])
        followers = followerRows ?? []
        following = followingRows ?? []
        preparedPlayerID = playerID
        lastRefresh = Date()

        let failures = [values.0 == nil, values.1 == nil, values.2 == nil,
                        values.3 == nil, values.4 == nil, values.5 == nil,
                        values.6 == nil, followerRows == nil, followingRows == nil]
            .filter { $0 }.count
        if failures > 0 {
            errorMessage = "Wyrm loaded, but \(failures) live section\(failures == 1 ? "" : "s") could not refresh yet."
        }
        loading = false
        WyrmDiagnostics.record("service bootstrap finished player=\(playerID ?? "none") failures=\(failures)", category: "ACCOUNT")
    }

    func refreshGlobalChat() async {
        await perform { self.globalChat = try await WyrmServiceClient.shared.globalMessages(token: self.token) }
    }

    /// The newest global message this phone has shown in the open room.
    static let globalSeenKey = "wyrm.global-chat.seen-at"

    /// Global chat's count (OM, 2026-10-04): messages from others newer than
    /// the newest one shown in the open room. The first look only sets that
    /// mark, so nobody starts with a day's worth of unread. Quiet on failure:
    /// a missed count is not worth an error on screen.
    func refreshGlobalUnread() async {
        guard !token.isEmpty,
              let items = try? await WyrmServiceClient.shared.globalMessages(token: token) else { return }
        guard let seen = UserDefaults.standard.string(forKey: Self.globalSeenKey) else {
            noteGlobalSeen(items)
            return
        }
        let me = preparedPlayerID ?? ""
        globalUnread = items.filter { $0.createdAt > seen && $0.authorID != me }.count
    }

    /// The room is on screen: everything in it is read.
    func noteGlobalSeen(_ items: [WyrmChatItem]? = nil) {
        guard let newest = (items ?? globalChat).map(\.createdAt).max() else { return }
        let seen = UserDefaults.standard.string(forKey: Self.globalSeenKey)
        if seen == nil || newest > seen! { UserDefaults.standard.set(newest, forKey: Self.globalSeenKey) }
        globalUnread = 0
    }

    func sendGlobal(_ body: String) async -> Bool {
        var sent = false
        await perform {
            try await WyrmServiceClient.shared.sendGlobal(body: body, token: self.token)
            sent = true
            self.globalChat = try await WyrmServiceClient.shared.globalMessages(token: self.token)
        }
        return sent
    }

    func report(_ message: WyrmChatItem, reason: String) async {
        await perform { try await WyrmServiceClient.shared.report(messageID: message.id, reason: reason, token: self.token) }
    }

    /// Stale-while-revalidate (OM, 2026-09-29): the profile as it was last
    /// time paints at once, the server's answer replaces it in place.
    func loadPlayer(_ id: String) async {
        guard !id.isEmpty else { return }
        if profiles[id] == nil, let cached = WyrmCache.loadObject("player-\(id)") {
            profiles[id] = WyrmServicePlayer(cached)
        }
        await perform {
            let object = try await WyrmServiceClient.shared.playerObject(id, token: self.token)
            self.profiles[id] = WyrmServicePlayer(object)
            WyrmCache.saveObject("player-\(id)", object)
        }
    }

    /// Alerts that arrived since the last look, for the in-app banner. Quiet:
    /// a failed poll changes nothing on screen.
    func pollAlerts() async -> [WyrmServiceAlert] {
        guard !token.isEmpty else { return [] }
        let revision = sessionRevision
        let known = Set(alerts.map(\.id))
        guard let fresh = try? await WyrmServiceClient.shared.notifications(token: token),
              revision == sessionRevision else { return [] }
        let shown = WyrmTrailsFeature.visible(fresh)
        alerts = shown
        return shown.filter { !known.contains($0.id) && !$0.read }
    }

    /// The badge trail: every unread alert of these kinds, read (the destination opened).
    func markKindsRead(_ kinds: Set<String>) {
        alerts.filter { !$0.read && kinds.contains($0.kind) }.forEach(markRead)
    }

    /// A trail opened: its likes and replies are read.
    func markTrailRead(_ trailID: String) {
        alerts.filter { !$0.read && $0.meta["trailId"] == trailID }.forEach(markRead)
    }

    /// Marks one alert read on screen at once and on the server behind it.
    func markRead(_ alert: WyrmServiceAlert) {
        guard !alert.read, let index = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[index] = alert.markedRead()
        let token = token
        Task { try? await WyrmServiceClient.shared.setRead(alert.id, read: true, token: token) }
    }

    /// A counted run moves the leaderboards and may earn achievement notices.
    func observeGameSync() {
        guard syncObservers.isEmpty else { return }
        syncObservers.append(NotificationCenter.default.addObserver(forName: WyrmGameSync.profileChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshLeaderboardsAfterRun() }
        })
        syncObservers.append(NotificationCenter.default.addObserver(forName: WyrmGameSync.achievementsEarned, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshAlerts() }
        })
    }

    func refreshAlerts() async { await perform { self.alerts = try await WyrmTrailsFeature.visible(WyrmServiceClient.shared.notifications(token: self.token)) } }
    /// A pull never invalidates the signed-in session or clears already visible rows.
    func refreshSocial() async {
        guard !token.isEmpty else { return }
        // A pull right after the last one only plays the spinner: this is
        // seven requests, and repeated pulls hit the server's limit.
        guard Date().timeIntervalSince(lastSocialPull) >= 10 else {
            try? await Task.sleep(nanoseconds: 450_000_000)
            return
        }
        lastSocialPull = Date()
        let revision = sessionRevision
        let currentToken = token
        let playerID = preparedPlayerID
        async let score: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.leaderboard(sort: "score", token: currentToken)
        async let kills: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.leaderboard(sort: "kills", token: currentToken)
        async let chats: [WyrmConversation]? = try? await WyrmServiceClient.shared.conversations(token: currentToken)
        async let rooms: [WyrmVoiceRoom]? = try? await WyrmServiceClient.shared.voiceRooms(token: currentToken)
        async let notices: [WyrmServiceAlert]? = try? await WyrmServiceClient.shared.notifications(token: currentToken)
        let values = await (score, kills, chats, rooms, notices)
        guard !Task.isCancelled, revision == sessionRevision else { return }
        if let rows = values.0 { scoreLeaders = rows }
        if let rows = values.1 { killLeaders = rows }
        if let rows = values.2 { conversations = rows }
        if let rows = values.3 { voiceRooms = rows }
        if let rows = values.4 { alerts = WyrmTrailsFeature.visible(rows) }
        if let playerID {
            await loadConnectionLists(playerID: playerID)
        }
        lastRefresh = Date()
    }
    func markAllRead() async { await perform { try await WyrmServiceClient.shared.markAllRead(token: self.token); await self.refreshAlerts() } }
    func setRead(_ alert: WyrmServiceAlert, read: Bool) async { await perform { try await WyrmServiceClient.shared.setRead(alert.id, read: read, token: self.token); await self.refreshAlerts() } }
    func delete(_ alert: WyrmServiceAlert) async { await perform { try await WyrmServiceClient.shared.deleteAlert(alert.id, token: self.token); await self.refreshAlerts() } }

    /// After counted runs: only when the boards are older than 20 s and the
    /// server has not asked for a pause, and never as an error on screen
    /// (it used to show under Global chat when it failed). Auto restart can
    /// end a run every few seconds.
    func refreshLeaderboardsAfterRun() async {
        guard !token.isEmpty, !WyrmRateLimit.quiet else { return }
        if let at = leadersAt, Date().timeIntervalSince(at) < 20 { return }
        let token = token
        let revision = sessionRevision
        async let a: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.leaderboard(sort: "score", token: token)
        async let b: [WyrmServicePlayer]? = try? await WyrmServiceClient.shared.leaderboard(sort: "kills", token: token)
        let rows = await (a, b)
        guard revision == sessionRevision else { return }
        if let score = rows.0 { scoreLeaders = score }
        if let kills = rows.1 { killLeaders = kills }
        if rows.0 != nil, rows.1 != nil { leadersAt = Date() }
    }
    private var leadersAt: Date?
    private var lastSocialPull = Date.distantPast

    func refreshLeaderboards() async { await perform { async let a = WyrmServiceClient.shared.leaderboard(sort: "score", token: self.token); async let b = WyrmServiceClient.shared.leaderboard(sort: "kills", token: self.token); let rows = try await (a, b); self.scoreLeaders = rows.0; self.killLeaders = rows.1; self.leadersAt = Date() } }
    func searchPeople(_ query: String) async { await perform { self.people = try await WyrmServiceClient.shared.search(query, token: self.token) } }
    func loadConnections(playerID: String, kind: String) async { await perform { self.people = try await WyrmServiceClient.shared.connections(playerID: playerID, kind: kind, token: self.token) } }
    func loadConnectionLists(playerID: String) async { await perform {
        async let a = WyrmServiceClient.shared.connections(playerID: playerID, kind: "followers", token: self.token)
        async let b = WyrmServiceClient.shared.connections(playerID: playerID, kind: "following", token: self.token)
        let rows = try await (a, b); self.followers = rows.0; self.following = rows.1
    } }
    /// Follows or unfollows, and keeps the player the server answers with, so
    /// the profile's button flips (the answer used to be thrown away).
    func follow(_ player: WyrmServicePlayer) async {
        await perform {
            let object = try await WyrmServiceClient.shared.setFollowObject(playerID: player.id, following: !player.isFollowing, token: self.token)
            self.profiles[player.id] = WyrmServicePlayer(object)
            WyrmCache.saveObject("player-\(player.id)", object)
        }
    }

    func refreshConversations() async { await perform { self.conversations = try await WyrmServiceClient.shared.conversations(token: self.token) } }
    func loadThread(playerID: String) async { await perform { self.messages = try await WyrmServiceClient.shared.directMessages(playerID: playerID, token: self.token) } }
    func sendDirect(playerID: String, body: String) async { await perform { try await WyrmServiceClient.shared.sendDirect(playerID: playerID, body: body, token: self.token); self.messages = try await WyrmServiceClient.shared.directMessages(playerID: playerID, token: self.token) } }

    func refreshVoice() async { await perform { self.voiceRooms = try await WyrmServiceClient.shared.voiceRooms(token: self.token) } }
    func refreshVoiceVerification() async { await perform { self.voiceVerification = try await WyrmServiceClient.shared.voiceVerification(token: self.token) } }
    func startVoiceVerification(email: String) async -> Bool {
        var ok = false
        await perform { self.voiceChallenge = try await WyrmServiceClient.shared.startVoiceVerification(email: email, token: self.token); ok = true }
        return ok
    }
    func resendVoiceVerification(email: String) async -> Bool {
        guard let challenge = voiceChallenge else { return false }
        var ok = false
        await perform { self.voiceChallenge = try await WyrmServiceClient.shared.resendVoiceVerification(challengeID: challenge.id, email: email, token: self.token); ok = true }
        return ok
    }
    func confirmVoiceVerification(code: String) async -> Bool {
        guard let challenge = voiceChallenge else { return false }
        var ok = false
        await perform { self.voiceVerification = try await WyrmServiceClient.shared.confirmVoiceVerification(challengeID: challenge.id, code: code, token: self.token); ok = self.voiceVerification.verified }
        return ok
    }
    func joinVoice(_ room: WyrmVoiceRoom, password: String = "") async { await perform { try await WyrmServiceClient.shared.joinVoice(roomID: room.id, password: password, token: self.token); self.voiceRooms = try await WyrmServiceClient.shared.voiceRooms(token: self.token) } }
    func leaveVoice(_ room: WyrmVoiceRoom) async { await perform { try await WyrmServiceClient.shared.leaveVoice(roomID: room.id, token: self.token); self.voiceRooms = try await WyrmServiceClient.shared.voiceRooms(token: self.token) } }

    func refreshArenasLive() async {
        guard !arenaRefreshInFlight else { return }
        arenaRefreshInFlight = true
        defer { arenaRefreshInFlight = false }
        do {
            let rows = try await WyrmServiceClient.shared.arenas()
            installArenaDirectory(rows)
            lastRefresh = Date()
            await refreshArenaCountries()
        } catch {
            WyrmDiagnostics.record("live arena refresh failed=\(error.localizedDescription)", category: "NETWORK")
        }
    }

    /// Every listed arena gets a ping while the picker is open (OM, 2026-10-09;
    /// it used to be the first ten "active" ones, one at a time). One `/ptc`
    /// ping per machine on port 80, never the game port, up to eight machines
    /// at once; the arenas the player already knows go first.
    func measurePickerArenas(preferredEndpoints: [String]) async {
        let preferred = preferredEndpoints.compactMap { endpoint in arenas.first { $0.endpoint == endpoint } }
        var seenMachines = Set<String>()
        let machines = (preferred + arenas).filter { seenMachines.insert($0.address).inserted }
        await withTaskGroup(of: (String, Int).self) { group in
            var next = 0
            while next < min(8, machines.count) {
                let arena = machines[next]
                next += 1
                group.addTask { (arena.address, await WyrmArenaProbe.latency(to: arena) ?? -1) }
            }
            while let result = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                for arena in arenas where arena.address == result.0 { arenaLatencies[arena.id] = result.1 }
                refreshRecommendation()
                if next < machines.count {
                    let arena = machines[next]
                    next += 1
                    group.addTask { (arena.address, await WyrmArenaProbe.latency(to: arena) ?? -1) }
                }
            }
        }
        WyrmDiagnostics.record("picker probes finished machines=\(machines.count) arenas=\(arenas.count)", category: "NETWORK")
    }

    func measureCustomArena(_ endpoint: String) async -> Int? {
        guard let arena = WyrmArena.custom(endpoint) else { return nil }
        return await WyrmArenaProbe.latency(to: arena)
    }

    private func installArenaDirectory(_ rows: [WyrmArena]) {
        arenas = rows.sorted { $0.players > $1.players }
        let currentIDs = Set(arenas.map(\.id))
        arenaLatencies = arenaLatencies.filter { currentIDs.contains($0.key) }
        refreshRecommendation()
    }

    private func refreshRecommendation() {
        // Every listed arena; the directory's first byte ("active") only
        // weights the web client's own automatic pick, it hides nothing.
        let candidates = arenas
        guard !candidates.isEmpty else { recommendedArena = nil; return }
        recommendedArena = candidates.min { a, b in
            let left = arenaLatencies[a.id].flatMap { $0 > 0 ? $0 : nil } ?? .max
            let right = arenaLatencies[b.id].flatMap { $0 > 0 ? $0 : nil } ?? .max
            if left != right { return left < right }
            return a.players > b.players
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        guard !token.isEmpty else { return }
        errorMessage = ""
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }

    private func clearPublishedSession() {
        leadersAt = nil
        lastSocialPull = .distantPast
        alerts = []
        globalUnread = 0
        scoreLeaders = []
        killLeaders = []
        conversations = []
        voiceRooms = []
        arenas = []
        arenaLatencies = [:]
        recommendedArena = nil
        people = []
        profiles = [:]
        globalChat = []
        followers = []
        following = []
        messages = []
        voiceVerification = WyrmVoiceVerification([:])
        voiceChallenge = nil
        errorMessage = ""
        lastRefresh = nil
        preparedPlayerID = nil
    }
}
