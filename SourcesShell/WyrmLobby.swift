import SwiftUI
import UIKit

/// A landscape canvas drawn inside the portrait app with the same quarter turn
/// Main.m gives the engine surface, so SwiftUI and the arena share one frame.
/// Content receives the landscape size; its leading edge sits under the
/// Dynamic Island and its trailing edge by the home indicator.
struct WyrmLandscapeStage<Content: View>: View {
    let content: (CGSize, EdgeInsets) -> Content
    /// Playing upright (Settings › Controls › Play orientation): no turn, the
    /// content gets the portrait canvas, as the engine surface does (Main.m).
    @ObservedObject private var orientation = WyrmPlayOrientation.shared

    init(@ViewBuilder content: @escaping (CGSize, EdgeInsets) -> Content) { self.content = content }

    var body: some View {
        GeometryReader { outer in
            let safe = Self.windowInsets
            if orientation.portrait {
                content(outer.size, EdgeInsets(top: safe.top, leading: safe.left, bottom: safe.bottom, trailing: safe.right))
                    .frame(width: outer.size.width, height: outer.size.height)
                    .position(x: outer.size.width / 2, y: outer.size.height / 2)
            } else {
                let size = CGSize(width: outer.size.height, height: outer.size.width)
                content(size, EdgeInsets(top: safe.left, leading: safe.top, bottom: safe.right, trailing: safe.bottom))
                    .frame(width: size.width, height: size.height)
                    .rotationEffect(.degrees(90))
                    .position(x: outer.size.width / 2, y: outer.size.height / 2)
            }
        }
        .ignoresSafeArea()
    }

    static var windowInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
    }
}

/// Android's `WyrmLabel`: small, bold, widely tracked capitals.
struct WyrmCapsLabel: View {
    let text: String
    var color = ATheme.quiet
    init(_ text: String, color: Color = ATheme.quiet) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.androidWyrm(10, .bold)).tracking(1.6).foregroundColor(color)
    }
}

extension Font {
    /// Android's `Wyrm.Display` (Bodoni Moda, semibold).
    static func wyrmDisplay(_ size: CGFloat) -> Font { .custom("Bodoni Moda", size: size).weight(.semibold) }
}

