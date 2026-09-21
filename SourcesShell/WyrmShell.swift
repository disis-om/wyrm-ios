import SwiftUI
import UIKit
import CoreText

private let paper = Color(red: 0.969, green: 0.965, blue: 0.953)
private let ink = Color(red: 0.216, green: 0.208, blue: 0.184)
private let quiet = Color(red: 0.47, green: 0.46, blue: 0.43)
private let live = Color(red: 0.27, green: 0.52, blue: 0.38)
private let card = Color.white
private let rule = ink.opacity(0.09)

private extension Font {
    static func wyrm(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", size: size).weight(weight)
    }
}

private enum WyrmFontLoader {
    static func register() {
        guard let url = Bundle.main.url(forResource: "manrope", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

private func copiedCString(_ pointer: UnsafePointer<CChar>?) -> String {
    guard let pointer = pointer else { return "" }
    return String(cString: pointer)
}

struct EngineSetting: Identifiable, Equatable {
    let id: String
    let group: String
    let type: String
    let label: String
    let hint: String
    var values: [Double]
    let minimum: Double
    let maximum: Double
    let options: [String]

    var displayValue: String {
        switch type {
        case "bool": return (values.first ?? 0) != 0 ? "On" : "Off"
        case "enum":
            let index = Int(values.first ?? 0)
            return options.indices.contains(index) ? options[index] : "\(index)"
        case "int": return "\(Int(values.first ?? 0))"
        case "color3", "color4": return "Colour"
        default: return String(format: "%.2f", values.first ?? 0)
        }
    }
}

struct EngineHotkey: Identifiable, Equatable {
    let id: Int
    let name: String
    let key: Int
    let keyName: String
    let mode: Int
    let fixedMode: Bool
    var visible: Bool
    let x: Double
    let y: Double
}

@MainActor
final class WyrmShellStore: ObservableObject {
    @Published var nickname = "Wyrm Player"
    @Published var arena = ""
    @Published var score = 0
    @Published var kills = 0
    @Published var settings: [EngineSetting] = []
    @Published var hotkeys: [EngineHotkey] = []
    @Published var settingsVersion = ""
    @Published var toast = ""
    @Published private(set) var arenaRefusalSequence: UInt64 = 0
    @Published private(set) var refusedArena = ""
    @Published private(set) var refusedArenaSeconds = 0
    private var timer: Timer?

    init() {
        WyrmDiagnostics.record("SwiftUI shell store started", category: "LIFECYCLE")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--smoke-settings-write") {
            verifySmokeSettingsWrite(attemptsRemaining: 20)
        }
        if args.contains("--smoke-arena-refusal") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                "127.0.0.1:444".withCString { WyrmIOSPublishArenaRefusal($0, 120) }
                self?.refresh()
            }
        }
    }

