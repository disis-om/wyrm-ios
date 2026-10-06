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
    @ObservedObject var performance = WyrmPerformance.shared
    @ObservedObject var support = WyrmSupportStore.shared
    let open: (WyrmDesignRoute) -> Void
    @AppStorage("wyrm.ios.developer-mode") var developerMode = false
    @State var confirming = false
    @ObservedObject var search = WyrmSettingsFocus.shared

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WYRM").font(.androidWyrm(11.5, .semibold)).tracking(0.92).foregroundColor(ATheme.quiet)
                    Text("Settings").font(.androidWyrm(30, .bold)).tracking(-0.5).foregroundColor(ATheme.ink)
                }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

                WyrmSettingsSearchField(query: $search.query)

                if !search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    WyrmSettingsSearchResults(query: search.query.trimmingCharacters(in: .whitespaces), engine: engine) { route in
                        if let route { open(route) } else { withAnimation(.easeOut(duration: 0.2)) { search.query = "" } }
                    }
                    Spacer().frame(height: 102)
                } else {
                Group {
                group("Arena", [
                    ("Display", "Scores, names, minimap, text sizes", "", .display),
                    ("Controls", "Steering, boost, zoom bar", engine.setting("controls.joystick_mode")?.index == 2 || WyrmPlayOrientation.shared.portrait ? "Arrow" : "Joystick", .controls),
                    ("On-screen buttons", "Which buttons appear and how they fire", engine.hotkeys.isEmpty ? "" : "\(WyrmButtonsContent.allowed(engine.hotkeys).filter(\.visible).count) on", .buttons),
                ])
                group("Playing help", [
                    ("Modes", "Normal, Assist, helper lines and arena colours", "", .modes),
                    ("Bot", "When it circles, how wide it swings", "", .bot),
                ])
                group("Food", [("Food style", "Original, rings and geometric shapes", WyrmFoodPage.label(engine), .food)])
                group("Performance", [("Performance", "Frame rate, heat and battery", performance.summary, .performance)])
                group("Account", [
                    ("Profile", "Name, username, photo, bio", account.player?.handle ?? "", .profile("")),
                    ("Notifications", "Invites, team pings, follows", notifications.enabledCount > 0 ? "\(notifications.enabledCount) on" : "", .notificationSettings),
                    ("Privacy", "Who can reach you, what is stored", "", .privacy),
                ])
                group("Accessibility", [("Themes", "Paper, dark and colour appearances", theme.theme.displayName, .themes)])
                group("This device", [(
                    "Updates & version",
                    "Wyrm \(WyrmBuild.version) · your settings are saved to your account",
                    "", .backup)])
                group("Help & feedback", [("Help & feedback", "Report a problem, suggest an idea, crash reports", "", .help)])
                group("About", [("About Wyrm", "The story, the maker, and how to support", "", .about)])
                }

                WSSectionLabel("Developer", top: 0)
                WSCard {
                    WSBoolRow(title: "Developer Mode", detail: "Local diagnostics and export tools", on: developerMode, first: true) { developerMode = $0 }
                        .wyrmSettingAnchor("app.developer")
                    if developerMode { WSValueRow(title: "Wyrm logs", value: "7 days", onOpen: { open(.developer) }) }
                }
                Spacer().frame(height: 22)

                WSCard {
                    WSActionRow(title: confirming ? "Tap again to reset everything" : "Reset everything to defaults", first: true, danger: true) {
                        if confirming { confirming = false; engine.reset(1, message: "All settings reset") } else { confirming = true }
                    }
                }
                // Log out (OM, 2026-10-01): the very bottom of Settings; asks first.
                Spacer().frame(height: 22)
                WSCard {
                    WSActionRow(title: "Log out", first: true, danger: true) {
                        WyrmAccountSync.shared.askingLogOut = true
                    }
                }
                Text(engine.settingsVersion.isEmpty ? "Wyrm" : "Wyrm · settings format v\(engine.settingsVersion)")
                    .font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                    .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 12)
                Spacer().frame(height: 102)
                }
            }
        }
        .wyrmTourScroll(proxy)
        .onChange(of: search.pulse) { _ in
            // Hub settings: the search just cleared, so scroll the row into view.
            guard search.target == "app.developer" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("app.developer", anchor: .center) }
            }
        }
        }
        .onAppear { notifications.refreshSystem() }
    }

    /// The app tour lights these groups (OM, 2026-10-05).
    private static let tourIDs = ["Arena": "settings.arena", "Playing help": "settings.help",
                                  "Performance": "settings.performance", "Account": "settings.account",
                                  "Help & feedback": "settings.support"]

    @ViewBuilder
    private func group(_ title: String, _ rows: [(String, String, String, WyrmDesignRoute)]) -> some View {
        if let id = Self.tourIDs[title] {
            groupBody(title, rows).wyrmTourAnchor(id)
        } else {
            groupBody(title, rows)
        }
    }

    private func groupBody(_ title: String, _ rows: [(String, String, String, WyrmDesignRoute)]) -> some View {
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
                                // The Settings tab's count, on the row that leads to it.
                                if row.3 == .help && support.unseenReplies > 0 {
                                    WyrmCountBadge(count: support.unseenReplies)
                                    Spacer().frame(width: 8)
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
    /// Look ahead (OM, 2026-10-05): lives on Display, not Controls.
    @ObservedObject private var playFeel = WyrmPlayFeelStore.shared
    private static let basicIDs = ["general.snake_scores", "general.show_own_name", "general.minimap_size", "general.ui_font"]

    var body: some View {
        let basic = Self.basicIDs.compactMap { engine.setting($0) }
        let rest = engine.settings.filter {
            ($0.group == "general" || $0.group.hasPrefix("general.")) && $0.group != "general.bot"
                && !Self.basicIDs.contains($0.id) && !$0.label.isEmpty
                && $0.id != "general.vsync" // Settings › Performance owns it now
        }
        WSScaffold(title: "Display", onBack: close) {
            WSSectionLabel("Basic", top: 18)
                .onAppear { if rest.contains(where: { WyrmSettingsFocus.shared.wants($0.id) }) { advanced = true } }
            WSCard { WSRows(rows: basic, engine: engine) }
            // Look ahead (OM, 2026-10-05): moved off Controls. Same switch, both modes.
            WSSectionLabel("Camera")
            WSCard {
                WSBoolRow(title: "Look ahead",
                          detail: "Like slither: the view moves ahead of your snake, toward where it is going, and a little further while boosting.",
                          on: playFeel.lookAhead, first: true) { playFeel.setLookAhead($0) }
                    .wyrmSettingAnchor("app.look-ahead")
            }
            if basic.isEmpty { WSCaption("These controls appear as soon as the engine has started.") }
            if !rest.isEmpty {
                WSAdvancedFold(label: "Advanced", open: advanced) { withAnimation(.easeInOut(duration: 0.25)) { advanced.toggle() } }
                if advanced {
                    WSCard { WSRows(rows: rest, engine: engine) }
                    WSCaption("Zoom step, cursor size and after-death delay live here — the things nobody touches twice. Frame rate is in Settings › Performance.")
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
                   }.padding(.horizontal, 14).padding(.vertical, 10).wyrmTourAnchor("controls.tabs")),
                   onBack: close) {
            ZStack(alignment: .top) {
                switch tab {
                case .controls: WyrmControlsContent(engine: engine).transition(slide)
                case .buttons: WyrmButtonsContent(engine: engine).transition(slide)
                case .arenaUI: WyrmArenaUIContent(engine: engine).transition(slide)
                }
            }
        }
        .wyrmAdjustPreviewCard(engine: engine)
        // The app tour picks the tab its step is about (OM, 2026-10-05).
        .onReceive(WyrmTour.shared.$step) { _ in
            DispatchQueue.main.async {
                let wanted: WyrmControlsTab?
                switch WyrmTour.shared.current?.place {
                case .controls?: wanted = .controls
                case .buttons?: wanted = .buttons
                case .arenaUI?: wanted = .arenaUI
                default: wanted = nil
                }
                guard let wanted, wanted != tab else { return }
                direction = wanted.rawValue > tab.rawValue ? 1 : -1
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26)) { tab = wanted }
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
    var body: some View {
        WSScaffold(title: "Controls", parent: parent, onBack: close) { WyrmControlsContent(engine: engine) }
            .wyrmAdjustPreviewCard(engine: engine)
    }
}

struct WyrmControlsContent: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var orientation = WyrmPlayOrientation.shared
    /// Home › Near Original (OM, 2026-10-02): slither's own joystick, boost and
    /// arrow; only the arrow's size stays the player's. Nothing stored changes.
    @ObservedObject var nearOriginal = WyrmNearOriginalStore.shared
    /// The zoom bar's style (OM, 2026-10-05). Look ahead lives on Display.
    @ObservedObject var playFeel = WyrmPlayFeelStore.shared
    @State var behaviourOpen = false
    @State var zoomOpen = false

    var body: some View {
        let steeringSetting = engine.setting("controls.joystick_mode")
        let steering = steeringSetting?.index ?? 0
        // Upright play steers with the arrow only (OM, 2026-10-02; engine
        // mobile_controls_steering_mode); the sideways choice is kept.
        let arrow = orientation.portrait || steering == 2
        let boostMode = engine.setting("controls.boost_mode")
        let boostButton = (boostMode?.index ?? 0) == 1
        let joystickSize = engine.setting("controls.joystick_size")
        let boostSize = engine.setting("controls.boost_size")
        let opacity = engine.setting("controls.opacity")
        let handedness = engine.setting("controls.handedness")
        let zoomRows = engine.settings.filter { $0.group == "controls.zoom" }

        VStack(alignment: .leading, spacing: 0) {
            WyrmControlsPreview(engine: engine).padding(.horizontal, 16).padding(.top, 16)

            // Play orientation (OM, 2026-10-01): the lobby, the match and the editor upright.
            WSSectionLabel("Play orientation")
            WSCard {
                WSEnumBlock(title: "Hold the phone",
                            detail: "Portrait turns the lobby, the match and the layout editor upright. Each way keeps its own layout.",
                            options: ["Landscape", "Portrait"], selected: orientation.portrait ? 1 : 0, first: true) { pick in
                    orientation.switchTo(pick == 1, engine: engine)
                }
                .wyrmSettingAnchor("app.play-orientation")
            }

            WSSectionLabel("Basic · steering")
            WSCard {
                if !orientation.portrait {
                    WSEnumBlock(title: "Steering style", options: ["Joystick", "Arrow"], selected: arrow ? 1 : 0, first: true) { pick in
                        guard let setting = steeringSetting else { return }
                        engine.write(setting, values: [pick == 1 ? 2 : Double((0...1).contains(steering) ? steering : 0)])
                    }
                    .wyrmSettingAnchor("controls.joystick_mode")
                }
                if !arrow, !nearOriginal.on, let setting = steeringSetting, setting.options.count >= 2 {
                    let behaviour = Array(setting.options.prefix(2))
                    WSValueRow(title: "Joystick behaviour", value: behaviour[min(max(steering, 0), 1)]) {
                        withAnimation(.easeInOut(duration: 0.25)) { behaviourOpen.toggle() }
                    }
                    if behaviourOpen {
                        WSSegmented(options: behaviour, selected: min(max(steering, 0), 1)) { engine.write(setting, values: [Double($0)]) }
                            .padding(.horizontal, 14).padding(.bottom, 14)
                    }
                }
                // Upright there is no left or right hand (OM, 2026-10-02): the row
                // hides; the stored choice stays for sideways play.
                if let handedness, !orientation.portrait {
                    WSEnumBlock(title: handedness.label, detail: handedness.hint, options: ["Left", "Right"],
                                selected: min(max(handedness.index, 0), 1)) { engine.write(handedness, values: [Double($0)]) }
                        .wyrmSettingAnchor(handedness.id)
                }
                if let boostMode {
                    WSEnumBlock(title: "Boost", detail: boostMode.hint, options: boostMode.options,
                                selected: min(max(boostMode.index, 0), max(boostMode.options.count - 1, 0)),
                                first: orientation.portrait) { engine.write(boostMode, values: [Double($0)]) }
                        .opacity(nearOriginal.on ? 0.38 : 1).allowsHitTesting(!nearOriginal.on)
                        .wyrmSettingAnchor(boostMode.id)
                }
            }

            if orientation.portrait { WSCaption("Upright you always steer with the arrow: the joystick is for sideways play, and your sideways choice is kept. No left or right hand: your first finger steers, a second finger boosts.") }

            if nearOriginal.on { WSCaption("Near Original is on: slither's own joystick, boost button and arrow, at their original places. Only the arrow's size is yours. Turn it off on Home to bring your own back.") }

            WSSectionLabel("Basic · size")
            WSCard {
                let sizeRows = [arrow ? nil : joystickSize, boostButton ? boostSize : nil, opacity].compactMap { $0 }
                WSRows(rows: sizeRows, engine: engine)
            }
            .opacity(nearOriginal.on ? 0.38 : 1).allowsHitTesting(!nearOriginal.on)

            if arrow {
                WSSectionLabel("Basic · arrow")
                if nearOriginal.on {
                    WSCard { if let size = engine.setting("arrow.size") { WSTypedRow(setting: size, engine: engine) } }
                } else {
                    WyrmArrowSettingsCard(engine: engine).wyrmSettingAnchor("app.arrow-style", card: true)
                }
            }

            if !zoomRows.isEmpty {
                WSAdvancedFold(label: "Advanced · zoom bar", open: zoomOpen) { withAnimation(.easeInOut(duration: 0.25)) { zoomOpen.toggle() } }
                if zoomOpen {
                    WSCard {
                        WSRows(rows: zoomRows, engine: engine)
                        // The zoom bar's style (OM, 2026-10-05): the slider, or a
                        // spring whose knob rests in the middle and springs back.
                        WSHairline()
                        VStack(alignment: .leading, spacing: 8) {
                            // The bar itself, so Slider and Spring can be felt here (OM, 2026-10-05).
                            WyrmZoomBarActionPreview(
                                vertical: engine.setting("controls.zoom_orientation")?.index == 1,
                                springStyle: playFeel.zoomSpring)
                            Text("Zoom bar style").font(.androidWyrm(15.5)).foregroundColor(ATheme.ink)
                            WSSegmented(options: ["Slider", "Spring"], selected: playFeel.zoomSpring ? 1 : 0) {
                                playFeel.setZoomSpring($0 == 1)
                            }
                            Text(playFeel.zoomSpring
                                 ? "Push the knob toward + to zoom in, toward - to zoom out; let go and it springs back to the middle."
                                 : "Slide to the zoom you want; it stays there.")
                                .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .wyrmSettingAnchor("app.zoom-style")
                    }
                }
            }

            VStack(spacing: 9) {
                WSPrimaryButton(label: "Arrange the layout") { engine.openLayoutEditor() }
                WSOutlineButton(label: "Reset positions") {
                    WyrmPlayOrientation.shared.reset([2], engine: engine, message: "Control positions reset")
                }
            }.padding(.horizontal, 16).padding(.top, 22)
            WSCaption("Opens sideways, the way you hold the phone in a match.")
        }
        .onAppear { if zoomRows.contains(where: { WyrmSettingsFocus.shared.wants($0.id) }) { zoomOpen = true } }
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
        // slither's own arrow (Near Original, 2026-10-02), from the original's 64 px shape.
        [(-0.56, -0.3155), (-0.56, 0.3155), (0, 0.2227), (0, 0.7423), (0.56, 0), (0, -0.7423), (0, -0.2227)],
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
    @ObservedObject var arrowSkins = WyrmArrowSkinStore.shared
    @ObservedObject var orientation = WyrmPlayOrientation.shared
    var body: some View {
        let steering = engine.setting("controls.joystick_mode")?.index ?? 0
        let opacity = engine.value("controls.opacity", 1)
        let arrowChannels = engine.setting("arrow.color")?.channels ?? [1, 1, 1, 1]
        let arrowSize = engine.value("arrow.size", 1)
        let arrowStyle = engine.setting("arrow.style")?.index ?? 0
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Text("PREVIEW").font(.androidWyrm(9, .bold)).tracking(1.4).foregroundColor(ATheme.quiet).padding(12)
                if steering != 2 && !orientation.portrait {
                    WyrmPaperJoystick(diameter: 60 * engine.value("controls.joystick_size", 1), opacity: opacity)
                        .wyrmAdjustPlace(.joystick)
                        .position(previewCentre("layout.joystick", proxy.size, child: 60 * engine.value("controls.joystick_size", 1)))
                } else {
                    // The arena's arrow as chosen: a drawn style or an image skin.
                    WyrmArrowGlyph(codeStyle: arrowStyle, imageSkin: arrowSkins.skin, colour: arrowChannels,
                                   brightness: arrowSkins.brightness)
                        .frame(width: 104 * arrowSize, height: 74 * arrowSize)
                        .opacity(min(max(opacity, 0), 1))
                        .wyrmAdjustPlace(.arrow)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                if engine.setting("controls.boost_mode")?.index == 1 {
                    let d = 46 * engine.value("controls.boost_size", 1)
                    WyrmPaperBoost(diameter: d, opacity: opacity).wyrmAdjustPlace(.boost).position(previewCentre("layout.boost", proxy.size, child: d))
                }
                if engine.setting("controls.zoom_enabled")?.enabled ?? true {
                    let vertical = engine.setting("controls.zoom_orientation")?.index == 1
                    let length = 102 * engine.value("controls.zoom_length", 1)
                    WyrmPaperZoomBar(length: length, vertical: vertical, opacity: opacity, value: 0.45)
                        .wyrmAdjustPlace(.zoom)
                        .position(previewCentre("layout.zoom", proxy.size, child: vertical ? 26 : length, childHeight: vertical ? length : 26))
                }
            }
        }
        .frame(width: orientation.portrait ? 160 : nil, height: orientation.portrait ? 300 : 190)
        .frame(maxWidth: .infinity)
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

/// Slider stays where you leave it. Spring returns to the middle, as in a match.
struct WyrmZoomBarActionPreview: View {
    let vertical: Bool
    let springStyle: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var held: CGFloat = 0.45
    @State private var pull: CGFloat = 0
    @State private var dragging = false
    @State private var springTask: Task<Void, Never>?

    /// 0 is the minus end, 1 the plus end. A spring rests at half.
    private var shown: CGFloat {
        springStyle ? min(1, max(0, CGFloat(0.5) + pull * CGFloat(0.5))) : held
    }

    var body: some View {
        let length: CGFloat = vertical ? 156 : 220
        let thickness: CGFloat = 26
        let travel = length - thickness
        let along = vertical ? 1 - shown : shown
        let knobAt = thickness / 2 + travel * along
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
            VStack(spacing: 8) {
                ZStack {
                    Capsule().fill(ATheme.card)
                    barFill(length: length, thickness: thickness, knobAt: knobAt)
                    if springStyle { springMarks(length: length, thickness: thickness) }
                    Circle().fill(ATheme.ink).frame(width: 18, height: 18)
                        .offset(x: vertical ? 0 : knobAt - length / 2, y: vertical ? knobAt - length / 2 : 0)
                }
                .frame(width: vertical ? thickness : length, height: vertical ? length : thickness)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(ATheme.ink, lineWidth: 1))
                .frame(width: vertical ? 48 : length, height: vertical ? length : 48)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            springTask?.cancel()
                            dragging = true
                            let pos = vertical ? value.location.y : value.location.x
                            let t = min(1, max(0, vertical ? 1 - pos / length : pos / length))
                            var step = Transaction()
                            step.animation = nil
                            withTransaction(step) {
                                if springStyle { pull = (t - CGFloat(0.5)) * 2 }
                                else { held = t }
                            }
                        }
                        .onEnded { _ in
                            dragging = false
                            guard springStyle else { return }
                            springTask?.cancel()
                            if reduceMotion {
                                pull = 0
                                return
                            }
                            // Same return as the arena bar: each frame multiplies the pull by 0.72.
                            springTask = Task { @MainActor in
                                while abs(pull) > CGFloat(0.01) {
                                    if Task.isCancelled { return }
                                    try? await Task.sleep(nanoseconds: 16_000_000)
                                    if Task.isCancelled { return }
                                    pull *= CGFloat(0.72)
                                }
                                pull = 0
                            }
                        }
                )
                .accessibilityLabel("Zoom bar preview")
                Text("Move the zoom bar to see its action.")
                    .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(ATheme.well)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        }
        .onDisappear { springTask?.cancel() }
    }

    /// The ink run: from the near end for a slider, from the middle for a spring.
    @ViewBuilder private func barFill(length: CGFloat, thickness: CGFloat, knobAt: CGFloat) -> some View {
        let mid = length / 2
        if springStyle {
            let from = min(mid, knobAt)
            let span = max(1, abs(knobAt - mid))
            Rectangle().fill(ATheme.track)
                .frame(width: vertical ? thickness : span, height: vertical ? span : thickness)
                .offset(x: vertical ? 0 : from - length / 2 + span / 2,
                        y: vertical ? from - length / 2 + span / 2 : 0)
        } else if vertical {
            Rectangle().fill(ATheme.track)
                .frame(width: thickness, height: max(1, length - knobAt))
                .offset(y: knobAt / 2)
        } else {
            Rectangle().fill(ATheme.track)
                .frame(width: max(1, knobAt), height: thickness)
                .offset(x: knobAt / 2 - length / 2)
        }
    }

    private func springMarks(length: CGFloat, thickness: CGFloat) -> some View {
        let mark = thickness * 0.22
        let inset = thickness * 1.1
        return Canvas { context, _ in
            func line(_ a: CGPoint, _ b: CGPoint) {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(ATheme.ink), lineWidth: 2.5)
            }
            if vertical {
                let x = thickness / 2
                let plus = inset
                let minus = length - inset
                line(CGPoint(x: x - mark, y: plus), CGPoint(x: x + mark, y: plus))
                line(CGPoint(x: x, y: plus - mark), CGPoint(x: x, y: plus + mark))
                line(CGPoint(x: x - mark, y: minus), CGPoint(x: x + mark, y: minus))
            } else {
                let y = thickness / 2
                let minus = inset
                let plus = length - inset
                line(CGPoint(x: minus - mark, y: y), CGPoint(x: minus + mark, y: y))
                line(CGPoint(x: plus - mark, y: y), CGPoint(x: plus + mark, y: y))
                line(CGPoint(x: plus, y: y - mark), CGPoint(x: plus, y: y + mark))
            }
        }
        .frame(width: vertical ? thickness : length, height: vertical ? length : thickness)
        .allowsHitTesting(false)
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
    static let order = [1, 2, 3, 4, 6, 7, 8, 9, 14, 15] // 14 = Auto restart (OM, 2026-10-05), 15 = Eyes back (OM, 2026-10-06)
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
                    WyrmHotkeyRow(key: key, engine: engine).wyrmSettingAnchor("hotkey.\(key.id)")
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

/// One on-screen button: its name, Toggle/Hold (or a fixed Tap) and whether it shows.
struct WyrmHotkeyRow: View {
    let key: EngineHotkey
    @ObservedObject var engine: WyrmShellStore
    var body: some View {
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
    /// Shown in the Snake card, not again under Advanced (OM, 2026-10-05).
    private static let snakeIDs: Set<String> = ["render_mode", "spine", "hide_cosmetics"]

    var body: some View {
        WSScaffold(title: "Modes", parent: parent, onBack: close) {
            // A page that opens on a card keeps the same gap below the header as one
            // that opens on a section label.
            Spacer().frame(height: 18)
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
        .onAppear {
            let target = WyrmSettingsFocus.shared.target ?? ""
            if target.hasPrefix("normal.") { mode = 0 } else if target.hasPrefix("assist.") { mode = 1 }
            if target.hasPrefix("general.laser") { advanced = true }
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
        let rest = rows.filter { row in !colours.contains(where: { $0.id == row.id }) && !Self.foodIDs.contains(local(row)) && !Self.dotIDs.contains(local(row)) && local(row) != "bg_scale" && !Self.snakeIDs.contains(local(row)) }
        let renderMode = rows.first { local($0) == "render_mode" }
        let spine = rows.first { local($0) == "spine" }
        let hideCosmetics = rows.first { local($0) == "hide_cosmetics" }
        let laser = ["general.laser_thickness", "general.laser_color"].compactMap { engine.setting($0) }

        VStack(alignment: .leading, spacing: 0) {
            // Snake look (OM, 2026-10-05): the preview sits on this card, not a landscape page.
            WSSectionLabel("Snake")
            WSCard {
                WyrmSnakeBodyPreview(mode: renderMode?.index ?? 0, spine: spine?.enabled == true,
                                     hideCosmetics: visibleMode == 1 && hideCosmetics?.enabled == true)
                if let renderMode { WSTypedRow(setting: renderMode, engine: engine) }
                if let spine { WSTypedRow(setting: spine, engine: engine) }
                if visibleMode == 1, let hideCosmetics { WSTypedRow(setting: hideCosmetics, engine: engine) }
            }
            WSCaption("Skinless keeps the plain snake's width and length. Only the skin turns see-through. Spine is a thin white line down every snake.")

            WSSectionLabel("Arena colours")
            WSCard { WSRows(rows: colours, engine: engine) }

            // The size slider moved into a live editor over the arena (OM, 2026-10-01).
            WSSectionLabel("Arena background")
            WSCard {
                WSValueRow(title: "Adjust arena background size",
                           value: WyrmBackgroundSize.label(engine.value("normal.bg_scale", WyrmBackgroundSize.standard)),
                           first: true) { engine.openBackgroundEditor() }
                    .wyrmSettingAnchor("app.bg-size")
            }

            WSSectionLabel("Joystick guide")
            WSCard {
                WyrmHeadDotPreview(size: dotSize?.number ?? 10, colour: dotColour?.channels ?? [1, 1, 1, 1])
                if let dot { WSTypedRow(setting: dot, engine: engine) }
                if let dotSize { WSTypedRow(setting: dotSize, engine: engine) }
                if let dotColour { WSColourRow(setting: dotColour, engine: engine).wyrmSettingAnchor(dotColour.id) }
            }

            // OM, 2026-10-01: the assist laser for joystick players, with a live preview.
            if visibleMode == 1 { WyrmJoystickLaserSection(engine: engine) }

            WSAdvancedFold(label: "Advanced · helper lines", open: advanced) { withAnimation(.easeInOut(duration: 0.25)) { advanced.toggle() } }
            if advanced { WSCard { WSRows(rows: laser + rest, engine: engine) } }
        }
    }
}

/// The player's own snake as the arena draws it in each mode (OM, 2026-10-05:
/// "asli skin ... jaisi arena me dikhegi vaisi"). Texture is the Skin tab's own
/// bead drawing (the arena's sprites); Solid and Flat follow the engine's
/// render modes 1 and 2 (`redraw.c`): Solid paints every bead in its pattern
/// colour from the head back, Flat the first bead's colour; Skinless is one
/// see-through stroke (.8) of the plain body's width in that first colour,
/// round at both ends. The head (eyes, accessory, Wyrm look) is drawn in every
/// mode, as in the arena; in assist with "Hide own tag and accessories" on,
/// the accessory and the look are left off. Same as Android's SnakeBodyPreview.
struct WyrmSnakeBodyPreview: View {
    let mode: Int
    let spine: Bool
    var hideCosmetics = false
    @StateObject private var textures = WyrmSkinTextureLibrary.acquire()
    @ObservedObject private var look = WyrmLookStore.shared

    var body: some View {
        let skin = WyrmTrailSkin.current()
        let custom = skin.wearsPattern
        let groups = skin.wornGroups   // index 0 is the head, as the engine counts
        let colors = skin.wornColors
        let accessory = hideCosmetics ? -1 : skin.wornAccessory
        let showLook = !hideCosmetics
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
            Canvas { context, canvas in
                let total = 160
                let span = 1 + CGFloat(total - 1) * (8.0 / 48.0) + 0.7
                let scale = min(canvas.height * 0.34, (canvas.width - 28) / span)
                let step = 8 * (scale / 48)
                let left = (canvas.width - span * scale) / 2
                let amp = canvas.height * 0.16
                // Segment 0 is the tail (left), total - 1 the head (right).
                func place(_ segment: Int) -> CGPoint {
                    let along = CGFloat(segment) / CGFloat(total - 1)
                    return CGPoint(x: left + scale * 0.5 + CGFloat(segment) * step,
                                   y: canvas.height * 0.5 + amp * sin(along * 6.2831855 * 1.15))
                }
                func heading(_ segment: Int) -> CGFloat {
                    let a = place(max(0, segment - 1))
                    let b = place(min(total - 1, segment + 1))
                    return atan2(b.y - a.y, b.x - a.x)
                }
                // One bead's colour as the engine paints Solid/Flat/Skinless:
                // a picked colour when there is one (Wyrm beads opaque), else
                // the colour group's own.
                func beadColour(_ codeIndex: Int) -> Color {
                    let rgba = codeIndex < colors.count ? colors[codeIndex] : 0
                    if rgba != 0 {
                        let alpha = WyrmBead.kind(of: rgba) != nil ? 1.0 : Double((rgba >> 24) & 0xff) / 255
                        return Color(airRGB: rgba & 0xffffff).opacity(alpha)
                    }
                    let group = groups.isEmpty ? 7 : groups[codeIndex % groups.count]
                    return Color(airRGB: WyrmAirSkin.groupRGB(group))
                }
                func bodyPath() -> Path {
                    var path = Path()
                    path.move(to: place(0))
                    for segment in 1..<total { path.addLine(to: place(segment)) }
                    return path
                }
                let head = place(total - 1)

                if mode == 3 {
                    let rgba = colors.first ?? 0
                    let group = groups.first ?? 7
                    let rgb = rgba != 0 ? rgba & 0xffffff : WyrmAirSkin.groupRGB(group)
                    context.stroke(bodyPath(), with: .color(Color(airRGB: rgb).opacity(0.8)),
                                   style: StrokeStyle(lineWidth: scale, lineCap: .round, lineJoin: .round))
                } else if mode == 0 && textures.ready {
                    for segment in 0..<total {
                        let codeIndex = total - 1 - segment
                        let group = groups.isEmpty ? 7 : groups[codeIndex % groups.count]
                        if group < 0 { continue }
                        let rgba = codeIndex < colors.count ? colors[codeIndex] : 0
                        let air = WyrmAirSkin.kind(of: rgba)
                        let wyrm = WyrmBead.kind(of: rgba)
                        guard let bead = wyrm.flatMap({ textures.wyrmBeads[$0] })
                                ?? air.flatMap({ textures.airBeads[$0] })
                                ?? textures.beads[rgba == 0 ? group : 40] else { continue }
                        var inked = context
                        if let wyrm {
                            if WyrmBead.tinted[wyrm] { inked.addFilter(.colorMultiply(Color(airRGB: rgba & 0xffffff))) }
                        } else if air != nil {
                            inked.addFilter(.colorMultiply(Color(airRGB: WyrmAirSkin.bodyTint(rgba))))
                        } else if rgba != 0 {
                            inked.addFilter(.colorMultiply(Color(airRGB: rgba & 0xffffff)))
                        }
                        let p = place(segment)
                        // Heading right is the Skin preview's head row (turned 180).
                        inked.translateBy(x: p.x, y: p.y)
                        inked.rotate(by: .radians(Double(heading(segment)) + .pi))
                        inked.draw(Image(decorative: bead, scale: 1),
                                   in: CGRect(x: -scale * 0.5, y: -scale * 0.5, width: scale, height: scale))
                    }
                } else {
                    // Solid: each bead its own colour; Flat (and Texture before
                    // the sprites load): Flat uses the first bead's.
                    for segment in 0..<total {
                        let codeIndex = total - 1 - segment
                        let p = place(segment)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - scale * 0.5, y: p.y - scale * 0.5,
                                                            width: scale, height: scale)),
                                     with: .color(beadColour(mode == 2 ? 0 : codeIndex)))
                    }
                }
                if spine {
                    let line = bodyPath()
                    context.stroke(line, with: .color(Color.black.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
                    context.stroke(line, with: .color(Color.white.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                }
                // The head over everything, as the arena draws its eyes,
                // accessory and look last.
                if textures.ready {
                    var h = context
                    h.translateBy(x: head.x, y: head.y)
                    h.rotate(by: .radians(Double(heading(total - 1))))
                    let unit = scale / 29
                    let iris = 12 * unit
                    let pupil = (custom ? 7 : skin.preset == 63 ? 5 : 7) * unit
                    let irisColor: Color = !custom && skin.preset == 63 ? .black :
                        !custom && skin.preset == 64 ? Color(red: 1, green: 1, blue: 0.50196) :
                        !custom && skin.preset == 25 ? Color(red: 1, green: 0.3373, blue: 0.0353) :
                        !custom && skin.preset == 44 ? Color(red: 0.8314, green: 0.8314, blue: 0.8314) : .white
                    let pupilColor: Color = !custom && skin.preset == 63 ? Color(white: 0.8) : .black
                    if let eye = textures.beads[40] {
                        let image = Image(decorative: eye, scale: 1)
                        for side in 0..<2 {
                            let ey = side == 0 ? -6 * unit - 0.5 : 6 * unit
                            var irisContext = h
                            irisContext.addFilter(.colorMultiply(irisColor))
                            irisContext.draw(image, in: CGRect(x: 6 * unit - iris / 2, y: ey - iris / 2,
                                                               width: iris, height: iris))
                            var pupilContext = h
                            pupilContext.addFilter(.colorMultiply(pupilColor))
                            let py = side == 0 ? -6 * unit : 6 * unit
                            pupilContext.draw(image, in: CGRect(x: 6 * unit + 0.5 + 2 * unit - pupil / 2,
                                                                y: py - pupil / 2, width: pupil, height: pupil))
                        }
                    }
                    if let item = WyrmSkinCatalog.accessories.first(where: { $0.id == accessory }),
                       let image = textures.accessories[accessory] {
                        let size = scale * CGFloat(item.scale)
                        let cx = CGFloat(item.offset) * 6 * unit
                        h.draw(Image(decorative: image, scale: 1),
                               in: CGRect(x: cx - size / 2, y: -size / 2, width: size, height: size))
                    }
                    if showLook {
                        WyrmLook.draw(in: h, cells: textures.looks, head: .zero, r: scale / 2,
                                      hair: look.hair, hairRGB: look.hairRGB,
                                      ears: look.ears, glasses: look.glasses)
                    }
                }
            }
            .frame(height: 88).background(ATheme.well)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .onAppear { textures.prepare() }
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
            // A page that opens on a card keeps the same gap below the header as one
            // that opens on a section label.
            Spacer().frame(height: 18)
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

    /*
     * Settings › Food (redesigned, OM 2026-10-01; Android: SettingsFoodScreen.kt):
     * a live arena preview drawn by the settings below, a grid of shape tiles
     * with each food glowing as in a match, and one Look card for size, colour
     * and motion. Only drawing changes: position, value and eating stay original.
     */
    static let hueCodes: [UInt32] = [0xC080FF, 0x9099FF, 0x80D0D0, 0x80FF80, 0xEEEE70, 0xFFA060, 0xFF9090, 0xFF4040, 0xE030E0]
    static let hues: [Color] = hueCodes.map { (code: UInt32) -> Color in
        let red = Double((code >> 16) & 0xFF) / 255
        let green = Double((code >> 8) & 0xFF) / 255
        let blue = Double(code & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }
    static let floor = Color(red: 0.086, green: 0.106, blue: 0.133)

    static func isFood(_ s: EngineSetting) -> Bool {
        let local = s.id.components(separatedBy: ".").dropFirst().joined(separator: ".")
        return local.hasPrefix("food_") || local == "const_food_scale" || local == "uniform_food_color"
    }
    static func label(_ engine: WyrmShellStore) -> String {
        guard let s = engine.setting("normal.food_type"), s.options.indices.contains(s.index) else { return "Original" }
        return s.options[s.index]
    }
    /// Style (Original, Rings, Mixed, Star, Triangle, Diamond, Hexagon, Square, Flower) → drawn shape.
    static func shape(of style: Int) -> Int { style <= 1 ? style : style - 1 }

    var body: some View {
        let group = mode == 0 ? "normal" : "assist"
        let food = engine.settings.filter { $0.group == group && Self.isFood($0) }
        let named: (String) -> EngineSetting? = { local in food.first { $0.id == "\(group).\(local)" } }
        let style = named("food_type")
        let uniform = named("uniform_food_color")
        let colour = named("food_color")
        let order = ["food_scale", "const_food_scale", "uniform_food_color", "food_color", "food_float", "food_flicker"]
        let uniformOn = uniform?.enabled == true
        let ordered: [EngineSetting] = order.compactMap(named).filter { $0.id != colour?.id || uniformOn }
        let rest: [EngineSetting] = food.filter { (row: EngineSetting) -> Bool in
            let local = row.id.components(separatedBy: ".").dropFirst().joined(separator: ".")
            return row.id != style?.id && !order.contains(local)
        }
        let look: [EngineSetting] = ordered + rest
        WSScaffold(title: "Food", parent: parent, onBack: close) {
            Spacer().frame(height: 18)
            VStack(spacing: 12) {
                WyrmFoodPreview(style: style?.index ?? 0,
                                scale: named("food_scale")?.number ?? 1,
                                uniform: uniform?.enabled == true,
                                uniformColour: colour.map { Color(red: $0.channels[0], green: $0.channels[1], blue: $0.channels[2]) } ?? Self.hues[3],
                                drift: named("food_float")?.enabled == true,
                                flicker: named("food_flicker")?.enabled == true)
                WSSegmented(options: ["Normal mode", "With assist"], selected: mode) { mode = $0 }
            }
            .padding(.horizontal, 16)
            .onAppear {
                let target = WyrmSettingsFocus.shared.target ?? ""
                if target.hasPrefix("assist.") { mode = 1 } else if target.hasPrefix("normal.") { mode = 0 }
            }

            WSSectionLabel("Shape")
            if let style {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(style.options.indices, id: \.self) { index in
                        WyrmFoodTile(style: index, label: style.options[index], selected: style.index == index) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            engine.write(style, values: [Double(index)])
                        }
                    }
                }
                .padding(.horizontal, 16)
                .wyrmSettingAnchor("\(group).food_type")
            }
            WSCaption("Mixed uses every shape and keeps each morsel the same shape for its whole life.")

            WSSectionLabel("Look")
            WSCard { WSRows(rows: look, engine: engine) }
            WSCaption("Only how food looks changes. Where it lies, what it is worth and eating it stay the arena's own.")
            Spacer().frame(height: 22)
        }
    }
}

/// A slice of arena with food on it, drawn by the same rules as the settings.
/// It moves only when the settings say food moves.
struct WyrmFoodPreview: View {
    let style: Int
    let scale: Double
    let uniform: Bool
    let uniformColour: Color
    let drift: Bool
    let flicker: Bool

    private static let morsels: [(x: Double, y: Double, size: Double, phase: Double, hue: Int, shape: Int)] = {
        var seed: UInt64 = 0x5715
        func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        return (0..<34).map { _ in (next(), next(), next(), next() * 6.283, Int(next() * 9) % 9, Int(next() * 8) % 8) }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !drift && !flicker)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 6.283
            Canvas { context, size in
                // A faint dot lattice, as the arena floor has.
                let step: CGFloat = 22
                var y = step / 2, row = 0
                while y < size.height {
                    var x = row % 2 == 0 ? step / 2 : step
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8)), with: .color(.white.opacity(0.035)))
                        x += step
                    }
                    y += step * 0.86; row += 1
                }
                let base = 5.5 * CGFloat(min(max(scale, 0.25), 3))
                for m in Self.morsels {
                    let wobble: CGFloat = drift ? 4 : 0
                    let c = CGPoint(x: m.x * size.width + CGFloat(cos(t + m.phase)) * wobble,
                                    y: m.y * size.height + CGFloat(sin(t * 1.3 + m.phase)) * wobble)
                    let glow = flicker ? 0.55 + 0.45 * (sin(t * 3 + m.phase * 2) + 1) / 2 : 1
                    let hue = uniform ? uniformColour : WyrmFoodPage.hues[m.hue]
                    let shape = style == 2 ? m.shape : WyrmFoodPage.shape(of: style)
                    WyrmFoodTile.glowing(shape, c, base * CGFloat(0.65 + m.size * 0.7), hue, glow, into: &context)
                }
            }
        }
        .frame(height: 176)
        .background(WyrmFoodPage.floor)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule))
        .overlay(alignment: .topLeading) {
            Text("LIVE PREVIEW").font(.androidWyrm(9.5, .bold)).tracking(1.2).foregroundColor(.white.opacity(0.72))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.08))).padding(12)
        }
    }
}

