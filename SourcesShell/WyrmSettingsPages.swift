import SwiftUI
import UIKit
import UserNotifications
import UniformTypeIdentifiers

/*
 * Settings, page for page the Android app's paper settings (SettingsScreen.kt
 * and the Settings*Screen.kt files beside it). Rows are drawn from the engine's
 * own settings description, so a value on this page is the value the arena uses.
 */

// MARK: - Hub

struct WyrmSettingsHub: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var theme = WyrmThemeStore.shared
    @ObservedObject var notifications = WyrmNotificationPrefs.shared
    let open: (WyrmDesignRoute) -> Void
    @AppStorage("wyrm.ios.developer-mode") var developerMode = false
    @AppStorage(WyrmBackup.lastKey) var lastBackup = ""
    @State var confirming = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WYRM").font(.androidWyrm(11.5, .semibold)).tracking(0.92).foregroundColor(ATheme.quiet)
                    Text("Settings").font(.androidWyrm(30, .bold)).tracking(-0.5).foregroundColor(ATheme.ink)
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

                Group {
                group("Arena", [
                    ("Display", "Scores, names, minimap, text sizes", "", .display),
                    ("Controls", "Steering, boost, zoom bar", engine.setting("controls.joystick_mode")?.index == 2 ? "Arrow" : "Joystick", .controls),
                    ("On-screen buttons", "Which buttons appear and how they fire", engine.hotkeys.isEmpty ? "" : "\(WyrmButtonsContent.allowed(engine.hotkeys).filter(\.visible).count) on", .buttons),
                ])
                group("Playing help", [
                    ("Modes", "Normal, Assist, helper lines and arena colours", "", .modes),
                    ("Bot", "When it circles, how wide it swings", "", .bot),
                ])
                group("Food", [("Food style", "Original, rings and geometric shapes", WyrmFoodPage.label(engine), .food)])
                group("Account", [
                    ("Profile", "Name, username, photo, bio", account.player?.handle ?? "", .profile("")),
                    ("Notifications", "Invites, team pings, follows", notifications.enabledCount > 0 ? "\(notifications.enabledCount) on" : "", .notificationSettings),
                    ("Privacy", "Who can reach you, what is stored", "", .privacy),
                ])
                group("Accessibility", [("Themes", "Paper, dark and colour appearances", theme.theme.displayName, .themes)])
                group("This device", [(
                    "Backup & version",
                    (lastBackup.isEmpty ? "Skins, controls, settings and theme" : "Last backup \(lastBackup)")
                        + " · Wyrm \(WyrmBuild.version)"
                        + (engine.settingsVersion.isEmpty ? "" : " · format v\(engine.settingsVersion)"),
                    "", .backup)])
                }

                WSSectionLabel("Developer", top: 0)
                WSCard {
                    WSBoolRow(title: "Developer Mode", detail: "Local diagnostics and export tools", on: developerMode, first: true) { developerMode = $0 }
                    if developerMode { WSValueRow(title: "Wyrm logs", value: "7 days", onOpen: { open(.developer) }) }
                }
                Spacer().frame(height: 22)

                WSCard {
                    WSActionRow(title: confirming ? "Tap again to reset everything" : "Reset everything to defaults", first: true, danger: true) {
                        if confirming { confirming = false; engine.reset(1, message: "All settings reset") } else { confirming = true }
                    }
                }
                Text(engine.settingsVersion.isEmpty ? "Wyrm" : "Wyrm · settings format v\(engine.settingsVersion)")
                    .font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                    .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 12)
                Spacer().frame(height: 102)
            }
        }
        .onAppear { notifications.refreshSystem() }
    }

    private func group(_ title: String, _ rows: [(String, String, String, WyrmDesignRoute)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WSSectionLabel(title, top: 0)
            WSCard {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    VStack(spacing: 0) {
                        if index > 0 { WSHairline() }
                        Button { open(row.3) } label: {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.0).font(.androidWyrm(15.5)).foregroundColor(ATheme.ink)
                                    Text(row.1).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                                        .fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)
                                if !row.2.isEmpty {
                                    Text(row.2).font(.androidWyrm(14)).foregroundColor(ATheme.quiet).lineLimit(1)
                                    Spacer().frame(width: 6)
                                }
                                Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 56).contentShape(Rectangle())
                        }.buttonStyle(WSPressStyle())
                    }
                }
            }
            Spacer().frame(height: 22)
        }
    }
}

enum WyrmBuild {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
}

// MARK: - Display

struct WyrmDisplayPage: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    @State var advanced = false
    private static let basicIDs = ["general.snake_scores", "general.show_own_name", "general.minimap_size", "general.ui_font"]

    var body: some View {
        let basic = Self.basicIDs.compactMap { engine.setting($0) }
        let rest = engine.settings.filter {
            ($0.group == "general" || $0.group.hasPrefix("general.")) && $0.group != "general.bot"
                && !Self.basicIDs.contains($0.id) && !$0.label.isEmpty
        }
        WSScaffold(title: "Display", onBack: close) {
            WSSectionLabel("Basic", top: 18)
            WSCard { WSRows(rows: basic, engine: engine) }
            if basic.isEmpty { WSCaption("These controls appear as soon as the engine has started.") }
            if !rest.isEmpty {
                WSAdvancedFold(label: "Advanced", open: advanced) { withAnimation(.easeInOut(duration: 0.25)) { advanced.toggle() } }
                if advanced {
                    WSCard { WSRows(rows: rest, engine: engine) }
                    WSCaption("VSync, zoom step, cursor size and after-death delay live here — the things nobody touches twice.")
                }
            }
        }
    }
}

// MARK: - Controls workspace

enum WyrmControlsTab: Int, CaseIterable {
    case controls, buttons, arenaUI
    var label: String { ["Controls", "On-screen buttons", "Arena UI"][rawValue] }
}

/// Play › Controls: the three layout surfaces as tabs of one page.
struct WyrmControlsWorkspace: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    @State var tab = WyrmControlsTab.controls
    @State var direction = 1

    var body: some View {
        WSScaffold(title: "Controls", parent: "Play",
                   sectionTabs: AnyView(WSSegmented(options: WyrmControlsTab.allCases.map(\.label), selected: tab.rawValue, fontSize: 12.5) { next in
                       direction = next > tab.rawValue ? 1 : -1
                       withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26)) { tab = WyrmControlsTab(rawValue: next) ?? .controls }
                   }.padding(.horizontal, 14).padding(.vertical, 10)),
                   onBack: close) {
            ZStack(alignment: .top) {
                switch tab {
                case .controls: WyrmControlsContent(engine: engine).transition(slide)
                case .buttons: WyrmButtonsContent(engine: engine).transition(slide)
                case .arenaUI: WyrmArenaUIContent(engine: engine).transition(slide)
                }
            }
        }
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: CGFloat(direction) * 60)),
                    removal: .opacity.combined(with: .offset(x: CGFloat(-direction) * 50)))
    }
}

struct WyrmControlsPage: View {
    @ObservedObject var engine: WyrmShellStore
    var parent = "Settings"
    let close: () -> Void
    var body: some View { WSScaffold(title: "Controls", parent: parent, onBack: close) { WyrmControlsContent(engine: engine) } }
}

struct WyrmControlsContent: View {
    @ObservedObject var engine: WyrmShellStore
    @State var behaviourOpen = false
    @State var zoomOpen = false

