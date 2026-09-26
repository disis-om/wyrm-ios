import Foundation
import Security

struct WyrmTeamMember: Identifiable, Equatable {
    let id: String
    let name: String
    let score: Int
    let x: Int
    let y: Int
    let bot: Bool
    let arena: String
    let rank: Int
    let snakeID: Int
    let tag: Int

    func packed(relativeTo currentArena: String) -> String {
        let safeName = name.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let present = arena == currentArena && arena != "_GAME_MENU_" && snakeID > 0
        return [safeName, "\(x)", "\(y)", "\(score)", "\(rank)", bot ? "1" : "0",
                present ? "1" : "0", "\(snakeID)", "\(tag)"].joined(separator: "\t")
    }
}

struct WyrmTeamChatLine: Identifiable, Equatable {
    let id: String
    let author: String
    let body: String
}

private struct WyrmTeamCredentials: Codable {
    let auth: String
    let teamID: String
}

private enum WyrmTeamKeychain {
    private static let service = "com.omrajput.wyrmios.ntl-team"
    private static let account = "credentials"

    static func read() -> WyrmTeamCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WyrmTeamCredentials.self, from: data)
    }

    static func write(_ value: WyrmTeamCredentials) throws {
        clear()
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw NSError(domain: "WyrmTeam", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not secure Team credentials."])
        }
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

private struct WyrmTeamPresence {
    let nickname: String
    let score: Int
    let x: Int
    let y: Int
    let bot: Bool
    let arena: String
    let rank: Int
    let snakeID: Int
    let tag: Int
    let cosmetic: Int

    static func current() -> WyrmTeamPresence? {
        guard let pointer = WyrmIOSTeamPresenceSnapshot() else { return nil }
        let fields = String(cString: pointer)
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 10, !fields[0].isEmpty else { return nil }
        return WyrmTeamPresence(nickname: fields[0], score: Int(fields[1]) ?? 0,
                                x: Int(fields[2]) ?? 0, y: Int(fields[3]) ?? 0,
                                bot: fields[4] == "1", arena: fields[5],
                                rank: Int(fields[6]) ?? 0, snakeID: Int(fields[7]) ?? 0,
                                tag: Int(fields[8]) ?? -1, cosmetic: Int(fields[9]) ?? -1)
    }
}

@MainActor
final class WyrmTeamStore: ObservableObject {
    enum State: Equatable { case disconnected, connecting, connected, failed(String) }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var members: [WyrmTeamMember] = []
    @Published private(set) var chat: [WyrmTeamChatLine] = []
    @Published private(set) var teamID = ""
    @Published private(set) var lastUpdated: Date?

    private var credentials: WyrmTeamCredentials?
    private var loop: Task<Void, Never>?
    private var queuedMessage = ""
    private var seenMessages = Set<String>()
    private let endpoint = URL(string: "https://ntl-slither.com/slither/ntlplay-mt.php")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    deinit { loop?.cancel() }

    func start() {
        guard loop == nil else { return }
        credentials = WyrmTeamKeychain.read()
        teamID = credentials?.teamID ?? ""
        guard credentials != nil else { state = .disconnected; return }
        state = .connecting
        beginLoop()
    }

    func connect(auth: String, teamID: String) throws {
        let auth = auth.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard auth.count >= 16, teamID.count >= 16 else {
            throw NSError(domain: "WyrmTeam", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "NTL Auth and Team ID must each be at least 16 characters."])
        }
        let saved = WyrmTeamCredentials(auth: auth, teamID: teamID)
        try WyrmTeamKeychain.write(saved)
        credentials = saved
        self.teamID = teamID
        state = .connecting
        loop?.cancel()
        loop = nil
        beginLoop()
    }

    func disconnect() {
        loop?.cancel()
        loop = nil
        credentials = nil
        WyrmTeamKeychain.clear()
        teamID = ""
        members = []
        chat = []
        state = .disconnected
        "".withCString { WyrmIOSSetTeamMembers($0) }
        WyrmDiagnostics.record("NTL Team disconnected", category: "TEAM")
    }

    func send(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 280 else { return }
        queuedMessage = value
        Task { await poll() }
    }

    private func beginLoop() {
        guard credentials != nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func poll() async {
        guard let credentials, let presence = WyrmTeamPresence.current() else { return }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "auth", value: credentials.auth),
            URLQueryItem(name: "tid", value: credentials.teamID),
            URLQueryItem(name: "nick", value: presence.nickname),
            URLQueryItem(name: "score", value: "\(presence.score)"),
            URLQueryItem(name: "valx", value: "\(presence.x)"),
            URLQueryItem(name: "valy", value: "\(presence.y)"),
            URLQueryItem(name: "bot", value: presence.bot ? "true" : "false"),
            URLQueryItem(name: "sos", value: "false"),
            URLQueryItem(name: "food", value: "false"),
            URLQueryItem(name: "srv", value: presence.arena),
            URLQueryItem(name: "sid", value: "\(presence.snakeID)"),
            URLQueryItem(name: "msg", value: queuedMessage),
            URLQueryItem(name: "rank", value: "\(presence.rank)"),
            URLQueryItem(name: "an", value: "false"),
            URLQueryItem(name: "dt", value: "Wyrm iOS"),
            URLQueryItem(name: "cs", value: "\(presence.cosmetic)"),
            // NTL tags are off (they got snakes dropped); -1 is "no tag".
            URLQueryItem(name: "tg", value: "-1"),
            URLQueryItem(name: "ver", value: "9.68"),
            URLQueryItem(name: "tlm", value: ""),
            URLQueryItem(name: "di", value: "0"),
            URLQueryItem(name: "tar", value: ""),
        ]
        guard let url = components.url else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let object = try JSONSerialization.jsonObject(with: data)
            guard let rows = object as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
            let decoded = rows.compactMap(Self.member)
            let packed = decoded.map { $0.packed(relativeTo: presence.arena) }.joined(separator: "\n")
            packed.withCString { WyrmIOSSetTeamMembers($0) }
            members = decoded
            ingestChat(rows)
            queuedMessage = ""
            lastUpdated = Date()
            state = .connected
            WyrmDiagnostics.record("NTL Team poll accepted members=\(decoded.count)", category: "TEAM")
        } catch {
            state = .failed("Could not reach NTL Team")
            WyrmDiagnostics.record("NTL Team poll failed type=\(String(describing: type(of: error)))", category: "TEAM")
        }
    }

    private static func member(_ row: [String: Any]) -> WyrmTeamMember? {
        let nick = string(row["nick"])
        guard !nick.isEmpty, nick != "00000000" else { return nil }
        let sid = integer(row["sid"])
        return WyrmTeamMember(id: "\(sid):\(nick)", name: displayName(nick),
                              score: integer(row["score"]), x: integer(row["valx"]),
                              y: integer(row["valy"]), bot: boolean(row["bot"]),
                              arena: string(row["srv"]), rank: integer(row["rank"]),
                              snakeID: sid, tag: integer(row["tg"], fallback: -1))
    }

    private func ingestChat(_ rows: [[String: Any]]) {
        for row in rows {
            let author = Self.displayName(Self.string(row["nick"]))
            let raw = Self.string(row["msg"])
            for body in raw.replacingOccurrences(of: "<br>", with: "\n")
                .split(separator: "\n").map(String.init) where !body.isEmpty {
                let key = "\(author)\u{1f}\(body)"
                guard seenMessages.insert(key).inserted else { continue }
                chat.append(WyrmTeamChatLine(id: key, author: author, body: body))
            }
        }
        if chat.count > 200 { chat.removeFirst(chat.count - 200) }
    }

    private static func string(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
    private static func integer(_ value: Any?, fallback: Int = 0) -> Int {
        Int(string(value)) ?? fallback
    }
    private static func boolean(_ value: Any?) -> Bool {
        let value = string(value).lowercased()
        return value == "true" || value == "1"
    }
    private static func displayName(_ nick: String) -> String {
        guard nick.count > 8 else { return nick }
        let prefix = nick.prefix(8)
        guard prefix.allSatisfy({ $0.isHexDigit }) else { return nick }
        return String(nick.dropFirst(8))
    }
}
