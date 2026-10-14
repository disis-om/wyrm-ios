import Foundation

/// Arena chat tabs (OM, 2026-10-14). The arena's chat window (engine,
/// `android_team.c`) has TEAM, GLOBAL and ONLINE tabs. While a match is on
/// screen this hands it Wyrm's global chat every 4 s and the players online
/// every 16 s; nothing is asked outside a match. The message box on the GLOBAL
/// tab writes to everyone. Android twin: WyrmOverlay.startArenaFeed.
@MainActor
final class WyrmArenaFeed {
    static let shared = WyrmArenaFeed()

    private var screen = 0
    private var task: Task<Void, Never>?
    private var seenIDs = Set<String>()
    private var total = 0

    /// The engine changed screen (WyrmShellStore): 2 is a match.
    func engineScreen(_ next: Int) {
        screen = next
        guard next == 2, task == nil else { return }
        task = Task { [weak self] in
            var tick = 0
            while let self, self.screen == 2, !Task.isCancelled {
                let token = WyrmPresence.shared.token
                if !token.isEmpty {
                    await self.pushGlobal(token: token)
                    if tick % 4 == 0 { await self.pushOnline(token: token) }
                }
                tick += 1
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            self?.task = nil
        }
    }

    /// The window's tab where the message box was tapped: 1 = everyone.
    var globalTab: Bool { WyrmIOSChatTab() == 1 }

    /// Sends from the GLOBAL tab; the window shows it on the next push.
    func sendGlobal(_ body: String) {
        let token = WyrmPresence.shared.token
        let text = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        guard !token.isEmpty, !text.isEmpty else { return }
        Task {
            do {
                try await WyrmArenaFeedAPI.sendGlobal(body: text, token: token)
                await pushGlobal(token: token)
            } catch {}
        }
    }

    /// In-game name first, else the username, else the account name.
    private static func name(_ ingame: String, _ username: String, _ display: String) -> String {
        if !ingame.isEmpty { return ingame }
        if !username.isEmpty { return username }
        return display.isEmpty ? "Player" : display
    }

    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func pushGlobal(token: String) async {
        guard let items = try? await WyrmArenaFeedAPI.globalMessages(token: token) else { return }
        let shown = items.sorted { $0.createdAt < $1.createdAt }.suffix(80)
        for item in shown where seenIDs.insert(item.id).inserted { total += 1 }
        var packed = String(max(total, shown.count))
        for item in shown {
            packed += "\n" + Self.oneLine(Self.name(item.authorIngame, item.authorUsername, item.authorName))
            packed += "\t" + Self.oneLine(item.body)
        }
        packed.withCString { WyrmIOSSetGlobalChat($0) }
    }

    private func pushOnline(token: String) async {
        guard let players = try? await WyrmArenaFeedAPI.onlinePlayers(token: token) else { return }
        let lines = players.prefix(120).map { player -> String in
            let handle = player.username.isEmpty ? player.displayName : "@" + player.username
            let server = player.arena.isEmpty ? "Not in an arena" : WyrmPresence.shared.arenaName(player.arena)
            return Self.oneLine(Self.name(player.ingameName, player.username, player.displayName)) + "\t"
                + Self.oneLine("\(handle) · \(server)")
        }
        lines.joined(separator: "\n").withCString { WyrmIOSSetOnlinePlayers($0) }
    }
}