    var body: some View {
        let steeringSetting = engine.setting("controls.joystick_mode")
        let steering = steeringSetting?.index ?? 0
        let arrow = steering == 2
        let boostMode = engine.setting("controls.boost_mode")
        let boostButton = (boostMode?.index ?? 0) == 1
        let joystickSize = engine.setting("controls.joystick_size")
        let boostSize = engine.setting("controls.boost_size")
        let opacity = engine.setting("controls.opacity")
        let handedness = engine.setting("controls.handedness")
        let zoomRows = engine.settings.filter { $0.group == "controls.zoom" }
        let arrowRows = engine.settings.filter { $0.group == "controls.arrow" }

        VStack(alignment: .leading, spacing: 0) {
            WyrmControlsPreview(engine: engine).padding(.horizontal, 16).padding(.top, 16)

            WSSectionLabel("Basic · steering")
            WSCard {
                WSEnumBlock(title: "Steering style", options: ["Joystick", "Arrow"], selected: arrow ? 1 : 0, first: true) { pick in
                    guard let setting = steeringSetting else { return }
                    engine.write(setting, values: [pick == 1 ? 2 : Double((0...1).contains(steering) ? steering : 0)])
                }
                if !arrow, let setting = steeringSetting, setting.options.count >= 2 {
                    let behaviour = Array(setting.options.prefix(2))
                    WSValueRow(title: "Joystick behaviour", value: behaviour[min(max(steering, 0), 1)]) {
                        withAnimation(.easeInOut(duration: 0.25)) { behaviourOpen.toggle() }
                    }
                    if behaviourOpen {
                        WSSegmented(options: behaviour, selected: min(max(steering, 0), 1)) { engine.write(setting, values: [Double($0)]) }
                            .padding(.horizontal, 14).padding(.bottom, 14)
                    }
                }
                if let handedness {
                    WSEnumBlock(title: handedness.label, detail: handedness.hint, options: ["Left", "Right"],
                                selected: min(max(handedness.index, 0), 1)) { engine.write(handedness, values: [Double($0)]) }
                }
                if let boostMode {
                    WSEnumBlock(title: "Boost", detail: boostMode.hint, options: boostMode.options,
                                selected: min(max(boostMode.index, 0), max(boostMode.options.count - 1, 0))) { engine.write(boostMode, values: [Double($0)]) }
                }
            }

            WSSectionLabel("Basic · size")
            WSCard {
                let sizeRows = [arrow ? nil : joystickSize, boostButton ? boostSize : nil, opacity].compactMap { $0 }
                WSRows(rows: sizeRows, engine: engine)
            }

            if arrow && !arrowRows.isEmpty {
                WSSectionLabel("Basic · arrow")
                WSCard { WSRows(rows: arrowRows, engine: engine) }
            }

            if !zoomRows.isEmpty {
                WSAdvancedFold(label: "Advanced · zoom bar", open: zoomOpen) { withAnimation(.easeInOut(duration: 0.25)) { zoomOpen.toggle() } }
                if zoomOpen { WSCard { WSRows(rows: zoomRows, engine: engine) } }
            }

            VStack(spacing: 9) {
                WSPrimaryButton(label: "Arrange the layout") { engine.openLayoutEditor() }
                WSOutlineButton(label: "Reset positions") { engine.reset(2, message: "Control positions reset") }
            }.padding(.horizontal, 16).padding(.top, 22)
            WSCaption("Opens sideways, the way you hold the phone in a match.")
        }
    }
}

/// Normalized silhouettes shared with `mobile_controls.c`, so the preview and
/// the arena draw the same arrow.
enum WyrmArrowShapes {
    private static let raw: [[(CGFloat, CGFloat)]] = [
        [(0.66, 0), (0.08, -0.56), (0.01, -0.24), (-0.52, -0.24), (-0.52, 0.24), (0.01, 0.24), (0.08, 0.56)],
        [(0.72, 0), (0.02, -0.72), (-0.06, -0.30), (-0.58, -0.30), (-0.58, 0.30), (-0.06, 0.30), (0.02, 0.72)],
        [(0.82, 0), (0.05, -0.22), (0.16, -0.075), (-0.72, -0.075), (-0.72, 0.075), (0.16, 0.075), (0.05, 0.22)],
        [(0.78, 0), (0.12, -0.42), (-0.10, -0.22), (-0.25, -0.16), (-0.70, 0), (-0.25, 0.16), (-0.10, 0.22), (0.12, 0.42)],
        [(0.82, 0), (-0.64, -0.26), (-0.64, 0.26)],
    ]
    static let points: [[CGPoint]] = raw.map { shape in shape.map { CGPoint(x: $0.0, y: $0.1) } }

    static func path(style: Int, center: CGPoint, length: CGFloat, width: CGFloat) -> Path {
        let shape = points[min(max(style, 0), points.count - 1)]
        var path = Path()
        for (index, point) in shape.enumerated() {
            let p = CGPoint(x: center.x + point.x * length, y: center.y + point.y * width)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// The controls as they will appear, placed at their saved landscape positions.
struct WyrmControlsPreview: View {
    @ObservedObject var engine: WyrmShellStore
    var body: some View {
        let steering = engine.setting("controls.joystick_mode")?.index ?? 0
        let opacity = engine.value("controls.opacity", 1)
        let arrowChannels = engine.setting("arrow.color")?.channels ?? [1, 1, 1, 1]
        let arrowSize = engine.value("arrow.size", 1)
        let arrowStyle = engine.setting("arrow.style")?.index ?? 0
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Text("PREVIEW").font(.androidWyrm(9, .bold)).tracking(1.4).foregroundColor(ATheme.quiet).padding(12)
                if steering != 2 {
                    WyrmPaperJoystick(diameter: 60 * engine.value("controls.joystick_size", 1), opacity: opacity)
                        .position(previewCentre("layout.joystick", proxy.size, child: 60 * engine.value("controls.joystick_size", 1)))
                } else {
                    Canvas { context, size in
                        let path = WyrmArrowShapes.path(style: arrowStyle, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                        length: 52 * arrowSize, width: 30 * arrowSize)
                        let fill = Color(.sRGB, red: arrowChannels[0], green: arrowChannels[1], blue: arrowChannels[2], opacity: min(max(opacity, 0), 1))
                        context.fill(path, with: .color(fill))
                        context.stroke(path, with: .color(Color(red: 0.016, green: 0.024, blue: 0.035).opacity(opacity)), lineWidth: 2)
                    }.padding(18)
                }
                if engine.setting("controls.boost_mode")?.index == 1 {
                    let d = 46 * engine.value("controls.boost_size", 1)
                    WyrmPaperBoost(diameter: d, opacity: opacity).position(previewCentre("layout.boost", proxy.size, child: d))
                }
                if engine.setting("controls.zoom_enabled")?.enabled ?? true {
                    let vertical = engine.setting("controls.zoom_orientation")?.index == 1
                    let length = 102 * engine.value("controls.zoom_length", 1)
                    WyrmPaperZoomBar(length: length, vertical: vertical, opacity: opacity, value: 0.45)
                        .position(previewCentre("layout.zoom", proxy.size, child: vertical ? 26 : length, childHeight: vertical ? length : 26))
                }
            }
        }
        .frame(height: 190)
        .background(ATheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
    }

    /// `previewItemTopLeft`: the exact normalized centre, clamped so the whole
    /// control stays inside the preview.
    private func previewCentre(_ prefix: String, _ size: CGSize, child: Double, childHeight: Double? = nil) -> CGPoint {
        wsPreviewCentre(x: engine.value("\(prefix)_x", 0.5), y: engine.value("\(prefix)_y", 0.7), in: size,
                        child: CGSize(width: child, height: childHeight ?? child))
    }
}

func wsPreviewCentre(x: Double, y: Double, in size: CGSize, child: CGSize) -> CGPoint {
    let sx = x.isFinite ? min(max(x, 0), 1) : 0.5
    let sy = y.isFinite ? min(max(y, 0), 1) : 0.7
    let halfW = min(child.width / 2, size.width / 2), halfH = min(child.height / 2, size.height / 2)
    return CGPoint(x: min(max(sx * size.width, halfW), size.width - halfW),
                   y: min(max(sy * size.height, halfH), size.height - halfH))
}

struct WyrmPaperJoystick: View {
    let diameter: Double
    var opacity = 1.0
    var body: some View {
        ZStack {
            Circle().fill(ATheme.card).overlay(Circle().stroke(ATheme.ink, lineWidth: 1.5))
            Circle().stroke(ATheme.rule, lineWidth: 1).frame(width: diameter * 0.62, height: diameter * 0.62)
            Circle().fill(ATheme.ink).frame(width: diameter * 0.42, height: diameter * 0.42)
        }
        .frame(width: diameter, height: diameter).opacity(min(max(opacity, 0), 1))
    }
}

struct WyrmPaperBoost: View {
    let diameter: Double
    var opacity = 1.0
    var body: some View {
        Text("»").font(.androidWyrm(diameter * 0.44, .bold)).foregroundColor(ATheme.ink)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(ATheme.card.opacity(min(max(opacity, 0), 1))))
            .overlay(Circle().stroke(ATheme.ink, lineWidth: 1.5))
    }
}

struct WyrmPaperZoomBar: View {
    let length: Double
    var vertical = false
    var opacity = 1.0
    var value = 0.5
    var body: some View {
        let thickness = 26.0, knob = 18.0, travel = length - thickness
        ZStack(alignment: vertical ? .top : .leading) {
            Capsule().fill(ATheme.card)
            Rectangle().fill(ATheme.track)
                .frame(width: vertical ? thickness : length * value, height: vertical ? length * value : thickness)
            // Android's PaperZoomBar: the knob rides the centre line and only
            // travels along the bar, four points in from either end.
            Circle().fill(ATheme.ink).frame(width: knob, height: knob)
                .offset(x: vertical ? 0 : travel * value + 4, y: vertical ? travel * value + 4 : 0)
        }
        .frame(width: vertical ? thickness : length, height: vertical ? length : thickness)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(ATheme.ink, lineWidth: 1))
        .opacity(min(max(opacity, 0), 1))
    }
}

