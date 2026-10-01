import SwiftUI

/// Account-linked settings (OM, 2026-10-01). Android twin: `data/AccountSync.kt`;
/// backend: `backend/src/account-settings.mjs`.
///
/// Everything a player sets lives in their account, not on the phone. The app
/// saves it when it goes to the background and when the player logs out, and
/// puts it back behind the W during log in. Log out wipes the phone, so nothing
/// of one account is left for the next.
///
/// Two documents per account: **ios** (this platform's own copy: the engine's
/// settings table, the on-screen buttons and the `wyrm.*` defaults marked
/// `.sync` in [rules]) and **shared** (the same on every platform: the skin, the
/// Wyrm look, the arena background, the in-game name).
///
/// **The rule for every future build** (CLAUDE.md): a new `wyrm.*` default must
/// match a rule here; a renamed key or setting gets an entry in [renames]; a
/// restore is per key and skips what it does not understand.
/// `Tests/account_sync_contract_test.py` fails when a key in the code has no rule.
@MainActor
final class WyrmAccountSync: ObservableObject {
    static let shared = WyrmAccountSync()
    static let platform = "ios"
    static let schema = 1
    private static let base = "https://wyrm-api.77-245-76-86.sslip.io"
    private static let owedKey = "wyrm.ios.account-sync.owed"

    enum Scope { case sync, wipe, keep }

    /// First match wins. Keys outside `wyrm.` (Apple's, SDL's) are never touched.
    static let rules: [(prefix: String, scope: Scope)] = [
        // About the phone itself: kept.
        ("wyrm.crash.running", .keep),              // + runningVersion: crash detection
        ("wyrm.ios.update.prompted", .keep),
        // Account caches and retired things: wiped, never uploaded.
        ("wyrm.ios.backup.", .wipe),                // manual backups, retired 2026-10-01
        ("wyrm.ios.update.backup-first", .wipe),
        ("wyrm.ios.look.", .wipe),                  // travels in the shared document
        ("wyrm.nickname.chosen", .wipe),            // travels in the shared document
        ("wyrm.support.", .wipe),
        ("wyrm.ios.account-sync.", .wipe),
        // The player's choices: synced.
        ("wyrm.ios.skin.", .sync),
        ("wyrm.ios.arena.", .sync),
        ("wyrm.notify.", .sync),
        ("wyrm.ios.theme", .sync),                  // + theme-intensity
        ("wyrm.ios.arrow.", .sync),
        ("wyrm.ios.joystick-laser.", .sync),        // Modes › Assist: joystick laser on, length
        ("wyrm.ios.orientation.", .sync),           // Controls › Play orientation + each orientation's layout
        ("wyrm.ios.performance.", .sync),           // Settings › Performance: mode, FPS limit
        ("wyrm.ios.keyboard.", .sync),
        ("wyrm.ios.developer-mode", .sync),
        ("wyrm.ios.stats.", .sync),
        ("wyrm.ios.runs.", .sync),                  // receipts not yet uploaded; the server dedupes
        ("wyrm.ios.onboarding.", .sync),
        ("wyrm.ios.updates.beta", .sync),
        ("wyrm.crash.autoSend", .sync),
        ("wyrm.drop.autoSend", .sync),
        ("wyrm.trails.", .sync),
    ]

    /// Old default key → new, for documents saved by older builds.
    static let renames: [String: String] = [:]

    static func scope(of key: String) -> Scope? {
        guard key.hasPrefix("wyrm.") else { return nil }
        return rules.first(where: { key.hasPrefix($0.prefix) })?.scope ?? .wipe
    }

    enum LogOutStage: Equatable { case idle, saving, failed(String) }

