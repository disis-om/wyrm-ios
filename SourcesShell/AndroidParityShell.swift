import SwiftUI
import UIKit

private enum ATheme {
    static let paper = Color(red: 247/255, green: 246/255, blue: 243/255)
    static let card = Color.white
    static let ink = Color(red: 55/255, green: 53/255, blue: 47/255)
    static let onInk = Color.white
    static let quiet = Color(red: 120/255, green: 119/255, blue: 116/255)
    static let mute = Color(red: 107/255, green: 102/255, blue: 96/255)
    static let rule = ATheme.ink.opacity(0.078)
    static let rowRule = ATheme.ink.opacity(0.071)
    static let live = Color(red: 68/255, green: 131/255, blue: 97/255)
    static let link = Color(red: 47/255, green: 111/255, blue: 222/255)
    static let tabIdle = Color(red: 124/255, green: 119/255, blue: 111/255)
    static let tabBar = Color(red: 252/255, green: 251/255, blue: 250/255).opacity(0.94)
    static let chevron = Color(red: 198/255, green: 193/255, blue: 184/255)
    static let well = Color(red: 240/255, green: 238/255, blue: 233/255)
    static let track = Color(red: 239/255, green: 237/255, blue: 232/255)
}

private extension Font {
    static func androidWyrm(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Manrope", size: size).weight(weight)
    }
}

private enum AndroidRootTab: String, CaseIterable {
    case notifications = "Notifications", social = "Social", play = "Play", skin = "Skin", settings = "Settings"
}

private enum SettingsDestination: String, Identifiable {
    case display = "Display", controls = "Controls", buttons = "On-screen buttons"
    case modes = "Modes", bot = "Bot", food = "Food style"
    case profile = "Profile", notificationSettings = "Notifications", privacy = "Privacy"
    case themes = "Themes", backup = "Backup & version"
    var id: String { rawValue }
}

struct WyrmAndroidParityRoot: View {
    @StateObject private var store = WyrmShellStore()
    @State private var tab: AndroidRootTab = ProcessInfo.processInfo.arguments.contains("--smoke-settings") ? .settings : .play
    @State private var settingsDestination: SettingsDestination?

