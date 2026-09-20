import Foundation
import Security
import SwiftUI

struct WyrmPlayer: Decodable, Identifiable {
    let id: String
    var ingameName: String?
    var username: String?
    var displayName: String
    var avatarKey: String
    var avatarURL: String
    var bio: String
    var highestScore: Int64
    var kills: Int64
    var followerCount: Int64
    var followingCount: Int64

    private enum CodingKeys: String, CodingKey {
        case id, ingameName, username, displayName, avatarKey, avatarUrl, bio
        case highestScore, kills, followerCount, followingCount
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        ingameName = try box.decodeIfPresent(String.self, forKey: .ingameName)
        username = try box.decodeIfPresent(String.self, forKey: .username)
        displayName = try box.decodeIfPresent(String.self, forKey: .displayName) ?? "Unnamed"
        avatarKey = try box.decodeIfPresent(String.self, forKey: .avatarKey) ?? "mono-ink"
        avatarURL = try box.decodeIfPresent(String.self, forKey: .avatarUrl) ?? ""
        bio = try box.decodeIfPresent(String.self, forKey: .bio) ?? ""
        highestScore = try box.decodeIfPresent(Int64.self, forKey: .highestScore) ?? 0
        kills = try box.decodeIfPresent(Int64.self, forKey: .kills) ?? 0
        followerCount = try box.decodeIfPresent(Int64.self, forKey: .followerCount) ?? 0
        followingCount = try box.decodeIfPresent(Int64.self, forKey: .followingCount) ?? 0
    }

    var handle: String { username.map { "@\($0)" } ?? "" }
    var arenaName: String { ingameName?.isEmpty == false ? ingameName! : displayName }
    var initials: String {
        let words = displayName.split(separator: " ").prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined().uppercased()
        return value.isEmpty ? "W" : value
    }
}

private struct WyrmAuthEnvelope: Decodable { let token: String; let player: WyrmPlayer }
private struct WyrmErrorEnvelope: Decodable { let error: String? }

enum WyrmAccountError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

private enum WyrmKeychain {
    private static let service = "com.omrajput.wyrmios.session"
    private static let account = "bearer"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String) throws {
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw WyrmAccountError.message("Could not secure this session on the device.")
        }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private actor WyrmAPI {
    static let shared = WyrmAPI()
    private let base = URL(string: "https://wyrm-api.77-245-76-86.sslip.io")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    func signUp(displayName: String, username: String, password: String) async throws -> WyrmAuthEnvelope {
        try await request("/v1/auth/guest", method: "POST", body: ["displayName": displayName, "username": username, "password": password], token: nil)
    }

    func login(username: String, password: String) async throws -> WyrmAuthEnvelope {
        try await request("/v1/auth/login", method: "POST", body: ["username": username, "password": password], token: nil)
    }

    func me(token: String) async throws -> WyrmPlayer {
        try await request("/v1/me", token: token)
    }

    func update(token: String, displayName: String, ingameName: String, username: String, bio: String, avatarKey: String) async throws -> WyrmPlayer {
        var body: [String: Any] = [
            "displayName": displayName, "username": username,
            "bio": bio, "avatarKey": avatarKey,
        ]
        // Guest accounts begin without an arena name. Sending an empty string
        // would fail the backend's 3–20 character IGN contract, so leave the
        // field untouched until the player actually chooses one.
        if !ingameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["ingameName"] = ingameName
        }
        return try await request("/v1/me", method: "PATCH", body: body, token: token)
    }

    func deleteAccount(token: String) async throws {
        let _: EmptyResponse = try await request("/v1/me", method: "DELETE", token: token)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, token: String?) async throws -> T {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: base.appendingPathComponent(cleanPath))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WyrmAccountError.message("The server sent an invalid response.") }
            guard 200..<300 ~= http.statusCode else {
                let code = (try? JSONDecoder().decode(WyrmErrorEnvelope.self, from: data).error) ?? "HTTP_\(http.statusCode)"
                throw WyrmAccountError.message(Self.friendly(code))
            }
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as WyrmAccountError { throw error }
        catch { throw WyrmAccountError.message("Could not reach Wyrm. Check your connection and try again.") }
    }

    private static func friendly(_ code: String) -> String {
        switch code {
        case "USERNAME_TAKEN": return "That username is already taken."
        case "INVALID_LOGIN": return "Username or password is incorrect."
        case "NAME_CHANGE_LIMIT", "USERNAME_CHANGE_LIMIT": return "The monthly name-change limit has been reached."
        case "IGN_TAKEN": return "That arena name is already in use."
        case "INVALID_PROFILE", "INVALID_BODY": return "Please check the fields and try again."
        default: return "Wyrm could not complete that request (\(code))."
        }
    }

    private struct EmptyResponse: Decodable {}
}