    /// Release builds intentionally initialize the atlas and Vulkan renderer
    /// away from UIKit's launch runloop. The settings mailbox becomes ready at
    /// the end of that bootstrap, so the smoke probe waits for real data rather
    /// than racing a fixed one-second deadline.
    private func verifySmokeSettingsWrite(attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.refresh()
            if let row = self.settings.first(where: { $0.id == "general.minimap_size" }) {
                self.write(row, values: row.values)
                NSLog("Wyrm SwiftUI settings bridge verified rows=%d id=%@", self.settings.count, row.id)
            } else if attemptsRemaining > 1 {
                self.verifySmokeSettingsWrite(attemptsRemaining: attemptsRemaining - 1)
            } else {
                NSLog("Wyrm SwiftUI settings bridge unavailable after bootstrap wait")
            }
        }
    }

    func refresh() {
        let home = copiedCString(WyrmIOSHomeSnapshot())
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if home.count >= 4 {
            nickname = home[0].isEmpty ? "Wyrm Player" : home[0]
            arena = home[1]
            score = Int(home[2]) ?? 0
            kills = Int(home[3]) ?? 0
        }
        let refusal = copiedCString(WyrmIOSArenaRefusalSnapshot())
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if refusal.count >= 3, let sequence = UInt64(refusal[0]), sequence > arenaRefusalSequence {
            arenaRefusalSequence = sequence
            refusedArena = refusal[1]
            refusedArenaSeconds = Int(refusal[2]) ?? 120
            WyrmDiagnostics.record(
                "arena refusal bridge sequence=\(sequence) endpoint=\(refusedArena) taint=\(refusedArenaSeconds)s",
                category: "NETWORK"
            )
            if ProcessInfo.processInfo.arguments.contains("--smoke-arena-refusal") {
                NSLog("Wyrm arena refusal bridge verified sequence=%llu endpoint=%@ taint=%ds",
                      sequence, refusedArena, refusedArenaSeconds)
            }
        }
        settingsVersion = copiedCString(WyrmIOSSettingsVersion())
        settings = Self.parseSettings(copiedCString(WyrmIOSSettingsSnapshot()))
        hotkeys = Self.parseHotkeys(copiedCString(WyrmIOSHotkeysSnapshot()))
    }

    func enterLobby(name: String, address: String) {
        WyrmDiagnostics.record("lobby requested address=\(address.isEmpty ? "automatic" : "manual")", category: "ENGINE")
        name.withCString { namePointer in
            address.withCString { addressPointer in WyrmIOSRequestLobby(namePointer, addressPointer) }
        }
    }

    func playOnline(name: String, address: String) {
        guard !address.isEmpty else { return }
        WyrmDiagnostics.record("online failover requested address=alternate", category: "ENGINE")
        name.withCString { namePointer in
            address.withCString { addressPointer in WyrmIOSRequestPlay(namePointer, addressPointer, false) }
        }
    }

    func playOffline(name: String) {
        WyrmDiagnostics.record("offline practice requested", category: "ENGINE")
        name.withCString { namePointer in
            "".withCString { empty in WyrmIOSRequestPlay(namePointer, empty, true) }
        }
    }

    func write(_ setting: EngineSetting, values: [Double]) {
        let v = values + Array(repeating: 0, count: max(0, 4 - values.count))
        let accepted = setting.id.withCString {
            WyrmIOSQueueSetting($0, Float(v[0]), Float(v[1]), Float(v[2]), Float(v[3]), Int32(values.count))
        }
        if !accepted { toast = "Engine is still starting" }
        WyrmDiagnostics.record("setting queued id=\(setting.id) accepted=\(accepted)", category: "ENGINE")
    }

    func setHotkey(_ hotkey: EngineHotkey, visible: Bool) {
        if !WyrmIOSQueueHotkey(Int32(hotkey.id), Int32(hotkey.key), Int32(hotkey.mode),
                               visible, Float(hotkey.x), Float(hotkey.y)) {
            toast = "Engine is still starting"
        }
        WyrmDiagnostics.record("hotkey queued id=\(hotkey.id) visible=\(visible)", category: "ENGINE")
    }

    func reset(_ mask: Int32, message: String) {
        WyrmIOSSettingsAction(mask)
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
    }

    private static func parseSettings(_ text: String) -> [EngineSetting] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 9 else { return nil }
            return EngineSetting(id: f[0], group: f[1], type: f[2], label: f[3], hint: f[4],
                                 values: f[5].split(separator: ",").compactMap { Double($0) },
                                 minimum: Double(f[6]) ?? 0, maximum: Double(f[7]) ?? 1,
                                 options: f[8].split(separator: "|").map(String.init))
        }
    }

    private static func parseHotkeys(_ text: String) -> [EngineHotkey] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 9, let action = Int(f[0]) else { return nil }
            return EngineHotkey(id: action, name: f[1], key: Int(f[2]) ?? 0, keyName: f[3],
                                mode: Int(f[4]) ?? 0, fixedMode: f[5] == "1", visible: f[6] == "1",
                                x: Double(f[7]) ?? 0.5, y: Double(f[8]) ?? 0.22)
        }
    }
}

private enum ShellTab: String, CaseIterable {
    case notifications = "Notifications", social = "Social", play = "Play", skin = "Skin", settings = "Settings"
}

struct WyrmShellRoot: View {
    @StateObject private var store = WyrmShellStore()
    @State private var tab: ShellTab = ProcessInfo.processInfo.arguments.contains("--smoke-settings") ? .settings : .play

