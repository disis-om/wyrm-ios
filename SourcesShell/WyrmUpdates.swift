import SwiftUI

/*
 * New-build notices, with a stable and a beta channel like Android.
 *
 * iOS cannot install an IPA from inside an app, so this only tells the player
 * a newer build exists and opens its download; they sign and install it with
 * AltStore as always. Stable is update/latest.json in the Wyrm iOS repository,
 * beta is update/beta.json beside it (published only for test builds, marked
 * as pre-releases). With "Beta updates" on, both are read and the newer build
 * wins, so a stable build that overtakes the last beta is still offered.
 * Only a download from Wyrm iOS's own releases is ever opened.
 */
struct WyrmUpdateInfo: Equatable {
    let version: String
    let build: Int
    let url: URL
    let beta: Bool
}

@MainActor
final class WyrmUpdateStore: ObservableObject {
    static let shared = WyrmUpdateStore()
    static let betaKey = "wyrm.ios.updates.beta"

    @Published private(set) var available: WyrmUpdateInfo?
    @Published private(set) var checking = false
    @Published private(set) var failed = false

    private static let base = "https://raw.githubusercontent.com/disis-om/wyrm-ios/main/update/"
    private static let releasePrefix = "/disis-om/wyrm-ios/releases/download/"

    var betaEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.betaKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.betaKey)
            objectWillChange.send()
            Task { await check() }
        }
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let installed = Int(WyrmBuild.build) ?? 0
        var best: WyrmUpdateInfo?
        var anyRead = false
        for (file, beta) in [("latest.json", false)] + (betaEnabled ? [("beta.json", true)] : []) {
            let (info, reached) = await Self.fetch(file, beta: beta)
            // A missing manifest (404) only means nothing is published on that
            // channel yet: that is "up to date", not a failed check.
            if reached { anyRead = true }
            guard let info else { continue }
            if info.build > installed, info.build > (best?.build ?? 0) { best = info }
        }
        failed = !anyRead && best == nil
        available = best
        WyrmDiagnostics.record("update check beta=\(betaEnabled) newer=\(best.map { "\($0.version)(\($0.build))" } ?? "none")", category: "NETWORK")
    }

    /// The build on offer, if any, and whether the server answered at all.
    private static func fetch(_ file: String, beta: Bool) async -> (WyrmUpdateInfo?, Bool) {
        // A changing query makes every check a fresh read past any cache.
        guard let url = URL(string: base + file + "?t=\(Int(Date().timeIntervalSince1970))") else { return (nil, false) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return (nil, false) }
        if status == 404 { return (nil, true) }
        return (parse(data, status: status, beta: beta), status == 200)
    }

    private static func parse(_ data: Data, status: Int, beta: Bool) -> WyrmUpdateInfo? {
        guard status == 200,
              data.count < 64 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String,
              let build = (object["build"] as? Int) ?? Int(object["build"] as? String ?? ""),
              let link = object["ipaUrl"] as? String,
              let ipa = URL(string: link),
              ipa.scheme == "https", ipa.host == "github.com",
              ipa.path.hasPrefix(releasePrefix), ipa.path.hasSuffix(".ipa") else { return nil }
        return WyrmUpdateInfo(version: version, build: build, url: ipa, beta: beta)
    }
}
