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
    /// The NTL key this player plays under (NTL's "key owner").
    var owner: String = ""
    /// From the player's own NTL status line, when their client sends one.
    var fps: Int? = nil
    var ping: Int? = nil

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
    var at = Date()
}

/// One saved NTL Team. Several can be kept; only the selected one runs.
struct WyrmSavedTeam: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var auth: String
    var teamID: String
}

private struct WyrmSavedTeams: Codable {
    var selected: String?
    var teams: [WyrmSavedTeam]
}

private struct WyrmTeamCredentials: Codable {
    let auth: String
    let teamID: String
}

private enum WyrmTeamKeychain {
    private static let service = "com.omrajput.wyrmios.ntl-team"
    private static let account = "credentials"
    private static let listAccount = "teams"

    private static func data(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    /// Every saved team. A phone that saved one team before this list existed
    /// has it moved in, selected, the first time this runs.
    static func readAll() -> WyrmSavedTeams {
        if let data = data(listAccount), let list = try? JSONDecoder().decode(WyrmSavedTeams.self, from: data) {
            return list
        }
        if let data = data(account), let old = try? JSONDecoder().decode(WyrmTeamCredentials.self, from: data) {
            let team = WyrmSavedTeam(id: UUID().uuidString, name: "Team", auth: old.auth, teamID: old.teamID)
            let list = WyrmSavedTeams(selected: team.id, teams: [team])
            if (try? writeAll(list)) != nil { delete(account) }
            return list
        }
        return WyrmSavedTeams(selected: nil, teams: [])
    }

    static func writeAll(_ value: WyrmSavedTeams) throws {
        delete(listAccount)
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: listAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw NSError(domain: "WyrmTeam", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not secure Team credentials."])
        }
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
    /// Saved teams (names and ids only reach the UI; keys stay in here).
    @Published private(set) var saved: [WyrmSavedTeam] = []
    @Published private(set) var selectedTeam: String?
    /// Which saved team the Connect page edits; nil adds a new one.
    @Published var connectEditing: String?

    var selected: WyrmSavedTeam? { saved.first { $0.id == selectedTeam } }

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
        let list = WyrmTeamKeychain.readAll()
        saved = list.teams
        selectedTeam = list.selected
        guard let team = selected else { state = .disconnected; teamID = ""; return }
        run(team)
    }

    /// Saves a team (a new one, or [editing] replaced) and runs it.
    func connect(auth: String, teamID: String, name: String = "", editing: String? = nil) throws {
        let auth = auth.trimmingCharacters(in: .whitespacesAndNewlines)
        let teamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard auth.count >= 16, teamID.count >= 16 else {
            throw NSError(domain: "WyrmTeam", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "NTL Auth and Team ID must each be at least 16 characters."])
        }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var teams = saved
        let team: WyrmSavedTeam
        if let editing, let index = teams.firstIndex(where: { $0.id == editing }) {
            teams[index].auth = auth
            teams[index].teamID = teamID
            if !label.isEmpty { teams[index].name = label }
            team = teams[index]
        } else {
            team = WyrmSavedTeam(id: UUID().uuidString, name: label.isEmpty ? "Team \(teams.count + 1)" : label,
                                 auth: auth, teamID: teamID)
            teams.append(team)
        }
        try WyrmTeamKeychain.writeAll(WyrmSavedTeams(selected: team.id, teams: teams))
        saved = teams
        selectedTeam = team.id
        run(team)
    }

    /// Runs a saved team instead of the current one.
    func select(_ id: String) {
        guard let team = saved.first(where: { $0.id == id }) else { return }
        try? WyrmTeamKeychain.writeAll(WyrmSavedTeams(selected: id, teams: saved))
        selectedTeam = id
        run(team)
    }

    /// Stops the running team. It stays saved, ready to pick again.
    func disconnect() {
        stop()
        selectedTeam = nil
        try? WyrmTeamKeychain.writeAll(WyrmSavedTeams(selected: nil, teams: saved))
        WyrmDiagnostics.record("NTL Team disconnected", category: "TEAM")
    }

    /// Forgets a saved team, and stops it if it was running.
    func remove(_ id: String) {
        if id == selectedTeam { stop(); selectedTeam = nil }
        saved.removeAll { $0.id == id }
        try? WyrmTeamKeychain.writeAll(WyrmSavedTeams(selected: selectedTeam, teams: saved))
    }

