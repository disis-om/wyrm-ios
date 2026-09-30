import SwiftUI

struct WyrmDesignRoot: View {
    @StateObject private var engine = WyrmShellStore()
    @StateObject private var account = WyrmAccountStore()
    @StateObject private var services = WyrmServiceStore()
    @StateObject private var team = WyrmTeamStore()
    /// Share run's studio, drawn over everything while it is open.
    @ObservedObject private var shareRun = WyrmShareRun.shared

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
        arguments.contains("--smoke-settings") || arguments.contains("--smoke-developer") || arguments.contains("--smoke-backup")
    }

    private var socialSmoke: Bool {
        arguments.contains("--smoke-social") || arguments.contains("--smoke-leaderboard") || arguments.contains("--smoke-chat-keyboard")
    }

    private var skinSmoke: Bool {
        arguments.contains("--smoke-skin") || arguments.contains("--smoke-skin-accessories") || arguments.contains("--smoke-skin-tags") || arguments.contains("--smoke-skin-presets") || arguments.contains("--smoke-skin-pattern") || arguments.contains("--smoke-skin-wheel")
    }

    private var teamSmoke: Bool { arguments.contains("--smoke-team") }

    private var authSmokeStage: WyrmAuthStage? {
        if arguments.contains("--smoke-auth-create") { return .createUsername }
        if arguments.contains("--smoke-auth-login") { return .loginUsername }
        if arguments.contains("--smoke-auth-landing") { return .landing }
        return nil
    }

    private var sessionSmokeTitle: String? {
        if arguments.contains("--smoke-session-signout") { return "Signing you out…" }
        if arguments.contains("--smoke-session-sync") { return "Syncing your Wyrm…" }
        return nil
    }

    private var sessionLifecycleID: String {
        "\(String(describing: account.phase)):\(account.player?.id ?? "none")"
    }

    /// The Ready Room and the layout editor sit above the rotated engine
    /// surface; the portrait shell underneath is kept alive but hidden.
    private var engineOverlay: Bool {
        engine.layoutEditorActive || engine.engineScreen == WyrmShellStore.lobbyScreen
    }

    var body: some View {
        ZStack {
            shell
                .opacity(engineOverlay ? 0 : 1)
                .allowsHitTesting(!engineOverlay)
            if engine.layoutEditorActive {
                WyrmLayoutEditor(engine: engine) { engine.closeLayoutEditor() }
            } else if engine.engineScreen == WyrmShellStore.lobbyScreen && shareRun.run == nil {
                // Not under Share run: its sideways keyboard would take the
                // studio's typing.
                WyrmReadyRoom(engine: engine, services: services)
            }
            // Share run (OM, 2026-09-30): the Trails studio in its share mode,
            // portrait like all of UIKit, over the Home the lobby returned to.
            if let run = shareRun.run {
                WyrmTrailStudio(account: account, close: { shareRun.close() }, run: run,
                                onPosted: { shareRun.posted() })
                    .transition(.move(edge: .bottom))
                    .zIndex(90)
            }
            // After a crash: asked once the first real screen is up, never over
            // the launch mark or a match.
            if !launchSyncing && account.phase != .restoring && !engineOverlay && engine.engineScreen == 0
                && shareRun.run == nil {
                WyrmCrashPromptHost().zIndex(100)
            }
            // After an arena drop: asked on the first SwiftUI surface after
            // the match, the Ready Room (landscape) or the portrait app.
            if !launchSyncing && account.phase != .restoring && !engine.layoutEditorActive && shareRun.run == nil
                && (engine.engineScreen == 0 || engine.engineScreen == WyrmShellStore.lobbyScreen) {
                WyrmDropPromptHost(landscape: engine.engineScreen == WyrmShellStore.lobbyScreen).zIndex(99)
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
            WyrmGameSync.shared.start()
            services.observeGameSync()
            WyrmCrashWatch.shared.token = { [weak account] in account?.sessionToken ?? "" }
            WyrmDropWatch.shared.token = { [weak account] in account?.sessionToken ?? "" }
            WyrmDropWatch.shared.arenaLookup = { [weak services] endpoint in
                services?.arenas.first(where: { $0.endpoint == endpoint })
            }
            WyrmSupportStore.shared.token = { [weak account] in account?.sessionToken ?? "" }
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
            case .signingOut:
                WyrmGameSync.shared.deactivate()
                services.resetSession()
                WyrmTrailsStore.shared.reset()
                WyrmShareRun.shared.close()
                WyrmSkinTrial.shared.end()
                WyrmBadgeStore.shared.reset()
                WyrmSupportStore.shared.reset()
                try? await Task.sleep(nanoseconds: 920_000_000)
                guard !Task.isCancelled else { return }
                account.completeSignOut()
            default:
                break
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
                        : arguments.contains("--smoke-backup") ? .backup : nil
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
                    WyrmSessionTransition(title: "Signing you out…")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ATheme.paper.ignoresSafeArea())
    }
}

private struct WyrmDesignLaunch: View {
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
                    .foregroundColor(ATheme.quiet)
                ProgressView().tint(ATheme.ink).padding(.top, 16)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { visible = true }
        }
    }
}