struct WyrmPaperKey: View {
    let label: String
    var opacity = 1.0
    var scale = 1.0
    var body: some View {
        Text(label.uppercased()).font(.androidWyrm(max(5, 12 * scale), .semibold)).tracking(0.7).foregroundColor(ATheme.ink)
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(width: 104 * scale, height: 54 * scale)
            .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(ATheme.card.opacity(min(max(opacity, 0), 1))))
            .overlay(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).stroke(ATheme.ink, lineWidth: 1.25))
    }
}

// MARK: - On-screen buttons

struct WyrmButtonsPage: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    var body: some View { WSScaffold(title: "On-screen buttons", onBack: close) { WyrmButtonsContent(engine: engine) } }
}

struct WyrmButtonsContent: View {
    @ObservedObject var engine: WyrmShellStore
    /// Same allowlist as the Android keys page and the engine.
    static let order = [1, 2, 3, 4, 6, 7, 8, 9]
    static func allowed(_ keys: [EngineHotkey]) -> [EngineHotkey] { order.compactMap { id in keys.first { $0.id == id } } }

    var body: some View {
        let allowed = Self.allowed(engine.hotkeys)
        let visible = allowed.filter(\.visible)
        let size = engine.setting("keys.key_scale")
        let opacity = engine.setting("keys.opacity")
        VStack(alignment: .leading, spacing: 0) {
            WSSectionLabel("Live preview", top: 18)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Text("PREVIEW").font(.androidWyrm(9, .bold)).tracking(1.4).foregroundColor(ATheme.quiet).padding(12)
                    ForEach(visible) { key in
                        let scale = (size?.number ?? 1) * 0.48
                        WyrmPaperKey(label: key.name, opacity: opacity?.number ?? 1, scale: scale)
                            .position(wsPreviewCentre(x: key.x, y: key.y, in: proxy.size, child: CGSize(width: 104 * scale, height: 54 * scale)))
                    }
                }
            }
            .frame(height: 156).background(ATheme.well)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .padding(.horizontal, 16)

            WSSectionLabel("Buttons · \(visible.count) of \(allowed.count) on", top: 18)
            WSCard {
                ForEach(Array(allowed.enumerated()), id: \.element.id) { index, key in
                    if index > 0 { WSHairline() }
                    HStack(spacing: 9) {
                        Text(key.name).font(.androidWyrm(15.5)).foregroundColor(ATheme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        if key.fixedMode {
                            Text("Tap").font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.quiet)
                                .frame(width: 116, height: 38).background(ATheme.track)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                        } else {
                            WSSegmented(options: ["Toggle", "Hold"], selected: min(max(key.mode, 0), 1), fontSize: 13) { mode in
                                var next = key; next.mode = mode; engine.writeHotkey(next)
                            }.frame(width: 116)
                        }
                        WSInkSwitch(on: key.visible) { engine.setHotkey(key, visible: $0) }
                    }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 58)
                }
            }

            WSSectionLabel("Appearance")
            WSCard { WSRows(rows: [size, opacity].compactMap { $0 }, engine: engine) }

            VStack(spacing: 9) {
                WSPrimaryButton(label: "Arrange the layout", enabled: !visible.isEmpty) { engine.openLayoutEditor() }
                WSOutlineButton(label: "Reset positions") { engine.reset(4, message: "Button positions reset") }
            }.padding(.horizontal, 16).padding(.top, 22)
            WSCaption(visible.isEmpty
                      ? "Turn on at least one button above before arranging the layout."
                      : "The preview uses each button's real position, size and opacity. Toggle and Hold choose how a press behaves; the switch controls whether it appears.")
        }
    }
}

// MARK: - Arena UI

struct WyrmArenaUIContent: View {
    @ObservedObject var engine: WyrmShellStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WSSectionLabel("Arena HUD", top: 18)
            WSCard {
                Text("Move every screen-space element without changing the arena beneath it.")
                    .font(.androidWyrm(15.5, .medium)).foregroundColor(ATheme.ink).lineSpacing(5).padding(14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WSSectionLabel("Size and type")
            WSCard { WSRows(rows: ["general.minimap_size", "general.lb_font", "general.stats_font"].compactMap { engine.setting($0) }, engine: engine) }
            WSCaption("These are the same saved values shown in Settings › Display. Changes stay synchronized.")
            VStack(spacing: 9) {
                WSPrimaryButton(label: "Arrange arena UI") { engine.openLayoutEditor() }
                WSOutlineButton(label: "Reset arena positions") { engine.reset(8, message: "Arena positions reset") }
            }.padding(.horizontal, 16).padding(.top, 22)
            WSCaption("Leaderboard, stats, minimap, team roster and chat can each be placed independently in landscape.")
        }
    }
}

// MARK: - Modes

struct WyrmModesPage: View {
    @ObservedObject var engine: WyrmShellStore
    var parent = "Settings"
    let close: () -> Void
    @State var mode = 1
    @State var advanced = true
    private static let foodIDs: Set<String> = ["food_type", "food_scale", "food_float", "food_flicker", "const_food_scale", "uniform_food_color", "food_color"]
    private static let dotIDs: Set<String> = ["show_crosshair", "head_dot_size", "head_dot_color"]

    var body: some View {
        WSScaffold(title: "Modes", parent: parent, onBack: close) {
            WSCard {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arena modes").font(.androidWyrm(16, .semibold)).foregroundColor(ATheme.ink)
                    Text("Tune the normal arena and the helper view independently.").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                }.padding(.horizontal, 14).padding(.vertical, 15)
            }
            WSSectionLabel("Choose mode")
            WSCard {
                WSSegmented(options: ["Assist mode", "Normal mode"], selected: mode == 1 ? 0 : 1) { pick in
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.24)) { mode = pick == 0 ? 1 : 0 }
                }.padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            }
            modeContent(mode).id(mode)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: mode == 1 ? -40 : 40)), removal: .opacity))
        }
    }

    static func local(_ s: EngineSetting) -> String { s.id.components(separatedBy: ".").dropFirst().joined(separator: ".") }

    @ViewBuilder private func modeContent(_ visibleMode: Int) -> some View {
        let group = visibleMode == 1 ? "assist" : "normal"
        let rows = engine.settings.filter { $0.group == group && !$0.label.isEmpty }
        let local = Self.local
        let colours = rows.filter { !Self.foodIDs.contains(local($0)) && !Self.dotIDs.contains(local($0)) && ($0.type == "color3" || $0.type == "color4") }
        let dot = rows.first { local($0) == "show_crosshair" }
        let dotSize = rows.first { local($0) == "head_dot_size" }
        let dotColour = rows.first { local($0) == "head_dot_color" }
        let rest = rows.filter { row in !colours.contains(where: { $0.id == row.id }) && !Self.foodIDs.contains(local(row)) && !Self.dotIDs.contains(local(row)) }
        let laser = ["general.laser_thickness", "general.laser_color"].compactMap { engine.setting($0) }

        VStack(alignment: .leading, spacing: 0) {
            WSSectionLabel("Arena colours")
            WSCard { WSRows(rows: colours, engine: engine) }

            WSSectionLabel("Joystick guide")
            WSCard {
                WyrmHeadDotPreview(size: dotSize?.number ?? 10, colour: dotColour?.channels ?? [1, 1, 1, 1])
                if let dot { WSTypedRow(setting: dot, engine: engine) }
                if let dotSize { WSTypedRow(setting: dotSize, engine: engine) }
                if let dotColour { WSColourRow(setting: dotColour, engine: engine) }
            }

            WSAdvancedFold(label: "Advanced · helper lines", open: advanced) { withAnimation(.easeInOut(duration: 0.25)) { advanced.toggle() } }
            if advanced { WSCard { WSRows(rows: laser + rest, engine: engine) } }
        }
    }
}

