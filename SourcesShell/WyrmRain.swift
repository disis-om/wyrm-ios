import Foundation
import Security
import SwiftUI
import UIKit
import CryptoKit

struct WyrmRainCharacter: Codable, Identifiable {
    /// Every new character is "wyrm.bot", the first one too (OM, 2026-10-14).
    static let defaultName = "wyrm.bot"
    var id = UUID().uuidString
    var label = defaultName
    var name = defaultName
    var skin = "uuuuuuuauuuuuuaauuuuuaaauuuuaaaauuuaaaaauuaaaaaauaaaaaaauuaaaaaauuuaaaaauuuuaaaauuuuuaaauuuuuuaa"
    var tag = "12"
    var cosmetic = 11
    var hash = ""
    var enabled = true
    var dictionary: [String: Any] { ["id": id, "label": label, "name": name, "skin": skin, "tag": tag, "cosmetic": cosmetic, "hash": hash, "enabled": enabled] }
    static func from(_ raw: [String: Any]) -> Self {
        var v = Self()
        v.id = String((raw["id"] as? String ?? v.id).prefix(80))
        v.label = String((raw["label"] as? String ?? v.label).prefix(24))
        v.name = String((raw["name"] as? String ?? v.name).unicodeScalars.filter { (32...126).contains(Int($0.value)) }.prefix(24).map(String.init).joined())
        v.skin = ascii(raw["skin"] as? String ?? v.skin, limit:250)
        v.tag = ascii(raw["tag"] as? String ?? v.tag, limit:255)
        let cosmetic = (raw["cosmetic"] as? NSNumber)?.intValue ?? 255
        v.cosmetic = (0...31).contains(cosmetic) || cosmetic == 255 ? cosmetic : 255
        v.hash = ascii(raw["hash"] as? String ?? "", limit:64)
        v.enabled = raw["enabled"] as? Bool ?? true
        return v
    }
    private static func ascii(_ value: String, limit: Int) -> String {
        value.unicodeScalars.filter { (32...126).contains(Int($0.value)) }.prefix(limit).map(String.init).joined()
    }
}