@MainActor
final class WyrmAccountStore: ObservableObject {
    enum Phase: Equatable { case restoring, signedOut, onboarding, signedIn }
    @Published private(set) var phase: Phase = .restoring
    @Published private(set) var player: WyrmPlayer?
    @Published var busy = false
    @Published var errorMessage = ""
    private var token: String?

    /// Read-only handoff for the app service store. Views never persist or log it;
    /// the bearer remains owned by this account object and the device Keychain.
    var sessionToken: String { token ?? "" }

    init() { Task { await restore() } }

    func restore() async {
        guard let saved = WyrmKeychain.read() else { phase = .signedOut; return }
        do {
            let player = try await WyrmAPI.shared.me(token: saved)
            token = saved
            self.player = player
            phase = UserDefaults.standard.bool(forKey: onboardingKey(player.id)) ? .signedIn : .onboarding
        } catch {
            WyrmKeychain.clear()
            phase = .signedOut
        }
    }

    func signUp(displayName: String, username: String, password: String) async {
        await authenticate {
            try await WyrmAPI.shared.signUp(displayName: displayName, username: username, password: password)
        }
        if player != nil { phase = .onboarding }
    }

    func login(username: String, password: String) async {
        await authenticate { try await WyrmAPI.shared.login(username: username, password: password) }
        if player != nil { phase = .signedIn }
    }

    func finishOnboarding() {
        guard let player else { return }
        UserDefaults.standard.set(true, forKey: onboardingKey(player.id))
        phase = .signedIn
    }