struct WyrmHeadDotPreview: View {
    let size: Double
    let colour: [Double]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Size relative to snake head").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
            Canvas { context, canvas in
                let head: CGFloat = 22
                let centre = CGPoint(x: canvas.width * 0.5 - head * 0.35, y: canvas.height * 0.5)
                // The arena head is 29 world units wide and both it and the dot
                // share the snake scale, so this ratio survives every zoom.
                let dot = head * CGFloat(min(max(size, 4), 32)) / 29
                context.fill(Path(ellipseIn: CGRect(x: centre.x - head, y: centre.y - head, width: head * 2, height: head * 2)), with: .color(ATheme.ink))
                context.fill(Path(ellipseIn: CGRect(x: centre.x + head - dot, y: centre.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(Color(.sRGB, red: colour[0], green: colour[1], blue: colour[2], opacity: 1)))
            }
            .frame(height: 74).background(ATheme.well)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Bot

struct WyrmBotPage: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    var body: some View {
        WSScaffold(title: "Bot", onBack: close) {
            WSCard {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let the bot play").font(.androidWyrm(16, .semibold)).foregroundColor(ATheme.ink)
                    Text("Turn it on with the Bot button in a match. It hunts food, then circles once it is big.")
                        .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 14).padding(.vertical, 15)
            }
            WSSectionLabel("Basic · behaviour")
            WSCard { WSRows(rows: ["general.bot_circle", "general.bot_radius"].compactMap { engine.setting($0) }, engine: engine) }
            WSCaption("Laser and helper drawing moved to Assist, where you can actually see them.")
        }
    }
}

// MARK: - Food

struct WyrmFoodPage: View {
    @ObservedObject var engine: WyrmShellStore
    var parent = "Settings"
    let close: () -> Void
    @State var mode = 0
    @State var advanced = false

    static func isFood(_ s: EngineSetting) -> Bool {
        let local = s.id.components(separatedBy: ".").dropFirst().joined(separator: ".")
        return local.hasPrefix("food_") || local == "const_food_scale" || local == "uniform_food_color"
    }
    static func label(_ engine: WyrmShellStore) -> String {
        guard let s = engine.setting("normal.food_type"), s.options.indices.contains(s.index) else { return "Original" }
        return s.options[s.index]
    }

    var body: some View {
        let group = mode == 0 ? "normal" : "assist"
        let food = engine.settings.filter { $0.group == group && Self.isFood($0) }
        let style = food.first { $0.id.hasSuffix(".food_type") }
        let details = food.filter { $0.id != style?.id }
        WSScaffold(title: "Food", parent: parent, onBack: close) {
            WSCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Arena food").font(.androidWyrm(16, .semibold)).foregroundColor(ATheme.ink)
                    Text("Change only how food is drawn. Position, value and eating stay original.")
                        .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2).padding(.bottom, 12)
                    WSSegmented(options: ["Normal mode", "With assist"], selected: mode) { mode = $0 }
                }.padding(14)
            }
            WSSectionLabel("Shape")
            WSCard {
                if let style {
                    ForEach(style.options.indices, id: \.self) { index in
                        if index > 0 { WSHairline() }
                        Button { engine.write(style, values: [Double(index)]) } label: {
                            HStack(spacing: 12) {
                                WyrmFoodIcon(style: index).frame(width: 58, height: 42).background(ATheme.well)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                                Text(style.options[index]).font(.androidWyrm(15.5, style.index == index ? .semibold : .regular))
                                    .foregroundColor(ATheme.ink).frame(maxWidth: .infinity, alignment: .leading)
                                WSRadio(selected: style.index == index)
                            }.padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 56).contentShape(Rectangle())
                        }.buttonStyle(WSPressStyle())
                    }
                }
            }
            Text("Mixed uses every shape and keeps each morsel stable for its whole life.")
                .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).lineSpacing(5)
                .padding(.horizontal, 20).padding(.top, 10)
            if !details.isEmpty {
                WSAdvancedFold(label: "Advanced · size, motion and colour", open: advanced) { withAnimation(.easeInOut(duration: 0.25)) { advanced.toggle() } }
                if advanced { WSCard { WSRows(rows: details, engine: engine) } }
            }
        }
    }
}

/// The Android food glyphs: circle, ring, star, triangle, square, hexagon,
/// block and flower; index 2 is the mixed set.
struct WyrmFoodIcon: View {
    let style: Int
    var body: some View {
        Canvas { context, size in
            let area = CGRect(x: (size.width - 46) / 2, y: (size.height - 30) / 2, width: 46, height: 30)
            if style == 2 {
                let mini = min(area.width, area.height) * 0.12
                for (spot, shape) in [0, 2, 3, 5].enumerated() {
                    let x = area.minX + area.width * (spot % 2 == 0 ? 0.30 : 0.70)
                    let y = area.minY + area.height * (spot < 2 ? 0.30 : 0.70)
                    Self.draw(shape, CGPoint(x: x, y: y), mini, into: &context)
                }
            } else {
                let shape = style <= 1 ? style : style - 1
                Self.draw(shape, CGPoint(x: area.midX, y: area.midY), min(area.width, area.height) * 0.34, into: &context)
            }
        }
    }

    static func draw(_ shape: Int, _ c: CGPoint, _ r: CGFloat, into context: inout GraphicsContext) {
        let colour = GraphicsContext.Shading.color(ATheme.live)
        switch shape {
        case 0: context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: colour)
        case 1:
            let rr = r * 0.88
            context.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: colour, lineWidth: r * 0.34)
        case 2: context.fill(polygon(c, r, 10) { $0 % 2 == 0 ? 1 : 0.45 }, with: colour)
        case 3: context.fill(polygon(c, r, 3), with: colour)
        case 4: context.fill(polygon(c, r, 4), with: colour)
        case 5: context.fill(polygon(c, r, 6), with: colour)
        case 6: context.fill(Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: colour)
        default: context.fill(polygon(c, r, 24) { 0.82 + 0.18 * CGFloat(cos(Double($0) * 6 * 2 * .pi / 24)) }, with: colour)
        }
    }

    static func polygon(_ c: CGPoint, _ r: CGFloat, _ points: Int, radius: (Int) -> CGFloat = { _ in 1 }) -> Path {
        var path = Path()
        for point in 0..<points {
            let angle = -Double.pi / 2 + Double(point) * 2 * .pi / Double(points)
            let rr = r * radius(point)
            let p = CGPoint(x: c.x + CGFloat(cos(angle)) * rr, y: c.y + CGFloat(sin(angle)) * rr)
            if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Play's loadout well for Food: three morsels in the arena colours.
struct WyrmFoodWell: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) * 0.115
            func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ colour: Color) {
                context.fill(Path(ellipseIn: CGRect(x: size.width * x - radius, y: size.height * y - radius, width: radius * 2, height: radius * 2)), with: .color(colour))
            }
            dot(0.32, 0.38, r, ATheme.live)
            dot(0.68, 0.34, r * 0.82, ATheme.link)
            dot(0.55, 0.69, r * 1.08, Color(red: 0.827, green: 0.545, blue: 0.365))
        }
        .frame(width: 26, height: 26).background(ATheme.well).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Notifications

/// Which kinds of notice the player wants. iOS owns the master permission;
/// Wyrm owns the categories, so turning notifications off in iOS does not
/// erase a carefully chosen set. Mirrors Android's NotificationPreferences.
final class WyrmNotificationPrefs: ObservableObject {
    static let shared = WyrmNotificationPrefs()
    static let knownKinds = ["dm", "invite", "voice_invite", "notice", "broadcast", "event", "update", "feature", "follow", "achievement", "rank", "backup"]
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var revision = 0

    var systemEnabled: Bool { status == .authorized || status == .provisional || status == .ephemeral }
    var enabledCount: Int { systemEnabled ? Self.knownKinds.filter(isEnabled).count : 0 }

    /// A new kind starts enabled so an older preference file cannot hide it forever.
    func isEnabled(_ kind: String) -> Bool { UserDefaults.standard.object(forKey: "wyrm.notify.kind.\(kind)") as? Bool ?? true }

    /// The in-app feed honours the same choices; unknown kinds always show.
    func allows(_ kind: String) -> Bool { !Self.knownKinds.contains(kind) || isEnabled(kind) }

    func set(_ kind: String, _ enabled: Bool) {
        guard Self.knownKinds.contains(kind) else { return }
        UserDefaults.standard.set(enabled, forKey: "wyrm.notify.kind.\(kind)")
        revision += 1
    }