    var body: some View {
        ZStack(alignment: .bottom) {
            paper.ignoresSafeArea()
            Group {
                switch tab {
                case .play: PlayRoot(store: store)
                case .notifications: EmptyRoot(title: "Notifications", symbol: "bell", message: "You’re all caught up. Real invites and system notices will appear here when services are connected.")
                case .social: EmptyRoot(title: "Social", symbol: "person.2", message: "No signed-in social session yet. The engine stays playable without an account.")
                case .skin: EmptyRoot(title: "Skin", symbol: "circle.hexagongrid", message: "Skin Studio is intentionally not wired in this build. Your existing engine skins remain untouched.")
                case .settings: SettingsRoot(store: store)
                }
            }.padding(.bottom, 68)
            ShellTabBar(selection: $tab).zIndex(20)
            if !store.toast.isEmpty {
                Text(store.toast).font(.wyrm(12, .bold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10).background(ink).cornerRadius(12)
                    .padding(.bottom, 78).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundColor(ink)
        .onChange(of: store.toast) { value in
            guard !value.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { if store.toast == value { store.toast = "" } }
            }
        }
    }
}

private struct PageTitle: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("WYRM / IOS").font(.wyrm(11, .bold)).tracking(1.7).foregroundColor(quiet)
            Text(title).font(.wyrm(30, .bold))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
    }
}

private struct PlayRoot: View {
    @ObservedObject var store: WyrmShellStore
    @State private var name = ""
    @State private var address = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                PageTitle(title: "Play")
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 7) { Circle().fill(live).frame(width: 7, height: 7); Text("ORIGINAL ENGINE READY").font(.wyrm(11, .bold)).foregroundColor(live) }
                    TextField("In-game name", text: $name).font(.wyrm(23, .bold))
                        .textInputAutocapitalization(.never).disableAutocorrection(true)
                    TextField("Arena IP or host", text: $address).font(.wyrm(13))
                        .textInputAutocapitalization(.never).disableAutocorrection(true)
                        .padding(12).background(paper).cornerRadius(10)
                    Button {
                        store.enterLobby(name: cleanName, address: address.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        HStack { Text("ENTER LOBBY"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.wyrm(15, .bold)).padding(.horizontal, 16).frame(height: 50)
                            .background(ink).foregroundColor(.white).cornerRadius(12)
                    }
                    Button { store.playOffline(name: cleanName) } label: {
                        HStack { Image(systemName: "airplane"); Text("PRACTICE OFFLINE"); Spacer(); Text("AI") }
                            .font(.wyrm(12, .bold)).padding(.horizontal, 16).frame(height: 46)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(rule))
                    }.buttonStyle(.plain)
                }.padding(18).background(card).cornerRadius(18).overlay(RoundedRectangle(cornerRadius: 18).stroke(rule)).padding(.horizontal, 16)

                Text("ENGINE RECORD").font(.wyrm(11, .bold)).tracking(1.2).foregroundColor(quiet)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 8)
                HStack(spacing: 0) {
                    Metric(label: "BEST SCORE", value: "\(store.score)")
                    Divider().frame(height: 45)
                    Metric(label: "TOTAL KILLS", value: "\(store.kills)")
                }.padding(.vertical, 8).background(card).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(rule)).padding(.horizontal, 16)

                Text("The lobby and arena keep Android’s exact native renderer, protocol, leaderboard, HUD and snake simulation. iOS stays portrait; only that engine surface rotates.")
                    .font(.wyrm(12)).foregroundColor(quiet).fixedSize(horizontal: false, vertical: true).padding(20)
            }
        }
        .onAppear {
            if name.isEmpty { name = store.nickname }
            if address.isEmpty { address = store.arena }
        }
    }

    private var cleanName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Wyrm Player" : String(value.prefix(24))
    }
}

private struct Metric: View {
    let label: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 2) { Text(label).font(.wyrm(10, .bold)).foregroundColor(quiet); Text(value).font(.wyrm(18, .bold)) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16) }
}

private struct EmptyRoot: View {
    let title: String, symbol: String, message: String
    var body: some View { VStack { PageTitle(title: title); Spacer(); Image(systemName: symbol).font(.system(size: 48, weight: .ultraLight)).foregroundColor(quiet); Text(message).font(.wyrm(14)).foregroundColor(quiet).multilineTextAlignment(.center).padding(.horizontal, 42).padding(.top, 12); Spacer() } }
}