    var body: some View {
        GeometryReader { viewport in
            ZStack(alignment: .bottom) {
                ATheme.paper.ignoresSafeArea()
                if let destination = settingsDestination {
                    AndroidSettingsDestination(store: store, destination: destination) { settingsDestination = nil }
                        .frame(width: viewport.size.width)
                        .zIndex(30)
                } else {
                    Group {
                        switch tab {
                        case .play:
                            AndroidPlayPage(store: store, openSettings: openSettings)
                        case .notifications:
                            AndroidNotificationsPage()
                        case .social:
                            AndroidSocialPage()
                        case .skin:
                            AndroidSkinPlaceholder()
                        case .settings:
                            AndroidSettingsPage(store: store, open: openSettings)
                        }
                    }
                    .frame(width: viewport.size.width)
                    .padding(.bottom, 70)
                    AndroidRootTabs(selection: $tab)
                        .frame(width: viewport.size.width)
                        .zIndex(20)
                }
                if !store.toast.isEmpty {
                    Text(store.toast).font(.androidWyrm(12, .bold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10).background(ATheme.ink).cornerRadius(12)
                        .padding(.bottom, settingsDestination == nil ? 80 : 18).zIndex(50)
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
            .clipped()
        }
        .foregroundColor(ATheme.ink)
        .onChange(of: store.toast) { value in
            guard !value.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { if store.toast == value { store.toast = "" } }
            }
        }
    }

    private func openSettings(_ destination: SettingsDestination) {
        tab = .settings
        settingsDestination = destination
    }
}

private struct AndroidPlayPage: View {
    @ObservedObject var store: WyrmShellStore
    let openSettings: (SettingsDestination) -> Void
    @State private var nickname = ""
    @State private var arena = ""

    private var controlsValue: String { store.settings.first(where: { $0.id == "controls.joystick_mode" })?.displayValue ?? "Joystick" }
    private var foodValue: String { store.settings.first(where: { $0.id == "normal.food_type" })?.displayValue ?? "Original" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wyrm").font(.androidWyrm(11.5, .bold)).tracking(0.9).foregroundColor(ATheme.quiet)
                        TextField("Wyrm Player", text: $nickname).font(.androidWyrm(30, .bold))
                            .textInputAutocapitalization(.never).disableAutocorrection(true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Guest player").font(.androidWyrm(13, .bold))
                        Text("Offline profile").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
                    }
                    Text(initials).font(.androidWyrm(11, .bold)).foregroundColor(.white)
                        .frame(width: 36, height: 36).background(ATheme.ink).cornerRadius(11)
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 7) {
                            Circle().fill(arena.isEmpty ? ATheme.quiet : ATheme.live).frame(width: 6, height: 6)
                            Text(arena.isEmpty ? "SELECT AN ARENA" : "NEAREST ARENA").font(.androidWyrm(11.5, .bold)).tracking(0.8).foregroundColor(arena.isEmpty ? ATheme.quiet : ATheme.live)
                        }
                        HStack(alignment: .bottom) {
                            Text(arena.isEmpty ? "Pick a server" : arena).font(.androidWyrm(21, .bold)).lineLimit(1)
                            Spacer()
                        }.padding(.top, 10)
                        Text(arena.isEmpty ? "Pick a server to enter" : "Waiting on the directory")
                            .font(.androidWyrm(13.5)).foregroundColor(ATheme.mute).padding(.top, 4)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(ATheme.track)
                                Capsule().fill(ATheme.ink).frame(width: proxy.size.width * (arena.isEmpty ? 0.02 : 0.18))
                            }
                        }.frame(height: 4).padding(.top, 12)
                        HStack(spacing: 9) {
                            Button { store.enterLobby(name: cleanName, address: arena) } label: {
                                Text("Enter lobby").font(.androidWyrm(15.5, .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).frame(height: 46).background(ATheme.ink).cornerRadius(11)
                            }
                            Button { store.toast = "Edit the server below" } label: {
                                Image(systemName: "globe").font(.system(size: 18)).foregroundColor(ATheme.mute)
                                    .frame(width: 46, height: 46).overlay(RoundedRectangle(cornerRadius: 11).stroke(ATheme.rule))
                            }
                        }.padding(.top, 16)
                    }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 16)
                    Rectangle().fill(ATheme.rule).frame(height: 1)
                    HStack(spacing: 0) {
                        AndroidStatCell(label: "BEST SCORE", value: "\(store.score)")
                        Rectangle().fill(ATheme.rule).frame(width: 1, height: 52)
                        AndroidStatCell(label: "TOTAL KILLS", value: "\(store.kills)")
                    }
                }.background(ATheme.card).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(ATheme.rule)).padding(.horizontal, 16)

                AndroidSectionLabel("Loadout")
                AndroidGroupedCard {
                    AndroidIndexRow(icon: "circle.hexagongrid.fill", title: "Food", value: foodValue, first: true) { openSettings(.food) }
                    AndroidIndexRow(icon: "gamecontroller.fill", title: "Controls", value: controlsValue) { openSettings(.controls) }
                    AndroidIndexRow(icon: "scope", title: "Mode") { openSettings(.modes) }
                }

                AndroidSectionLabel("Rooms & team")
                AndroidGroupedCard {
                    AndroidDoubleRow(title: "Your public room", detail: "None yet", first: true) { store.toast = "Voice services are not connected yet" }
                    VStack(spacing: 0) {
                        Rectangle().fill(ATheme.rowRule).frame(height: 1)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pick a server").font(.androidWyrm(15.5))
                            TextField("IP address or host", text: $arena).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                                .textInputAutocapitalization(.never).disableAutocorrection(true)
                        }.padding(.horizontal, 14).frame(minHeight: 58)
                    }
                    AndroidIndexRow(icon: "person.3.fill", title: "Team mode", value: "Not connected") { store.toast = "Team services are not connected yet" }
                }
                Spacer().frame(height: 20)
            }
        }.onAppear {
            if nickname.isEmpty { nickname = store.nickname }
            if arena.isEmpty { arena = store.arena }
        }
    }

    private var cleanName: String {
        let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Wyrm Player" : String(value.prefix(24))
    }
    private var initials: String { String(cleanName.filter(\.isLetter).prefix(2)).uppercased() }
}

private struct AndroidStatCell: View {
    let label: String, value: String
    var body: some View { VStack(alignment: .leading, spacing: 2) { Text(label).font(.androidWyrm(11, .bold)).tracking(0.75).foregroundColor(ATheme.quiet); Text(value).font(.androidWyrm(17, .bold)) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 12) }
}

