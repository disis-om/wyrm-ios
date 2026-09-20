import Foundation

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
    let read: Bool

    init(_ json: [String: Any]) {
        id = json.string("id")
        kind = json.string("kind", fallback: "broadcast")
        title = json.string("title")
        body = json.string("body")
        createdAt = json.string("createdAt")
        read = json.bool("read")
        let raw = json["meta"] as? [String: Any] ?? [:]
        meta = raw.reduce(into: [:]) { result, pair in result[pair.key] = String(describing: pair.value) }
    }
}

struct WyrmChatItem: Identifiable, Equatable {
    let id: String
    let body: String
    let createdAt: String
    let authorID: String
    let authorName: String
    let authorUsername: String

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
        capacity = json.int("capacity", fallback: 10)
        suspended = json.bool("suspended")
        createdAt = json.string("createdAt")
    }
}

struct WyrmArena: Identifiable, Equatable {
    let address: String
    let port: Int
    let players: Int
    let number: Int
    let cluster: Int
    var id: String { endpoint }
    var endpoint: String { "\(address):\(port)" }
    var title: String { "Arena \(number) · Cluster \(cluster)" }
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

    func joinVoice(roomID: String, password: String?, token: String) async throws {
        var body: [String: Any] = [:]
        if let password, !password.isEmpty { body["password"] = password }
        _ = try await request("/v1/voice/rooms/\(roomID)/join", method: "POST", body: body, token: token)
    }

    func leaveVoice(roomID: String, token: String) async throws {
        _ = try await request("/v1/voice/rooms/\(roomID)/leave", method: "POST", token: token)
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
            if (1...65535).contains(port) { result.append(WyrmArena(address: address, port: port, players: min(65535, players), number: number, cluster: cluster)) }
        }
        guard !result.isEmpty else { throw WyrmServiceError.message("No playable arenas were returned.") }
        return result
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
    @Published private(set) var people: [WyrmServicePlayer] = []
    @Published private(set) var messages: [WyrmChatItem] = []
    @Published var loading = false
    @Published var errorMessage = ""
    @Published var lastRefresh: Date?
    private var token = ""

    var unreadCount: Int { alerts.filter { !$0.read }.count }
    var liveRooms: [WyrmVoiceRoom] { voiceRooms.filter { $0.active && !$0.suspended } }

    func bootstrap(token: String) async {
        guard !token.isEmpty else { return }
        self.token = token
        loading = true
        errorMessage = ""
        do {
            async let alertRows = WyrmServiceClient.shared.notifications(token: token)
            async let scoreRows = WyrmServiceClient.shared.leaderboard(sort: "score", token: token)
            async let killRows = WyrmServiceClient.shared.leaderboard(sort: "kills", token: token)
            async let conversationRows = WyrmServiceClient.shared.conversations(token: token)
            async let roomRows = WyrmServiceClient.shared.voiceRooms(token: token)
            async let arenaRows = WyrmServiceClient.shared.arenas()
            let values = try await (alertRows, scoreRows, killRows, conversationRows, roomRows, arenaRows)
            alerts = values.0; scoreLeaders = values.1; killLeaders = values.2
            conversations = values.3; voiceRooms = values.4
            arenas = values.5.sorted { $0.players > $1.players }
            lastRefresh = Date()
        } catch { errorMessage = error.localizedDescription }
        loading = false
    }

    func refreshAlerts() async { await perform { self.alerts = try await WyrmServiceClient.shared.notifications(token: self.token) } }
    func markAllRead() async { await perform { try await WyrmServiceClient.shared.markAllRead(token: self.token); await self.refreshAlerts() } }
    func setRead(_ alert: WyrmServiceAlert, read: Bool) async { await perform { try await WyrmServiceClient.shared.setRead(alert.id, read: read, token: self.token); await self.refreshAlerts() } }
    func delete(_ alert: WyrmServiceAlert) async { await perform { try await WyrmServiceClient.shared.deleteAlert(alert.id, token: self.token); await self.refreshAlerts() } }

    func refreshLeaderboards() async { await perform { async let a = WyrmServiceClient.shared.leaderboard(sort: "score", token: self.token); async let b = WyrmServiceClient.shared.leaderboard(sort: "kills", token: self.token); let rows = try await (a, b); self.scoreLeaders = rows.0; self.killLeaders = rows.1 } }
    func searchPeople(_ query: String) async { await perform { self.people = try await WyrmServiceClient.shared.search(query, token: self.token) } }
    func loadConnections(playerID: String, kind: String) async { await perform { self.people = try await WyrmServiceClient.shared.connections(playerID: playerID, kind: kind, token: self.token) } }
    func follow(_ player: WyrmServicePlayer) async { await perform { _ = try await WyrmServiceClient.shared.setFollow(playerID: player.id, following: !player.isFollowing, token: self.token) } }

    func refreshConversations() async { await perform { self.conversations = try await WyrmServiceClient.shared.conversations(token: self.token) } }
    func loadThread(playerID: String) async { await perform { self.messages = try await WyrmServiceClient.shared.directMessages(playerID: playerID, token: self.token) } }
    func sendDirect(playerID: String, body: String) async { await perform { try await WyrmServiceClient.shared.sendDirect(playerID: playerID, body: body, token: self.token); self.messages = try await WyrmServiceClient.shared.directMessages(playerID: playerID, token: self.token) } }

    func refreshVoice() async { await perform { self.voiceRooms = try await WyrmServiceClient.shared.voiceRooms(token: self.token) } }
    func joinVoice(_ room: WyrmVoiceRoom, password: String = "") async { await perform { try await WyrmServiceClient.shared.joinVoice(roomID: room.id, password: password, token: self.token); self.voiceRooms = try await WyrmServiceClient.shared.voiceRooms(token: self.token) } }
    func leaveVoice(_ room: WyrmVoiceRoom) async { await perform { try await WyrmServiceClient.shared.leaveVoice(roomID: room.id, token: self.token); self.voiceRooms = try await WyrmServiceClient.shared.voiceRooms(token: self.token) } }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        guard !token.isEmpty else { return }
        errorMessage = ""
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }
}
