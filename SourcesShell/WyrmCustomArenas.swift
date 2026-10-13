import Foundation
import Security
import UIKit

/// Custom arenas (OM, 2026-10-13). Android twin: `data/CustomArenas.kt`, same
/// meaning.
///
/// Community-run arenas know a player by a 16-character id ([0-9A-Za-z]) that
/// NTL sends right after the challenge answer: 'C' + the id, only to the
/// arenas on NTL's list (`ntl-slither.com/slither/useplayerid.php?v=<n>`
/// answers `{"v":n,"d":["ip:port",...]}`; official arenas are not on it).
/// The engine sends it (network/callback.c, `WyrmIOSSetCustomArenas`).
///
/// - The id is made once (crypto random, NTL's alphabet, bytes >= 248 thrown
///   away) and follows the account: `wyrm.ios.custom-arena.id` (sync) and the
///   shared document key `customArenaId`, the same on every platform.
/// - The list is this phone's cache (`wyrm.ios.custom-arena-list.*`, keep),
///   asked for again at most every 6 hours, as NTL does.
final class WyrmCustomArenas {
    static let shared = WyrmCustomArenas()
    static let idKey = "wyrm.ios.custom-arena.id"
    private static let linesKey = "wyrm.ios.custom-arena-list.lines"
    private static let versionKey = "wyrm.ios.custom-arena-list.version"
    private static let checkedKey = "wyrm.ios.custom-arena-list.checked"
    private static let listURL = "https://ntl-slither.com/slither/useplayerid.php"
    private static let every: TimeInterval = 6 * 3600
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    private var fetching = false
    private var observer: NSObjectProtocol?

    private init() {}

    static func isValid(_ id: String) -> Bool {
        id.count == 16 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// The player's id, made the first time it is asked for.
    var id: String {
        let d = UserDefaults.standard
        if let saved = d.string(forKey: Self.idKey), Self.isValid(saved) { return saved }
        var made = ""
        var bytes = [UInt8](repeating: 0, count: 16)
        while made.count < 16 {
            if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
                bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
            }
            for byte in bytes where byte < 248 && made.count < 16 {
                made.append(Self.alphabet[Int(byte) % 62])
            }
        }
        d.set(made, forKey: Self.idKey)
        return made
    }

    /// The account's id (shared document `customArenaId`); anything else is skipped.
    func adopt(_ value: Any?) {
        guard let text = value as? String, Self.isValid(text) else { return }
        UserDefaults.standard.set(text, forKey: Self.idKey)
    }

    /// Launch (WyrmShellHost): hand the engine what is saved, then ask for a
    /// newer list, and again whenever the app comes back.
    func start() {
        publish()
        refresh()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
    }

    /// The id and the list reach the engine (also after a log in or log out).
    func publish() {
        WyrmIOSSetCustomArenas(id, UserDefaults.standard.string(forKey: Self.linesKey) ?? "")
    }

    func reloadFromDefaults() { publish() }

    /// NTL's list, at most every 6 hours; a newer version replaces the cache.
    func refresh(force: Bool = false) {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        guard !fetching, force || now - d.double(forKey: Self.checkedKey) >= Self.every else { return }
        var components = URLComponents(string: Self.listURL)!
        let version = d.integer(forKey: Self.versionKey)
        components.queryItems = [URLQueryItem(name: "v", value: String(version))]
        guard let url = components.url else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        // The service answers pages from the game's own site only.
        request.setValue("https://slither.io", forHTTPHeaderField: "Origin")
        request.setValue("https://slither.io/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        fetching = true
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                self.fetching = false
                guard ok, let json else { return }
                d.set(now, forKey: Self.checkedKey)
                guard let newer = (json["v"] as? NSNumber)?.intValue, newer > version,
                      let list = json["d"] as? [Any] else { return }
                let lines = list.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.contains("\n") }
                d.set(newer, forKey: Self.versionKey)
                d.set(lines.joined(separator: "\n"), forKey: Self.linesKey)
                WyrmDiagnostics.record("Custom arena list v\(newer): \(lines.count) arenas", category: "NETWORK")
                self.publish()
            }
        }.resume()
    }
}