    func refreshSystem() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.status = settings.authorizationStatus }
        }
    }

    /// iOS asks once; after that only the Settings app can change the answer.
    func openSystem() {
        if status == .notDetermined {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in self.refreshSystem() }
            return
        }
        var target = URL(string: UIApplication.openSettingsURLString)
        if #available(iOS 16.0, *) { target = URL(string: UIApplication.openNotificationSettingsURLString) ?? target }
        if let target { UIApplication.shared.open(target) }
    }
}

struct WyrmNotificationSettingsPage: View {
    let close: () -> Void
    @ObservedObject var prefs = WyrmNotificationPrefs.shared
    private let groups: [(String, [(String, String, String)])] = [
        ("People", [("invite", "Arena invites", "Someone sends you a server and key."),
                    ("dm", "Direct messages", "New thread or reply."),
                    ("voice_invite", "Voice invitations", "Private invitations to verified voice rooms."),
                    ("follow", "New followers", "When another player starts following you.")]),
        ("Wyrm", [("notice", "Notices", "Maintenance, downtime and important alerts."),
                  ("broadcast", "Broadcasts", "General announcements sent to everyone."),
                  ("event", "Battledome events", "Scheduled events, start times and arena addresses."),
                  ("update", "Updates", "New versions and their changelogs."),
                  ("feature", "New features", "What has been added or changed inside Wyrm.")]),
        ("You", [("achievement", "Achievements", "Personal bests and milestones after a run."),
                 ("rank", "Rank changes", "Leaderboard movement after a finished run."),
                 ("backup", "Backup receipts", "Local backup and restore results from this device.")]),
    ]

    var body: some View {
        let master = prefs.systemEnabled
        WSScaffold(title: "Notifications", onBack: close) {
            WSSectionLabel("iPhone", top: 16)
            WSCard {
                WSBoolRow(title: "All notifications",
                          detail: master ? "Allowed by iOS. Tap to manage the master permission."
                              : prefs.status == .notDetermined ? "Not asked yet. Tap to allow Wyrm notifications."
                              : "Off in iOS. Tap here, then allow Wyrm notifications.",
                          on: master, first: true) { _ in prefs.openSystem() }
            }
            ForEach(groups.indices, id: \.self) { groupIndex in
                let group = groups[groupIndex]
                WSSectionLabel(group.0)
                WSCard {
                    ForEach(Array(group.1.enumerated()), id: \.offset) { index, row in
                        let checked = master && prefs.isEnabled(row.0)
                        WSBoolRow(title: row.1, detail: row.2, on: checked, first: index == 0) { _ in
                            prefs.set(row.0, !prefs.isEnabled(row.0))
                        }
                        .disabled(!master).opacity(master ? 1 : 0.46)
                    }
                }
            }
            WSCaption("Nothing here fires while you are inside an arena. Kinds you switch off are also hidden from Alerts.")
        }
        .onAppear { prefs.refreshSystem() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in prefs.refreshSystem() }
    }
}

// MARK: - Privacy

struct WyrmPrivacyPage: View {
    var parent = "Settings"
    let close: () -> Void
    @State var blocks: [WyrmPolicyBlock] = []
    var body: some View {
        WSScaffold(title: "Privacy", parent: parent, onBack: close) {
            WSSectionLabel("What Wyrm keeps", top: 18)
            WSCard {
                WSValueRow(title: "Stored on this phone", value: "Team ID, auth key, all settings", first: true)
                WSValueRow(title: "Stored on the server", value: "Name, username, photo, bio, scores")
                WSValueRow(title: "Chat retention", value: "Global 24 hours · direct until deleted")
                WSValueRow(title: "Analytics", value: "None · local logs only")
            }
            WSSectionLabel("The policy")
            VStack(alignment: .leading, spacing: 0) { ForEach(blocks.indices, id: \.self) { blockView(blocks[$0]) } }
                .padding(.horizontal, 20)
        }
        .onAppear { if blocks.isEmpty { blocks = WyrmPolicyBlock.parse(WyrmPolicyBlock.load()) } }
    }

    @ViewBuilder private func blockView(_ block: WyrmPolicyBlock) -> some View {
        switch block {
        case .title(let text):
            Text(text).font(.androidWyrm(22, .bold)).foregroundColor(ATheme.ink).padding(.top, 20).padding(.bottom, 6)
        case .heading(let text, let level):
            Text(text).font(.androidWyrm(level == 2 ? 17 : 14, .bold)).tracking(level == 2 ? 0 : 1.2)
                .foregroundColor(level == 2 ? ATheme.ink : ATheme.quiet).padding(.top, 26).padding(.bottom, 8)
        case .paragraph(let text):
            inline(text).font(.androidWyrm(14)).foregroundColor(ATheme.mute).lineSpacing(8).padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 10) {
                Text("—").font(.androidWyrm(14)).foregroundColor(ATheme.quiet)
                inline(text).font(.androidWyrm(14)).foregroundColor(ATheme.mute).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 10)
        case .pair(let term, let detail):
            VStack(alignment: .leading, spacing: 2) {
                inline(term).font(.androidWyrm(13, .bold)).foregroundColor(ATheme.ink)
                inline(detail).font(.androidWyrm(13)).foregroundColor(ATheme.mute).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 12)
        case .rule:
            Rectangle().fill(ATheme.rule).frame(height: 1).padding(.top, 12).padding(.bottom, 6)
        }
    }

    /// Bold spans only; link targets are flattened to their label, as on Android.
    private func inline(_ source: String) -> Text {
        let text = source.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1", options: .regularExpression)
        var result = Text("")
        var bold = false
        for part in text.components(separatedBy: "**") {
            result = result + (bold ? Text(part).fontWeight(.bold).foregroundColor(ATheme.ink) : Text(part))
            bold.toggle()
        }
        return result
    }
}

enum WyrmPolicyBlock {
    case title(String), heading(String, Int), paragraph(String), bullet(String), pair(String, String), rule

    static func load() -> String {
        guard let url = Bundle.main.url(forResource: "privacy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The privacy policy could not be opened on this device."
        }
        return text
    }

    /// Enough Markdown for this one document, the same subset Android parses.
    static func parse(_ source: String) -> [WyrmPolicyBlock] {
        var blocks: [WyrmPolicyBlock] = []
        var paragraph = ""
        func flush() { if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.trimmingCharacters(in: .whitespaces))); paragraph = "" } }
        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush() }
            else if line.hasPrefix("# ") { flush(); blocks.append(.title(String(line.dropFirst(2)))) }
            else if line.hasPrefix("### ") { flush(); blocks.append(.heading(String(line.dropFirst(4)), 3)) }
            else if line.hasPrefix("## ") { flush(); blocks.append(.heading(String(line.dropFirst(3)), 2)) }
            else if line.hasPrefix("---") { flush(); blocks.append(.rule) }
            else if line.hasPrefix("|") && line.allSatisfy({ "|- ".contains($0) }) { flush() }
            else if line.hasPrefix("|") {
                flush()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.count >= 2 && cells[0].lowercased() != "what" { blocks.append(.pair(cells[0], cells[1])) }
            }
            else if line.hasPrefix("- ") { flush(); blocks.append(.bullet(String(line.dropFirst(2)))) }
            else if raw.hasPrefix("  "), paragraph.isEmpty, case .bullet(let text)? = blocks.last {
                blocks[blocks.count - 1] = .bullet(text + " " + line)
            }
            else { paragraph += paragraph.isEmpty ? line : " " + line }
        }
        flush()
        return blocks
    }
}

// MARK: - Accessibility