/// One shape: a small arena tile with the food glowing in it, its name, and a check when chosen.
struct WyrmFoodTile: View {
    let style: Int
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Canvas { context, size in
                    let r = min(size.width, size.height) * 0.17
                    if style == 2 {
                        for (spot, shape) in [0, 2, 3, 5].enumerated() {
                            let c = CGPoint(x: size.width * (spot % 2 == 0 ? 0.33 : 0.67), y: size.height * (spot < 2 ? 0.33 : 0.67))
                            Self.glowing(shape, c, r * 0.62, WyrmFoodPage.hues[(spot * 2 + 1) % 9], 1, into: &context)
                        }
                    } else {
                        Self.glowing(WyrmFoodPage.shape(of: style), CGPoint(x: size.width / 2, y: size.height / 2), r,
                                     WyrmFoodPage.hues[style % 9], 1, into: &context)
                    }
                }
                .aspectRatio(1.25, contentMode: .fit)
                .background(WyrmFoodPage.floor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.onInk)
                            .frame(width: 20, height: 20).background(Circle().fill(ATheme.ink)).padding(6)
                    }
                }
                Text(label).font(.androidWyrm(12.5, selected ? .bold : .semibold))
                    .foregroundColor(selected ? ATheme.ink : ATheme.mute).lineLimit(1)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(WSPressStyle())
        .accessibilityLabel("\(label) food")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Food as the arena draws it: a soft halo, the body, a small bright highlight.
    static func glowing(_ shape: Int, _ c: CGPoint, _ r: CGFloat, _ colour: Color, _ glow: Double, into context: inout GraphicsContext) {
        let halo = r * 2.8
        context.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
                     with: .radialGradient(Gradient(colors: [colour.opacity(0.55 * glow), colour.opacity(0)]),
                                           center: c, startRadius: 0, endRadius: halo))
        let body = GraphicsContext.Shading.color(colour.opacity(0.55 + 0.45 * glow))
        switch shape {
        case 0: context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: body)
        case 1:
            let rr = r * 0.88
            context.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: body, lineWidth: r * 0.34)
        case 2: context.fill(WyrmFoodIcon.polygon(c, r, 10) { $0 % 2 == 0 ? 1 : 0.45 }, with: body)
        case 3: context.fill(WyrmFoodIcon.polygon(c, r, 3), with: body)
        case 4: context.fill(WyrmFoodIcon.polygon(c, r, 4), with: body)
        case 5: context.fill(WyrmFoodIcon.polygon(c, r, 6), with: body)
        case 6: context.fill(Path(CGRect(x: c.x - r * 0.85, y: c.y - r * 0.85, width: r * 1.7, height: r * 1.7)), with: body)
        default: context.fill(WyrmFoodIcon.polygon(c, r, 24) { 0.82 + 0.18 * CGFloat(cos(Double($0) * 6 * 2 * .pi / 24)) }, with: body)
        }
        if shape != 1 {
            let h = r * 0.28
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.3 - h, y: c.y - r * 0.32 - h, width: h * 2, height: h * 2)),
                         with: .color(.white.opacity(0.38 * glow)))
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
    static let knownKinds = ["dm", "invite", "voice_invite", "notice", "broadcast", "event", "update", "feature", "follow", "achievement", "rank", "backup", "trail_like", "trail_reply", "support"]
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var revision = 0

    var systemEnabled: Bool { status == .authorized || status == .provisional || status == .ephemeral }
    var enabledCount: Int {
        systemEnabled ? Self.knownKinds.filter { WyrmTrailsFeature.shows(alertKind: $0) && isEnabled($0) }.count : 0
    }

    /// A new kind starts enabled so an older preference file cannot hide it forever.
    func isEnabled(_ kind: String) -> Bool { UserDefaults.standard.object(forKey: "wyrm.notify.kind.\(kind)") as? Bool ?? true }

    /// The in-app feed honours the same choices; unknown kinds always show.
    func allows(_ kind: String) -> Bool {
        guard WyrmTrailsFeature.shows(alertKind: kind) else { return false }
        return !Self.knownKinds.contains(kind) || isEnabled(kind)
    }

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
    /// The groups shown here and in settings search. The Trails group stays
    /// out while Trails are paused (`WyrmTrailsFeature`).
    static let groups: [(String, [(String, String, String)])] = allGroups.filter { WyrmTrailsFeature.enabled || $0.0 != "Trails" }
    private static let allGroups: [(String, [(String, String, String)])] = [
        ("People", [("invite", "Arena invites", "Someone sends you a server and key."),
                    ("dm", "Direct messages", "New thread or reply."),
                    ("voice_invite", "Voice invitations", "Private invitations to verified voice rooms."),
                    ("follow", "New followers", "When another player starts following you.")]),
        ("Trails", [("trail_like", "Beads on your trails", "When someone gives a trail you posted a bead."),
                    ("trail_reply", "Replies to your trails", "When someone replies to a trail you posted.")]),
        ("Wyrm", [("notice", "Notices", "Maintenance, downtime and important alerts."),
                  ("broadcast", "Broadcasts", "General announcements sent to everyone."),
                  ("event", "Battledome events", "Scheduled events, start times and arena addresses."),
                  ("update", "Updates", "New versions and their changelogs."),
                  ("feature", "New features", "What has been added or changed inside Wyrm."),
                  ("support", "Replies from Wyrm", "Answers to your reports, ideas and questions.")]),
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
                    .wyrmSettingAnchor("app.notify.all")
            }
            ForEach(Self.groups.indices, id: \.self) { groupIndex in
                let group = Self.groups[groupIndex]
                WSSectionLabel(group.0)
                WSCard {
                    ForEach(Array(group.1.enumerated()), id: \.offset) { index, row in
                        let checked = master && prefs.isEnabled(row.0)
                        WSBoolRow(title: row.1, detail: row.2, on: checked, first: index == 0) { _ in
                            prefs.set(row.0, !prefs.isEnabled(row.0))
                        }
                        .disabled(!master).opacity(master ? 1 : 0.46)
                        .wyrmSettingAnchor("app.notify.\(row.0)")
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
        guard let url = Bundle.main.url(forResource: "privacy", withExtension: "txt"),
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
            .wyrmSettingAnchor("app.theme", card: true)
            .onAppear {
                if WyrmSettingsFocus.shared.wants("app.theme-intensity") { advancedOpen = true; Self.rememberedOpen = true }
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
                        .wyrmSettingAnchor("app.theme-intensity")
                    WSHairline()
                    WSOutlineButton(label: "Reset", enabled: abs(store.intensity - 0.5) >= 0.001) { store.setIntensity(0.5) }.padding(14)
                }
            }
            WSSectionLabel("Keyboard")
            WSCard { WyrmKeyboardLookRows() }.wyrmSettingAnchor("app.keyboard", card: true)
            WSCaption("The Wyrm keyboard follows your theme. Its gear key holds the same two controls, and in the lobby the knob under it drags it anywhere.")
        }
    }
}

