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
 *
 * Beta updates are on by default (OM, 2026-09-27); a player who switched them
 * off stays off. A newer build raises `WyrmUpdatePrompt` once per build; its
 * button opens Settings › Updates, where the update itself starts.
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
    private static let promptedKey = "wyrm.ios.update.prompted"

    /// The build to raise the prompt for, if it has not been answered yet.
    var promptable: WyrmUpdateInfo? {
        guard let next = available, next.build != UserDefaults.standard.integer(forKey: Self.promptedKey) else { return nil }
        return next
    }

    /// Later or Update: this build's prompt is answered and not raised again.
    func answerPrompt() {
        if let next = available { UserDefaults.standard.set(next.build, forKey: Self.promptedKey) }
        objectWillChange.send()
    }

    private static let base = "https://raw.githubusercontent.com/disis-om/wyrm-ios/main/update/"
    private static let releasePrefix = "/disis-om/wyrm-ios/releases/download/"

    var betaEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.betaKey) as? Bool ?? true }
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

/// "Update available" / "Beta update available": raised over the menu once per
/// new build. Its button opens Settings › Updates, where the update starts; the
/// beta card also says what a beta is and gives a shortcut to switch them off.
struct WyrmUpdatePrompt: View {
    let info: WyrmUpdateInfo
    let onLater: () -> Void
    let onUpdate: () -> Void
    let onBetaSettings: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.38 : 0).ignoresSafeArea()
                .onTapGesture(perform: onLater)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(ATheme.live).frame(width: 6, height: 6)
                    Text(info.beta ? "BETA UPDATE AVAILABLE" : "UPDATE AVAILABLE")
                        .font(.androidWyrm(11.5, .semibold)).tracking(0.8).foregroundColor(ATheme.live)
                }
                Text(info.beta ? "Wyrm \(info.version) beta" : "Wyrm \(info.version)")
                    .font(.androidWyrm(22, .bold)).foregroundColor(ATheme.ink).padding(.top, 9)
                Text("Build \(info.build) is ready. Update from Settings › Updates; it installs through AltStore as always.")
                    .font(.androidWyrm(13.5)).foregroundColor(ATheme.quiet).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
                if info.beta {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This is a beta update").font(.androidWyrm(14, .bold)).foregroundColor(ATheme.ink)
                        Text("Beta updates are early builds: you get new features before everyone else, but they can have rough edges or bugs. Stable updates come later, for everyone.")
                            .font(.androidWyrm(13)).foregroundColor(ATheme.mute)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onBetaSettings) {
                            Text("Don't want beta updates? Turn them off in Settings › Updates ›")
                                .font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.link)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(.plain).padding(.top, 6)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ATheme.well)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 16)
                }
                HStack(spacing: 9) {
                    WSOutlineButton(label: "Later", onClick: onLater)
                    WSPrimaryButton(label: "Update", onClick: onUpdate)
                }.padding(.top, 18)
            }
            .padding(EdgeInsets(top: 20, leading: 18, bottom: 18, trailing: 18))
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
            .padding(.horizontal, 12).padding(.bottom, 12)
            .offset(y: shown ? 0 : 420)
        }
        .onAppear { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { shown = true } }
    }
}