struct WyrmAccessibilityPage: View {
    let close: () -> Void
    @ObservedObject var store = WyrmThemeStore.shared
    /// A theme change rebuilds the shell; the fold remembers it was open.
    static var rememberedOpen = false
    @State var advancedOpen = WyrmAccessibilityPage.rememberedOpen
    var body: some View {
        WSScaffold(title: "Accessibility", onBack: close) {
            WSSectionLabel("Themes", top: 18)
            WSCard {
                ForEach(Array(WyrmThemeID.allCases.enumerated()), id: \.element) { index, theme in
                    if index > 0 { WSHairline() }
                    let palette = theme.palette.withIntensity(store.intensity)
                    Button { withAnimation(.easeInOut(duration: 0.3)) { store.select(theme) } } label: {
                        HStack(spacing: 0) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.paper.color)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(palette.rule.color, lineWidth: 1))
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.card.color)
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.rule.color, lineWidth: 1))
                                    .frame(width: 38, height: 23).frame(maxHeight: .infinity)
                                HStack(spacing: 3) { ForEach([palette.ink, palette.live, palette.link], id: \.argb) { Circle().fill($0.color).frame(width: 5, height: 5) } }
                                    .padding(.bottom, 6)
                            }.frame(width: 58, height: 42)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(theme.displayName).font(.androidWyrm(15.5, store.theme == theme ? .semibold : .regular)).foregroundColor(ATheme.ink)
                                Text(theme.description).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                            WSRadio(selected: store.theme == theme)
                        }.padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 68).contentShape(Rectangle())
                    }.buttonStyle(WSPressStyle())
                }
            }
            Text("Themes colour the app and arena interface only. Skins, arena background and gameplay stay untouched.")
                .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).lineSpacing(5)
                .padding(.horizontal, 16).padding(.top, 12)
            WSAdvancedFold(label: "Advanced settings", open: advancedOpen) {
                withAnimation(.easeInOut(duration: 0.25)) { advancedOpen.toggle() }
                Self.rememberedOpen = advancedOpen
            }
            if advancedOpen {
                WSCard {
                    WSSliderRow(title: "Theme intensity", valueText: "\(Int((store.intensity * 100).rounded()))%",
                                detail: "50% is the original theme look. Lower moves towards Paper; higher is richer.",
                                value: store.intensity, range: 0...1, first: true) { store.setIntensity($0) }
                    WSHairline()
                    WSOutlineButton(label: "Reset", enabled: abs(store.intensity - 0.5) >= 0.001) { store.setIntensity(0.5) }.padding(14)
                }
            }
        }
    }
}

// MARK: - Backup & version

/// Everything that makes this phone's Wyrm yours, in one portable file:
/// every engine setting, every button, the skin, the theme and notification
/// choices. Account and Team secrets stay in Keychain and are never exported.
struct WyrmBackup: Codable {
    static let lastKey = "wyrm.ios.backup.last"
    var format = 1
    var created: String
    var app: String
    var settingsFormat: String
    var settings: [String: [Double]]
    var hotkeys: [Hotkey]
    var defaults: [String: Value]

    struct Hotkey: Codable { var id: Int; var key: Int; var mode: Int; var visible: Bool; var x: Double; var y: Double }

    enum Value: Codable {
        case string(String), bool(Bool), int(Int), double(Double)

        init?(_ any: Any) {
            if let text = any as? String { self = .string(text); return }
            guard let number = any as? NSNumber else { return nil }
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
            else if CFNumberIsFloatType(number as CFNumber) { self = .double(number.doubleValue) }
            else { self = .int(number.intValue) }
        }

        var object: Any {
            switch self {
            case .string(let v): return v
            case .bool(let v): return v
            case .int(let v): return v
            case .double(let v): return v
            }
        }

        var text: String? { if case .string(let v) = self { return v }; return nil }
        var number: Double? {
            switch self {
            case .int(let v): return Double(v)
            case .double(let v): return v
            default: return nil
            }
        }
    }

    static let defaultPrefixes = ["wyrm.ios.skin.", "wyrm.ios.arena.", "wyrm.notify.", "wyrm.ios.theme"]

    @MainActor static func capture(_ engine: WyrmShellStore) -> WyrmBackup {
        var defaults: [String: Value] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation()
        where defaultPrefixes.contains(where: key.hasPrefix) {
            defaults[key] = Value(value)
        }
        return WyrmBackup(created: ISO8601DateFormatter().string(from: Date()),
                          app: "\(WyrmBuild.version) (\(WyrmBuild.build))",
                          settingsFormat: engine.settingsVersion,
                          settings: Dictionary(uniqueKeysWithValues: engine.settings.filter { !$0.id.hasPrefix("tags.index") }.map { ($0.id, $0.values) }),
                          hotkeys: engine.hotkeys.map { Hotkey(id: $0.id, key: $0.key, mode: $0.mode, visible: $0.visible, x: $0.x, y: $0.y) },
                          defaults: defaults)
    }

    /// The engine mailbox holds 128 changes, so settings go across in slices
    /// a few frames apart instead of all at once. Returns how many were sent.
    @MainActor func restore(into engine: WyrmShellStore) async -> Int {
        let known = Set(engine.settings.map(\.id))
        let rows = settings.filter { known.contains($0.key) && !$0.value.isEmpty }.sorted { $0.key < $1.key }
        for (key, value) in defaults { UserDefaults.standard.set(value.object, forKey: key) }
        var index = 0
        while index < rows.count {
            for row in rows[index..<min(index + 60, rows.count)] { engine.write(id: row.key, values: row.value) }
            index += 60
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        for key in hotkeys {
            guard let base = engine.hotkeys.first(where: { $0.id == key.id }) else { continue }
            var next = base; next.mode = key.mode; next.visible = key.visible; next.x = key.x; next.y = key.y
            engine.writeHotkey(next, log: false)
        }
        WyrmBackup.reapplySkin(engine)
        return rows.count
    }

    /// The Skin Studio's saved choice, sent to the engine the same way the
    /// studio sends it.
    @MainActor static func reapplySkin(_ engine: WyrmShellStore) {
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
}

struct WyrmBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct WyrmBackupPage: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @AppStorage(WyrmBackup.lastKey) var lastBackup = ""
    @AppStorage("wyrm.ios.backup.detail") var lastDetail = ""
    @State var exporting = false
    @State var importing = false
    @State var document = WyrmBackupDocument(data: Data())
    @State var working = ""
    @State var failed = false
    @State var confirmingReset = false

    var body: some View {
        WSScaffold(title: "Backup", onBack: close) {
            WSCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Circle().fill(failed ? ATheme.badge : ATheme.live).frame(width: 6, height: 6)
                        Text("LAST BACKUP").font(.androidWyrm(11.5, .semibold)).tracking(0.8).foregroundColor(failed ? ATheme.badge : ATheme.live)
                    }
                    Text(working.isEmpty ? (lastBackup.isEmpty ? "No backup from this phone yet" : "Backed up \(lastBackup)") : working)
                        .font(.androidWyrm(19, .semibold)).foregroundColor(ATheme.ink).padding(.top, 9)
                    Text(lastDetail.isEmpty ? "Skins, controls, settings and theme." : lastDetail)
                        .font(.androidWyrm(13)).foregroundColor(ATheme.quiet).padding(.top, 3).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) {
                        WSPrimaryButton(label: exporting ? "Backing up…" : "Back up now", enabled: working.isEmpty) { backUp() }
                        WSOutlineButton(label: importing ? "Loading…" : "Restore", enabled: working.isEmpty) { importing = true }
                    }.padding(.top, 14)
                }.padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 14))
            }

            WSSectionLabel("Version")
            WSCard {
                WSValueRow(title: "Wyrm", value: "\(WyrmBuild.version) (\(WyrmBuild.build))", first: true)
                WSValueRow(title: "Updates", value: "New builds install through AltStore")
                if !engine.settingsVersion.isEmpty { WSValueRow(title: "Settings format", value: "v\(engine.settingsVersion)") }
                WSLinkRow(title: "What's in this build") { open(.buildNotes) }
            }

            Spacer().frame(height: 22)
            WSCard {
                WSActionRow(title: confirmingReset ? "Tap again to reset everything" : "Reset everything to defaults", first: true, danger: true) {
                    if confirmingReset { confirmingReset = false; engine.reset(1, message: "All settings reset") } else { confirmingReset = true }
                }
            }
            WSCaption("A backup is one file you keep in Files, iCloud Drive or anywhere else. Account and Team credentials stay in this iPhone's Keychain and are never written into it.")
        }
        // Two file sheets on one view can shadow each other on iOS 15-16, so
        // each lives on its own invisible anchor.
        .background(Color.clear.frame(width: 0, height: 0).fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "Wyrm-backup-\(Self.stamp())") { result in
            switch result {
            case .success:
                failed = false
                lastBackup = Self.readable()
                lastDetail = "\(engine.settings.count) settings, \(engine.hotkeys.count) buttons, skin and theme."
                engine.toast = "Backup saved"
            case .failure(let error):
                failed = true
                engine.toast = "Backup not saved: \(error.localizedDescription)"
            }
        })
        .background(Color.clear.frame(width: 0, height: 0).fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let backup = try? JSONDecoder().decode(WyrmBackup.self, from: data) else {
                failed = true
                engine.toast = "That file is not a Wyrm backup"
                return
            }
            failed = false
            working = "Restoring backup…"
            if let theme = WyrmThemeID(rawValue: (backup.defaults["wyrm.ios.theme"]?.text ?? "paper").lowercased()) { WyrmThemeStore.shared.select(theme) }
            if let intensity = backup.defaults["wyrm.ios.theme-intensity"]?.number { WyrmThemeStore.shared.setIntensity(intensity) }
            Task { @MainActor in
                let count = await backup.restore(into: engine)
                working = ""
                lastDetail = "Restored \(count) settings from \(backup.app)."
                engine.toast = "Backup restored"
            }
        })
    }

    private func backUp() {
        guard let data = try? JSONEncoder().encode(WyrmBackup.capture(engine)) else { failed = true; return }
        document = WyrmBackupDocument(data: data)
        exporting = true
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmm"; return f.string(from: Date())
    }
    private static func readable() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: Date())
    }
}