private struct AndroidNotificationsPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Notifications").font(.androidWyrm(30, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).frame(height: 82)
            Rectangle().fill(ATheme.rule).frame(height: 1)
            Spacer()
            VStack(spacing: 6) {
                Text("All caught up").font(.androidWyrm(22, .bold))
                Text("Nothing new right now.").font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
            }
            Spacer()
        }
    }
}

private struct AndroidSocialPage: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                AndroidPageHeader(kicker: "Arena", title: "Social")
                AndroidGroupedCard {
                    AndroidDoubleRow(icon: "chart.bar.fill", tint: Color(red: 0.61, green: 0.48, blue: 0.24), well: Color(red: 0.96, green: 0.93, blue: 0.89), title: "Leaderboard", detail: "Score and kills", first: true) {}
                    AndroidDoubleRow(icon: "message.fill", tint: Color(red: 0.23, green: 0.37, blue: 0.66), well: Color(red: 0.89, green: 0.91, blue: 0.97), title: "Messages", detail: "No conversations yet") {}
                    AndroidDoubleRow(icon: "waveform", tint: ATheme.live, well: Color(red: 0.90, green: 0.94, blue: 0.91), title: "Voice rooms", detail: "No room joined") {}
                    AndroidDoubleRow(icon: "person.2.fill", title: "Followers", detail: "0 follow you · 0 followed") {}
                    AndroidDoubleRow(icon: "person.crop.circle", tint: Color(red: 0.23, green: 0.37, blue: 0.66), well: Color(red: 0.89, green: 0.91, blue: 0.97), title: "Your profile", detail: "Guest player") {}
                }
                AndroidSectionLabel("Recently played with")
                AndroidGroupedCard {
                    Text("People you play with will land here.").font(.androidWyrm(14)).foregroundColor(ATheme.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 18)
                }
                Spacer().frame(height: 20)
            }
        }
    }
}

private struct AndroidSkinPlaceholder: View {
    var body: some View {
        VStack(spacing: 0) {
            AndroidPageHeader(kicker: "WYRM", title: "Skin")
            Spacer()
            Image(systemName: "circle.hexagongrid").font(.system(size: 46, weight: .ultraLight)).foregroundColor(ATheme.quiet)
            Text("Skin Studio comes next").font(.androidWyrm(20, .bold)).padding(.top, 14)
            Text("The tab keeps Android’s place in the app, but it is intentionally not wired in this build.")
                .font(.androidWyrm(13)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center).padding(.horizontal, 44).padding(.top, 6)
            Spacer()
        }
    }
}

private struct AndroidSettingsPage: View {
    @ObservedObject var store: WyrmShellStore
    let open: (SettingsDestination) -> Void
    @State private var confirmReset = false

    private var controlsValue: String { store.settings.first(where: { $0.id == "controls.joystick_mode" })?.displayValue ?? "Joystick" }
    private var foodValue: String { store.settings.first(where: { $0.id == "normal.food_type" })?.displayValue ?? "Original" }
    private var buttonCount: Int { store.hotkeys.filter(\.visible).count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer().frame(height: 44)
                AndroidPageHeader(kicker: "WYRM", title: "Settings", bottom: 16)
                AndroidSettingsSection(title: "Arena", rows: [
                    ("Display", "Scores, names, minimap, text sizes", "", SettingsDestination.display),
                    ("Controls", "Steering, boost, zoom bar", controlsValue, .controls),
                    ("On-screen buttons", "Which buttons appear and how they fire", "\(buttonCount) on", .buttons),
                ], open: open)
                AndroidSettingsSection(title: "Playing help", rows: [
                    ("Modes", "Normal, Assist, helper lines and arena colours", "", .modes),
                    ("Bot", "When it circles, how wide it swings", "", .bot),
                ], open: open)
                AndroidSettingsSection(title: "Food", rows: [
                    ("Food style", "Original, rings and geometric shapes", foodValue, .food),
                ], open: open)
                AndroidSettingsSection(title: "Account", rows: [
                    ("Profile", "Name, username, photo, bio", "Guest", .profile),
                    ("Notifications", "Invites, team pings, follows", "", .notificationSettings),
                    ("Privacy", "Who can reach you, what is stored", "", .privacy),
                ], open: open)
                AndroidSettingsSection(title: "Accessibility", rows: [
                    ("Themes", "Paper, dark and colour appearances", "Paper", .themes),
                ], open: open)
                AndroidSettingsSection(title: "This device", rows: [
                    ("Backup & version", "Skins, controls, settings and team keys · Wyrm 0.6.0 · format v\(store.settingsVersion)", "Build 27", .backup),
                ], open: open)
                AndroidGroupedCard {
                    Button {
                        if confirmReset { store.reset(1, message: "All engine settings reset"); confirmReset = false }
                        else { confirmReset = true }
                    } label: {
                        Text(confirmReset ? "Tap again to reset everything" : "Reset everything to defaults")
                            .font(.androidWyrm(15.5)).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).frame(minHeight: 52)
                    }.buttonStyle(.plain)
                }
                Text("Wyrm · settings format v\(store.settingsVersion)").font(.androidWyrm(12)).foregroundColor(ATheme.quiet).padding(.vertical, 16)
            }
        }.safeAreaInset(edge: .top) { Color.clear.frame(height: 1) }
    }
}