    private func run(_ team: WyrmSavedTeam) {
        stop()
        credentials = WyrmTeamCredentials(auth: team.auth, teamID: team.teamID)
        teamID = team.teamID
        state = .connecting
        beginLoop()
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        credentials = nil
        teamID = ""
        members = []
        chat = []
        seenMessages = []
        state = .disconnected
        "".withCString { WyrmIOSSetTeamMembers($0) }
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
            // Eight characters, then the name: the service keeps only what
            // follows the first eight (NTL sends a random id there). Sent bare,
            // a name lost its first eight letters. Same prefix as Android.
            URLQueryItem(name: "nick", value: "WYRMPLYR" + presence.nickname),
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
            // Accessories reach the arena in the join packet only, never NTL.
            // -1 is "no cosmetic". Was: presence.cosmetic
            URLQueryItem(name: "cs", value: "-1"),
            // NTL tags are off (they got snakes dropped); -1 is "no tag".
            URLQueryItem(name: "tg", value: "-1"),
            // Wyrm's own version, the same one Android reports. Was: 9.68
            URLQueryItem(name: "ver", value: "1.5.1"),
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
        let status = decodeEntities(string(row["dt"]).removingPercentEncoding ?? string(row["dt"]))
        return WyrmTeamMember(id: "\(sid):\(nick)", name: displayName(nick),
                              score: integer(row["score"]), x: integer(row["valx"]),
                              y: integer(row["valy"]), bot: boolean(row["bot"]),
                              arena: string(row["srv"]), rank: integer(row["rank"]),
                              snakeID: sid, tag: integer(row["tg"], fallback: -1),
                              owner: decodeEntities(string(row["owner"])),
                              fps: firstNumber(in: status, pattern: #"FPS:\s*(\d+)"#),
                              ping: firstNumber(in: status, pattern: #"@\s*(\d+)\s*(?:\(\d+\))?\s*ms"#))
    }

    private static func firstNumber(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    /// NTL writes chat and names as HTML: a space arrives as `&nbsp;` (or
    /// `&nbsp` with no semicolon), and & < > " ' as their entities.
    /// Names and messages can arrive escaped twice (`&amp;nbsp;`), so a second
    /// pass runs when the first still leaves an entity, as on Android.
    static func decodeEntities(_ text: String) -> String {
        let once = decodeEntitiesOnce(text)
        return once.range(of: "&[a-zA-Z]{2,8};?|&#[0-9]{2,6};", options: .regularExpression) == nil
            ? once : decodeEntitiesOnce(once)
    }

    private static func decodeEntitiesOnce(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, value) in [("&nbsp;", " "), ("&nbsp", " "), ("&lt;", "<"), ("&gt;", ">"),
                                ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"), ("&apos;", "'")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(\\d{1,6});") {
            for match in regex.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(match.range, in: out), let digits = Range(match.range(at: 1), in: out),
                      let code = UInt32(out[digits]), let scalar = Unicode.Scalar(code) else { continue }
                out.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    private func ingestChat(_ rows: [[String: Any]]) {
        for row in rows {
            let nick = Self.string(row["nick"])
            // NTL's own notices come from the all-zero nick.
            let author = nick == "00000000" ? "NTL" : Self.displayName(nick)
            let raw = Self.string(row["msg"])
            for line in raw.replacingOccurrences(of: "<br>", with: "\n")
                .split(separator: "\n").map(String.init) {
                let body = Self.decodeEntities(line).trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { continue }
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
    /// NTL puts an 8-character id in front of every nick and always shows the
    /// rest (`nick.slice(8)`), whatever those 8 characters are.
    /// The id is taken only when it looks like one (as Android does): eight
    /// letters or digits with a name after them. The old hex-only test left
    /// NTL's ids, which use every letter, showing as a code before the name.
    private static func displayName(_ nick: String) -> String {
        let id = nick.prefix(8)
        let rest = nick.dropFirst(8)
        let hasID = nick.count > 8 && id.allSatisfy { $0.isLetter || $0.isNumber }
            && !rest.trimmingCharacters(in: .whitespaces).isEmpty
        let name = decodeEntities(hasID ? String(rest) : nick).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Teammate" : name
    }
}