    func update(displayName: String, ingameName: String, username: String, bio: String, avatarKey: String) async -> Bool {
        guard let token else { return false }
        busy = true; errorMessage = ""
        defer { busy = false }
        do {
            player = try await WyrmAPI.shared.update(token: token, displayName: displayName, ingameName: ingameName, username: username, bio: bio, avatarKey: avatarKey)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func signOut() {
        WyrmKeychain.clear(); token = nil; player = nil; errorMessage = ""; phase = .signedOut
    }

    func deleteAccount() async {
        guard let token else { return }
        busy = true; errorMessage = ""
        do { try await WyrmAPI.shared.deleteAccount(token: token); signOut() }
        catch { errorMessage = error.localizedDescription }
        busy = false
    }

    func refreshProfile() async {
        guard let token else { return }
        do { player = try await WyrmAPI.shared.me(token: token) }
        catch { errorMessage = error.localizedDescription }
    }

    private func authenticate(_ action: () async throws -> WyrmAuthEnvelope) async {
        busy = true; errorMessage = ""
        defer { busy = false }
        do {
            let result = try await action()
            try WyrmKeychain.write(result.token)
            token = result.token; player = result.player
        } catch { errorMessage = error.localizedDescription }
    }

    private func onboardingKey(_ id: String) -> String { "wyrm.ios.onboarding.\(id)" }
}

struct WyrmAccountGate: View {
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var engine: WyrmShellStore

    var body: some View {
        switch account.phase {
        case .restoring: WyrmAccountLoading()
        case .signedOut: WyrmAuthView(account: account)
        case .onboarding: WyrmOnboardingView(account: account, engine: engine)
        case .signedIn: EmptyView()
        }
    }
}

private struct WyrmAccountLoading: View {
    var body: some View {
        ZStack {
            ATheme.paper.ignoresSafeArea()
            VStack(spacing: 14) {
                WyrmAccountMark(text: "W")
                Text("OPENING YOUR DEN").font(.androidWyrm(11, .bold)).tracking(1.8).foregroundColor(ATheme.quiet)
                ProgressView().tint(ATheme.ink)
            }
        }
    }
}

private enum WyrmAuthRoute { case welcome, create, login }

private struct WyrmAuthView: View {
    @ObservedObject var account: WyrmAccountStore
    @State private var route: WyrmAuthRoute = .welcome
    @State private var displayName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        ZStack {
            ATheme.paper.ignoresSafeArea()
            Circle().fill(ATheme.live.opacity(0.10)).frame(width: 360, height: 360).blur(radius: 3).offset(x: 150, y: -310)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { WyrmAccountMark(text: "W"); Spacer(); Text("IOS / ACCOUNT").font(.androidWyrm(10.5, .bold)).tracking(1.6).foregroundColor(ATheme.quiet) }
                    .padding(.top, 28)
                    Spacer().frame(height: route == .welcome ? 104 : 54)
                    Text(route == .welcome ? "The arena,\nand your place in it." : route == .create ? "Make your\nWyrm identity." : "Welcome\nback.")
                        .font(.androidWyrm(40, .bold)).tracking(-1.4).lineSpacing(-4)
                    Text(route == .welcome ? "One profile for your arena name, scores and people. No Google account required." : route == .create ? "Choose a username you will remember. There is no email recovery yet." : "Use the username and password you created.")
                        .font(.androidWyrm(14)).foregroundColor(ATheme.mute).lineSpacing(4).padding(.top, 18)
                    if route != .welcome {
                        VStack(spacing: 12) {
                            if route == .create { WyrmField(title: "DISPLAY NAME", text: $displayName, placeholder: "What people call you") }
                            WyrmField(title: "USERNAME", text: $username, placeholder: "letters_numbers")
                            WyrmSecureField(title: "PASSWORD", text: $password, placeholder: "At least 8 characters")
                            if route == .create { WyrmSecureField(title: "CONFIRM PASSWORD", text: $confirm, placeholder: "Type it again") }
                        }.padding(.top, 28)
                    }
                    if !account.errorMessage.isEmpty {
                        Text(account.errorMessage).font(.androidWyrm(12.5, .semibold)).foregroundColor(.red).padding(.top, 14)
                    }
                    VStack(spacing: 10) {
                        if route == .welcome {
                            WyrmPrimaryButton("CREATE ACCOUNT", busy: false) { route = .create }
                            WyrmOutlineButton("I ALREADY HAVE ONE") { route = .login }
                        } else {
                            WyrmPrimaryButton(route == .create ? "CREATE & CONTINUE" : "SIGN IN", busy: account.busy) { submit() }
                            WyrmOutlineButton("BACK") { account.errorMessage = ""; route = .welcome }
                        }
                    }.padding(.top, 24)
                }.padding(.horizontal, 24).padding(.bottom, 40)
            }
        }.foregroundColor(ATheme.ink)
    }

    private func submit() {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if route == .create {
            let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanName.count >= 2, cleanUser.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil,
                  password.count >= 8, password == confirm else {
                account.errorMessage = "Use a 2+ character name, a 3–20 character username, and matching 8+ character passwords."
                return
            }
            Task { await account.signUp(displayName: cleanName, username: cleanUser, password: password) }
        } else {
            guard !cleanUser.isEmpty, !password.isEmpty else { account.errorMessage = "Enter your username and password."; return }
            Task { await account.login(username: cleanUser, password: password) }
        }
    }
}

private struct WyrmOnboardingView: View {
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var engine: WyrmShellStore
    @State private var page = 0
    @State private var steering = 0