struct WyrmBuildNotesPage: View {
    let close: () -> Void
    var body: some View {
        WSScaffold(title: "This build", parent: "Backup", onBack: close) {
            WSSectionLabel("Wyrm \(WyrmBuild.version) (\(WyrmBuild.build))", top: 18)
            WSCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.notes, id: \.self) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("—").foregroundColor(ATheme.quiet)
                            Text(line).foregroundColor(ATheme.mute).fixedSize(horizontal: false, vertical: true)
                        }.font(.androidWyrm(14)).lineSpacing(5)
                    }
                }.padding(14)
            }
        }
    }

    static let notes = [
        "The Ready Room is laid out like the Android app — the faint W top right, the selected arena card, Playing as and the four actions — and follows your theme.",
        "Arrange the layout now opens over a live bot arena, so the real joystick, buttons, minimap and leaderboard move under your finger. Tap the leaderboard to toggle it.",
        "Every switch and segmented pill is the system control: on iOS 26 it lifts into Liquid Glass and can be dragged between options.",
        "The tab bar is clear glass; its pill rests flat and lifts into a lens when held, dragged or tapped. Icons keep their contrast in every theme.",
        "Opening the app syncs your account behind the launch mark; \"Syncing your Wyrm…\" appears only after signing in or creating an account.",
        "The zoom bar preview knob sits on the bar's centre line again.",
    ]
}

// MARK: - Layout editor

/// Android's `UnifiedArenaLayoutEditor`: one sideways canvas for every piece of
/// the match surface, laid over a bot-driven AI arena. The engine draws the
/// real joystick, buttons, minimap and leaderboard; this layer holds only
/// near-invisible drag targets at the same places, like Android's 0.01 alpha.
/// Positions are written live; Cancel puts back what was there on entry.
struct WyrmLayoutEditor: View {
    @ObservedObject var engine: WyrmShellStore
    let onClose: () -> Void
    @State var snapshot: [EngineSetting] = []
    @State var keySnapshot: [EngineHotkey] = []
    @State var options: Options?
    @State var dragStart: [String: CGPoint] = [:]

    struct Slider { let label: String; let id: String; let range: ClosedRange<Double>; var whole = false }
    struct Options: Identifiable { let id: String; let title: String; let sliders: [Slider]; var zoomChoice = false }

    private enum HUD: String, CaseIterable {
        case minimap, leaderboard, stats, team, chat
        var prefix: String { "hud.\(rawValue)" }
        var fallback: CGPoint {
            switch self {
            case .minimap: return CGPoint(x: 0.095, y: 0.205)
            case .leaderboard: return CGPoint(x: 0.905, y: 0.155)
            case .stats: return CGPoint(x: 0.945, y: 0.530)
            case .team: return CGPoint(x: 0.095, y: 0.610)
            case .chat: return CGPoint(x: 0.790, y: 0.075)
            }
        }
    }

    var body: some View {
        WyrmLandscapeStage { size, _ in canvas(size) }
            .statusBar(hidden: true)
        .onAppear { snapshot = engine.settings; keySnapshot = engine.hotkeys }
    }

