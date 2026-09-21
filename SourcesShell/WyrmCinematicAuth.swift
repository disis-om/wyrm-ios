import Combine
import SwiftUI
import UIKit

enum WyrmAuthStage: Equatable {
    case landing
    case createUsername
    case createPassword
    case createConfirmation
    case loginUsername
    case loginPassword
    case creating
    case signingIn
    case success
}

private enum WyrmAuthFocus: Hashable {
    case username
    case password
    case confirmation
}

private enum WyrmUsernameAvailabilityState: Equatable {
    case idle
    case checking
    case available
    case taken
    case unavailable
}

private enum WyrmPasswordConfirmationState: Equatable {
    case idle
    case checking
    case matched
    case mismatched
}

@MainActor
private final class WyrmKeyboardMonitor: ObservableObject {
    @Published var height: CGFloat = 0
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let frameChanges = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let hides = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        frameChanges
            .sink { [weak self] note in self?.consume(note) }
            .store(in: &subscriptions)
        hides
            .sink { [weak self] note in self?.consume(note, hidden: true) }
            .store(in: &subscriptions)
    }

    private func consume(_ note: Notification, hidden: Bool = false) {
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let nextHeight = hidden ? 0 : max(0, UIScreen.main.bounds.height - (frame?.minY ?? UIScreen.main.bounds.height))
        withAnimation(.easeOut(duration: duration)) { height = nextHeight }
    }
}

struct WyrmCinematicAuth: View {
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var keyboard = WyrmKeyboardMonitor()
    @FocusState private var focus: WyrmAuthFocus?
    @State private var stage: WyrmAuthStage
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var logoDissolved = false
    @State private var usernameAvailability: WyrmUsernameAvailabilityState = .idle
    @State private var confirmationState: WyrmPasswordConfirmationState = .idle
    @State private var availabilityTask: Task<Void, Never>?
    @State private var confirmationTask: Task<Void, Never>?

    private let autofocus: Bool