private struct AndroidSettingsSection: View {
    let title: String
    let rows: [(String, String, String, SettingsDestination)]
    let open: (SettingsDestination) -> Void
    var body: some View {
        VStack(spacing: 0) {
            Text(title.uppercased()).font(.androidWyrm(11.5, .semibold)).tracking(0.92).foregroundColor(ATheme.quiet)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 8)
            AndroidGroupedCard {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    AndroidDoubleRow(title: row.0, detail: row.1, value: row.2, first: index == 0) { open(row.3) }
                }
            }
            Spacer().frame(height: 22)
        }
    }
}

private struct AndroidSettingsDestination: View {
    @ObservedObject var store: WyrmShellStore
    let destination: SettingsDestination
    let onBack: () -> Void
    @AppStorage("wyrm.ios.theme") private var chosenTheme = "Paper"

    private var rows: [EngineSetting] {
        store.settings.filter { row in
            guard !row.label.isEmpty && !row.id.hasPrefix("tags.") else { return false }
            switch destination {
            case .display: return (row.group == "general" || row.group == "general.type") && row.group != "general.bot"
            case .controls: return row.group == "controls" || row.group.hasPrefix("controls.")
            case .buttons: return row.group == "keys"
            case .modes: return (row.group == "normal" || row.group == "assist") && !row.id.contains("food")
            case .bot: return row.group == "general.bot"
            case .food: return (row.group == "normal" || row.group == "assist") && row.id.contains("food")
            default: return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("‹ Settings").font(.androidWyrm(16)).foregroundColor(ATheme.link).frame(maxWidth: .infinity, alignment: .leading).onTapGesture(perform: onBack)
                Text(destination.rawValue).font(.androidWyrm(16, .semibold))
            }.padding(.horizontal, 20).frame(height: 50)
            Rectangle().fill(ATheme.rule).frame(height: 1)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if destination == .buttons {
                        AndroidSectionLabel("Buttons · \(store.hotkeys.filter(\.visible).count) of \(store.hotkeys.count) on", top: 18)
                        AndroidGroupedCard {
                            ForEach(store.hotkeys.indices, id: \.self) { index in
                                AndroidHotkeyLine(store: store, hotkey: store.hotkeys[index], first: index == 0)
                            }
                        }
                        if !rows.isEmpty { AndroidSectionLabel("Appearance") }
                    }
                    if destination == .themes {
                        AndroidSectionLabel("Themes", top: 18)
                        AndroidGroupedCard {
                            ForEach(["Paper", "Graphite", "Blush", "Sun", "Slate", "Lilac", "Forest", "Midnight"], id: \.self) { name in
                                Button { chosenTheme = name; store.toast = "\(name) selected" } label: {
                                    HStack { Text(name).font(.androidWyrm(15.5)); Spacer(); if chosenTheme == name { Image(systemName: "checkmark").foregroundColor(ATheme.live) } }
                                        .padding(.horizontal, 14).frame(minHeight: 52)
                                }.buttonStyle(.plain)
                            }
                        }
                    } else if destination == .profile || destination == .notificationSettings || destination == .privacy {
                        AndroidSectionLabel(destination.rawValue, top: 18)
                        AndroidGroupedCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Account services are not connected").font(.androidWyrm(15.5, .semibold))
                                Text("This page matches Android’s place in Settings without inventing account data.").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        }
                    } else if destination == .backup {
                        AndroidSectionLabel("This device", top: 18)
                        AndroidGroupedCard {
                            AndroidDoubleRow(title: "Wyrm", detail: "iOS native engine", value: "0.6.0 (27)", first: true) {}
                            AndroidDoubleRow(title: "Settings format", detail: "Original engine save", value: store.settingsVersion) {}
                        }
                        AndroidSectionLabel("Reset layouts")
                        AndroidGroupedCard {
                            AndroidActionLine("Reset controls layout") { store.reset(2, message: "Controls reset") }
                            AndroidActionLine("Reset button layout") { store.reset(4, message: "Buttons reset") }
                            AndroidActionLine("Reset arena HUD positions") { store.reset(8, message: "HUD reset") }
                        }
                    }
                    if !rows.isEmpty {
                        let blocks = Dictionary(grouping: rows, by: \.group).sorted { $0.key < $1.key }
                        ForEach(blocks.indices, id: \.self) { blockIndex in
                            let block = blocks[blockIndex]
                            AndroidSectionLabel(friendly(block.key), top: blockIndex == 0 ? 18 : 22)
                            AndroidGroupedCard {
                                ForEach(block.value.indices, id: \.self) { index in
                                    let row = block.value[index]
                                    AndroidSettingLine(store: store, row: row, first: index == 0).id(row.id + row.displayValue)
                                }
                            }
                        }
                    }
                    Spacer().frame(height: 30)
                }
            }
        }.background(ATheme.paper.ignoresSafeArea())
    }

    private func friendly(_ group: String) -> String {
        let names = ["general":"Basic", "general.type":"Text sizes", "general.bot":"Bot", "controls":"Basic · steering", "controls.boost":"Boost", "controls.zoom":"Zoom", "controls.arrow":"Arrow", "keys":"Appearance", "normal":"Normal", "assist":"Assist"]
        return (names[group] ?? group.replacingOccurrences(of: ".", with: " · ")).uppercased()
    }
}