// MARK: - Updates & version

/// Settings › Updates & version. Until 2026-10-01 this page also made and
/// restored `.json` backups; settings now live in the account
/// (WyrmAccountSync), so only updates, the beta switch and the version remain.
struct WyrmBackupPage: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State var confirmingReset = false
    @ObservedObject var updates = WyrmUpdateStore.shared
    @Environment(\.openURL) var openURL
    @State var updateNote = ""

    private var updateLabel: String {
        if updates.checking { return "Checking…" }
        if let next = updates.available { return next.beta ? "Beta \(next.version) available" : "\(next.version) available" }
        return updates.failed ? "Check failed" : "Up to date"
    }

    var body: some View {
        WSScaffold(title: "Updates", onBack: close) {
            Spacer().frame(height: 18)
            if let next = updates.available {
                WSSectionLabel("Update", top: 0)
                WSCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Wyrm \(next.version) is ready").font(.androidWyrm(18, .semibold)).foregroundColor(ATheme.ink)
                        Text(updateNote.isEmpty ? (next.beta ? "Beta build \(next.build)" : "Build \(next.build)") : updateNote)
                            .font(.androidWyrm(13)).foregroundColor(ATheme.quiet).padding(.top, 3)
                            .fixedSize(horizontal: false, vertical: true)
                        WSPrimaryButton(label: "Update now", enabled: true) { handOff(next) }.padding(.top, 14)
                    }.padding(16)
                }
            }

            WSSectionLabel("Version", top: updates.available == nil ? 0 : 22)
            WSCard {
                WSValueRow(title: "Wyrm", value: "\(WyrmBuild.version) (\(WyrmBuild.build))", first: true)
                // Opens the new build's download; it installs through AltStore.
                WSValueRow(title: "Updates", value: updateLabel) {
                    if let next = updates.available { openURL(next.url) } else { Task { await updates.check() } }
                }
                WSBoolRow(title: "Beta updates", detail: "Get early builds before everyone else. They can have rough edges or bugs; turn this off to get stable updates only.",
                          on: updates.betaEnabled) { updates.betaEnabled = $0 }
                    // Also where the beta prompt's "turn them off" shortcut lands.
                    .wyrmSettingAnchor("app.beta-updates")
                if !engine.settingsVersion.isEmpty { WSValueRow(title: "Settings format", value: "v\(engine.settingsVersion)") }
                WSLinkRow(title: "What's in this build") { open(.buildNotes) }
            }

            WyrmInstallersSection(update: updates.available)

            Spacer().frame(height: 22)
            WSCard {
                WSActionRow(title: confirmingReset ? "Tap again to reset everything" : "Reset everything to defaults", first: true, danger: true) {
                    if confirmingReset { confirmingReset = false; engine.reset(1, message: "All settings reset") } else { confirmingReset = true }
                }
            }
            WSCaption("Your settings, skin and layouts are saved to your Wyrm account, so an update or a new iPhone never loses them. Log in and they come back.")
        }
        .task { await updates.check() }
    }

    /// Update now: the IPA goes to the sideloader on this iPhone, or downloads if there is none.
    private func handOff(_ next: WyrmUpdateInfo) {
        if let installer = WyrmInstaller.preferred {
            updateNote = installer.hand(next) { openURL($0) }
        } else {
            openURL(next.url)
            updateNote = "Downloading the new build. Install it with AltStore, SideStore, KSign or ESign."
        }
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

    /// This release (0.18.38, OM 2026-10-05). Trails notes show only while Trails are on (`WyrmTrailsFeature`).
    static let notes: [String] = (WyrmTrailsFeature.enabled ? trailNotes : ["Trails are paused in this beta. They come back in a later build."]) + otherNotes
    private static let trailNotes: [String] = [
        "Trails is open: post photos, text or a canvas, like with a bead and reply. Trails has its own tab; Alerts moved to the bell on Play.",
        "Photo editor: swipe through looks, Adjust sliders, emoji stickers, and text with Glow and Line.",
        "Video trails are coming later.",
    ]
    private static let otherNotes: [String] = [
        "Near Original: one switch on Home gives you slither's own minimap, leaderboard, joystick, boost and arrow.",
        "Team Mode is back, with a team roster and team chat in the arena. Move, resize and recolour both; fold the chat away.",
        "NTL tags show to everyone, even without a team, and swing exactly like NTL's.",
        "Skinless and Spine snake looks in normal and assist; in assist you can hide your own tag and accessories.",
        "Play feel: slither's own arrow movement, Look ahead, and a spring zoom bar.",
        "Auto restart: an on-screen button that jumps you back in after you die, and turns itself off if the arena drops you.",
        "Leaderboard: your row stands out, and you can search the Score and Kills boards.",
        "Global chat shows how many new messages are waiting.",
        "Fixed: a crash at launch on some iPhones, crashes when resizing the HUD, beads vanishing in Build a Wyrm, and a lost last bead in custom patterns.",
        "Profiles no longer show badges or the Best/Kills/Beads chips. Something new is coming in their place.",
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
    /// Editor chrome only. Not saved, not synced. Nil until the player drags it.
    @State var footerNorm: CGPoint?
    @State var footerDragOrigin: CGPoint?
    @State var footerSize: CGSize = .zero
    /// Long-press card. Starts tall so the first frame stays on screen, then shrinks to the rows.
    @State var popupHeight: CGFloat = 800

    private struct PopupHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
    /// The team roster's and chat window's look (OM, 2026-10-04), saved app side.
    @ObservedObject var teamHud = WyrmTeamHudStore.shared

    struct Slider { let label: String; let id: String; let range: ClosedRange<Double>; var whole = false }
    /// A row of colour swatches for a `teamhud.<key>` colour.
    struct ColourRow { let label: String; let key: String }
    struct Options: Identifiable {
        let id: String; let title: String; let sliders: [Slider]; var zoomChoice = false
        var colours: [ColourRow] = []
    }

    private func teamHudSlider(_ label: String, _ key: String) -> Slider {
        Slider(label: label, id: "teamhud.\(key)", range: teamHud.range(key))
    }

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
                // Upright steers with the arrow only (OM, 2026-10-02): no joystick to place.
                // Near Original (OM, 2026-10-02): the original's joystick, boost and HUD
                // are fixed; only the on-screen buttons (and the zoom bar) move.
                if engine.setting("controls.joystick_mode")?.index != 2 && !WyrmPlayOrientation.shared.portrait
                    && !WyrmNearOriginalStore.shared.on {
                    piece("layout.joystick", size, CGSize(width: 112 * joystick, height: 112 * joystick),
                          Options(id: "joystick", title: "JOYSTICK", sliders: [Slider(label: "SIZE", id: "controls.joystick_size", range: 0.65...1.45),
                                                                              Slider(label: "OPACITY", id: "layout.joystick_opacity", range: 0.05...1)])) {
                        WyrmPaperJoystick(diameter: 112 * joystick, opacity: engine.value("layout.joystick_opacity", baseOpacity))
                    }
                }
                if engine.setting("controls.boost_mode")?.index == 1 && !WyrmNearOriginalStore.shared.on {
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
            if !WyrmNearOriginalStore.shared.on {
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
                                                                Slider(label: "OPACITY", id: "layout.stats_opacity", range: 0.05...1),
                                                                // BACK (OM, 2026-10-05): the plate only.
                                                                teamHudSlider("BACK", "stats_panel")]),
                  fallback: HUD.stats.fallback) {
                panel("STATS\nSCORE   9503\nKILLS      4\nRANK    8 / 46\nPING    64 ms\nFPS     61",
                      CGSize(width: 142 * statsScale / scale, height: 132 * statsScale / scale), opacity: engine.value("layout.stats_opacity", 1))
            }
            }
            }
            // The roster and chat stay editable in Near Original. The engine draws
            // them; these are their hit boxes at the same size.
            let teamScale = teamHud.value("team_scale")
            let teamSize = CGSize(width: teamHud.value("team_width") * teamScale / scale,
                                  height: teamHud.value("team_height") * teamScale / scale)
            piece(HUD.team.prefix, size, teamSize,
                  Options(id: "team", title: "TEAM",
                          sliders: [teamHudSlider("SIZE", "team_scale"), teamHudSlider("OPACITY", "team_opacity"),
                                    teamHudSlider("BACK", "team_panel"),
                                    teamHudSlider("WIDTH", "team_width"), teamHudSlider("HEIGHT", "team_height")],
                          colours: [ColourRow(label: "PLAYER NAME AND SCORE", key: "team_name"),
                                    ColourRow(label: "KEY NAME AND SERVER", key: "team_data")]),
                  fallback: HUD.team.fallback) {
                RoundedRectangle(cornerRadius: 14).fill(ATheme.card).frame(width: teamSize.width, height: teamSize.height)
            }
            let chatSize = CGSize(width: teamHud.value("chat_width") * chatScale / scale,
                                  height: teamHud.value("chat_height") * chatScale / scale)
            piece(HUD.chat.prefix, size, chatSize,
                  Options(id: "chat", title: "CHAT",
                          sliders: [Slider(label: "SIZE", id: "layout.chat_scale", range: 0.65...1.60),
                                    Slider(label: "OPACITY", id: "layout.chat_opacity", range: 0.05...1),
                                    teamHudSlider("BACK", "chat_panel"),
                                    teamHudSlider("WIDTH", "chat_width"), teamHudSlider("HEIGHT", "chat_height")],
                          colours: [ColourRow(label: "PLAYER NAME", key: "chat_name"),
                                    ColourRow(label: "MESSAGES", key: "chat_text")]),
                  fallback: HUD.chat.fallback) {
                RoundedRectangle(cornerRadius: 14).fill(ATheme.card).frame(width: chatSize.width, height: chatSize.height)
            }
            footerBar(in: size)
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

    /// The bar's centre. Nil [footerNorm] is the bottom centre, 14 pt up.
    private func footerCentre(in area: CGSize, measured: CGSize) -> CGPoint {
        let margin: CGFloat = 8
        let raw: CGPoint
        if let footerNorm, area.width > 1, area.height > 1 {
            raw = CGPoint(x: footerNorm.x * area.width, y: footerNorm.y * area.height)
        } else {
            raw = CGPoint(x: area.width / 2, y: area.height - 14 - measured.height / 2)
        }
        let halfW = measured.width / 2
        let halfH = measured.height / 2
        let minX = margin + halfW
        let minY = margin + halfH
        let maxX = max(minX, area.width - margin - halfW)
        let maxY = max(minY, area.height - margin - halfH)
        return CGPoint(x: min(max(raw.x, minX), maxX), y: min(max(raw.y, minY), maxY))
    }

    private func footerBar(in area: CGSize) -> some View {
        let measured = footerSize.width > 1 ? footerSize : CGSize(width: 280, height: 44)
        let centre = footerCentre(in: area, measured: measured)
        return footerChrome(in: area)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { footerSize = geo.size }
                    .onChange(of: geo.size) { footerSize = $0 }
            })
            .position(x: centre.x, y: centre.y)
    }

    private func footerKnob(in area: CGSize) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().fill(ATheme.quiet).frame(width: 16, height: 2)
            }
        }
        .frame(width: 36, height: 36)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("wyrm-layout"))
            .onChanged { value in
                let measured = footerSize.width > 1 ? footerSize : CGSize(width: 280, height: 44)
                let start = footerDragOrigin ?? footerCentre(in: area, measured: measured)
                if footerDragOrigin == nil { footerDragOrigin = start }
                let margin: CGFloat = 8
                let halfW = measured.width / 2
                let halfH = measured.height / 2
                let nx = min(max(start.x + value.translation.width, margin + halfW), max(margin + halfW, area.width - margin - halfW))
                let ny = min(max(start.y + value.translation.height, margin + halfH), max(margin + halfH, area.height - margin - halfH))
                guard area.width > 1, area.height > 1 else { return }
                footerNorm = CGPoint(x: nx / area.width, y: ny / area.height)
            }
            .onEnded { _ in footerDragOrigin = nil })
    }

    private func footerChrome(in area: CGSize) -> some View {
        // Upright the bar is too narrow for the hint and the actions on one
        // line: the hint goes above, in its own small pill. The grip moves
        // the whole bar for this session only.
        let upright = WyrmPlayOrientation.shared.portrait
        return VStack(spacing: 6) {
            if upright {
                // Upright: the knob sits at the bar's left end, below this card.
                barHint(arrow: "arrow.down.left")
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.card.opacity(0.92)))
            }
            HStack(spacing: 8) {
                footerKnob(in: area)
                if !upright {
                    barHint(arrow: "arrow.left")
                }
                // Turns the phone and swaps to that orientation's layout; the
                // edits so far stay with the orientation they were made in.
                footerAction(upright ? "LANDSCAPE" : "PORTRAIT") {
                    WyrmPlayOrientation.shared.switchTo(!upright, engine: engine)
                    snapshot = engine.settings
                    keySnapshot = engine.hotkeys
                }
                footerAction("CANCEL") { cancel() }
                footerAction("RESET") {
                    WyrmPlayOrientation.shared.reset([2, 4, 8], engine: engine, message: "Layout reset")
                }
                footerAction("SAVE", filled: true) { onClose() }
            }
            .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 5)
            .background(Capsule().fill(ATheme.card.opacity(0.96)))
            .overlay(Capsule().stroke(ATheme.rule, lineWidth: 1))
        }
    }

    /// The bar's hint (OM, 2026-10-05): "hold any object" moved up, and under
    /// it an arrow pointing at the grip knob with "drag this knob to move this bar".
    private func barHint(arrow: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text("HOLD ANY OBJECT FOR MORE OPTIONS").font(.androidWyrm(9)).tracking(0.6).foregroundColor(ATheme.quiet)
            HStack(spacing: 4) {
                Image(systemName: arrow).font(.system(size: 9, weight: .bold)).foregroundColor(ATheme.ink)
                Text("DRAG THIS KNOB TO MOVE THIS BAR").font(.androidWyrm(8, .bold)).tracking(0.6)
                    .foregroundColor(ATheme.ink.opacity(0.8))
            }
        }
    }

    private func footerAction(_ label: String, filled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.androidWyrm(9, .bold)).tracking(1).foregroundColor(filled ? ATheme.onInk : ATheme.quiet)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Capsule().fill(filled && !WyrmGlass.native ? ATheme.ink : Color.clear))
        }.modifier(WyrmGlassButtonModifier(prominent: filled, fallback: PlainButtonStyleShim()))
    }

    private func optionsPopup(_ options: Options) -> some View {
        GeometryReader { geo in
        ZStack {
            Color.black.opacity(0.001).onTapGesture { self.options = nil }
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(options.title).font(.androidWyrm(13, .bold)).tracking(1.4).foregroundColor(ATheme.ink)
                if options.sliders.isEmpty && !options.zoomChoice {
                    Text("POSITION ONLY").font(.androidWyrm(11)).tracking(1).foregroundColor(ATheme.quiet)
                }
                ForEach(options.sliders, id: \.id) { slider in
                    Text(slider.label).font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                    let fallback = slider.id.hasPrefix("layout.key_") ? engine.value(slider.id.hasSuffix("opacity") ? "keys.opacity" : "keys.key_scale", 1)
                        : slider.id.hasPrefix("layout.") && slider.id.hasSuffix("opacity") ? engine.value("controls.opacity", 1) : 1
                    SwiftUI.Slider(value: Binding(get: {
                                                      let current = WyrmTeamHudStore.owns(slider.id)
                                                          ? teamHud.value(String(slider.id.dropFirst(8))) : engine.value(slider.id, fallback)
                                                      return min(max(current, slider.range.lowerBound), slider.range.upperBound)
                                                  },
                                                  set: {
                                                      if WyrmTeamHudStore.owns(slider.id) {
                                                          teamHud.set(slider.id, $0)
                                                      } else {
                                                          engine.write(id: slider.id, values: [slider.whole ? $0.rounded() : $0])
                                                      }
                                                  }),
                                   in: slider.range, step: slider.whole ? 1 : 0.01)
                        .tint(ATheme.ink)
                }
                if options.zoomChoice, let orientation = engine.setting("controls.zoom_orientation") {
                    Text("ORIENTATION").font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                    WSSegmented(options: ["Horizontal", "Vertical"], selected: orientation.index == 1 ? 1 : 0) {
                        engine.write(orientation, values: [Double($0)])
                    }
                }
                ForEach(options.colours, id: \.key) { row in
                    let selected = Int(teamHud.value(row.key))
                    Text("\(row.label) · \(WyrmTeamHudStore.colourNames[min(max(selected, 0), 8)].uppercased())")
                        .font(.androidWyrm(10, .bold)).tracking(1).foregroundColor(ATheme.quiet)
                    HStack(spacing: 5) {
                        ForEach(0..<WyrmTeamHudStore.swatches.count, id: \.self) { index in
                            Circle().fill(WyrmTeamHudStore.swatches[index] ?? ATheme.ink)
                                .padding(3)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(index == selected ? ATheme.ink : ATheme.rule,
                                                         lineWidth: index == selected ? 2 : 1))
                                .onTapGesture { teamHud.set("teamhud.\(row.key)", Double(index)) }
                        }
                    }
                }
                HStack { Spacer(); Button("DONE") { self.options = nil }.font(.androidWyrm(10, .bold)).foregroundColor(ATheme.ink).padding(8) }
            }
            .padding(18)
            .background(GeometryReader { row in
                Color.clear.preference(key: PopupHeightKey.self, value: row.size.height)
            })
            }
            .frame(width: 300)
            .frame(height: min(max(popupHeight, 1), max(120, geo.size.height - 28)))
            .onPreferenceChange(PopupHeightKey.self) { popupHeight = $0 }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        }
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