    init(account: WyrmAccountStore, services: WyrmServiceStore,
         initialStage: WyrmAuthStage = .landing, autofocus: Bool = true) {
        self.account = account
        self.services = services
        self.autofocus = autofocus
        _stage = State(initialValue: initialStage)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = max(proxy.safeAreaInsets.top, 18)
            let safeBottom = max(proxy.safeAreaInsets.bottom, 12)
            ZStack {
                WyrmPaperBackground()

                if stage == .landing {
                    WyrmDotField()
                        .frame(height: min(280, max(232, proxy.size.height * 0.31)))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }

                stageContent(proxy: proxy, safeTop: safeTop, safeBottom: safeBottom)

                WyrmBrandMark(size: logoSize)
                    .position(x: proxy.size.width / 2, y: logoY(in: proxy, safeTop: safeTop))
                    .scaleEffect(stage == .success ? 1.08 : 1)
                    .opacity(logoDissolved ? 0 : 1)
                    .blur(radius: logoDissolved ? 18 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(4)

                if showsBack {
                    backButton
                        .position(x: 42, y: safeTop + 24)
                        .transition(.wyrmBlurFade)
                        .zIndex(6)
                }

                if showsKeyboardAction {
                    WyrmAuthKeyboardAction(title: actionTitle, enabled: actionEnabled, action: advance)
                        .padding(.horizontal, 16)
                        .padding(.bottom, keyboard.height > 0 ? keyboard.height + 9 : safeBottom + 10)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.wyrmBlurFade)
                        .zIndex(8)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.container, edges: .all)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .foregroundColor(ATheme.ink)
        .animation(motion, value: stage)
        .animation(motion, value: showsKeyboardAction)
        .animation(motion, value: keyboard.height > 0)
        .onAppear {
            recordStage(stage)
            focusInitialStageIfNeeded()
        }
        .onChange(of: stage) { next in
            recordStage(next)
            if next == .createUsername { scheduleUsernameAvailability() }
            if next == .createConfirmation { schedulePasswordComparison() }
        }
        .onChange(of: username) { _ in scheduleUsernameAvailability() }
        .onChange(of: password) { _ in
            confirmationTask?.cancel()
            confirmationState = .idle
            if stage == .createConfirmation { schedulePasswordComparison() }
        }
        .onChange(of: confirmation) { _ in schedulePasswordComparison() }
        .onDisappear {
            availabilityTask?.cancel()
            confirmationTask?.cancel()
        }
    }

    @ViewBuilder
    private func stageContent(proxy: GeometryProxy, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        ZStack {
            switch stage {
            case .landing:
                landing(proxy: proxy, safeBottom: safeBottom)
                    .transition(.wyrmBlurFade)
            case .createUsername, .createPassword, .createConfirmation, .loginUsername, .loginPassword:
                credentialStage(proxy: proxy, safeTop: safeTop)
                    .id(stage)
                    .transition(.wyrmBlurFade)
            case .creating:
                WyrmAuthWorkingStatus(title: "Creating your account…")
                    .position(x: proxy.size.width / 2, y: workingStatusY(in: proxy))
                    .transition(.wyrmBlurFade)
            case .signingIn:
                WyrmAuthWorkingStatus(title: "Entering Wyrm…")
                    .position(x: proxy.size.width / 2, y: workingStatusY(in: proxy))
                    .transition(.wyrmBlurFade)
            case .success:
                Color.clear
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
    }

    private func landing(proxy: GeometryProxy, safeBottom: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: min(280, max(232, proxy.size.height * 0.31)))

            Text("WELCOME TO WYRM")
                .font(.androidWyrm(11.5, .semibold))
                .tracking(1.1)
                .foregroundColor(ATheme.quiet)

            Text("The arena\nand people in it.")
                .font(.androidWyrm(31, .bold))
                .tracking(-0.7)
                .lineSpacing(-1)
                .padding(.top, 8)

            Text("A High Performance Engine — plus assist mode, team play, global chat and a live leaderboard.")
                .font(.androidWyrm(15.5))
                .foregroundColor(ATheme.mute)
                .lineSpacing(5)
                .padding(.top, 11)

            Spacer(minLength: 18)

            WyrmPrimaryAction(title: "Create Wyrm account", icon: "arrow.right") {
                enter(.createUsername, focus: .username)
            }

            Button {
                enter(.loginUsername, focus: .username)
            } label: {
                Text("Login")
                    .font(.androidWyrm(14.5, .semibold))
                    .foregroundColor(ATheme.link)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Sign in with an existing Wyrm username and password")

            Text("Privacy")
                .font(.androidWyrm(12.5))
                .foregroundColor(ATheme.quiet.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, safeBottom + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func credentialStage(proxy: GeometryProxy, safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 150)

            VStack(spacing: 16) {
                Text(stageKicker)
                    .font(.androidWyrm(10.5, .bold))
                    .tracking(1.35)
                    .foregroundColor(ATheme.quiet)

                composer

                Text(stageInstruction)
                    .font(.androidWyrm(12.5))
                    .foregroundColor(ATheme.mute)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)

                if !account.errorMessage.isEmpty {
                    Text(account.errorMessage)
                        .font(.androidWyrm(12, .semibold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .transition(.wyrmBlurFade)
                } else if let validationMessage {
                    Text(validationMessage)
                        .font(.androidWyrm(11.5, .semibold))
                        .foregroundColor(ATheme.quiet)
                        .transition(.wyrmBlurFade)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 155)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: keyboard.height > 0 ? -min(116, max(78, keyboard.height * 0.28)) : 0)
    }

    @ViewBuilder
    private var composer: some View {
        switch stage {
        case .createUsername, .loginUsername:
            HStack(spacing: 5) {
                Text("@").font(.androidWyrm(22, .semibold)).foregroundColor(ATheme.quiet)
                TextField("username", text: usernameBinding)
                    .focused($focus, equals: .username)
                    .font(.androidWyrm(21, .semibold))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textContentType(.username)
                    .submitLabel(.continue)
                    .onSubmit { if actionEnabled { advance() } }
                    .accessibilityLabel("Wyrm username")

                if stage == .createUsername && usernameValid {
                    usernameAvailabilityIndicator
                        .frame(width: 27, height: 27)
                        .transition(.wyrmBlurFade)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 60)
            .background(Color.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(ATheme.rule))
            .shadow(color: ATheme.ink.opacity(0.045), radius: 22, y: 9)

        case .createPassword, .loginPassword:
            SecureField("Password", text: $password)
                .focused($focus, equals: .password)
                .font(.androidWyrm(19, .semibold))
                .textContentType(stage == .createPassword ? .newPassword : .password)
                .submitLabel(stage == .createPassword ? .next : .go)
                .onSubmit { if actionEnabled { advance() } }
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(Color.white.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(ATheme.rule))
                .shadow(color: ATheme.ink.opacity(0.045), radius: 22, y: 9)
                .accessibilityLabel(stage == .createPassword ? "Choose password" : "Password")

        case .createConfirmation:
            VStack(alignment: .leading, spacing: 9) {
                SecureField("Password again", text: $confirmation)
                    .focused($focus, equals: .confirmation)
                    .font(.androidWyrm(19, .semibold))
                    .textContentType(.newPassword)
                    .submitLabel(.go)
                    .onSubmit { if actionEnabled { advance() } }
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                    .background(Color.white.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(ATheme.rule))
                    .shadow(color: ATheme.ink.opacity(0.045), radius: 22, y: 9)
                    .accessibilityLabel("Confirm password")

                passwordConfirmationFeedback
                    .padding(.leading, 5)
                    .frame(minHeight: 24, alignment: .leading)
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var usernameAvailabilityIndicator: some View {
        switch usernameAvailability {
        case .checking:
            ProgressView()
                .tint(ATheme.quiet)
                .scaleEffect(0.82)
                .accessibilityLabel("Checking username availability")
        case .available:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
                .background(ATheme.live)
                .clipShape(Circle())
                .accessibilityLabel("Username available")
        case .taken:
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.white)
                .frame(width: 25, height: 25)
                .background(Color.red.opacity(0.88))
                .clipShape(Circle())
                .accessibilityLabel("Username unavailable")
        case .unavailable:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(ATheme.quiet)
                .accessibilityLabel("Availability check unavailable")
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var passwordConfirmationFeedback: some View {
        switch confirmationState {
        case .checking:
            ProgressView()
                .tint(ATheme.quiet)
                .scaleEffect(0.76)
                .frame(width: 22, height: 22)
                .transition(.wyrmBlurFade)
                .accessibilityLabel("Checking passwords")
        case .matched:
            WyrmPasswordMatchLabel(
                text: "Password matched, continue!",
                systemImage: "checkmark",
                colour: ATheme.live
            )
            .transition(.wyrmBlurFade)
        case .mismatched:
            WyrmPasswordMatchLabel(
                text: "Password didn't match, recheck!",
                systemImage: "xmark",
                colour: .red
            )
            .transition(.wyrmBlurFade)
        case .idle:
            EmptyView()
        }
    }

    private var backButton: some View {
        Button(action: goBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(ATheme.ink)
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(0.88))
                .clipShape(Circle())
                .overlay(Circle().stroke(ATheme.rule))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var usernameBinding: Binding<String> {
        Binding(
            get: { username },
            set: { value in
                username = String(value.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(20))
                account.errorMessage = ""
            }
        )
    }

    private var stageKicker: String {
        switch stage {
        case .createUsername: return "YOUR WYRM ID"
        case .loginUsername: return "WELCOME BACK"
        case .createPassword: return "SECURE YOUR ACCOUNT"
        case .loginPassword: return "YOUR PASSWORD"
        case .createConfirmation: return "ONE MORE TIME"
        default: return ""
        }
    }

    private var stageInstruction: String {
        switch stage {
        case .createUsername:
            return "Choose a username for your Wyrm account. It links your global leaderboard data, follows, follow-backs and messages."
        case .loginUsername:
            return "Enter the username connected to your Wyrm profile."
        case .createPassword:
            return "Use at least 8 characters. This account has no email recovery, so keep the password somewhere safe."
        case .loginPassword:
            return "Enter the password for @\(username)."
        case .createConfirmation:
            return "Re-enter your password to make sure it is correct."
        default:
            return ""
        }
    }

    private var validationMessage: String? {
        switch stage {
        case .createUsername where !username.isEmpty && !usernameValid:
            return "3–20 letters, numbers or underscores"
        case .createUsername where usernameAvailability == .taken:
            return "That username is already taken"
        case .createUsername where usernameAvailability == .unavailable:
            return "Could not check availability. Edit the username to retry."
        case .createPassword where !password.isEmpty && !passwordValid:
            return "\(max(0, 8 - password.count)) more character\(password.count == 7 ? "" : "s")"
        default:
            return nil
        }
    }

    private var usernameValid: Bool {
        username.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    private var passwordValid: Bool { password.count >= 8 && password.count <= 200 }

    private var actionTitle: String {
        switch stage {
        case .createUsername, .loginUsername: return "Continue"
        case .createPassword: return "Next"
        case .loginPassword: return "Login"
        case .createConfirmation: return "Create account"
        default: return "Continue"
        }
    }

    private var actionEnabled: Bool {
        switch stage {
        case .createUsername: return usernameValid && usernameAvailability == .available
        case .loginUsername: return !username.isEmpty
        case .createPassword: return passwordValid
        case .loginPassword: return !password.isEmpty && password.count <= 200
        case .createConfirmation: return passwordValid && confirmationState == .matched
        default: return false
        }
    }

    private var showsKeyboardAction: Bool {
        switch stage {
        case .createUsername: return usernameValid
        case .loginUsername: return !username.isEmpty
        case .createPassword, .loginPassword: return !password.isEmpty
        case .createConfirmation: return confirmationState == .matched
        default: return false
        }
    }

    private var showsBack: Bool {
        switch stage {
        case .createUsername, .createPassword, .createConfirmation, .loginUsername, .loginPassword: return true
        default: return false
        }
    }

    private var logoSize: CGFloat {
        switch stage {
        case .landing: return 108
        case .creating, .signingIn: return 118
        case .success: return 132
        default: return 74
        }
    }

    private func logoY(in proxy: GeometryProxy, safeTop: CGFloat) -> CGFloat {
        switch stage {
        case .landing:
            return min(188, safeTop + 132)
        case .creating, .signingIn, .success:
            return proxy.size.height * 0.45
        default:
            return safeTop + 72
        }
    }

    private func workingStatusY(in proxy: GeometryProxy) -> CGFloat {
        proxy.size.height * 0.45 + 92
    }

    private var motion: Animation {
        reduceMotion ? .linear(duration: 0.16) : .spring(response: 0.58, dampingFraction: 0.86)
    }

    private func focusInitialStageIfNeeded() {
        guard autofocus else { return }
        switch stage {
        case .createUsername, .loginUsername: scheduleFocus(.username)
        case .createPassword, .loginPassword: scheduleFocus(.password)
        case .createConfirmation: scheduleFocus(.confirmation)
        default: break
        }
    }

    private func recordStage(_ value: WyrmAuthStage) {
        let message = "cinematic auth stage=\(String(describing: value))"
        WyrmDiagnostics.record(message, category: "AUTH-UI")
        NSLog("Wyrm %@", message)
    }

    private func enter(_ next: WyrmAuthStage, focus nextFocus: WyrmAuthFocus?) {
        account.errorMessage = ""
        focus = nil
        withAnimation(motion) { stage = next }
        if let nextFocus { scheduleFocus(nextFocus) }
    }

    private func scheduleFocus(_ next: WyrmAuthFocus) {
        guard autofocus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.34)) {
            focus = next
        }
    }

    private func scheduleUsernameAvailability() {
        availabilityTask?.cancel()
        guard stage == .createUsername, usernameValid else {
            withAnimation(motion) { usernameAvailability = .idle }
            return
        }

        let candidate = username
        withAnimation(motion) { usernameAvailability = .checking }
        availabilityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled, candidate == username, stage == .createUsername else { return }
            let result = await account.usernameAvailability(candidate)
            guard !Task.isCancelled, candidate == username, stage == .createUsername else { return }
            withAnimation(motion) {
                switch result {
                case .available: usernameAvailability = .available
                case .taken: usernameAvailability = .taken
                case .unavailable: usernameAvailability = .unavailable
                }
            }
        }
    }

    private func schedulePasswordComparison() {
        confirmationTask?.cancel()
        guard stage == .createConfirmation,
              !password.isEmpty,
              confirmation.count >= password.count else {
            withAnimation(motion) { confirmationState = .idle }
            return
        }

        let candidate = confirmation
        withAnimation(motion) { confirmationState = .checking }
        confirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, candidate == confirmation, stage == .createConfirmation else { return }
            withAnimation(motion) {
                confirmationState = candidate == password ? .matched : .mismatched
            }
        }
    }

    private func goBack() {
        switch stage {
        case .createUsername, .loginUsername:
            enter(.landing, focus: nil)
        case .createPassword:
            enter(.createUsername, focus: .username)
        case .createConfirmation:
            enter(.createPassword, focus: .password)
        case .loginPassword:
            enter(.loginUsername, focus: .username)
        default:
            break
        }
    }

    private func advance() {
        guard actionEnabled else { return }
        switch stage {
        case .createUsername:
            enter(.createPassword, focus: .password)
        case .loginUsername:
            enter(.loginPassword, focus: .password)
        case .createPassword:
            enter(.createConfirmation, focus: .confirmation)
        case .loginPassword:
            authenticate(create: false)
        case .createConfirmation:
            authenticate(create: true)
        default:
            break
        }
    }

    private func authenticate(create: Bool) {
        focus = nil
        account.errorMessage = ""
        withAnimation(motion) { stage = create ? .creating : .signingIn }

        Task { @MainActor in
            let succeeded: Bool
            if create {
                // The backend requires an initial display name. The username is
                // a valid, honest default and remains editable from Profile.
                succeeded = await account.signUp(displayName: username, username: username, password: password)
            } else {
                succeeded = await account.login(username: username, password: password)
            }

            guard succeeded else {
                let usernameFailure = create && account.errorMessage.localizedCaseInsensitiveContains("username")
                enter(usernameFailure ? .createUsername : (create ? .createConfirmation : .loginPassword),
                      focus: usernameFailure ? .username : (create ? .confirmation : .password))
                return
            }

            // Keep the existing W working stage on screen until every
            // account-scoped surface has received a fresh snapshot. Home never
            // renders with the previous account's or an empty bootstrap state.
            await services.bootstrap(token: account.sessionToken, playerID: account.player?.id)

            withAnimation(motion) { stage = .success }
            if !reduceMotion { try? await Task.sleep(nanoseconds: 700_000_000) }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.16 : 0.52)) { logoDissolved = true }
            try? await Task.sleep(nanoseconds: reduceMotion ? 170_000_000 : 520_000_000)
            account.completeAuthentication()
        }
    }
}

/// Full-screen account transition shared by restore and sign-out. It preserves
/// the same W-logo language as authentication instead of flashing a modal.
struct WyrmSessionTransition: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 22) {
                WyrmBrandMark(size: 118)
                    .scaleEffect(appeared ? 1 : 0.86)
                    .blur(radius: appeared ? 0 : 14)
                    .opacity(appeared ? 1 : 0)
                WyrmAuthWorkingStatus(title: title)
                    .opacity(appeared ? 1 : 0)
                    .blur(radius: appeared ? 0 : 8)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.14) : .spring(response: 0.56, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WyrmBrandMark: View {
    let size: CGFloat

    var body: some View {
        WyrmBrandStroke()
            .stroke(
                LinearGradient(
                    colors: [ATheme.ink.opacity(0.76), ATheme.ink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
    }
}

private struct WyrmAuthWorkingStatus: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOffset: CGFloat = -1.4

    var body: some View {
        Text(title)
            .font(.androidWyrm(13, .bold))
            .tracking(0.55)
            .foregroundColor(ATheme.quiet.opacity(0.58))
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, ATheme.ink.opacity(0.96), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(72, proxy.size.width * 0.58))
                    .offset(x: shimmerOffset * proxy.size.width)
                }
                .mask(
                    Text(title)
                        .font(.androidWyrm(13, .bold))
                        .tracking(0.55)
                )
            }
            .onAppear {
                guard !reduceMotion else { shimmerOffset = 0; return }
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.5
                }
            }
            .accessibilityLabel(title)
    }
}

private struct WyrmBrandStroke: Shape {
    func path(in rect: CGRect) -> Path {
        let width = min(rect.width, rect.height)
        let height = width * 0.78
        let left = rect.midX - width / 2
        let top = rect.midY - height / 2
        var path = Path()
        path.move(to: CGPoint(x: left + width * 0.06, y: top + height * 0.10))
        path.addCurve(
            to: CGPoint(x: left + width * 0.36, y: top + height * 0.38),
            control1: CGPoint(x: left + width * 0.13, y: top + height * 0.92),
            control2: CGPoint(x: left + width * 0.30, y: top + height * 0.96)
        )
        path.addCurve(
            to: CGPoint(x: left + width * 0.64, y: top + height * 0.38),
            control1: CGPoint(x: left + width * 0.42, y: top + height * 0.94),
            control2: CGPoint(x: left + width * 0.58, y: top + height * 0.94)
        )
        path.addCurve(
            to: CGPoint(x: left + width * 0.94, y: top + height * 0.10),
            control1: CGPoint(x: left + width * 0.70, y: top + height * 0.96),
            control2: CGPoint(x: left + width * 0.87, y: top + height * 0.92)
        )
        return path
    }
}

private struct WyrmDotField: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 19
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    let rect = CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)
                    context.fill(Path(ellipseIn: rect), with: .color(ATheme.ink.opacity(0.10)))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WyrmAuthKeyboardAction: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.androidWyrm(15, .bold))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(enabled ? ATheme.ink : ATheme.ink.opacity(0.34))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: ATheme.ink.opacity(enabled ? 0.18 : 0), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct WyrmPasswordMatchLabel: View {
    let text: String
    let systemImage: String
    let colour: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(colour)
                .clipShape(Circle())
            Text(text)
                .font(.androidWyrm(11.5, .semibold))
                .foregroundColor(colour)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

private struct WyrmBlurFadeModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.opacity(opacity).blur(radius: blur).scaleEffect(scale)
    }
}

private extension AnyTransition {
    static var wyrmBlurFade: AnyTransition {
        .modifier(
            active: WyrmBlurFadeModifier(opacity: 0, blur: 15, scale: 0.985),
            identity: WyrmBlurFadeModifier(opacity: 1, blur: 0, scale: 1)
        )
    }
}