private struct AndroidSettingLine: View {
    @ObservedObject var store: WyrmShellStore
    let row: EngineSetting
    let first: Bool
    @State private var scalar: Double
    @State private var color: Color

    init(store: WyrmShellStore, row: EngineSetting, first: Bool) {
        self.store = store; self.row = row; self.first = first
        _scalar = State(initialValue: row.values.first ?? 0)
        let v = row.values + [0, 0, 0, 1]
        _color = State(initialValue: Color(red: v[0], green: v[1], blue: v[2], opacity: row.type == "color4" ? v[3] : 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(ATheme.rowRule).frame(height: 1) }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label).font(.androidWyrm(15.5))
                        if !row.hint.isEmpty { Text(row.hint).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer()
                    control
                }
                if row.type == "float" || row.type == "int" {
                    Slider(value: Binding(get: { scalar }, set: { scalar = $0; store.write(row, values: [$0]) }), in: row.minimum...row.maximum, step: row.type == "int" ? 1 : max(0.001, (row.maximum-row.minimum)/100)).tint(ATheme.ink)
                }
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    @ViewBuilder private var control: some View {
        switch row.type {
        case "bool": Toggle("", isOn: Binding(get: { scalar != 0 }, set: { scalar = $0 ? 1 : 0; store.write(row, values: [scalar]) })).labelsHidden().tint(ATheme.live)
        case "enum": Picker("", selection: Binding(get: { Int(scalar) }, set: { scalar = Double($0); store.write(row, values: [scalar]) })) { ForEach(row.options.indices, id: \.self) { Text(row.options[$0]).tag($0) } }.pickerStyle(.menu).tint(ATheme.ink)
        case "color3", "color4": ColorPicker("", selection: Binding(get: { color }, set: { newColor in color = newColor; guard let c = UIColor(newColor).cgColor.components else { return }; let v = c.count >= 3 ? [c[0],c[1],c[2],c.count > 3 ? c[3] : 1] : [c[0],c[0],c[0],1]; store.write(row, values: v.prefix(row.type == "color4" ? 4 : 3).map(Double.init)) }), supportsOpacity: row.type == "color4").labelsHidden()
        default: Text(row.type == "int" ? "\(Int(scalar))" : String(format: "%.2f", scalar)).font(.androidWyrm(13, .bold)).foregroundColor(ATheme.quiet)
        }
    }
}

private struct AndroidHotkeyLine: View {
    @ObservedObject var store: WyrmShellStore
    let hotkey: EngineHotkey
    let first: Bool
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(ATheme.rowRule).frame(height: 1) }
            Toggle(isOn: Binding(get: { hotkey.visible }, set: { store.setHotkey(hotkey, visible: $0) })) {
                VStack(alignment: .leading, spacing: 2) { Text(hotkey.name).font(.androidWyrm(15.5)); Text("\(hotkey.keyName) · \(hotkey.fixedMode ? (hotkey.mode == 1 ? "Hold" : "Press") : (hotkey.mode == 1 ? "Hold" : "Toggle"))").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet) }
            }.tint(ATheme.live).padding(.horizontal, 14).frame(minHeight: 58)
        }
    }
}