    @Published var logOutStage: LogOutStage = .idle
    /// Settings › Log out asked; the root draws the sheet above every tab.
    @Published var askingLogOut = false
    /// Set by `WyrmDesignRoot`: the engine whose settings travel.
    weak var engine: WyrmShellStore?
    /// True once this phone holds the account's settings (after a restore, or
    /// a relaunch with nothing owed). Saves wait for it, so a fresh phone never
    /// uploads its defaults over the account's copy.
    private(set) var ready = false
    private var lastSave = Date.distantPast
    private var retry: Task<Void, Never>?

    // MARK: documents

    private static func encode(_ value: Any) -> [Any]? {
        if let text = value as? String { return ["s", text] }
        if let list = value as? [String] { return ["S", list] }
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return ["b", number.boolValue] }
        if CFNumberIsFloatType(number as CFNumber) { return ["f", number.doubleValue] }
        return ["i", number.intValue]
    }

    /// This phone's copy, or nil while the engine has not described its settings
    /// (a partial copy would replace a whole one).
    func platformDocument() -> [String: Any]? {
        guard let engine, !engine.settings.isEmpty else { return nil }
        var values: [String: String] = [:]
        for setting in engine.settings {
            values[setting.id] = setting.values.map { String(format: "%.4f", $0) }.joined(separator: ",")
        }
        let hotkeys: [[String: Any]] = engine.hotkeys.map {
            ["action": $0.id, "name": $0.name, "key": $0.key, "mode": $0.mode, "visible": $0.visible, "x": $0.x, "y": $0.y]
        }
        var defaults: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where Self.scope(of: key) == .sync {
            if let typed = Self.encode(value) { defaults[key] = typed }
        }
        return ["schema": Self.schema, "platform": Self.platform, "engine": values, "hotkeys": hotkeys, "defaults": defaults]
    }

    /// Skin (with the player's own pattern even while a preset is worn), look,
    /// arena background, name. The same JSON as Android's.
    func sharedDocument() -> [String: Any] {
        let d = UserDefaults.standard
        let preset = d.object(forKey: "wyrm.ios.skin.preset") as? Int ?? 2
        let customOn = d.object(forKey: "wyrm.ios.skin.custom-enabled") as? Bool ?? false
        let groups = Array((d.string(forKey: "wyrm.ios.skin.custom-groups") ?? "").split(separator: ",")
            .compactMap { Int($0) }.filter { WyrmSkinCatalog.validGroups.contains($0) }.prefix(256))
        let stored = (d.string(forKey: "wyrm.ios.skin.custom-colors") ?? "").split(separator: ",", omittingEmptySubsequences: false)
            .prefix(256).map { UInt32($0, radix: 16) ?? 0 }
        let accessory = d.object(forKey: "wyrm.ios.skin.accessory-id") as? Int ?? -1
        let look = WyrmLookStore.shared
        let skin: [String: Any] = [
            "v": 1,
            "custom": customOn && !groups.isEmpty,
            "preset": min(max(preset, 0), 255),
            "code": groups.isEmpty ? "" : WyrmSkinCatalog.code(for: groups),
            "colours": groups.indices.map { String(format: "%08X", $0 < stored.count ? stored[$0] : 0) },
            "accessory": WyrmSkinCatalog.accessories.contains(where: { $0.id == accessory }) ? accessory : -1,
            "look": ["hair": look.hair, "hairTone": look.hairTone.isFinite ? min(max(look.hairTone, 0), 1) : 0.22,
                     "ears": look.ears, "glasses": look.glasses],
        ]
        return [
            "schema": 1,
            "skin": skin,
            "arenaBackground": d.object(forKey: "wyrm.ios.skin.background-id") as? Int ?? 0,
            "nickname": engine?.nickname ?? "",
            "nicknameChosen": d.bool(forKey: "wyrm.nickname.chosen"),
            // Common to every platform (OM, 2026-10-01): the same on Android and iOS.
            "joystickLaser": ["on": WyrmJoystickLaserStore.shared.on, "length": WyrmJoystickLaserStore.shared.length],
            "playPortrait": WyrmPlayOrientation.shared.portrait,
            "performanceMode": WyrmPerformance.shared.mode.rawValue,
        ]
    }

    // MARK: restore

    /// The account's iOS copy, key by key. Engine values that already match are
    /// not sent; the rest go in slices, because the engine's mailbox holds 128.
    func applyPlatform(_ doc: [String: Any]) async {
        let d = UserDefaults.standard
        for (stored, raw) in doc["defaults"] as? [String: Any] ?? [:] {
            let key = Self.renames[stored] ?? stored
            guard Self.scope(of: key) == .sync, let typed = raw as? [Any], typed.count == 2, let kind = typed[0] as? String else { continue }
            switch kind {
            case "b": if let v = typed[1] as? Bool { d.set(v, forKey: key) }
            case "i": if let v = (typed[1] as? NSNumber)?.intValue { d.set(v, forKey: key) }
            case "f": if let v = (typed[1] as? NSNumber)?.doubleValue, v.isFinite { d.set(v, forKey: key) }
            case "s": if let v = typed[1] as? String { d.set(v, forKey: key) }
            case "S": if let v = typed[1] as? [String] { d.set(v, forKey: key) }
            default: continue
            }
        }
        guard let engine else { return }
        let current = Dictionary(engine.settings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [(String, [Double])] = []
        for (id, raw) in doc["engine"] as? [String: Any] ?? [:] {
            guard let setting = current[id], let text = raw as? String else { continue }
            let values = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.filter(\.isFinite)
            guard let first = values.first else { continue }
            let low = min(setting.minimum, setting.maximum), high = max(setting.minimum, setting.maximum)
            let wanted = setting.type.hasPrefix("color") ? values.map { min(max($0, 0), 1) } : [min(max(first, low), high)]
            let same = setting.values.count >= wanted.count && zip(setting.values, wanted).allSatisfy { abs($0 - $1) < 0.0006 }
            if !same { changes.append((id, wanted)) }
        }
        for (index, change) in changes.enumerated() {
            if index > 0 && index % 40 == 0 { try? await Task.sleep(nanoseconds: 150_000_000) }
            engine.write(id: change.0, values: change.1)
        }
        for row in doc["hotkeys"] as? [[String: Any]] ?? [] {
            guard let base = engine.hotkeys.first(where: { $0.name == row["name"] as? String })
                    ?? engine.hotkeys.first(where: { $0.id == (row["action"] as? NSNumber)?.intValue }),
                  let x = (row["x"] as? NSNumber)?.doubleValue, let y = (row["y"] as? NSNumber)?.doubleValue,
                  x.isFinite, y.isFinite else { continue }
            var next = base
            if !base.fixedMode { next.mode = (row["mode"] as? NSNumber)?.intValue ?? base.mode }
            next.visible = row["visible"] as? Bool ?? base.visible
            next.x = min(max(x, 0), 1)
            next.y = min(max(y, 0), 1)
            engine.writeHotkey(next, log: false)
        }
    }

    func applyShared(_ doc: [String: Any]) {
        let d = UserDefaults.standard
        if let skin = doc["skin"] as? [String: Any], (skin["v"] as? NSNumber)?.intValue == 1 {
            let preset = (skin["preset"] as? NSNumber)?.intValue ?? 2
            if WyrmSkinCatalog.presets.indices.contains(preset) { d.set(preset, forKey: "wyrm.ios.skin.preset") }
            let code = (skin["code"] as? String ?? "").lowercased()
            let colours = skin["colours"] as? [String] ?? []
            var groups: [Int] = []
            var colors: [UInt32] = []
            for (index, character) in code.prefix(256).enumerated() {
                guard let group = WyrmSkinCatalog.group(for: character) else { continue }
                groups.append(group)
                colors.append(index < colours.count ? (UInt32(colours[index], radix: 16) ?? 0) : 0)
            }
            if !groups.isEmpty {
                d.set(groups.map(String.init).joined(separator: ","), forKey: "wyrm.ios.skin.custom-groups")
                d.set(colors.map { String($0, radix: 16) }.joined(separator: ","), forKey: "wyrm.ios.skin.custom-colors")
            }
            d.set((skin["custom"] as? Bool ?? false) && !groups.isEmpty, forKey: "wyrm.ios.skin.custom-enabled")
            let accessory = (skin["accessory"] as? NSNumber)?.intValue ?? -1
            d.set(WyrmSkinCatalog.accessories.contains(where: { $0.id == accessory }) ? accessory : -1, forKey: "wyrm.ios.skin.accessory-id")
            if let look = skin["look"] as? [String: Any] {
                WyrmLookStore.shared.wear(hair: (look["hair"] as? NSNumber)?.intValue ?? -1,
                                          hairTone: (look["hairTone"] as? NSNumber)?.doubleValue ?? 0.22,
                                          ears: (look["ears"] as? NSNumber)?.intValue ?? -1,
                                          glasses: (look["glasses"] as? NSNumber)?.intValue ?? -1)
            }
        }
        if let background = (doc["arenaBackground"] as? NSNumber)?.intValue,
           WyrmSkinCatalog.backgrounds.indices.contains(background) {
            d.set(background, forKey: "wyrm.ios.skin.background-id")
        }
        if let engine { Self.reapplySkin(engine) }
        if let name = doc["nickname"] as? String {
            engine?.setNickname(name)
            d.set(doc["nicknameChosen"] as? Bool ?? !name.isEmpty, forKey: "wyrm.nickname.chosen")
        }
        // Common settings (OM, 2026-10-01). Written into this platform's own
        // keys before the stores reload, so they win over the platform copy.
        if let laser = doc["joystickLaser"] as? [String: Any] {
            if let on = laser["on"] as? Bool { d.set(on, forKey: "wyrm.ios.joystick-laser.on") }
            if let length = (laser["length"] as? NSNumber)?.doubleValue, length.isFinite {
                d.set(min(max(length, WyrmJoystickLaserStore.range.lowerBound), WyrmJoystickLaserStore.range.upperBound),
                      forKey: "wyrm.ios.joystick-laser.length")
            }
        }
        if let mode = doc["performanceMode"] as? String, WyrmPerformance.Mode(rawValue: mode) != nil {
            d.set(mode, forKey: "wyrm.ios.performance.mode")
        }
        // The orientation swaps layouts, so it waits for the restored layout (tryRestore).
        sharedPortraitPending = doc["playPortrait"] as? Bool
    }

    /// The account's common play orientation, applied once the restored layout is in.
    private var sharedPortraitPending: Bool?

    /// The Skin Studio's saved choice, sent to the engine as the studio sends it.
    static func reapplySkin(_ engine: WyrmShellStore) {
        let d = UserDefaults.standard
        let preset = d.object(forKey: "wyrm.ios.skin.preset") as? Int ?? 2
        let custom = d.bool(forKey: "wyrm.ios.skin.custom-enabled")
        let groups = (d.string(forKey: "wyrm.ios.skin.custom-groups") ?? "").split(separator: ",").compactMap { Int($0) }
        let colours = (d.string(forKey: "wyrm.ios.skin.custom-colors") ?? "").split(separator: ",").compactMap { UInt32($0, radix: 16) }
        let base = WyrmSkinCatalog.presets.indices.contains(preset) ? WyrmSkinCatalog.presets[preset] : [7]
        let source = custom && !groups.isEmpty ? groups : base
        let colourSource = custom && !groups.isEmpty ? colours : []
        engine.applySkin(preset: preset,
                         groups: (0..<256).map { source[$0 % source.count] },
                         colors: (0..<256).map { colourSource.isEmpty ? 0 : colourSource[$0 % colourSource.count] },
                         custom: custom && !groups.isEmpty,
                         accessory: d.object(forKey: "wyrm.ios.skin.accessory-id") as? Int ?? -1,
                         tag: d.object(forKey: "wyrm.ios.skin.tag-id") as? Int ?? -1,
                         background: d.object(forKey: "wyrm.ios.skin.background-id") as? Int ?? 0)
    }

    /// Stores that read their defaults once.
    func reloadStores() {
        WyrmThemeStore.shared.reloadFromDefaults()
        WyrmLookStore.shared.reloadFromDefaults()
        WyrmArrowSkinStore.shared.reloadFromDefaults()
        WyrmKeyboardController.shared.reloadFromDefaults()
        WyrmPerformance.shared.reloadFromDefaults()
        WyrmJoystickLaserStore.shared.reloadFromDefaults()
        WyrmPlayOrientation.shared.reloadFromDefaults()
    }

    // MARK: network

    private static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, token: String) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            WyrmDiagnostics.record("\(method) \(path) failed", category: "ACCOUNT")
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: lifecycle

    /// Saves this phone's settings to the account. [force] ignores the 20 s throttle.
    @discardableResult
    func save(token: String, force: Bool = false) async -> Bool {
        guard ready, !token.isEmpty else { return false }
        if !force && Date().timeIntervalSince(lastSave) < 20 { return true }
        guard let platform = platformDocument() else { return false }
        let body: [String: Any] = ["doc": platform, "shared": sharedDocument(), "appVersion": WyrmBuild.version]
        do {
            _ = try await Self.request("/v1/me/settings/\(Self.platform)", method: "PUT", body: body, token: token)
            lastSave = Date()
            WyrmDiagnostics.record("account settings saved", category: "ACCOUNT")
            return true
        } catch {
            return false
        }
    }

    /// Log in: behind the W. Offline: the restore is owed (it survives a
    /// relaunch) and retried every 30 s; nothing is saved until it lands.
    func restore(token: String, playerID: String) async {
        ready = false
        retry?.cancel()
        UserDefaults.standard.set(playerID, forKey: Self.owedKey)
        if await tryRestore(token: token) { return }
        retry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if await self.tryRestore(token: token) { return }
            }
        }
    }

    private func tryRestore(token: String) async -> Bool {
        guard let body = try? await Self.request("/v1/me/settings/\(Self.platform)", token: token) else { return false }
        // The engine describes its settings a moment after launch.
        for _ in 0..<40 where engine?.settings.isEmpty ?? true { try? await Task.sleep(nanoseconds: 150_000_000) }
        if let platform = (body["platform"] as? [String: Any])?["doc"] as? [String: Any] { await applyPlatform(platform) }
        if let shared = (body["shared"] as? [String: Any])?["doc"] as? [String: Any] { applyShared(shared) }
        reloadStores()
        // The account's common orientation: turn (and swap layouts) once the
        // engine has the restored layout.
        if let upright = sharedPortraitPending, let engine {
            sharedPortraitPending = nil
            try? await Task.sleep(nanoseconds: 700_000_000)
            engine.refresh()
            try? await Task.sleep(nanoseconds: 150_000_000)
            if upright != WyrmPlayOrientation.shared.portrait { WyrmPlayOrientation.shared.switchTo(upright, engine: engine) }
        }
        UserDefaults.standard.removeObject(forKey: Self.owedKey)
        ready = true
        WyrmDiagnostics.record("account settings restored", category: "ACCOUNT")
        return true
    }

    /// Relaunch with a session: finish an owed restore, or keep the copy current
    /// (the first save after this build uploads what the phone already had).
    func resume(token: String, playerID: String) {
        if let owed = UserDefaults.standard.string(forKey: Self.owedKey), owed == playerID {
            Task { await restore(token: token, playerID: playerID) }
            return
        }
        ready = true
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await save(token: token)
        }
    }

    /// Log out, step one: the settings go to the account. False (and the
    /// failed stage) when the account could not take them.
    func saveForLogOut(token: String) async -> Bool {
        guard ready else { return true }   // never overwrite the account with an unrestored phone
        logOutStage = .saving
        if await save(token: token, force: true) { return true }
        if platformDocument() == nil { return true }   // engine not ready: nothing meaningful to save
        logOutStage = .failed("Wyrm could not reach your account. If you log out anyway, the changes you made since the last save are cleared with this phone.")
        return false
    }

    /// Log out, last step: every `wyrm.*` default that is not about the phone,
    /// the engine back to its defaults, the stores re-read.
    func wipeDevice() {
        retry?.cancel()
        ready = false
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys {
            if let scope = Self.scope(of: key), scope != .keep { d.removeObject(forKey: key) }
        }
        engine?.reset(1, message: "")
        reloadStores()
        logOutStage = .idle
    }
}