private struct SettingsRoot: View {
    @ObservedObject var store: WyrmShellStore
    @State private var resetArmed = false

    private var groups: [(String, [EngineSetting])] {
        Dictionary(grouping: store.settings.filter { !$0.id.hasPrefix("tags.") }, by: { $0.group })
            .map { ($0.key, $0.value) }.sorted { friendly($0.0) < friendly($1.0) }
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    PageTitle(title: "Settings")
                    if store.settings.isEmpty {
                        ProgressView().padding(40)
                    } else {
                        SettingsCard {
                            ForEach(groups.indices, id: \.self) { index in
                                let group = groups[index]
                                NavigationLink(destination: SettingsGroup(store: store, title: friendly(group.0), rows: group.1)) {
                                    SettingsHubRow(title: friendly(group.0), detail: "\(group.1.count) engine controls")
                                }.buttonStyle(.plain)
                            }
                            NavigationLink(destination: HotkeySettings(store: store)) {
                                SettingsHubRow(title: "On-screen buttons", detail: "\(store.hotkeys.count) original actions")
                            }.buttonStyle(.plain)
                        }.padding(.horizontal, 16)
                    }
                    Text("ENGINE").font(.wyrm(11, .bold)).tracking(1.2).foregroundColor(quiet)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 8)
                    SettingsCard {
                        ActionRow(title: "Reset controls layout") { store.reset(2, message: "Controls reset") }
                        ActionRow(title: "Reset button layout") { store.reset(4, message: "Buttons reset") }
                        ActionRow(title: "Reset arena HUD positions") { store.reset(8, message: "HUD reset") }
                        ActionRow(title: resetArmed ? "Tap again: reset everything" : "Reset everything to defaults", destructive: true) {
                            if resetArmed { store.reset(1, message: "All engine settings reset"); resetArmed = false }
                            else { resetArmed = true }
                        }
                    }.padding(.horizontal, 16)
                    Text("Wyrm 0.5.0 · build 26 · settings \(store.settingsVersion)").font(.wyrm(11)).foregroundColor(quiet).padding(20)
                }
            }.background(paper.ignoresSafeArea()).navigationBarHidden(true)
        }.navigationViewStyle(StackNavigationViewStyle())
    }

    private func friendly(_ group: String) -> String {
        let names = ["general":"Display & arena", "controls":"Controls", "keys":"On-screen controls", "normal":"Normal mode", "assist":"Assist mode", "bot":"Bot", "accessibility":"Accessibility", "food":"Food"]
        return names[group] ?? group.replacingOccurrences(of: ".", with: " · ").capitalized
    }
}

private struct SettingsGroup: View {
    @ObservedObject var store: WyrmShellStore
    let title: String
    let rows: [EngineSetting]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(rows) { row in SettingControl(store: store, row: row) }
            }.padding(16)
        }.background(paper.ignoresSafeArea()).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingControl: View {
    @ObservedObject var store: WyrmShellStore
    let row: EngineSetting
    @State private var scalar: Double
    @State private var color: Color

    init(store: WyrmShellStore, row: EngineSetting) {
        self.store = store; self.row = row
        _scalar = State(initialValue: row.values.first ?? 0)
        let v = row.values + [0, 0, 0, 1]
        _color = State(initialValue: Color(red: v[0], green: v[1], blue: v[2], opacity: row.type == "color4" ? v[3] : 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text(row.label).font(.wyrm(15, .semibold)); if !row.hint.isEmpty { Text(row.hint).font(.wyrm(11)).foregroundColor(quiet).fixedSize(horizontal: false, vertical: true) } }; Spacer(); control }
            if row.type == "float" || row.type == "int" {
                Slider(value: Binding(get: { scalar }, set: { value in scalar = value; store.write(row, values: [value]) }), in: row.minimum...row.maximum, step: row.type == "int" ? 1 : max(0.001, (row.maximum-row.minimum)/100)).tint(ink)
            }
        }.padding(15).background(card).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(rule))
    }

    @ViewBuilder private var control: some View {
        switch row.type {
        case "bool":
            Toggle("", isOn: Binding(get: { scalar != 0 }, set: { scalar = $0 ? 1 : 0; store.write(row, values: [scalar]) })).labelsHidden().tint(live)
        case "enum":
            Picker("", selection: Binding(get: { Int(scalar) }, set: { scalar = Double($0); store.write(row, values: [scalar]) })) {
                ForEach(row.options.indices, id: \.self) { index in Text(row.options[index]).tag(index) }
            }.pickerStyle(.menu).tint(ink)
        case "color3", "color4":
            ColorPicker("", selection: Binding(get: { color }, set: { newColor in
                color = newColor
                guard let components = UIColor(newColor).cgColor.components else { return }
                let values = components.count >= 3 ? [components[0], components[1], components[2], components.count > 3 ? components[3] : 1] : [components[0], components[0], components[0], 1]
                store.write(row, values: values.prefix(row.type == "color4" ? 4 : 3).map(Double.init))
            }), supportsOpacity: row.type == "color4").labelsHidden()
        default:
            Text(row.type == "int" ? "\(Int(scalar))" : String(format: "%.2f", scalar)).font(.wyrm(13, .bold)).foregroundColor(quiet)
        }
    }
}