private struct AndroidActionLine: View {
    let title: String, action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View { Button(action: action) { Text(title).font(.androidWyrm(15.5)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(minHeight: 52) }.buttonStyle(.plain) }
}

private struct AndroidPageHeader: View {
    let kicker: String, title: String
    var bottom: CGFloat = 18
    var body: some View { VStack(alignment: .leading, spacing: 3) { Text(kicker).font(.androidWyrm(11.5, .bold)).tracking(0.92).foregroundColor(ATheme.quiet); Text(title).font(.androidWyrm(30, .bold)) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, bottom) }
}

private struct AndroidSectionLabel: View {
    let text: String
    var top: CGFloat = 26
    init(_ text: String, top: CGFloat = 26) { self.text = text; self.top = top }
    var body: some View { Text(text).font(.androidWyrm(11.5, .bold)).tracking(0.92).foregroundColor(ATheme.quiet).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, top).padding(.bottom, 8) }
}

private struct AndroidGroupedCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(spacing: 0) { content }.background(ATheme.card).cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(ATheme.rule)).padding(.horizontal, 16) }
}

private struct AndroidIndexRow: View {
    let icon: String, title: String, value: String, first: Bool, action: () -> Void
    init(icon: String = "circle", title: String, value: String = "", first: Bool = false, action: @escaping () -> Void) { self.icon = icon; self.title = title; self.value = value; self.first = first; self.action = action }
    var body: some View { VStack(spacing: 0) { if !first { Rectangle().fill(ATheme.rowRule).frame(height: 1) }; Button(action: action) { HStack(spacing: 12) { Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28).background(ATheme.well).cornerRadius(8); Text(title).font(.androidWyrm(15.5)); Spacer(); if !value.isEmpty { Text(value).font(.androidWyrm(14)).foregroundColor(ATheme.quiet) }; Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron) }.padding(.horizontal, 14).frame(height: 52) }.buttonStyle(.plain) } }
}

private struct AndroidDoubleRow: View {
    var icon: String? = nil, tint: Color = ATheme.mute, well: Color = ATheme.well
    let title: String, detail: String
    var value: String = "", first: Bool = false
    let action: () -> Void
    var body: some View { VStack(spacing: 0) { if !first { Rectangle().fill(ATheme.rowRule).frame(height: 1) }; Button(action: action) { HStack(spacing: 12) { if let icon = icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(tint).frame(width: 28, height: 28).background(well).cornerRadius(8) }; VStack(alignment: .leading, spacing: 1) { Text(title).font(.androidWyrm(15.5)); Text(detail).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).lineLimit(2) }; Spacer(); if !value.isEmpty { Text(value).font(.androidWyrm(14)).foregroundColor(ATheme.quiet) }; Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron) }.padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 56) }.buttonStyle(.plain) } }
}

private struct AndroidRootTabs: View {
    @Binding var selection: AndroidRootTab
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            AndroidTabButton(item: .notifications, icon: "bell", selection: $selection)
            AndroidTabButton(item: .social, icon: "person.2", selection: $selection)
            AndroidTabButton(item: .play, icon: "play.circle", selection: $selection, prominent: true)
            AndroidTabButton(item: .skin, icon: "circle.hexagongrid", selection: $selection)
            AndroidTabButton(item: .settings, icon: "slider.horizontal.3", selection: $selection)
        }.frame(height: 70).background(ATheme.tabBar).ignoresSafeArea(edges: .bottom)
    }
}

private struct AndroidTabButton: View {
    let item: AndroidRootTab
    let icon: String
    @Binding var selection: AndroidRootTab
    var prominent = false
    var body: some View {
        Button { selection = item } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: prominent ? 25 : 22, weight: selection == item ? .semibold : .regular)).frame(height: 28)
                Text(item.rawValue).font(.androidWyrm(item == .notifications ? 8.8 : 10.5, selection == item ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
                Capsule().fill(selection == item ? ATheme.ink : Color.clear).frame(width: selection == item ? 14 : 0, height: 2).padding(.top, 1)
            }.foregroundColor(selection == item ? ATheme.ink : ATheme.tabIdle).frame(maxWidth: .infinity).padding(.top, 10)
        }.buttonStyle(.plain)
    }
}