    private let titles = ["Welcome to Wyrm", "This is your name", "Choose your steering", "Your skin stays yours", "Two ways to play", "Ready for the arena"]
    private let notes = [
        "Your backend profile is live. Let’s set up the iPhone around the original engine.",
        "This identity follows your scores, messages and friends—not the phone.",
        "You can change every control later in Settings.",
        "Skin Studio stays untouched for now. The engine keeps its current skin until we wire the editor properly.",
        "Original mode keeps the classic rules. Assist mode can be tuned from Settings whenever you want.",
        "The shell is portrait; lobby and arena rotate inside it while iOS stays stable.",
    ]

    var body: some View {
        ZStack {
            ATheme.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SETUP \(page + 1) / 6").font(.androidWyrm(11, .bold)).tracking(1.4).foregroundColor(ATheme.quiet)
                    Spacer()
                    HStack(spacing: 5) { ForEach(0..<6) { Circle().fill($0 <= page ? ATheme.ink : ATheme.rule).frame(width: 6, height: 6) } }
                }
                Spacer()
                WyrmAccountMark(text: page == 1 ? (account.player?.initials ?? "W") : "W")
                Text(titles[page]).font(.androidWyrm(35, .bold)).tracking(-1).padding(.top, 22)
                Text(notes[page]).font(.androidWyrm(14)).foregroundColor(ATheme.mute).lineSpacing(4).padding(.top, 12)
                if page == 1, let player = account.player {
                    VStack(alignment: .leading, spacing: 5) { Text(player.displayName).font(.androidWyrm(22, .bold)); Text(player.handle).font(.androidWyrm(14)).foregroundColor(ATheme.quiet) }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.white).cornerRadius(18).padding(.top, 24)
                }
                if page == 2 {
                    HStack(spacing: 8) {
                        ForEach(Array(["Dynamic", "Fixed", "Arrow"].enumerated()), id: \.offset) { index, title in
                            Button { steering = index } label: { Text(title).font(.androidWyrm(12, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14).background(steering == index ? ATheme.ink : Color.white).foregroundColor(steering == index ? .white : ATheme.ink).cornerRadius(13) }.buttonStyle(.plain)
                        }
                    }.padding(.top, 24)
                }
                Spacer()
                WyrmPrimaryButton(page == 5 ? "ENTER WYRM" : "CONTINUE", busy: false) { advance() }
                if page > 0 { Button("Back") { page -= 1 }.font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.quiet).frame(maxWidth: .infinity).padding(.top, 14) }
            }.padding(.horizontal, 24).padding(.vertical, 28)
        }.foregroundColor(ATheme.ink)
    }

    private func advance() {
        if page == 2, let row = engine.settings.first(where: { $0.id == "controls.joystick_mode" }) {
            engine.write(row, values: [Double(steering)])
        }
        if page == 5 { account.finishOnboarding() } else { withAnimation(.easeOut(duration: 0.22)) { page += 1 } }
    }
}

struct WyrmProfileView: View {
    @ObservedObject var account: WyrmAccountStore
    @Environment(\.presentationMode) private var presentation
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                if let player = account.player {
                    WyrmAccountMark(text: player.initials).padding(.top, 24)
                    VStack(spacing: 3) { Text(player.displayName).font(.androidWyrm(27, .bold)); Text(player.handle).font(.androidWyrm(13)).foregroundColor(ATheme.quiet); Text(player.bio.isEmpty ? "No bio yet" : player.bio).font(.androidWyrm(13)).foregroundColor(ATheme.mute).padding(.top, 6) }
                    HStack(spacing: 0) {
                        WyrmProfileStat(value: "\(player.highestScore)", label: "BEST")
                        WyrmProfileStat(value: "\(player.kills)", label: "KILLS")
                        WyrmProfileStat(value: "\(player.followerCount)", label: "FOLLOWERS")
                    }.background(Color.white).cornerRadius(16)
                    WyrmPrimaryButton("EDIT PROFILE", busy: false) { editing = true }
                    WyrmOutlineButton("SIGN OUT") { account.signOut(); presentation.wrappedValue.dismiss() }
                    Button("Delete account") { confirmDelete = true }.font(.androidWyrm(13, .semibold)).foregroundColor(.red).padding(.top, 6)
                }
                if !account.errorMessage.isEmpty { Text(account.errorMessage).font(.androidWyrm(12)).foregroundColor(.red) }
            }.padding(.horizontal, 20).padding(.bottom, 34)
        }
        .background(ATheme.paper.ignoresSafeArea())
        .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { if let player = account.player { WyrmProfileEditor(account: account, player: player) } }
        .alert("Delete this Wyrm account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await account.deleteAccount(); presentation.wrappedValue.dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This closes the account and cannot be undone from the app.") }
    }
}