/// Pure Rain 6.36 codec; fields use UTF-8 lengths and little-endian numbers.
struct WyrmRainWire {
    var data: Data
    init(_ opcode: UInt8) { data = Data([opcode]) }
    mutating func byte(_ v: Int) { data.append(UInt8(clamping: v)) }
    mutating func short(_ v: Int) { let n = min(max(v, 0), 65535); byte(n & 255); byte(n >> 8) }
    mutating func text(_ v: String, wide: Bool = false) {
        let bytes = Data(v.utf8.prefix(wide ? 65535 : 255))
        if wide { short(bytes.count) } else { byte(bytes.count) }
        data.append(bytes)
    }
    mutating func float(_ v: Double) {
        var bits = (v.isFinite ? v : 0).bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }
    static func pair(_ opcode: UInt8, _ value: Int) -> Data { var w = Self(opcode); w.byte(value); return w.data }
    // The 6.36 private-tag proof format; never used to store login passwords.
    static func tagProof(_ key: String) -> String {
        key.isEmpty ? "" : Insecure.MD5.hash(data:Data(key.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    static func xy(_ opcode: UInt8, _ x: Double, _ y: Double) -> Data {
        var w = Self(opcode); w.short(coord(x)); w.short(coord(y)); return w.data
    }
    static func coord(_ x: Double) -> Int { x.isFinite ? Int(min(max(x.rounded(), 0), 65535)) : 0 }
    static func login(_ user: String, _ password: String) -> Data {
        var w = Self(97); w.text(user, wide: true); w.text(password, wide: true); w.byte(6); w.byte(36); return w.data
    }
}
struct WyrmRainReader {
    private var bytes: [UInt8]; private var offset = 0
    enum Failure: Error { case malformed }
    init(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 16384 else { throw Failure.malformed }; bytes = Array(data)
    }
    mutating func byte() throws -> Int {
        guard offset < bytes.count else { throw Failure.malformed }; defer { offset += 1 }; return Int(bytes[offset])
    }
    mutating func short() throws -> Int { let low = try byte(); let high = try byte(); return low | high << 8 }
    mutating func text(wide: Bool = false) throws -> String {
        let n = try wide ? short() : byte()
        guard offset + n <= bytes.count else { throw Failure.malformed }
        let string = String(decoding: bytes[offset..<(offset+n)], as: UTF8.self); offset += n; return string
    }
    var remaining: Int { bytes.count - offset }
}

@MainActor
final class WyrmRain: ObservableObject {
    static let shared = WyrmRain()
    static let settingsKey = "wyrm.ios.rain.settings"
    static let defaults: [String: Double] = ["maxBots":1000,"size":2000,"separation":800,"finalAng":90,"rOC":0.5,"rotationDir":1,"period":2000,"amplitude":45,"ranRate":1000,"evolveTime":30,"evolveBots":1,"panelSize":1,"panelOpacity":1,"panelBack":0.94]
    /// The last three are the arena panel's own look (OM, 2026-10-14): never sent to Rain.
    static let ranges: [(String, ClosedRange<Double>)] = [("maxBots",1...1000),("size",100...3000),("separation",0...3000),("finalAng",0...90),("rOC",0...1),("rotationDir",0...1),("period",100...10000),("amplitude",0...62),("ranRate",100...5000),("evolveTime",10...300),("evolveBots",1...5),("panelSize",0.7...1.3),("panelOpacity",0.3...1),("panelBack",0...1)]
    static let maxCharacters = 100
    /// Rain 6.36's factory account, shared by everyone.
    static let publicUser = "snakeyuser"
    static let publicPassword = "wormfood"
    static let defaultKeys = ["boost":"x","follow":"1","random":"2","straight":"3","copy":"4","mouse":"5","rain":"6","tornado":"7","circle":"F1","target":"F2","heart":"F3","wigwag":"F4","startAndStopBots":"=","rotateLeft":"a","rotateRight":"d"]
    static let modes = ["Follow","Unfollow","Random","Straight","Copy","Follow pointer","Hold pointer","Rain","Tornado","Circle CW","Circle CCW","Target","Heart","Wigwag"]
    @Published private(set) var config = defaults
    @Published private(set) var characters = [WyrmRainCharacter()]
    @Published private(set) var keys = defaultKeys
    @Published private(set) var enabled = false
    @Published private(set) var connected = false
    @Published private(set) var running = false
    @Published private(set) var boosting = false
    @Published private(set) var mode = 1
    @Published private(set) var count = 0
    @Published private(set) var status = "Public account"
    @Published private(set) var personal = false
    @Published private(set) var username = WyrmRain.publicUser
    @Published private(set) var password = WyrmRain.publicPassword
    @Published private(set) var rotation = 0
    @Published private(set) var evolveEnabled = false
    @Published private(set) var rotationEnabled = true
    @Published private(set) var snapshot: [String: Any] = [:]
    /// Grows on each tap of the arena's Rain key (engine `open` count): the panel opens or closes.
    @Published private(set) var panelRequests = 0
    private var lastOpen = -1
    private var socket: URLSessionWebSocketTask?
    private var poll: Task<Void, Never>?
    private var reader: Task<Void, Never>?
    private var settingsSend: Task<Void, Never>?
    private var characterSend: Task<Void, Never>?
    private var secretSignature = Data()
    private var generation = 0
    private var sentJoin = -1
    private var alive = false
    private var granted = 1000
    private var lastUI = Date.distantPast
    private let session = URLSession(configuration: .ephemeral)
    private init() {
        loadCredentials(); reload()
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in WyrmRain.shared.disconnect() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in if WyrmRain.shared.enabled { WyrmRain.shared.connect() } }
        }
    }
    func reload() {
        let raw = UserDefaults.standard.data(forKey: Self.settingsKey)
        if raw == nil {
            config = Self.defaults; characters = [WyrmRainCharacter()]; keys = Self.defaultKeys
            evolveEnabled = false; rotationEnabled = true; enable(false)
        }
        let doc = raw.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        restore(doc)
    }
    var document: [String: Any] {
        var d: [String: Any] = config
        d["v"] = 1; d["enabled"] = enabled; d["characters"] = characters.map { bot -> [String: Any] in
            var value = bot.dictionary; value["hash"] = ""; if bot.tag.hasPrefix("!") { value["tag"] = "-1" }; return value
        }
        d["evolveEnabled"] = evolveEnabled; d["rotationEnabled"] = rotationEnabled; d["keys"] = keys
        return d
    }
    func restore(_ d: [String: Any]) {
        for (key, range) in Self.ranges {
            if let v = (d[key] as? NSNumber)?.doubleValue, v.isFinite { config[key] = min(max(v, range.lowerBound), range.upperBound) }
        }
        if let on = d["evolveEnabled"] as? Bool { evolveEnabled = on }
        if let on = d["rotationEnabled"] as? Bool { rotationEnabled = on }
        if let raw = d["keys"] as? [String: String] { for (key, value) in raw where Self.defaultKeys[key] != nil { keys[key] = String(value.prefix(30)) } }
        // An empty list is the player's choice.
        if let raw = d["characters"] as? [[String: Any]] {
            var seen = Set<String>(); characters = raw.prefix(100).map(WyrmRainCharacter.from).filter { seen.insert($0.id).inserted }
        }
        loadBotSecrets()
        if let on = d["enabled"] as? Bool { enable(on) }
        save()
    }
    private func save() {
        if let data = try? JSONSerialization.data(withJSONObject: document) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
        let secrets = Dictionary(characters.filter { $0.tag.hasPrefix("!") || !$0.hash.isEmpty }.map { ($0.id,["tag":$0.tag,"hash":$0.hash]) },uniquingKeysWith:{a,_ in a})
        guard let signature = try? JSONSerialization.data(withJSONObject:secrets,options:.sortedKeys), signature != secretSignature else { return }
        secretSignature = signature
        var query = authQuery; query[kSecAttrAccount as String] = "bot-tags"; SecItemDelete(query as CFDictionary)
        if let data = try? JSONSerialization.data(withJSONObject:secrets) {
            query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(query as CFDictionary,nil)
        }
    }
    private func loadBotSecrets() {
        var query = authQuery; query[kSecAttrAccount as String] = "bot-tags"; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&found) == errSecSuccess, let data = found as? Data,
              let secrets = try? JSONSerialization.jsonObject(with:data) as? [String:[String:String]] else { return }
        characters = characters.map { raw in var c = raw; if let secret = secrets[c.id] { c.tag = secret["tag"] ?? c.tag; c.hash = secret["hash"] ?? "" }; return c }
    }
    func enable(_ on: Bool) {
        enabled = on; wyrm_rain_enable(on)
        if !on { disconnect(); poll?.cancel(); poll = nil }
        else if poll == nil {
            poll = Task { [weak self] in
                while !Task.isCancelled {
                    self?.observe(); try? await Task.sleep(nanoseconds: 30_000_000)
                }
            }; connect()
        }
        save()
    }
    func set(_ key: String, _ v: Double) {
        guard v.isFinite, let range = Self.ranges.first(where: { $0.0 == key })?.1 else { return }
        config[key] = min(max(v, range.lowerBound), range.upperBound); save(); sendSettings()
    }
    func flag(_ key: String, _ on: Bool) {
        if key == "evolveEnabled" { evolveEnabled = on } else if key == "rotationEnabled" { rotationEnabled = on; if !on { rotate(0) } }
        save(); sendSettings()
    }
    func update(_ bot: WyrmRainCharacter) { characters = characters.map { $0.id == bot.id ? WyrmRainCharacter.from(bot.dictionary) : $0 }; save(); sendCharacters() }
    /// Adds a "wyrm.bot" character and returns it (nil at Rain's 100).
    @discardableResult func add() -> WyrmRainCharacter? {
        guard characters.count < Self.maxCharacters else { return nil }
        let bot = WyrmRainCharacter(); characters.append(bot); save(); sendCharacters(); return bot
    }
    func remove(_ ids: Set<String>) { characters.removeAll { ids.contains($0.id) }; save(); sendCharacters() }
    func move(_ id: String, _ delta: Int) { guard let index = characters.firstIndex(where: { $0.id == id }), characters.indices.contains(index + delta) else { return }; characters.insert(characters.remove(at: index), at: index + delta); save(); sendCharacters() }
    func all(_ on: Bool) { for i in characters.indices { characters[i].enabled = on }; save(); sendCharacters() }
    func reset() { config = Self.defaults; keys = Self.defaultKeys; characters = [WyrmRainCharacter()]; evolveEnabled = false; rotationEnabled = true; save(); sendSettings(); sendCharacters() }
    private var authQuery: [String: Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.wyrm.rain", kSecAttrAccount as String:"personal"] }
    private func loadCredentials() {
        var query = authQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: String], let user = value["user"], let pass = value["pass"] else { return }
        username = user; password = pass; personal = true
    }
    func credentials(_ user: String, _ pass: String, personal: Bool) {
        disconnect(); self.personal = personal
        username = personal ? String(user.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128)) : Self.publicUser
        password = personal ? String(pass.prefix(256)) : Self.publicPassword
        SecItemDelete(authQuery as CFDictionary)
        if personal, let data = try? JSONSerialization.data(withJSONObject:["user":username,"pass":password]) {
            var query = authQuery; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { status = "Could not save personal login on this phone"; return }
        }
        if enabled { connect() }
    }
    func clearAccount() {
        enable(false); SecItemDelete(authQuery as CFDictionary)
        var tags = authQuery; tags[kSecAttrAccount as String] = "bot-tags"; SecItemDelete(tags as CFDictionary)
        personal = false; username = Self.publicUser; password = Self.publicPassword; characters = [WyrmRainCharacter()]; config = Self.defaults
    }
    func connect() {
        guard enabled, socket == nil else { return }
        guard !username.isEmpty, !password.isEmpty else { status = "Enter your Rain credentials"; return }
        generation += 1; let epoch = generation
        status = "Connecting…"
        var request = URLRequest(url:URL(string:"wss://snakeyrain.com:8421/")!)
        request.setValue("http://slither.io",forHTTPHeaderField:"Origin")
        let task = session.webSocketTask(with:request); socket = task; task.resume()
        task.send(.data(WyrmRainWire.login(username, password))) { _ in }
        reader = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard let self, self.generation == epoch else { return }
                    guard case .data(let data) = message else { continue }; try self.message(data)
                }
            } catch { if let self, self.generation == epoch { self.disconnect(); self.status = "Rain connection failed. Tap reconnect." } }
        }
    }
    func disconnect() {
        if connected { send(WyrmRainWire.pair(120, 0)) }
        generation += 1; reader?.cancel(); reader = nil; socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        connected = false; running = false; boosting = false; count = 0; sentJoin = -1; rotate(0)
        status = personal ? "Personal account" : "Public account"
    }
    private func send(_ data: Data) { guard connected else { return }; socket?.send(.data(data)) { _ in } }
    private func message(_ data: Data) throws {
        var r = try WyrmRainReader(data)
        switch try r.byte() {
        case 108:
            guard try r.byte() != 0 else { disconnect(); status = "Rain login was refused"; return }
            let limit = try r.short(); granted = limit > 0 ? limit : 1000; connected = true; status = personal ? "Personal account connected" : "Public account connected"
            sendSettings(); sendCharacters(); sentJoin = -1
        case 103: mode = min(max(try r.byte(), 1), 14)
        case 98: boosting = try r.byte() != 0
        case 105: count = try r.short()
        case 119: running = try r.byte() != 0
        case 109: status = String(try r.text(wide:true).prefix(240)); if r.remaining > 0 { _ = try r.text() }
        case 100: status = String(try r.text().prefix(240))
        case 80: send(WyrmRainWire.pair(80, 1))
        default: break
        }
    }
    private func observe() {
        var chars = [CChar](repeating:0,count:6144)
        chars.withUnsafeMutableBufferPointer { wyrm_rain_read($0.baseAddress, $0.count) }
        let bytes = Data(String(cString:chars).utf8)
        let d = (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] ?? [:]
        let live = d["alive"] as? Bool ?? false; let seq = (d["generation"] as? NSNumber)?.intValue ?? 0
        if let open = (d["open"] as? NSNumber)?.intValue, open >= 0 {
            if lastOpen >= 0 && open > lastOpen { panelRequests += 1 }; lastOpen = open
        }
        // Like Rain 6.36: a death or a new join never stops the storm; every
        // join is relayed again below and the bots carry on (OM, 2026-10-14).
        alive = live
        if connected && live && seq != sentJoin, let hex = d["join"] as? String, !hex.isEmpty, hex.count % 2 == 0 {
            var join = Data(); var cursor = hex.startIndex
            while cursor < hex.endIndex { let end = hex.index(cursor,offsetBy:2); guard let byte = UInt8(hex[cursor..<end],radix:16) else { return }; join.append(byte); cursor = end }
            var wire = WyrmRainWire(83); wire.data.append(join); send(wire.data); sentJoin = seq
        }
        if connected && live && [1,6,9].contains(mode) { send(WyrmRainWire.xy(112, (d["x"] as? NSNumber)?.doubleValue ?? 0, (d["y"] as? NSNumber)?.doubleValue ?? 0)) }
        if Date().timeIntervalSince(lastUI) >= 0.1 { snapshot = d; lastUI = Date() }
    }
    func start() {
        guard connected else { connect(); status = "Wait for Rain login, then tap Start"; return }
        guard characters.contains(where: \.enabled) else { status = "Add a character first"; return }
        guard snapshot["alive"] as? Bool == true, let address = snapshot["arena"] as? String, let colon = address.lastIndex(of:":") else { status = "Join an arena before starting Rain"; return }
        var wire = WyrmRainWire(114); wire.text(String(address[..<colon]).trimmingCharacters(in:CharacterSet(charactersIn:"[]"))); wire.text(String(address[address.index(after:colon)...])); send(wire.data)
    }
    func stop() { send(WyrmRainWire.pair(120,0)); rotate(0) }
    func boost() { send(WyrmRainWire.pair(98,boosting ? 0 : 1)) }
    func setMode(_ id: Int) {
        guard (1...14).contains(id) else { return }
        if [8,9,14].contains(id) { send(WyrmRainWire.xy(111,(snapshot["x"] as? NSNumber)?.doubleValue ?? 0,(snapshot["y"] as? NSNumber)?.doubleValue ?? 0)) }
        send(WyrmRainWire.pair(100,id))
    }
    func target(_ d: [String: Any]) {
        var w = WyrmRainWire(116); w.short((d["id"] as? NSNumber)?.intValue ?? 0); w.short(WyrmRainWire.coord((d["x"] as? NSNumber)?.doubleValue ?? 0)); w.short(WyrmRainWire.coord((d["y"] as? NSNumber)?.doubleValue ?? 0)); send(w.data); setMode(12)
    }
    func rotate(_ direction: Int) { rotation = rotationEnabled ? min(max(direction,-1),1) : 0; wyrm_rain_rotate(Int32(rotation)) }
    func handleKey(_ key: String) -> Bool {
        guard enabled, snapshot["alive"] as? Bool == true, !WyrmKeyboardController.shared.focused,
              let action = Self.defaultKeys.keys.sorted().first(where: { (keys[$0] ?? Self.defaultKeys[$0] ?? "").caseInsensitiveCompare(key) == .orderedSame }) else { return false }
        switch action {
        case "boost": boost()
        case "follow": setMode(mode == 1 ? 2:1)
        case "random": setMode(3)
        case "straight": setMode(4)
        case "copy": setMode(5)
        case "mouse": setMode(mode == 6 ? 7:6)
        case "rain": setMode(8)
        case "tornado": setMode(9)
        case "circle": setMode(mode == 10 ? 11:10)
        case "target": setMode(12)
        case "heart": setMode(13)
        case "wigwag": setMode(14)
        case "startAndStopBots": if running { stop() } else { start() }
        case "rotateLeft": rotate(rotation == -1 ? 0:-1)
        case "rotateRight": rotate(rotation == 1 ? 0:1)
        default: return false
        }
        return true
    }
    private func sendSettings() {
        settingsSend?.cancel()
        settingsSend = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:100_000_000) } catch { return }; self?.sendSettingsNow()
        }
    }
    private func sendSettingsNow() {
        var w = WyrmRainWire(84)
        w.short(Int(config["size"] ?? 2000)); w.short(Int(config["separation"] ?? 800)); w.byte(Int(config["finalAng"] ?? 90))
        w.short(Int((config["rOC"] ?? 0.5)*100)); w.byte(Int(config["rotationDir"] ?? 1)); w.short(Int(config["period"] ?? 2000)); w.byte(Int(config["amplitude"] ?? 45)); w.short(Int(config["ranRate"] ?? 1000)); send(w.data)
        var b = WyrmRainWire(66); b.short(min(Int(config["maxBots"] ?? 1000),granted)); send(b.data)
        var e = WyrmRainWire(69); e.byte(evolveEnabled ? 1:0); e.short(Int(config["evolveTime"] ?? 30)); e.byte(Int(config["evolveBots"] ?? 1)); send(e.data)
    }
    private func sendCharacters() {
        characterSend?.cancel()
        characterSend = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:2_000_000_000) } catch { return }; self?.sendCharactersNow()
        }
    }
    private func sendCharactersNow() {
        let bots = characters.filter(\.enabled); var w = WyrmRainWire(99); w.byte(6); w.byte(36); w.byte(bots.count)
        for b in bots { w.text(b.name); w.text(b.skin); w.text(b.tag); w.byte(b.cosmetic); w.text(b.hash) }; send(w.data)
    }
}
