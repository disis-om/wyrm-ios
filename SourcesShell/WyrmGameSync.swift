import Foundation

/*
 * Everything a match reports to Wyrm's backend, ported from Android's
 * WyrmOverlay run outbox and arena-skin side channel.
 *
 * The engine thread only drops facts into HomeMailbox.inc; this class drains
 * them on the main thread and does all network I/O off it. Nothing here goes
 * into a Slither packet or touches the arena socket.
 */
@MainActor
final class WyrmGameSync {
    static let shared = WyrmGameSync()
    static let profileChanged = Notification.Name("WyrmProfileChanged")
    static let achievementsEarned = Notification.Name("WyrmAchievementsEarned")

    private let base = "https://wyrm-api.77-245-76-86.sslip.io"
    private let session: URLSession
    private var token = ""
    private var playerID = ""
    private var timer: Timer?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration)
    }

    /// Engine facts are drained from launch, signed in or not, so a run is
    /// never lost from the local totals; uploads wait for an account.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func activate(token: String, playerID: String) {
        guard !token.isEmpty, !playerID.isEmpty else { return }
        let changed = playerID != self.playerID
        self.token = token
        self.playerID = playerID
        if changed { reconcileTask?.cancel(); reconcileTask = nil }
        flushRuns()
        startReconciliation()
    }

    func deactivate() {
        if let generation = skinGeneration { clearArenaSkin(generation) }
        skinGeneration = nil
        resetSkinCache()
        reconcileTask?.cancel()
        reconcileTask = nil
        token = ""
        playerID = ""
    }

    private func tick() {
        drainRuns()
        pollArenaIdentity()
        pollVisibleSkins()
    }

    // MARK: - Finished runs

    private struct PendingRun: Codable { let eventId: String; let playerId: String; let score: Int; let kills: Int }
    private static let outboxKey = "wyrm.ios.runs.pending"
    private var uploading = false
    private var reconcileTask: Task<Void, Never>?

    private func drainRuns() {
        let text = copiedString(WyrmIOSDrainFinishedRuns())
        guard !text.isEmpty else { return }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let score = Int(parts[0]), let kills = Int(parts[1]) else { continue }
            recordLocally(score: score, kills: kills)
            WyrmDiagnostics.record("run finished score=\(score) kills=\(kills) account=\(playerID.isEmpty ? "none" : "signed-in")", category: "STATS")
            guard !playerID.isEmpty else { continue }
            var outbox = pendingRuns()
            outbox.append(PendingRun(eventId: UUID().uuidString.lowercased(), playerId: playerID, score: score, kills: kills))
            savePendingRuns(Array(outbox.suffix(200)))
        }
        flushRuns()
    }

    /// Android's device totals: best score ever, kills added up. Kept per
    /// account here so a second player on this phone never inherits them.
    private func recordLocally(score: Int, kills: Int) {
        let key = playerID.isEmpty ? "guest" : playerID
        let defaults = UserDefaults.standard
        let best = max(defaults.integer(forKey: "wyrm.ios.stats.\(key).best"), score)
        let total = defaults.integer(forKey: "wyrm.ios.stats.\(key).kills") + max(0, kills)
        defaults.set(best, forKey: "wyrm.ios.stats.\(key).best")
        defaults.set(total, forKey: "wyrm.ios.stats.\(key).kills")
    }

    private func pendingRuns() -> [PendingRun] {
        guard let data = UserDefaults.standard.data(forKey: Self.outboxKey) else { return [] }
        return (try? JSONDecoder().decode([PendingRun].self, from: data)) ?? []
    }

    private func savePendingRuns(_ runs: [PendingRun]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(runs), forKey: Self.outboxKey)
    }

    /// Drains this account's receipts in order; the event id makes a retry of
    /// an already-counted run harmless on the server. Another account's
    /// receipts stay put until that account signs in again.
    private func flushRuns() {
        guard !uploading, !token.isEmpty else { return }
        let owner = playerID
        guard pendingRuns().contains(where: { $0.playerId == owner }) else { return }
        uploading = true
        Task {
            defer { uploading = false }
            var failures = 0
            var earned = false
            while owner == playerID, let run = pendingRuns().first(where: { $0.playerId == owner }) {
                do {
                    let response = try await call("/v1/me/stats", method: "POST",
                                                  body: ["eventId": run.eventId, "score": run.score, "kills": run.kills])
                    savePendingRuns(pendingRuns().filter { $0.eventId != run.eventId })
                    failures = 0
                    if let achievements = response["achievements"] as? [Any], !achievements.isEmpty { earned = true }
                    WyrmDiagnostics.record("run receipt accepted score=\(run.score) kills=\(run.kills)", category: "STATS")
                } catch WyrmSyncError.rejected(let status) where status == 400 {
                    // A receipt the server can never accept must not block the rest.
                    savePendingRuns(pendingRuns().filter { $0.eventId != run.eventId })
                } catch WyrmSyncError.rejected(let status) where status == 401 {
                    break
                } catch {
                    failures += 1
                    if failures >= 3 { break }
                    try? await Task.sleep(nanoseconds: UInt64(5_000_000_000 * failures))
                }
            }
            NotificationCenter.default.post(name: Self.profileChanged, object: nil)
            if earned { NotificationCenter.default.post(name: Self.achievementsEarned, object: nil) }
        }
    }

    /// Five-hour repair pass from local totals; it never lowers server data.
    private func startReconciliation() {
        guard reconcileTask == nil else { return }
        let owner = playerID
        reconcileTask = Task {
            while !Task.isCancelled, owner == playerID, !token.isEmpty {
                let key = "wyrm.ios.stats.\(owner).reconciled"
                let last = UserDefaults.standard.double(forKey: key)
                let remaining = 5 * 3600 - (Date().timeIntervalSince1970 - last)
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                guard !Task.isCancelled, owner == playerID else { return }
                let best = UserDefaults.standard.integer(forKey: "wyrm.ios.stats.\(owner).best")
                let kills = UserDefaults.standard.integer(forKey: "wyrm.ios.stats.\(owner).kills")
                do {
                    _ = try await call("/v1/me/stats/reconcile", method: "POST",
                                       body: ["highestScore": min(best, 10_000_000), "kills": min(kills, 10_000_000)])
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
                    NotificationCenter.default.post(name: Self.profileChanged, object: nil)
                } catch {
                    try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                }
            }
        }
    }

    // MARK: - In-game name

    /// Android's syncIngameName: the arena name follows the account when it is
    /// a valid IGN; anything else stays local to the engine.
    func syncIngameName(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty, name.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil else { return }
        Task {
            if (try? await call("/v1/me", method: "PATCH", body: ["ingameName": name])) != nil {
                NotificationCenter.default.post(name: Self.profileChanged, object: nil)
            }
        }
    }

    // MARK: - Arena skins

    private var identitySequence = ""
    private var skinArena = ""
    private var skinGeneration: String?
    private var heartbeat: Task<Void, Never>?
    private var visibleSequence = ""
    private var pending: [Int] = []
    private var inFlight = Set<Int>()
    private var resolvedAt: [Int: Date] = [:]
    private var retryAt: [Int: Date] = [:]
    private var attempts: [Int: Int] = [:]

    private func resetSkinCache() {
        pending.removeAll(); inFlight.removeAll(); resolvedAt.removeAll(); retryAt.removeAll(); attempts.removeAll()
        heartbeat?.cancel(); heartbeat = nil
        WyrmIOSArenaSkinsClear()
    }

    private func pollArenaIdentity() {
        let fields = copiedString(WyrmIOSArenaIdentitySnapshot()).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 4, fields[0] != identitySequence else { return }
        identitySequence = fields[0]
        let arena = fields[1], snakeID = Int(fields[2]) ?? -1, nickname = fields[3]
        let code = fields.count > 4 ? fields[4] : ""
        let colours = fields.count > 5 ? fields[5] : ""
        let previous = skinGeneration
        guard snakeID >= 0, !arena.isEmpty else {
            skinArena = ""
            skinGeneration = nil
            resetSkinCache()
            if let previous { clearArenaSkin(previous) }
            return
        }
        // A new arena or a new life: nothing learned in the last one applies.
        let generation = UUID().uuidString.lowercased()
        skinArena = arena
        skinGeneration = generation
        resetSkinCache()
        let exact = !code.isEmpty && colours.count == code.count * 8 && colours.contains(where: { $0 != "0" })
        guard exact, !token.isEmpty else {
            if let previous { clearArenaSkin(previous) }
            return
        }
        let body: [String: Any] = ["arena": arena, "snakeId": snakeID, "nickname": String(nickname.prefix(24)),
                                   "code": code, "colours": colours, "generation": generation]
        heartbeat = Task {
            if let previous { _ = try? await call("/v1/arena/skin", method: "DELETE", body: ["generation": previous]) }
            var attempt = 0
            while !Task.isCancelled, skinGeneration == generation {
                do {
                    _ = try await call("/v1/arena/skin", method: "POST", body: body)
                    attempt = 0
                    // The backend keeps a row for two minutes; a longer life
                    // republishes the same generation so late arrivals still see it.
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                } catch WyrmSyncError.rejected(let status) where status == 409 || status == 400 {
                    return
                } catch {
                    attempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(min(10_000, 250 << min(attempt, 5))) * 1_000_000)
                }
            }
        }
    }

    /// Captures the bearer now: on sign-out this runs just before it is dropped.
    private func clearArenaSkin(_ generation: String) {
        let bearer = token
        guard !bearer.isEmpty else { return }
        Task { _ = try? await call("/v1/arena/skin", method: "DELETE", body: ["generation": generation], bearer: bearer) }
    }

    private func pollVisibleSkins() {
        let fields = copiedString(WyrmIOSArenaVisibleSnapshot()).split(separator: "\t").map(String.init)
        guard fields.count == 2, fields[0] != visibleSequence else { return }
        visibleSequence = fields[0]
        guard let generation = skinGeneration, !skinArena.isEmpty, !token.isEmpty else { return }
        let now = Date()
        for id in fields[1].split(separator: ",").compactMap({ Int($0) }) where id >= 0 {
            if let at = resolvedAt[id], now.timeIntervalSince(at) < 30 { continue }
            resolvedAt[id] = nil
            if !inFlight.contains(id), (retryAt[id] ?? .distantPast) <= now, !pending.contains(id) { pending.append(id) }
        }
        let wanted = Array(pending.prefix(64))
        guard !wanted.isEmpty else { return }
        pending.removeFirst(wanted.count)
        inFlight.formUnion(wanted)
        let arena = skinArena
        Task {
            let result = try? await call("/v1/arena/skins", method: "POST", body: ["arena": arena, "snakeIds": wanted])
            guard skinGeneration == generation else { return }
            inFlight.subtract(wanted)
            guard let result else {
                for id in wanted {
                    let count = (attempts[id] ?? 0) + 1
                    attempts[id] = count
                    retryAt[id] = Date().addingTimeInterval(Double(min(10_000, 250 << min(count, 5))) / 1000)
                }
                return
            }
            let stamp = Date()
            for id in wanted { resolvedAt[id] = stamp; retryAt[id] = nil; attempts[id] = nil }
            for row in (result["skins"] as? [[String: Any]]) ?? [] {
                guard let id = (row["snakeId"] as? NSNumber)?.intValue, let hex = row["colours"] as? String else { continue }
                let colours: [UInt32] = stride(from: 0, to: hex.count - hex.count % 8, by: 8).compactMap { offset in
                    let start = hex.index(hex.startIndex, offsetBy: offset)
                    return UInt32(hex[start..<hex.index(start, offsetBy: 8)], radix: 16)
                }
                let nickname = row["nickname"] as? String ?? ""
                nickname.withCString { name in
                    colours.withUnsafeBufferPointer { WyrmIOSArenaSkinSet(Int32(id), name, $0.baseAddress, Int32($0.count)) }
                }
            }
        }
    }

    // MARK: - Transport

    enum WyrmSyncError: Error { case rejected(Int), transport }

    private func call(_ path: String, method: String, body: [String: Any], bearer: String? = nil) async throws -> [String: Any] {
        let token = bearer ?? self.token
        guard !token.isEmpty, let url = URL(string: base + path) else { throw WyrmSyncError.transport }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch {
            WyrmDiagnostics.record("\(method) \(path) transport failure", category: "STATS")
            throw WyrmSyncError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        WyrmDiagnostics.record("\(method) \(path) status=\(status)", category: "STATS")
        guard 200..<300 ~= status else { throw WyrmSyncError.rejected(status) }
        guard !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func copiedString(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        return String(cString: pointer)
    }
}