private struct WyrmProfileEditor: View {
    @ObservedObject var account: WyrmAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var ingameName: String
    @State private var username: String
    @State private var bio: String
    @State private var avatarKey: String

    init(account: WyrmAccountStore, player: WyrmPlayer) {
        self.account = account
        _displayName = State(initialValue: player.displayName)
        _ingameName = State(initialValue: player.ingameName ?? "")
        _username = State(initialValue: player.username ?? "")
        _bio = State(initialValue: player.bio)
        _avatarKey = State(initialValue: player.avatarKey)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    WyrmField(title: "DISPLAY NAME", text: $displayName, placeholder: "Display name")
                    WyrmField(title: "ARENA NAME", text: $ingameName, placeholder: "3–20 letters, numbers or _")
                    WyrmField(title: "USERNAME", text: $username, placeholder: "Username")
                    WyrmField(title: "BIO", text: $bio, placeholder: "150 characters max")
                    if !account.errorMessage.isEmpty { Text(account.errorMessage).font(.androidWyrm(12)).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading) }
                    WyrmPrimaryButton("SAVE PROFILE", busy: account.busy) {
                        Task { if await account.update(displayName: displayName, ingameName: ingameName, username: username, bio: bio, avatarKey: avatarKey) { dismiss() } }
                    }
                }.padding(20)
            }.background(ATheme.paper).navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct WyrmField: View {
    let title: String; @Binding var text: String; let placeholder: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.androidWyrm(10.5, .bold)).tracking(1).foregroundColor(ATheme.quiet); TextField(placeholder, text: $text).font(.androidWyrm(15)).textInputAutocapitalization(.never).disableAutocorrection(true).padding(14).background(Color.white).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)) } }
}

private struct WyrmSecureField: View {
    let title: String; @Binding var text: String; let placeholder: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.androidWyrm(10.5, .bold)).tracking(1).foregroundColor(ATheme.quiet); SecureField(placeholder, text: $text).font(.androidWyrm(15)).textContentType(.password).padding(14).background(Color.white).cornerRadius(13).overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule)) } }
}

private struct WyrmAccountMark: View {
    let text: String
    var body: some View { Text(text).font(.androidWyrm(22, .bold)).foregroundColor(.white).frame(width: 58, height: 58).background(ATheme.ink).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)) }
}

private struct WyrmProfileStat: View {
    let value: String; let label: String
    var body: some View { VStack(spacing: 4) { Text(value).font(.androidWyrm(18, .bold)); Text(label).font(.androidWyrm(9.5, .bold)).tracking(0.8).foregroundColor(ATheme.quiet) }.frame(maxWidth: .infinity).padding(.vertical, 16) }
}

private struct WyrmPrimaryButton: View {
    let title: String; let busy: Bool; let action: () -> Void
    init(_ title: String, busy: Bool, action: @escaping () -> Void) { self.title = title; self.busy = busy; self.action = action }
    var body: some View { Button(action: action) { HStack { Text(busy ? "PLEASE WAIT" : title).font(.androidWyrm(13, .bold)).tracking(1.1); Spacer(); if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.right") } }.foregroundColor(.white).padding(.horizontal, 18).frame(height: 54).background(ATheme.ink).cornerRadius(15) }.buttonStyle(.plain).disabled(busy) }
}

private struct WyrmOutlineButton: View {
    let title: String; let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { Button(action: action) { Text(title).font(.androidWyrm(12.5, .bold)).tracking(0.8).frame(maxWidth: .infinity).frame(height: 52).background(Color.white).foregroundColor(ATheme.ink).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(ATheme.rule)) }.buttonStyle(.plain) }
}
