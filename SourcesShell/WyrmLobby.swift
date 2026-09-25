import SwiftUI
import UIKit

/// A landscape canvas drawn inside the portrait app with the same quarter turn
/// Main.m gives the engine surface, so SwiftUI and the arena share one frame.
/// Content receives the landscape size; its leading edge sits under the
/// Dynamic Island and its trailing edge by the home indicator.
struct WyrmLandscapeStage<Content: View>: View {
    let content: (CGSize, EdgeInsets) -> Content

    init(@ViewBuilder content: @escaping (CGSize, EdgeInsets) -> Content) { self.content = content }

    var body: some View {
        GeometryReader { outer in
            let size = CGSize(width: outer.size.height, height: outer.size.width)
            let safe = Self.windowInsets
            content(size, EdgeInsets(top: safe.left, leading: safe.top, bottom: safe.right, trailing: safe.bottom))
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(90))
                .position(x: outer.size.width / 2, y: outer.size.height / 2)
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
    @FocusState var nameFocused: Bool
    @ObservedObject var keyboard = WyrmKeyboardController.shared

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
            keyboard.embedded = true
            nickname = engine.nickname
            lastRefusal = engine.arenaRefusalSequence
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
    }

    private func readyRoom(_ size: CGSize, _ safe: EdgeInsets) -> some View {
        // Android splits the row by weight, 1.25 : 0.92, with 34 between.
        let inner = max(size.width - safe.leading - safe.trailing - 80, 200)
        let cardWidth = (inner - 34) * 1.25 / 2.17
        let nameWidth = inner - 34 - cardWidth
        return ZStack(alignment: .topTrailing) {
            WyrmBrandStroke()
                .stroke(ATheme.ink.opacity(0.045), style: StrokeStyle(lineWidth: 110 * 0.16, lineCap: .round, lineJoin: .round))
                .frame(width: 110, height: 110)
                .padding(.trailing, 38 + safe.trailing).padding(.top, 5 + safe.top)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    WyrmCapsLabel("Ready room")
                    Text("Enter the arena").font(.androidWyrm(29, .bold)).tracking(-0.6).foregroundColor(ATheme.ink)
                }
                Spacer().frame(height: 18)
                Rectangle().fill(ATheme.rule).frame(height: 1)
                Spacer(minLength: 8)

                HStack(alignment: .bottom, spacing: 34) {
                    VStack(alignment: .leading, spacing: 0) {
                        WyrmCapsLabel("Selected arena")
                        Spacer().frame(height: 7)
                        Text(engine.arena.isEmpty ? "No arena selected" : engine.arena)
                            .font(.wyrmDisplay(34)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundColor(engine.arena.isEmpty ? ATheme.quiet : ATheme.ink)
                        Spacer().frame(height: 14)
                        HStack(spacing: 9) {
                            identity("Server code", serverCode)
                            if let arena, arena.number > 0 { identity("Cluster", "\(arena.cluster)") }
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 18)
                    .frame(width: cardWidth, alignment: .leading)
                    .background(ATheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 0) {
                        WyrmCapsLabel("Playing as")
                        Spacer().frame(height: 7)
                        TextField("", text: $nickname)
                            .font(.wyrmDisplay(48)).foregroundColor(entering ? ATheme.quiet : ATheme.ink)
                            .textInputAutocapitalization(.never).disableAutocorrection(true)
                            .submitLabel(.done).focused($nameFocused).disabled(entering)
                            .overlay(alignment: .leading) {
                                if nickname.isEmpty { Text("Wyrm Player").font(.wyrmDisplay(48)).foregroundColor(ATheme.quiet).allowsHitTesting(false) }
                            }
                            .onChange(of: nickname) { value in
                                let clean = String(value.filter { !$0.isASCII || !$0.asciiValue!.isControlCharacter }.prefix(24))
                                if clean != value { nickname = clean }
                            }
                            .onSubmit { saveName(); if !nickname.isEmpty { play() } }
                        Spacer().frame(height: 8)
                        LinearGradient(colors: [ATheme.ink.opacity(0.34), ATheme.rule], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(width: nameWidth, alignment: .leading)
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    paperButton("Quick settings", "slider.horizontal.3", width: 176, enabled: !entering) {
                        withAnimation(.easeInOut(duration: 0.28)) { quickSettings = true }
                    }
                    Spacer(minLength: 0)
                    paperButton("Home", "house", width: 112, enabled: !entering) { saveName(); engine.leaveLobby() }
                    paperButton("Play with AI", "sparkles", width: 142, enabled: !nickname.isEmpty && !entering) {
                        saveName(); engine.playOffline(name: nickname)
                    }
                    playButton
                }
            }
            .padding(.top, safe.top).padding(.bottom, safe.bottom)
            .padding(.leading, safe.leading).padding(.trailing, safe.trailing)
            .padding(.horizontal, 40).padding(.vertical, 24)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { if nameFocused { nameFocused = false; saveName() } }
    }

    private var playButton: some View {
        let enabled = !engine.arena.isEmpty && !nickname.isEmpty && !entering
        return Button(action: play) {
            HStack(spacing: 10) {
                if entering { ProgressView().tint(ATheme.quiet).scaleEffect(0.8) }
                else { Image(systemName: "play.fill").font(.system(size: 15, weight: .bold)) }
                Text(entering ? "ENTERING" : "PLAY").font(.androidWyrm(13, .bold)).tracking(2.5)
            }
            .foregroundColor(enabled ? ATheme.onInk : ATheme.quiet)
            .frame(width: 180, height: 62)
            .background(Capsule().fill(enabled ? ATheme.ink : ATheme.track))
            .contentShape(Capsule())
        }
        .buttonStyle(WSPressStyle()).disabled(!enabled)
    }

    private func play() {
        guard !engine.arena.isEmpty, !nickname.isEmpty, !entering else { return }
        saveName()
        entering = true
        engine.playOnline(name: nickname, address: engine.arena)
    }

    private func saveName() {
        let clean = nickname.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty, clean != engine.nickname {
            engine.setNickname(clean)
            WyrmGameSync.shared.syncIngameName(clean)
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
            .frame(width: width, height: 49)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(WyrmLobbyPressStyle()).disabled(!enabled)
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