/// The Ready Room, element for element Android's `LobbyScreen`: the faint W in
/// the top-right corner, the selected arena card, "Playing as", and the four
/// actions along the bottom. Every action enters the original home mailbox.
struct WyrmReadyRoom: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var services: WyrmServiceStore
    @State var nickname = ""
    @State var entering = false
    @State var quickSettings = false
    @State var lastRefusal: UInt64 = 0
    /// A finished run is kept until the next match starts: the last-run card
    /// and Share run. None since launch = nothing is shown at all (OM).
    @State private var lastRun: WyrmLastRun? = WyrmRunCapture.lastRun
    private var hasRun: Bool { lastRun != nil }
    @FocusState var nameFocused: Bool
    @ObservedObject var keyboard = WyrmKeyboardController.shared
    /// The upright name card's bottom on screen, before any lift.
    @State private var uprightNameBottom: CGFloat = 0

    private var arena: WyrmArena? { services.arenas.first { $0.endpoint == engine.arena } }
    private var serverCode: String {
        if engine.arena.isEmpty { return "—" }
        if let arena, arena.number > 0 { return "\(arena.number)" }
        return "CUSTOM"
    }

    var body: some View {
        WyrmLandscapeStage { size, safe in
            ZStack(alignment: .bottom) {
                ATheme.paper
                if quickSettings {
                    quickSettingsPage(safe).transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: size.width / 7)),
                                                                   removal: .opacity.combined(with: .offset(x: size.width / 7))))
                } else if size.height > size.width {
                    // Playing upright: the same room, stacked (OM, 2026-10-01).
                    readyRoomUpright(size, safe)
                        .offset(y: -uprightLift)
                        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: uprightLift)
                } else {
                    readyRoom(size, safe)
                        // Typing lifts the room so the name stays above the keys.
                        .offset(y: keyboard.focused ? -118 : 0)
                        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: keyboard.focused)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -size.width / 9)),
                                                removal: .opacity.combined(with: .offset(x: -size.width / 12))))
                }
                // The phone stays portrait, so the keyboard is drawn here, in
                // the landscape canvas, the way the player is holding it.
                if keyboard.focused && keyboard.embedded {
                    let width = min(size.width - safe.leading - safe.trailing - 24, 640 * keyboard.scale)
                    let height = keyboard.keysHeight(compact: true) + 20
                    // Dragged by its knob, but never off the canvas.
                    let limitX = max(0, (size.width - width) / 2 - 8)
                    let limitY = max(0, size.height - height - 16)
                    WyrmKeyboardView(compact: true)
                        .frame(width: width)
                        .shadow(color: ATheme.ink.opacity(0.18), radius: 18, y: 6)
                        .offset(x: min(max(keyboard.landscapeOffset.width, -limitX), limitX),
                                y: min(max(keyboard.landscapeOffset.height, -limitY), 0))
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: keyboard.focused)
        }
        .foregroundColor(ATheme.ink)
        .onAppear {
            // The embedded keys are for the sideways canvas only; upright the
            // phone's own docked keys are used (OM, 2026-10-02).
            keyboard.embedded = !WyrmPlayOrientation.shared.portrait
            // Near Original: the arena's number labels the original minimap.
            WyrmNearOriginalStore.shared.setServer(arena?.number ?? 0)
            nickname = engine.nickname
            lastRefusal = engine.arenaRefusalSequence
            lastRun = WyrmRunCapture.lastRun
        }
        .onReceive(NotificationCenter.default.publisher(for: WyrmRunCapture.didChange)) { _ in
            lastRun = WyrmRunCapture.lastRun
        }
        .onDisappear {
            nameFocused = false
            keyboard.embedded = false
        }
        .onChange(of: engine.engineScreen) { screen in if screen != WyrmShellStore.lobbyScreen { entering = false } }
        .onChange(of: engine.arenaRefusalSequence) { sequence in
            guard sequence > lastRefusal else { return }
            lastRefusal = sequence
            entering = false
        }
        // The same stuck ENTERING Android had: if the engine declines a Play
        // without dialling, the screen never changes and no refusal arrives,
        // so this flag was never cleared. The store's gate always ends.
        .onChange(of: engine.arenaPlayPending) { pending in if !pending { entering = false } }
    }

    private func readyRoom(_ size: CGSize, _ safe: EdgeInsets) -> some View {
        // Android splits the row by weight, 1.25 : 0.92, with 28 between. The
        // room runs edge to edge: only the island/home-indicator insets and a
        // slim 18 pt margin, not the old 40 pt on top of them.
        let inner = max(size.width - safe.leading - safe.trailing - 36, 200)
        let cardWidth = (inner - 28) * 1.25 / 2.17
        let nameWidth = inner - 28 - cardWidth
        return ZStack(alignment: .topTrailing) {
            if lastRun == nil {
                WyrmBrandStroke()
                    .stroke(ATheme.ink.opacity(0.045), style: StrokeStyle(lineWidth: 110 * 0.16, lineCap: .round, lineJoin: .round))
                    .frame(width: 90, height: 90)
                    .padding(.trailing, 24 + safe.trailing).padding(.top, 5 + safe.top)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        WyrmCapsLabel("Ready room")
                        Text("Enter the arena").font(.androidWyrm(24, .bold)).tracking(-0.5).foregroundColor(ATheme.ink)
                    }
                    Spacer(minLength: 0)
                    if let lastRun { WyrmLobbyLastRun(run: lastRun, compact: true) }
                }
                Spacer().frame(height: 12)
                Rectangle().fill(ATheme.rule).frame(height: 1)
                Spacer(minLength: 8)

                HStack(alignment: .bottom, spacing: 28) {
                    VStack(alignment: .leading, spacing: 0) {
                        WyrmCapsLabel("Selected arena")
                        Spacer().frame(height: 7)
                        Text(engine.arena.isEmpty ? "No arena selected" : engine.arena)
                            .font(.wyrmDisplay(28)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundColor(engine.arena.isEmpty ? ATheme.quiet : ATheme.ink)
                        Spacer().frame(height: 11)
                        HStack(spacing: 9) {
                            identity("Server code", serverCode)
                            if let arena, arena.number > 0 { identity("Cluster", "\(arena.cluster)") }
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .frame(width: cardWidth, alignment: .leading)
                    .background(ATheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 0) {
                        WyrmCapsLabel("Playing as")
                        Spacer().frame(height: 7)
                        TextField("", text: $nickname)
                            .font(.wyrmDisplay(38)).foregroundColor(entering ? ATheme.quiet : ATheme.ink)
                            .textInputAutocapitalization(.never).disableAutocorrection(true)
                            .submitLabel(.done).focused($nameFocused).disabled(entering)
                            .overlay(alignment: .leading) {
                                if nickname.isEmpty { Text("Wyrm Player").font(.wyrmDisplay(38)).foregroundColor(ATheme.quiet).allowsHitTesting(false) }
                            }
                            .onChange(of: nickname) { value in
                                let clean = String(value.filter { !$0.isASCII || !$0.asciiValue!.isControlCharacter }.prefix(24))
                                if clean != value { nickname = clean }
                            }
                            .onSubmit { saveName(); play() }
                        Spacer().frame(height: 8)
                        LinearGradient(colors: [ATheme.ink.opacity(0.34), ATheme.rule], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(width: nameWidth, alignment: .leading)
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    // Quick settings is gone from the lobby (OM); Home takes its place.
                    paperButton("Home", "house", width: 112, enabled: !entering) { saveName(); engine.leaveLobby() }
                    Spacer(minLength: 0)
                    // Share run (OM, 2026-09-30): the last finished run, until the next match.
                    if hasRun && WyrmTrailsFeature.enabled {
                        WyrmShareRunButton(width: 134, enabled: !entering && !engine.arenaPlayPending) {
                            shareRun()
                        }
                    }
                    // A blank name is allowed: the arena shows no name (OM).
                    paperButton("Play with AI", "sparkles", width: 128, enabled: !entering && !engine.arenaPlayPending) {
                        saveName(); engine.playOffline(name: nickname)
                    }
                    playButton()
                }
            }
            .padding(.top, safe.top).padding(.bottom, safe.bottom)
            .padding(.leading, safe.leading).padding(.trailing, safe.trailing)
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { if nameFocused { nameFocused = false; saveName() } }
    }

    /// The Ready Room held upright (OM, 2026-10-01; redesigned 2026-10-02 for
    /// the thumb zone). A top bar (round Home, "READY ROOM", a faint W), the
    /// title, the arena card and the name card (they scroll if the screen is
    /// short), and a dock at the bottom: Play with AI and Share run side by
    /// side, PLAY full width and tallest under them. Android:
    /// `LobbyReadyRoomUpright`.
    private func readyRoomUpright(_ size: CGSize, _ safe: EdgeInsets) -> some View {
        let showShare = hasRun && WyrmTrailsFeature.enabled
        let inner = max(size.width - safe.leading - safe.trailing - 40, 200)
        let half = showShare ? (inner - 10) / 2 : inner
        return VStack(spacing: 0) {
            ZStack {
                WyrmCapsLabel("Ready room")
                HStack {
                    Button { saveName(); engine.leaveLobby() } label: {
                        Image(systemName: "house").font(.system(size: 17, weight: .semibold))
                            .foregroundColor(entering ? ATheme.quiet : ATheme.ink)
                            .frame(width: 44, height: 44)
                            .background(WyrmGlass.native ? Color.clear : ATheme.card).clipShape(Circle())
                            .overlay(Circle().stroke(ATheme.rule, lineWidth: WyrmGlass.native ? 0 : 1))
                    }
                    .modifier(WyrmGlassCircleButton())
                    .disabled(entering)
                    .accessibilityLabel("Home")
                    Spacer()
                    // The real curvy Wyrm mark, in full ink (OM: the mark, never a letter).
                    WyrmBrandStroke()
                        .stroke(ATheme.ink, style: StrokeStyle(lineWidth: 30 * 0.16, lineCap: .round, lineJoin: .round))
                        .frame(width: 26, height: 26)
                        .padding(.trailing, 4)
                }
            }
            .frame(height: 48)
            .padding(.horizontal, 18).padding(.vertical, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 12)
                    Text("Enter the arena").font(.androidWyrm(30, .bold)).tracking(-0.6).foregroundColor(ATheme.ink)
                    Spacer().frame(height: 4)
                    Text("Check your arena and name, then play.").font(.androidWyrm(14)).foregroundColor(ATheme.quiet)
                    Spacer().frame(height: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        WyrmCapsLabel("Selected arena")
                        Spacer().frame(height: 7)
                        Text(engine.arena.isEmpty ? "No arena selected" : engine.arena)
                            .font(.wyrmDisplay(28)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundColor(engine.arena.isEmpty ? ATheme.quiet : ATheme.ink)
                        Spacer().frame(height: 12)
                        HStack(spacing: 9) {
                            identity("Server code", serverCode)
                            if let arena, arena.number > 0 { identity("Cluster", "\(arena.cluster)") }
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ATheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                    Spacer().frame(height: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        WyrmCapsLabel("Playing as")
                        Spacer().frame(height: 6)
                        TextField("", text: $nickname)
                            .font(.wyrmDisplay(36)).foregroundColor(entering ? ATheme.quiet : ATheme.ink)
                            .textInputAutocapitalization(.never).disableAutocorrection(true)
                            .submitLabel(.done).focused($nameFocused).disabled(entering)
                            .overlay(alignment: .leading) {
                                if nickname.isEmpty { Text("Wyrm Player").font(.wyrmDisplay(36)).foregroundColor(ATheme.quiet).allowsHitTesting(false) }
                            }
                            .onChange(of: nickname) { value in
                                let clean = String(value.filter { !$0.isASCII || !$0.asciiValue!.isControlCharacter }.prefix(24))
                                if clean != value { nickname = clean }
                            }
                            .onSubmit { saveName(); play() }
                        Spacer().frame(height: 8)
                        LinearGradient(colors: [ATheme.ink.opacity(0.34), ATheme.rule], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ATheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                    // Where the name card ends on screen, unlifted: typing
                    // lifts the room by its overlap with the keys.
                    .background(GeometryReader { proxy in
                        let edge = proxy.frame(in: .global).maxY + uprightLift
                        Color.clear
                            .onAppear { uprightNameBottom = edge }
                            .onChange(of: edge) { uprightNameBottom = $0 }
                    })
                    if let lastRun {
                        Spacer().frame(height: 12)
                        WyrmLobbyLastRun(run: lastRun, compact: false)
                    }
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 20)
            }

            // The dock: the thumb's reach, PLAY lowest and largest.
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    paperButton("Play with AI", "sparkles", width: half, enabled: !entering && !engine.arenaPlayPending) {
                        saveName(); engine.playOffline(name: nickname)
                    }
                    if showShare {
                        WyrmShareRunButton(width: half, enabled: !entering && !engine.arenaPlayPending) { shareRun() }
                    }
                }
                playButton(width: inner, height: 62)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 20 + safe.bottom)
            .frame(maxWidth: .infinity)
            .background(WyrmTopRounded(radius: 28).fill(ATheme.card))
            .overlay(WyrmTopRounded(radius: 28).stroke(ATheme.rule, lineWidth: 1))
        }
        .padding(.top, safe.top)
        .padding(.leading, safe.leading).padding(.trailing, safe.trailing)
        .frame(width: size.width, height: size.height)
        .background(ATheme.paper)
        .contentShape(Rectangle())
        .onTapGesture { if nameFocused { nameFocused = false; saveName() } }
    }

    /// Upright typing: how far the name card's bottom sits under the keys.
    private var uprightLift: CGFloat {
        guard keyboard.focused, !keyboard.embedded, let top = keyboard.keysTop else { return 0 }
        return max(0, uprightNameBottom - top + 12)
    }

    private func playButton(width: CGFloat = 160, height: CGFloat = 52) -> some View {
        let enabled = !engine.arena.isEmpty && !entering && !engine.arenaPlayPending
        return Button(action: play) {
            HStack(spacing: 10) {
                if entering { ProgressView().tint(ATheme.quiet).scaleEffect(0.8) }
                else { Image(systemName: "play.fill").font(.system(size: 15, weight: .bold)) }
                Text(entering ? "ENTERING" : "PLAY").font(.androidWyrm(13, .bold)).tracking(2.5)
            }
            .foregroundColor(enabled ? ATheme.onInk : ATheme.quiet)
            .frame(width: width, height: height)
            .background(Capsule().fill(WyrmGlass.native ? Color.clear : (enabled ? ATheme.ink : ATheme.track)))
            .contentShape(Capsule())
        }
        .modifier(WyrmGlassButtonModifier(prominent: true, fallback: WSPressStyle()))
        .disabled(!enabled)
    }

    private func play() {
        guard !engine.arena.isEmpty, !entering, !engine.arenaPlayPending else { return }
        saveName()
        entering = true
        WyrmNearOriginalStore.shared.setServer(arena?.number ?? 0)
        engine.playOnline(name: nickname, address: engine.arena)
    }

    /// Share run: the studio opens in portrait over the app (WyrmDesignRoot)
    /// and the lobby returns Home underneath, as Android leaves the lobby
    /// for its share route. Close lands on Home, Post on the Trails feed.
    private func shareRun() {
        guard let run = WyrmRunCapture.lastRun else { lastRun = nil; return }
        nameFocused = false
        saveName()
        WyrmShareRun.shared.open(run)
        engine.leaveLobby()
    }

    private func saveName() {
        // As typed, blank included: the arena shows it as is (OM).
        let clean = nickname
        if clean != engine.nickname {
            engine.setNickname(clean)
            if !clean.isEmpty { WyrmGameSync.shared.syncIngameName(clean) }
        }
    }

    private func identity(_ label: String, _ value: String) -> some View {
        HStack(spacing: 9) {
            Text(label.uppercased()).font(.androidWyrm(8, .bold)).tracking(1.2).foregroundColor(ATheme.quiet)
            Text(value).font(.androidWyrm(11, .bold)).foregroundColor(ATheme.ink)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(ATheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
    }

    private func paperButton(_ label: String, _ symbol: String, width: CGFloat, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(label).font(.androidWyrm(10, .bold))
            }
            .foregroundColor(enabled ? ATheme.ink : ATheme.quiet)
            .opacity(enabled ? 1 : 0.6)
            .frame(width: width, height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(WyrmGlass.native ? Color.clear : ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(ATheme.rule, lineWidth: WyrmGlass.native ? 0 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .modifier(WyrmGlassButtonModifier(radius: 11, fallback: WyrmLobbyPressStyle()))
        .disabled(!enabled)
    }

    private func quickSettingsPage(_ safe: EdgeInsets) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                paperButton("Back", "chevron.left", width: 106, enabled: true) {
                    withAnimation(.easeInOut(duration: 0.28)) { quickSettings = false }
                }
                VStack(alignment: .leading, spacing: 2) {
                    WyrmCapsLabel("Between rounds")
                    Text("Quick settings").font(.androidWyrm(27, .bold)).foregroundColor(ATheme.ink)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                WyrmCapsLabel("Quick settings")
                Spacer().frame(height: 5)
                Text("This area of Wyrm is in development.").font(.androidWyrm(28, .bold)).foregroundColor(ATheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 7)
                Text("The controls you reach for between rounds will live here.").font(.androidWyrm(11)).foregroundColor(ATheme.mute)
            }
            .padding(.horizontal, 30).padding(.vertical, 26)
            .frame(width: 520, alignment: .leading)
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.top, safe.top).padding(.bottom, safe.bottom)
        .padding(.leading, safe.leading).padding(.trailing, safe.trailing)
        .padding(.horizontal, 34).padding(.vertical, 22)
    }
}

/// Android's lobby paper button: the well colour and a darker edge while held.
/// "Share run", made the one thing the eye goes to (OM, 2026-09-30). The
/// lobby is paper and ink, so this is its only colour: a warm gradient, a
/// halo that breathes out every 1.8 s and a light sweep across the face
/// (contrast first, motion second, as CTA guides say). Reduce Motion keeps it
/// still. No Liquid Glass here on purpose: glass would make it look like its
/// neighbours. Android: `LobbyShareRunButton` in `LobbyScreen.kt`.
/// Rounded on the top corners only (the upright lobby's dock). iOS 15 has no
/// UnevenRoundedRectangle.
struct WyrmTopRounded: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct WyrmShareRunButton: View {
    let width: CGFloat
    let enabled: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var sweep: CGFloat = -0.6

    static let warm = [Color(red: 1, green: 0.663, blue: 0.122), Color(red: 1, green: 0.353, blue: 0.373),
                       Color(red: 0.839, green: 0.227, blue: 0.976)]
    static let coral = Color(red: 1, green: 0.353, blue: 0.373)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let moving = enabled && !reduceMotion
        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .bold))
                Text("Share run").font(.androidWyrm(11, .bold))
            }
            .foregroundColor(.white)
            .frame(width: width, height: 44)
            .background(shape.fill(LinearGradient(colors: Self.warm, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(
                // The light sweep.
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.42), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: proxy.size.width * 0.44, height: proxy.size.height)
                        .offset(x: proxy.size.width * (sweep - 0.22))
                }
                .clipShape(shape)
                .opacity(moving ? 1 : 0)
                .allowsHitTesting(false)
            )
            .background(
                // The halo: a coral ring that grows out and fades.
                shape.fill(Self.coral)
                    .padding(breathing ? -9 : 0)
                    .opacity(moving ? (breathing ? 0 : 0.55) : 0)
                    .allowsHitTesting(false)
            )
            .opacity(enabled ? 1 : 0.45)
            .contentShape(shape)
        }
        .buttonStyle(WyrmLobbyPressStyle())
        .disabled(!enabled)
        .accessibilityLabel("Share run")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { breathing = true }
            withAnimation(.easeInOut(duration: 2.6).delay(0.5).repeatForever(autoreverses: false)) { sweep = 1.6 }
        }
    }
}

