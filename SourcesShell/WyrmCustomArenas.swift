import Foundation
import Security

/// Custom arenas (OM, 2026-10-13; reworked 2026-10-24). Android twin:
/// `data/CustomArenas.kt`, same meaning.
///
/// Community-run arenas know a player by a 16-character id ([0-9A-Za-z]) that
/// NTL sends right after the challenge answer: 'C' + the id. The engine sends
/// it to every arena (network/callback.c, `WyrmIOSSetCustomArenas`), as NTL's
/// `!idforce` does: NTL 9.76 has no online list any more, so the old list
/// from `useplayerid.php` was always empty and the id never went out.
///
/// The id belongs to this phone (OM, 2026-10-24): made once (crypto random,
/// NTL's alphabet, bytes >= 248 thrown away) under `idKey`, kept through
/// restarts, updates, log out and log in (`wyrm.ios.custom-arena` is kept by
/// WyrmAccountSync), and gone only when the app is deleted (UserDefaults, not
/// the Keychain). It is not in the account any more. The account-era key and
/// the old list cache are dropped once, so every phone makes a fresh id with
/// this update and keeps it.
final class WyrmCustomArenas {
    static let shared = WyrmCustomArenas()
    static let idKey = "wyrm.ios.custom-arena.device-id"
    /// 2026-10-13 to 2026-10-23: the account's id and NTL's list cache.
    private static let oldKeys = ["wyrm.ios.custom-arena.id", "wyrm.ios.custom-arena-list.lines",
                                  "wyrm.ios.custom-arena-list.version", "wyrm.ios.custom-arena-list.checked"]
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    private init() {}

    static func isValid(_ id: String) -> Bool {
        id.count == 16 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// This phone's id, made the first time it is asked for and kept for good.
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
        Self.oldKeys.forEach { d.removeObject(forKey: $0) }
        return made
    }

    /// Launch (WyrmShellHost): hand the engine the id.
    func start() {
        publish()
    }

    /// The id reaches the engine (also after a log in or log out).
    func publish() {
        WyrmIOSSetCustomArenas(id, "")
    }

    func reloadFromDefaults() { publish() }
}