    private func canvas(_ size: CGSize) -> some View {
        let scale = UIScreen.main.scale
        let joystick = engine.value("controls.joystick_size", 1)
        let boost = engine.value("controls.boost_size", 1)
        let zoomLength = engine.value("controls.zoom_length", 1)
        let zoomVertical = engine.setting("controls.zoom_orientation")?.index == 1
        let baseOpacity = engine.value("controls.opacity", 1)
        let minimap = min(max(engine.value("general.minimap_size", 300), 128), 512) / scale
        let lbScale = 1 + Double(min(max(Int(engine.value("general.lb_font", 1)), 0), 2)) * 0.16
        let statsScale = (1 + Double(min(max(Int(engine.value("general.stats_font", 1)), 0), 2)) * 0.14) * engine.value("layout.stats_scale", 1)
        let chatScale = engine.value("layout.chat_scale", 1)

        return ZStack {
            // Clear: the AI arena shows through. The near-zero fill still
            // catches stray touches so they never reach the engine below.
            Color.black.opacity(0.001)
            Group {
                if engine.setting("controls.joystick_mode")?.index != 2 {
                    piece("layout.joystick", size, CGSize(width: 112 * joystick, height: 112 * joystick),
                          Options(id: "joystick", title: "JOYSTICK", sliders: [Slider(label: "SIZE", id: "controls.joystick_size", range: 0.65...1.45),
                                                                              Slider(label: "OPACITY", id: "layout.joystick_opacity", range: 0.05...1)])) {
                        WyrmPaperJoystick(diameter: 112 * joystick, opacity: engine.value("layout.joystick_opacity", baseOpacity))
                    }
                }
                if engine.setting("controls.boost_mode")?.index == 1 {
                    piece("layout.boost", size, CGSize(width: 86 * boost, height: 86 * boost),
                          Options(id: "boost", title: "BOOST", sliders: [Slider(label: "SIZE", id: "controls.boost_size", range: 0.65...1.45),
                                                                        Slider(label: "OPACITY", id: "layout.boost_opacity", range: 0.05...1)])) {
                        WyrmPaperBoost(diameter: 86 * boost, opacity: engine.value("layout.boost_opacity", baseOpacity))
                    }
                }
                if engine.setting("controls.zoom_enabled")?.enabled ?? true {
                    let length = 190 * zoomLength
                    piece("layout.zoom", size, CGSize(width: zoomVertical ? 26 : length, height: zoomVertical ? length : 26),
                          Options(id: "zoom", title: "ZOOM", sliders: [Slider(label: "LENGTH", id: "controls.zoom_length", range: 0.65...1.55),
                                                                      Slider(label: "OPACITY", id: "layout.zoom_opacity", range: 0.05...1)], zoomChoice: true)) {
                        WyrmPaperZoomBar(length: length, vertical: zoomVertical, opacity: engine.value("layout.zoom_opacity", baseOpacity), value: 0.45)
                    }
                }
            }
            ForEach(engine.hotkeys.filter(\.visible)) { key in
                let keyScale = engine.value("layout.key_\(key.id)_scale", engine.value("keys.key_scale", 1))
                keyPiece(key, size, CGSize(width: 104 * keyScale, height: 54 * keyScale),
                         Options(id: "key-\(key.id)", title: key.name.uppercased(),
                                 sliders: [Slider(label: "SIZE", id: "layout.key_\(key.id)_scale", range: 0.65...1.60),
                                           Slider(label: "OPACITY", id: "layout.key_\(key.id)_opacity", range: 0.05...1)])) {
                    WyrmPaperKey(label: key.name, opacity: engine.value("layout.key_\(key.id)_opacity", engine.value("keys.opacity", 1)), scale: keyScale)
                }
            }
            Group {
            piece(HUD.minimap.prefix, size, CGSize(width: minimap, height: minimap),
                  Options(id: "minimap", title: "MINIMAP", sliders: [Slider(label: "SIZE", id: "general.minimap_size", range: 128...512, whole: true)]),
                  fallback: HUD.minimap.fallback) {
                Text("MAP").font(.androidWyrm(14, .bold)).foregroundColor(ATheme.ink)
                    .frame(width: minimap, height: minimap)
                    .background(Circle().fill(ATheme.card.opacity(0.18)))
                    .overlay(Circle().stroke(ATheme.ink.opacity(0.76), lineWidth: 3))
            }
            piece(HUD.leaderboard.prefix, size, CGSize(width: 250 * lbScale / scale, height: 132 * lbScale / scale),
                  Options(id: "leaderboard", title: "LEADERBOARD", sliders: [Slider(label: "TEXT SIZE", id: "general.lb_font", range: 0...2, whole: true)]),
                  fallback: HUD.leaderboard.fallback, onTap: { engine.toggleEditorLeaderboard() }) {
                panel("LEADERBOARD\n1  Wyrm Player     9503\n2  Northwind       2819\n3  Orbit            418\n4  Meadow           389\n5  Drift            248",
                      CGSize(width: 250 * lbScale / scale, height: 132 * lbScale / scale))
            }
            piece(HUD.stats.prefix, size, CGSize(width: 142 * statsScale / scale, height: 132 * statsScale / scale),
                  Options(id: "stats", title: "STATS", sliders: [Slider(label: "SIZE", id: "layout.stats_scale", range: 0.65...1.60),
                                                                Slider(label: "OPACITY", id: "layout.stats_opacity", range: 0.05...1)]),
                  fallback: HUD.stats.fallback) {
                panel("STATS\nSCORE   9503\nKILLS      4\nRANK    8 / 46\nPING    64 ms\nFPS     61",
                      CGSize(width: 142 * statsScale / scale, height: 132 * statsScale / scale), opacity: engine.value("layout.stats_opacity", 1))
            }
            piece(HUD.team.prefix, size, CGSize(width: 210 / scale, height: 98 / scale),
                  Options(id: "team", title: "TEAM", sliders: []), fallback: HUD.team.fallback) {
                panel("TEAM\n● Om Rajput       9503\n● Northwind       2819\n○ Meadow           389", CGSize(width: 210 / scale, height: 98 / scale))
            }
            piece(HUD.chat.prefix, size, CGSize(width: 124 * chatScale / scale, height: 56 * chatScale / scale),
                  Options(id: "chat", title: "CHAT", sliders: [Slider(label: "SIZE", id: "layout.chat_scale", range: 0.65...1.60),
                                                              Slider(label: "OPACITY", id: "layout.chat_opacity", range: 0.05...1)]),
                  fallback: HUD.chat.fallback) {
                Text("CHAT").font(.androidWyrm(12, .bold)).foregroundColor(ATheme.ink)
                    .frame(width: 124 * chatScale / scale, height: 56 * chatScale / scale)
                    .background(RoundedRectangle(cornerRadius: 28).fill(ATheme.card.opacity(0.94 * engine.value("layout.chat_opacity", 1))))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(ATheme.ink.opacity(0.45), lineWidth: 1.5))
            }
            }
            VStack { Spacer(); footer }.padding(.bottom, 14)
            if let options { optionsPopup(options) }
        }
        .coordinateSpace(name: "wyrm-layout")
        .clipped()
    }

    private func panel(_ text: String, _ size: CGSize, opacity: Double = 1) -> some View {
        Text(text).font(.androidWyrm(12)).lineSpacing(6).foregroundColor(ATheme.ink)
            .frame(width: size.width, height: size.height, alignment: .topLeading).padding(0)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.card.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .opacity(min(max(opacity, 0.05), 1))
    }

    /// A draggable control or HUD panel whose position is a `prefix_x/_y` pair.
    private func piece<V: View>(_ prefix: String, _ area: CGSize, _ child: CGSize, _ more: Options,
                                fallback: CGPoint = CGPoint(x: 0.5, y: 0.7), onTap: (() -> Void)? = nil,
                                @ViewBuilder content: () -> V) -> some View {
        let x = engine.setting("\(prefix)_x")?.number ?? fallback.x
        let y = engine.setting("\(prefix)_y")?.number ?? fallback.y
        return draggable(key: prefix, centre: wsPreviewCentre(x: x, y: y, in: area, child: child), area: area, child: child, more: more,
                         onTap: onTap, move: { engine.moveLayout(prefix, x: $0.x, y: $0.y) }, content: content)
    }

    private func keyPiece<V: View>(_ key: EngineHotkey, _ area: CGSize, _ child: CGSize, _ more: Options, @ViewBuilder content: () -> V) -> some View {
        draggable(key: "key-\(key.id)", centre: wsPreviewCentre(x: key.x, y: key.y, in: area, child: child), area: area, child: child, more: more,
                  move: { point in
                      guard var next = engine.hotkeys.first(where: { $0.id == key.id }) else { return }
                      next.x = point.x; next.y = point.y
                      engine.writeHotkey(next, log: false)
                  }, content: content)
    }

    /// Reads the centre when the drag begins and adds the whole translation to
    /// it, so the piece follows the finger instead of chasing stale positions.
    private func draggable<V: View>(key: String, centre: CGPoint, area: CGSize, child: CGSize, more: Options,
                                    onTap: (() -> Void)? = nil,
                                    move: @escaping (CGPoint) -> Void, @ViewBuilder content: () -> V) -> some View {
        content()
            .opacity(0.012)
            .frame(width: child.width, height: child.height)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { onTap?() })
            .position(centre)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("wyrm-layout"))
                .onChanged { value in
                    let start = dragStart[key] ?? centre
                    if dragStart[key] == nil { dragStart[key] = centre }
                    let halfW = min(child.width / 2, area.width / 2), halfH = min(child.height / 2, area.height / 2)
                    let nx = min(max(start.x + value.translation.width, halfW), area.width - halfW)
                    let ny = min(max(start.y + value.translation.height, halfH), area.height - halfH)
                    move(CGPoint(x: nx / area.width, y: ny / area.height))
                }
                .onEnded { _ in dragStart[key] = nil })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { options = more }
            })
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("HOLD ANY OBJECT FOR MORE OPTIONS").font(.androidWyrm(9)).tracking(0.6).foregroundColor(ATheme.quiet)
            footerAction("CANCEL") { cancel() }
            footerAction("RESET") {
                engine.reset(2, message: ""); engine.reset(4, message: ""); engine.reset(8, message: "Layout reset")
            }
            footerAction("SAVE", filled: true) { onClose() }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 5)
        .background(Capsule().fill(ATheme.card.opacity(0.96)))
        .overlay(Capsule().stroke(ATheme.rule, lineWidth: 1))
    }

    private func footerAction(_ label: String, filled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.androidWyrm(9, .bold)).tracking(1).foregroundColor(filled ? ATheme.onInk : ATheme.quiet)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Capsule().fill(filled ? ATheme.ink : Color.clear))
        }.buttonStyle(.plain)
    }

    private func optionsPopup(_ options: Options) -> some View {
        ZStack {
            Color.black.opacity(0.001).onTapGesture { self.options = nil }
            VStack(alignment: .leading, spacing: 10) {
                Text(options.title).font(.androidWyrm(13, .bold)).tracking(1.4).foregroundColor(ATheme.ink)
                if options.sliders.isEmpty && !options.zoomChoice {
                    Text("POSITION ONLY").font(.androidWyrm(11)).tracking(1).foregroundColor(ATheme.quiet)
                }
                ForEach(options.sliders, id: \.id) { slider in
                    Text(slider.label).font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                    let fallback = slider.id.hasPrefix("layout.key_") ? engine.value(slider.id.hasSuffix("opacity") ? "keys.opacity" : "keys.key_scale", 1)
                        : slider.id.hasPrefix("layout.") && slider.id.hasSuffix("opacity") ? engine.value("controls.opacity", 1) : 1
                    SwiftUI.Slider(value: Binding(get: { min(max(engine.value(slider.id, fallback), slider.range.lowerBound), slider.range.upperBound) },
                                                  set: { engine.write(id: slider.id, values: [slider.whole ? $0.rounded() : $0]) }),
                                   in: slider.range, step: slider.whole ? 1 : 0.01)
                        .tint(ATheme.ink)
                }
                if options.zoomChoice, let orientation = engine.setting("controls.zoom_orientation") {
                    Text("ORIENTATION").font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                    WSSegmented(options: ["Horizontal", "Vertical"], selected: orientation.index == 1 ? 1 : 0) {
                        engine.write(orientation, values: [Double($0)])
                    }
                }
                HStack { Spacer(); Button("DONE") { self.options = nil }.font(.androidWyrm(10, .bold)).foregroundColor(ATheme.ink).padding(8) }
            }
            .padding(18).frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Puts back every position, size and opacity the editor could have moved.
    private func cancel() {
        let editable: (String) -> Bool = { id in
            id.hasPrefix("layout.") || id.hasPrefix("hud.") || id == "controls.joystick_size" || id == "controls.boost_size"
                || id == "controls.zoom_length" || id == "controls.zoom_orientation" || id == "general.minimap_size" || id == "general.lb_font"
        }
        for old in snapshot where editable(old.id) {
            if let now = engine.setting(old.id), now.values != old.values { engine.write(now, values: old.values) }
        }
        for old in keySnapshot {
            if let now = engine.hotkeys.first(where: { $0.id == old.id }), now != old { engine.writeHotkey(old, log: false) }
        }
        onClose()
    }
}