struct WyrmLobbyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(ATheme.ink.opacity(configuration.isPressed ? 0.05 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(ATheme.ink.opacity(configuration.isPressed ? 0.22 : 0), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.58), value: configuration.isPressed)
    }
}

private extension UInt8 {
    var isControlCharacter: Bool { self < 0x20 || self == 0x7F }
}

/// The last run (OM, 2026-10-02): the score, the kills and how long it
/// lasted. Shown only after a run since launch; `compact` is the sideways
/// room's header chip. Where it ended is a red dot on the arena's own minimap
/// during the next run (engine `ui_overlay.c`), not here. Android:
/// `LobbyLastRunCard`.
struct WyrmLobbyLastRun: View {
    let run: WyrmLastRun
    let compact: Bool

    static func time(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private var score: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: run.score)) ?? "\(run.score)"
    }

    private func stat(_ label: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.androidWyrm(8.5, .bold)).tracking(1.3).foregroundColor(ATheme.quiet).lineLimit(1)
            Text(value)
                .font(big ? .wyrmDisplay(26) : .androidWyrm(17, .bold))
                .foregroundColor(ATheme.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    var body: some View {
        if compact {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    WyrmCapsLabel("Last run")
                    HStack(alignment: .bottom, spacing: 16) {
                        stat("Score", score)
                        stat("Kills", "\(run.kills)")
                        stat("Time", Self.time(run.seconds))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    WyrmCapsLabel("Last run")
                    Spacer().frame(height: 8)
                    stat("Score", score, big: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 22) {
                    stat("Kills", "\(run.kills)")
                    stat("Time", Self.time(run.seconds))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }
}