/// Log out's question and, if the save failed, the three honest choices.
struct WyrmLogOutSheet: View {
    let name: String
    let handle: String
    let onLogOut: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(ATheme.rule).frame(width: 38, height: 5).padding(.top, 10)
            Circle().fill(ATheme.well).frame(width: 64, height: 64)
                .overlay(Text(String(name.prefix(1)).uppercased()).font(.androidWyrm(26, .bold)).foregroundColor(ATheme.ink))
                .padding(.top, 18)
            Text("Log out of Wyrm?").font(.wyrmDisplay(24)).foregroundColor(ATheme.ink).padding(.top, 12)
            Text(handle.isEmpty ? name : "\(name) · \(handle)").font(.androidWyrm(13.5, .semibold)).foregroundColor(ATheme.quiet).padding(.top, 4)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "icloud.and.arrow.up").font(.system(size: 17, weight: .semibold)).foregroundColor(ATheme.ink)
                Text("Your settings, skin and layouts are saved to your account first. Then this phone forgets everything, and it all comes back when you log in again.")
                    .font(.androidWyrm(13.5)).foregroundColor(ATheme.mute).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ATheme.well))
            .padding(.top, 16)
            Button(action: onLogOut) {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.androidWyrm(15.5, .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(ATheme.badge))
            }.buttonStyle(.plain).padding(.top, 18)
            Button(action: onCancel) {
                Text("Cancel").font(.androidWyrm(15.5, .bold)).foregroundColor(ATheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(ATheme.well))
            }.buttonStyle(.plain).padding(.top, 8)
        }
        .padding(.horizontal, 22).padding(.bottom, 18)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(ATheme.card))
        .padding(.horizontal, 10)
        .frame(maxWidth: 520)
    }
}