private struct HotkeySettings: View {
    @ObservedObject var store: WyrmShellStore
    var body: some View {
        ScrollView { VStack(spacing: 10) {
            ForEach(store.hotkeys) { hotkey in
                Toggle(isOn: Binding(get: { hotkey.visible }, set: { store.setHotkey(hotkey, visible: $0) })) {
                    VStack(alignment: .leading, spacing: 2) { Text(hotkey.name).font(.wyrm(15, .semibold)); Text("\(hotkey.keyName) · \(hotkey.fixedMode ? (hotkey.mode == 1 ? "Hold" : "Press") : (hotkey.mode == 1 ? "Hold" : "Toggle"))").font(.wyrm(11)).foregroundColor(quiet) }
                }.tint(live).padding(15).background(card).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(rule))
            }
        }.padding(16) }.background(paper.ignoresSafeArea()).navigationTitle("On-screen buttons").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(spacing: 0) { content }.background(card).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(rule)) }
}

private struct SettingsHubRow: View {
    let title: String, detail: String
    var body: some View { HStack { VStack(alignment: .leading, spacing: 2) { Text(title).font(.wyrm(15, .semibold)); Text(detail).font(.wyrm(11)).foregroundColor(quiet) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(quiet.opacity(0.5)) }.padding(.horizontal, 15).frame(minHeight: 57).overlay(Rectangle().fill(rule).frame(height: 1).padding(.leading, 15), alignment: .bottom) }
}

private struct ActionRow: View {
    let title: String
    var destructive = false
    let action: () -> Void
    var body: some View { Button(action: action) { Text(title).font(.wyrm(14, .semibold)).foregroundColor(destructive ? .red : ink).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).frame(minHeight: 50).overlay(Rectangle().fill(rule).frame(height: 1).padding(.leading, 15), alignment: .bottom) }.buttonStyle(.plain) }
}

private struct ShellTabBar: View {
    @Binding var selection: ShellTab
    private let icons: [ShellTab:String] = [.notifications:"bell", .social:"person.2", .play:"play.circle", .skin:"circle.hexagongrid", .settings:"slider.horizontal.3"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ShellTab.allCases, id: \.self) { item in
                Button { withAnimation(.easeOut(duration: 0.18)) { selection = item } } label: {
                    VStack(spacing: 3) { Image(systemName: icons[item]!).font(.system(size: item == .play ? 24 : 20, weight: selection == item ? .semibold : .regular)); Text(item.rawValue).font(.wyrm(9, selection == item ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.7) }
                        .foregroundColor(selection == item ? ink : quiet).frame(maxWidth: .infinity).padding(.top, 8)
                }.buttonStyle(.plain)
            }
        }.frame(height: 68).background(Color.white.opacity(0.96)).overlay(Divider(), alignment: .top).ignoresSafeArea(edges: .bottom)
    }
}

@objc(WyrmShellHost)
final class WyrmShellHost: NSObject {
    @objc static func makeViewController() -> UIViewController {
        WyrmFontLoader.register()
        NSLog("Wyrm SwiftUI shell installed")
        return UIHostingController(rootView: WyrmDesignRoot())
    }
}
