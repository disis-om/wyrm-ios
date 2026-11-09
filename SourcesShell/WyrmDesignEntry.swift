import SwiftUI

struct WyrmDesignRoot: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @StateObject private var engine = WyrmShellStore()
    @StateObject private var account = WyrmAccountStore()
    @StateObject private var services = WyrmServiceStore()
    @StateObject private var team = WyrmTeamStore()
    /// Share run's studio, drawn over everything while it is open.
    @ObservedObject private var shareRun = WyrmShareRun.shared
    /// Upright play: the lobby is portrait, so the drop card takes the portrait path.
    @ObservedObject private var playOrientation = WyrmPlayOrientation.shared
    /// Account-linked settings: saved in the background and on log out (WyrmAccountSync).
    @ObservedObject private var accountSync = WyrmAccountSync.shared
    /// The arena chat window's message box: one line above the keyboard.
    @ObservedObject private var teamComposer = WyrmTeamComposer.shared
    @Environment(\.scenePhase) private var scenePhase

    private let arguments = ProcessInfo.processInfo.arguments
    /// True from launch until the first account snapshot is installed. A
    /// session restored at launch syncs silently behind the W launch screen;
    /// only a fresh sign-in or sign-up shows "Syncing your Wyrm…".
    @State private var coldStart = true

    private var launchSyncing: Bool {
        account.phase == .restoring
            || (coldStart && account.phase == .signedIn && !services.isPrepared(for: account.player?.id))
    }

    private var settingsSmoke: Bool {
        arguments.contains("--smoke-settings") || arguments.contains("--smoke-developer") || arguments.contains("--smoke-backup") || arguments.contains("--smoke-modes") || arguments.contains("--smoke-controls")
    }

    private var socialSmoke: Bool {
        arguments.contains("--smoke-social") || arguments.contains("--smoke-leaderboard") || arguments.contains("--smoke-chat-keyboard")
    }

    private var skinSmoke: Bool {
        arguments.contains("--smoke-skin") || arguments.contains("--smoke-skin-studio") || arguments.contains("--smoke-skin-accessories") || arguments.contains("--smoke-skin-tags") || arguments.contains("--smoke-skin-presets") || arguments.contains("--smoke-skin-pattern") || arguments.contains("--smoke-skin-wheel")
    }

    private var teamSmoke: Bool { arguments.contains("--smoke-team") }

    private var authSmokeStage: WyrmAuthStage? {
        if arguments.contains("--smoke-auth-create") { return .createUsername }
        if arguments.contains("--smoke-auth-login") { return .loginUsername }
        if arguments.contains("--smoke-auth-landing") { return .landing }
        return nil
    }

    private var sessionSmokeTitle: String? {
        if arguments.contains("--smoke-session-signout") { return "Logging you out…" }
        if arguments.contains("--smoke-session-sync") { return "Syncing your Wyrm…" }
        return nil
    }

    private var sessionLifecycleID: String {
        "\(String(describing: account.phase)):\(account.player?.id ?? "none")"
    }

    /// The Ready Room/editor share the native game window; the persistent
    /// app shell is kept alive but hidden until the return to portrait.
    private var engineOverlay: Bool {
        engine.layoutEditorActive || engine.engineScreen == WyrmShellStore.lobbyScreen
            // The arena's team composer: only the bar over the match (OM, 2026-10-06).
            || (teamComposer.open && engine.engineScreen == 2)
            // The GPU was lost: only its card (OM, 2026-10-06).
            || engine.graphicsLost
    }

    var body: some View {
        ZStack {
            shell
                .opacity(engineOverlay ? 0 : 1)
                .allowsHitTesting(!engineOverlay)
            if engine.layoutEditorActive {
                // Snake look before the background editor (OM, 2026-10-05).
                if engine.snakeLookEditor {
                    WyrmSnakeLookEditor(engine: engine) { engine.closeLayoutEditor() }
                } else if engine.backgroundEditor {
                    WyrmBackgroundSizeEditor(engine: engine) { engine.closeLayoutEditor() }
                } else {
                    WyrmLayoutEditor(engine: engine) { engine.closeLayoutEditor() }
                }
            } else if engine.engineScreen == WyrmShellStore.lobbyScreen && !shareRun.isOpen {
                // Share run owns focus while its portrait studio is open.
                // The stage places itself above the keys from the measured keyboard
                // (WyrmLandscapeStage); SwiftUI must not move it a second time
                // (OM, 2026-11-07: the room slid up and the keys went under it).
                WyrmReadyRoom(engine: engine, services: services)
                    .ignoresSafeArea(.keyboard)
            }
            // Share run (OM, 2026-09-30): the Trails studio in its share mode,
            // portrait like all of UIKit, over the Home the lobby returned to.
            // Share this skin (Skin tab) opens the same studio with no run.
            if shareRun.isOpen {
                WyrmTrailStudio(account: account, close: { shareRun.close() }, run: shareRun.run,
                                skinOnly: shareRun.skinOnly, onPosted: { shareRun.posted() })
                    .transition(.move(edge: .bottom))
                    .zIndex(90)
            }
            // After a crash: asked once the first real screen is up, never over
            // the launch mark or a match.
            if !launchSyncing && account.phase != .restoring && !engineOverlay && engine.engineScreen == 0
                && !shareRun.isOpen {
                WyrmCrashPromptHost().zIndex(100)
            }
            // The developer's notice (OM, 2026-10-25): in the middle, never over the launch
            // mark, a match or an editor.
            if !launchSyncing && account.phase != .restoring && !engineOverlay && engine.engineScreen == 0
                && !shareRun.isOpen && !engine.layoutEditorActive {
                WyrmNoticeHost().zIndex(98)
            }
            // Events (2026-10-30): the join question and the wait for the start,
            // over the portrait app only.
            if !launchSyncing && account.phase != .restoring && !engineOverlay && engine.engineScreen == 0 && !shareRun.isOpen {
                WyrmEventOverlays(engine: engine).zIndex(97)
            }
            // After an arena drop: asked on the first SwiftUI surface after
            // the match, the Ready Room (landscape) or the portrait app.
            if !launchSyncing && account.phase != .restoring && !engine.layoutEditorActive && !shareRun.isOpen
                && (engine.engineScreen == 0 || engine.engineScreen == WyrmShellStore.lobbyScreen) {
                WyrmDropPromptHost(landscape: engine.engineScreen == WyrmShellStore.lobbyScreen && !playOrientation.portrait).zIndex(99)
            }
            WyrmInternalKeyboardOverlay().zIndex(200)
            // Writing to the team from the arena (OM, 2026-10-04); the match plays on.
            if teamComposer.open && engine.engineScreen == 2 {
                // The bar adds the measured keyboard overlap itself (WyrmTeamHud
                // nativeComposer); SwiftUI's own keyboard lift on top of it sent
                // the chat up twice as far (OM, 2026-11-07). Ignore it here.
                WyrmArenaComposerBar(team: team).ignoresSafeArea(.keyboard).zIndex(105)
            }
            // The GPU device was lost: the engine can draw nothing more this run.
            if engine.graphicsLost {
                let sideways = !playOrientation.portrait
                    && (engine.engineScreen == 2 || engine.engineScreen == WyrmShellStore.lobbyScreen)
                Group {
                    if sideways {
                        WyrmLandscapeStage { size, _ in
                            WyrmGraphicsLostCard(onClose: closeAfterGraphicsLoss)
                                .frame(width: size.width, height: size.height)
                        }
                    } else {
                        WyrmGraphicsLostCard(onClose: closeAfterGraphicsLoss)
                    }
                }
                .zIndex(130)
            }
            // Log out (OM, 2026-10-01): the question, the save, and a failed save's choices.
            if accountSync.askingLogOut {
                Color.black.opacity(0.32).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { accountSync.askingLogOut = false } }
                    .transition(.opacity).zIndex(110)
                VStack {
                    Spacer()
                    WyrmLogOutSheet(
                        name: account.player?.displayName ?? "Wyrm player",
                        handle: account.player?.handle ?? "",
                        onLogOut: logOut,
                        onCancel: { withAnimation(.easeOut(duration: 0.2)) { accountSync.askingLogOut = false } }
                    )
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom))
                .zIndex(111)
            }
            if accountSync.logOutStage == .saving {
                WyrmSessionTransition(title: "Saving your settings…").zIndex(112)
            }
            if case .failed(let reason) = accountSync.logOutStage {
                WyrmLogOutFailed(
                    message: reason,
                    onRetry: logOut,
                    onLogOutAnyway: {
                        accountSync.logOutStage = .idle
                        account.signOut()
                    },
                    onStay: { accountSync.logOutStage = .idle }
                ).zIndex(113)
            }
        }
        // The engine overlays reserve keyboard space themselves; never resize
        // the whole hosting root and expose the clear/black SDL underlay.
        .ignoresSafeArea(engineOverlay ? .all : [], edges: .all)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: accountSync.askingLogOut)
        // The account keeps a current copy of the settings: saved whenever the app leaves the screen.
        .onChange(of: scenePhase) { phase in
            guard phase == .background, account.phase == .signedIn else { return }
            let token = account.sessionToken
            let work = UIApplication.shared.beginBackgroundTask(withName: "wyrm.settings", expirationHandler: nil)
            Task {
                await accountSync.save(token: token)
                UIApplication.shared.endBackgroundTask(work)
            }
        }
        // A match that ends with the team composer open closes it, so the
        // shell is never left shown over a later screen.
        .onChange(of: engine.engineScreen) { screen in
            WyrmKeyboardController.shared.dismiss()
            if screen != 2 && teamComposer.open { teamComposer.closeNow() }
            WyrmPresence.shared.engineScreen(screen)
        }
        // CI: the team composer over an AI match, for a screenshot.
        .onChange(of: engine.engineScreen) { screen in
            guard screen == 2, arguments.contains("--smoke-team-composer") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                teamComposer.present()
                NSLog("Wyrm smoke: team composer opened")
            }
        }
        // A death picture that lands after Share run opened joins it.
        .onReceive(NotificationCenter.default.publisher(for: WyrmRunCapture.didChange)) { _ in shareRun.refresh() }
        .environmentObject(team)
        .onChange(of: account.phase) { phase in if phase == .signedOut || phase == .signingOut { coldStart = false } }
        .onChange(of: services.isPrepared(for: account.player?.id)) { prepared in
            if prepared {
                coldStart = false
                WyrmGameSync.shared.activate(token: account.sessionToken, playerID: account.player?.id ?? "")
            }
        }
        .task {
            team.start()
            // Skin textures decoded in the background shortly after launch, so the
            // Skin tab opens with its skins, not eyes first (OM, 2026-11-07).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { WyrmSkinTextureLibrary.prewarm() }
            WyrmGameSync.shared.start()
            services.observeGameSync()
            WyrmCrashWatch.shared.token = { [weak account] in account?.sessionToken ?? "" }
            // The developer's notice (OM, 2026-10-25): asked once per start.
            WyrmNoticeCenter.shared.check()
            WyrmDropWatch.shared.token = { [weak account] in account?.sessionToken ?? "" }
            WyrmDropWatch.shared.arenaLookup = { [weak services] endpoint in
                services?.arenas.first(where: { $0.endpoint == endpoint })
            }
            WyrmSupportStore.shared.token = { [weak account] in account?.sessionToken ?? "" }
            // Events (2026-10-30): signed in, an event's page also lists friends.
            WyrmEventsStore.shared.token = { [weak account] in account?.sessionToken ?? "" }
            // The beads and the last events list are ready before Home draws.
            WyrmEventBeads.shared.preload()
            accountSync.engine = engine
        }
        .task(id: sessionLifecycleID) {
            switch account.phase {
            case .signedIn:
                // Replies from Wyrm: the cached count at once (the Settings
                // badge), then the server's answer.
                WyrmSupportStore.shared.token = { [weak account] in account?.sessionToken ?? "" }
                WyrmSupportStore.shared.loadCache()
                Task { await WyrmSupportStore.shared.refresh() }
                guard !services.isPrepared(for: account.player?.id) else {
                    WyrmGameSync.shared.activate(token: account.sessionToken, playerID: account.player?.id ?? "")
                    return
                }
                await services.bootstrap(token: account.sessionToken, playerID: account.player?.id)
                // A session restored at launch: finish an owed restore, or keep the account's copy current.
                accountSync.resume(token: account.sessionToken, playerID: account.player?.id ?? "")
            case .signingOut:
                WyrmLiveInbox.shared.stop()
                WyrmPresence.shared.stop()
                WyrmPresence.shared.reset()
                WyrmGameSync.shared.deactivate()
                services.resetSession()
                WyrmTrailsStore.shared.reset()
                WyrmShareRun.shared.close()
                WyrmSkinTrial.shared.end()
                WyrmBadgeStore.shared.reset()
                WyrmSupportStore.shared.reset()
                WyrmEventsStore.shared.clearAll()
                // Nothing of this account stays on the phone: defaults, engine settings, looks.
                accountSync.wipeDevice()
                try? await Task.sleep(nanoseconds: 920_000_000)
                guard !Task.isCancelled else { return }
                account.completeSignOut()
            default:
                break
            }
        }
    }

    /// After a lost GPU: the settings go to the account first (at most a few
    /// seconds), then Wyrm closes so the player can open it again.
    private func closeAfterGraphicsLoss() {
        let token = account.sessionToken
        let signedIn = account.phase == .signedIn
        let sync = accountSync
        Task { @MainActor in
            if signedIn {
                let save = Task { @MainActor in await sync.save(token: token) }
                let limit = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    save.cancel()
                }
                _ = await save.value
                limit.cancel()
            }
            WyrmDiagnostics.record("closed after a lost GPU", category: "CRASH")
            exit(0)
        }
    }

    /// Log out: settings to the account first; a failed save asks before anything is lost.
    private func logOut() {
        withAnimation(.easeOut(duration: 0.2)) { accountSync.askingLogOut = false }
        let token = account.sessionToken
        Task {
            if await accountSync.saveForLogOut(token: token) {
                accountSync.logOutStage = .idle
                account.signOut()
            }
        }
    }

    private var shell: some View {
        Group {
            if let sessionSmokeTitle {
                WyrmSessionTransition(title: sessionSmokeTitle)
            } else if let authSmokeStage {
                WyrmCinematicAuth(account: account, services: services, initialStage: authSmokeStage, autofocus: false)
            } else if settingsSmoke {
                WyrmDesignMain(
                    engine: engine,
                    account: account,
                    services: services,
                    initialTab: .settings,
                    initialRoute: arguments.contains("--smoke-developer") ? .developer
                        : arguments.contains("--smoke-backup") ? .backup
                        : arguments.contains("--smoke-modes") ? .modes
                        : arguments.contains("--smoke-controls") ? .playControls : nil
                )
            } else if teamSmoke {
                WyrmDesignMain(engine: engine, account: account, services: services,
                               initialTab: .play, initialRoute: .team)
            } else if skinSmoke {
                WyrmDesignMain(
                    engine: engine,
                    account: account,
                    services: services,
                    initialTab: .skin
                )
            } else if socialSmoke {
                WyrmDesignMain(
                    engine: engine,
                    account: account,
                    services: services,
                    initialTab: .social,
                    initialRoute: arguments.contains("--smoke-leaderboard") ? .leaderboard
                        : arguments.contains("--smoke-chat-keyboard") ? .globalChat : nil
                )
            } else if launchSyncing {
                WyrmDesignLaunch()
            } else {
                switch account.phase {
                case .restoring:
                    WyrmDesignLaunch()
                case .signedOut:
                    WyrmCinematicAuth(account: account, services: services)
                case .onboarding:
                    // Username/password accounts now enter Home directly. The
                    // old six-screen onboarding route is intentionally retired.
                    WyrmDesignMain(engine: engine, account: account, services: services, initialTab: .play)
                case .signedIn:
                    if services.isPrepared(for: account.player?.id) {
                        WyrmDesignMain(engine: engine, account: account, services: services, initialTab: .play)
                    } else {
                        WyrmSessionTransition(title: "Syncing your Wyrm…")
                    }
                case .signingOut:
                    WyrmSessionTransition(title: "Logging you out…")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(wyrmScopedColours.paper.ignoresSafeArea())
    }
}

private struct WyrmDesignLaunch: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @State private var visible = false

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 18) {
                WyrmBrandMark(size: 108)
                    .scaleEffect(visible ? 1 : 0.86)
                    .opacity(visible ? 1 : 0)
                Text("WYRM")
                    .font(.androidWyrm(11, .bold))
                    .tracking(3)
                    .foregroundColor(wyrmScopedColours.quiet)
                ProgressView().tint(wyrmScopedColours.ink).padding(.top, 16)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { visible = true }
        }
    }
}

/// The GPU device was lost (Vulkan VK_ERROR_DEVICE_LOST, OM 2026-10-06): the
/// game can draw nothing more this run. Says so plainly, saves, closes Wyrm.
struct WyrmGraphicsLostCard: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let onClose: () -> Void
    @State private var closing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                WyrmCapsLabel("Graphics stopped")
                Text("Wyrm needs a restart")
                    .font(.wyrmDisplay(26)).foregroundColor(wyrmScopedColours.ink)
                Text("Your iPhone stopped Wyrm's graphics, so the game cannot draw any more. Close Wyrm and open it again to keep playing. Your settings are saved first.")
                    .font(.androidWyrm(14)).foregroundColor(wyrmScopedColours.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    guard !closing else { return }
                    closing = true
                    onClose()
                } label: {
                    Text(closing ? "SAVING" : "CLOSE WYRM")
                        .font(.androidWyrm(13, .bold)).tracking(1.2).foregroundColor(wyrmScopedColours.onInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Capsule().fill(wyrmScopedColours.ink))
                }
                .disabled(closing)
                .padding(.top, 6)
            }
            .padding(22)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(wyrmScopedColours.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(wyrmScopedColours.rule, lineWidth: 1))
            .padding(24)
        }
    }
}