struct WyrmLogOutFailed: View {
    let message: String
    let onRetry: () -> Void
    let onLogOutAnyway: () -> Void
    let onStay: () -> Void

    var body: some View {
        ZStack {
            ATheme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                WyrmBrandMark(size: 84)
                Image(systemName: "icloud.slash").font(.system(size: 21, weight: .semibold)).foregroundColor(ATheme.badge).padding(.top, 22)
                Text("Your settings could not be saved").font(.wyrmDisplay(23)).foregroundColor(ATheme.ink)
                    .multilineTextAlignment(.center).padding(.top, 10)
                Text(message).font(.androidWyrm(14)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
                    .lineSpacing(4).padding(.top, 8)
                Button(action: onRetry) {
                    Label("Try again", systemImage: "arrow.clockwise").font(.androidWyrm(15.5, .bold)).foregroundColor(ATheme.onInk)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(ATheme.ink))
                }.buttonStyle(.plain).padding(.top, 22)
                Button(action: onLogOutAnyway) {
                    Text("Log out anyway").font(.androidWyrm(15.5, .bold)).foregroundColor(ATheme.badge)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(ATheme.well))
                }.buttonStyle(.plain).padding(.top, 8)
                Button(action: onStay) {
                    Text("Stay logged in").font(.androidWyrm(15.5, .semibold)).foregroundColor(ATheme.mute)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }.buttonStyle(.plain).padding(.top, 8)
            }
            .padding(.horizontal, 24).frame(maxWidth: 420)
        }
    }
}
