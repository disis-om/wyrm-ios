import SwiftUI

struct WyrmDesignRoot: View {
    @StateObject private var engine = WyrmShellStore()
    @StateObject private var account = WyrmAccountStore()
    @StateObject private var services = WyrmServiceStore()

    private let arguments = ProcessInfo.processInfo.arguments

    private var settingsSmoke: Bool {
        arguments.contains("--smoke-settings") || arguments.contains("--smoke-developer")
    }

    private var authSmokeStage: WyrmAuthStage? {
        if arguments.contains("--smoke-auth-create") { return .createUsername }
        if arguments.contains("--smoke-auth-login") { return .loginUsername }
        if arguments.contains("--smoke-auth-landing") { return .landing }
        return nil
    }

    var body: some View {
        Group {
            if let authSmokeStage {
                WyrmCinematicAuth(account: account, initialStage: authSmokeStage, autofocus: false)
            } else if settingsSmoke {
                WyrmDesignMain(
                    engine: engine,
                    account: account,
                    services: services,
                    initialTab: .settings,
                    initialRoute: arguments.contains("--smoke-developer") ? .developer : nil
                )
            } else {
                switch account.phase {
                case .restoring:
                    WyrmDesignLaunch()
                case .signedOut:
                    WyrmCinematicAuth(account: account)
                case .onboarding, .signedIn:
                    // Username/password accounts now enter Home directly. The
                    // old six-screen onboarding route is intentionally retired.
                    WyrmDesignMain(engine: engine, account: account, services: services, initialTab: .play)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ATheme.paper.ignoresSafeArea())
        .task(id: account.player?.id) {
            guard account.phase == .signedIn else { return }
            await services.bootstrap(token: account.sessionToken)
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
