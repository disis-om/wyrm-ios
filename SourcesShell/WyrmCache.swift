import Foundation

/*
 * The last good answer for a screen, on disk (OM, 2026-09-29).
 *
 * Stale-while-revalidate: a screen paints what it showed last time at once,
 * asks the server in the background, and swaps the answer in place. Lists keep
 * their ids, so rows that did not change do not move, and a skeleton is only
 * ever seen on the very first open.
 *
 * Everything is kept per account (`owner`, the signed-in player id): a feed
 * carries "liked" and "mine" for the viewer, so one account's cache must never
 * paint another's screen. Signing out deletes the whole folder. Files live in
 * Caches, which iOS may clear when space is short; that only costs one
 * skeleton.
 */
enum WyrmCache {
    private static let lock = NSLock()
    private static var currentOwner = ""
    private static let queue = DispatchQueue(label: "com.omrajput.wyrm.cache", qos: .utility)

    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WyrmCache", isDirectory: true)
    }

    /// The signed-in player. Empty means nothing is read or written.
    static var owner: String {
        get { lock.lock(); defer { lock.unlock() }; return currentOwner }
        set { lock.lock(); currentOwner = newValue; lock.unlock() }
    }

    private static func file(_ key: String) -> URL? {
        let who = owner
        guard !who.isEmpty else { return nil }
        let safe = "\(who)-\(key)".map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return folder.appendingPathComponent(String(safe) + ".json")
    }

    /// Small files, read on the spot so the first frame already has them.
    static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let url = file(key), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ key: String, _ value: T) {
        guard let url = file(key), let data = try? JSONEncoder().encode(value) else { return }
        write(data, to: url)
    }

    /// For answers kept as plain JSON objects (`[String: Any]`).
    static func loadObject(_ key: String) -> [String: Any]? {
        guard let url = file(key), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func saveObject(_ key: String, _ object: [String: Any]) {
        guard let url = file(key), JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        write(data, to: url)
    }

    static func remove(_ key: String) {
        guard let url = file(key) else { return }
        queue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Sign-out: nothing of this account stays on the phone.
    static func clearAll() {
        owner = ""
        let target = folder
        queue.async { try? FileManager.default.removeItem(at: target) }
    }

    private static func write(_ data: Data, to url: URL) {
        let directory = folder
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
