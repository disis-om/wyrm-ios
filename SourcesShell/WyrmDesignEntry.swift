import SwiftUI

struct WyrmDesignRoot: View {
    @StateObject private var engine = WyrmShellStore()
    @StateObject private var account = WyrmAccountStore()
    @StateObject private var services = WyrmServiceStore()
    @StateObject private var team = WyrmTeamStore()

    private let arguments = ProcessInfo.processInfo.arguments

    private var settingsSmoke: Bool {
        arguments.contains("--smoke-settings") || arguments.contains("--smoke-developer")
    }

    private var socialSmoke: Bool {
        arguments.contains("--smoke-social") || arguments.contains("--smoke-leaderboard")
    }

    private var skinSmoke: Bool {
        arguments.contains("--smoke-skin") || arguments.contains("--smoke-skin-accessories") || arguments.contains("--smoke-skin-tags") || arguments.contains("--smoke-skin-presets") || arguments.contains("--smoke-skin-pattern")
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

    var body: some View {
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
                    initialRoute: arguments.contains("--smoke-developer") ? .developer : nil
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
                    initialRoute: arguments.contains("--smoke-leaderboard") ? .leaderboard : nil
                )
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
        .environmentObject(team)
        .task { team.start() }
        .task(id: sessionLifecycleID) {
            switch account.phase {
            case .signedIn:
                guard !services.isPrepared(for: account.player?.id) else { return }
                await services.bootstrap(token: account.sessionToken, playerID: account.player?.id)
            case .signingOut:
                services.resetSession()
                try? await Task.sleep(nanoseconds: 920_000_000)
                guard !Task.isCancelled else { return }
                account.completeSignOut()
            default:
                break
            }
        }
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
