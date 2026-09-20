import SwiftUI

struct WyrmDesignRoot: View {
    @StateObject private var engine = WyrmShellStore()
    @StateObject private var account = WyrmAccountStore()
    @StateObject private var services = WyrmServiceStore()
    private let smoke = ProcessInfo.processInfo.arguments.contains("--smoke-settings") ||
        ProcessInfo.processInfo.arguments.contains("--smoke-developer")
    private let smokeDeveloper = ProcessInfo.processInfo.arguments.contains("--smoke-developer")

    var body: some View {
        Group {
            if smoke {
                WyrmDesignMain(engine: engine, account: account, services: services,
                               initialTab: .settings,
                               initialRoute: smokeDeveloper ? .developer : nil)
            } else {
                switch account.phase {
                case .restoring: WyrmDesignLaunch()
                case .signedOut: WyrmDesignAuth(account: account)
                case .onboarding: WyrmDesignOnboarding(account: account, engine: engine)
                case .signedIn: WyrmDesignMain(engine: engine, account: account, services: services, initialTab: .play)
                }
            }
        }
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
                Text("W").font(.androidWyrm(96, .bold)).tracking(-12).foregroundColor(ATheme.ink)
                    .scaleEffect(visible ? 1 : 0.86).opacity(visible ? 1 : 0)
                Text("WYRM").font(.androidWyrm(11, .bold)).tracking(3).foregroundColor(ATheme.quiet)
                ProgressView().tint(ATheme.ink).padding(.top, 16)
            }
        }.onAppear { withAnimation(.easeOut(duration: 0.55)) { visible = true } }
    }
}

private enum WyrmAuthMode { case landing, create, login }

private struct WyrmDesignAuth: View {
    @ObservedObject var account: WyrmAccountStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: WyrmAuthMode = .landing
    @State private var displayName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(alignment: .leading, spacing: 0) {
                Text(mode == .landing ? "WELCOME TO WYRM" : mode == .create ? "CREATE YOUR DEN" : "WELCOME BACK")
                    .font(.androidWyrm(10.5, .bold)).tracking(1.8).foregroundColor(ATheme.quiet).padding(.top, 18)
                if mode == .landing { landing.transition(.opacity.combined(with: .scale(scale: 0.98))) }
                else { form.transition(.move(edge: .trailing).combined(with: .opacity)) }
            }.padding(.horizontal, 24)
        }
        .foregroundColor(ATheme.ink)
        .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.28), value: mode)
    }

    private var landing: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("W").font(.androidWyrm(112, .bold)).tracking(-16).frame(maxWidth: .infinity)
            Spacer()
            WyrmPrimaryAction(title: "Create Wyrm account", icon: "arrow.right") { mode = .create }
            HStack {
                Button("Use username") { mode = .login }
                Spacer()
                Button("Play as guest") { mode = .create }
            }.font(.androidWyrm(13.5, .semibold)).foregroundColor(ATheme.link).padding(.horizontal, 4).padding(.top, 18)
            Text("Privacy").font(.androidWyrm(11)).foregroundColor(ATheme.quiet.opacity(0.55)).frame(maxWidth: .infinity).padding(.top, 22).padding(.bottom, 18)
        }
    }

    private var form: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(mode == .create ? "A name for the arena.\nA login for this device." : "Your arena is\nwaiting.")
                    .font(.androidWyrm(35, .bold)).tracking(-1).lineSpacing(-3).padding(.top, 56)
                Text(mode == .create ? "No Google account is required. Your username and password restore this profile later." : "Sign in with the username and password you created.")
                    .font(.androidWyrm(13.5)).foregroundColor(ATheme.mute).lineSpacing(4).padding(.top, 15)
                VStack(spacing: 12) {
                    if mode == .create { WyrmDesignTextField(label: "Display name", placeholder: "What people call you", text: $displayName) }
                    WyrmDesignTextField(label: "Username", placeholder: "letters_numbers", text: $username)
                    WyrmDesignTextField(label: "Password", placeholder: "At least 8 characters", text: $password, secure: true)
                    if mode == .create { WyrmDesignTextField(label: "Confirm password", placeholder: "Type it again", text: $confirm, secure: true) }
                }.padding(.top, 30)
                if !account.errorMessage.isEmpty {
                    Text(account.errorMessage).font(.androidWyrm(12, .semibold)).foregroundColor(.red).padding(.top, 14)
                }
                WyrmPrimaryAction(title: mode == .create ? "Create & continue" : "Sign in", icon: account.busy ? nil : "arrow.right", disabled: account.busy) { submit() }
                    .padding(.top, 22)
                Button("Back") { account.errorMessage = ""; mode = .landing }
                    .font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.quiet).frame(maxWidth: .infinity).padding(.vertical, 18)
            }.padding(.bottom, 30)
        }
    }

    private func submit() {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .create {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2, user.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil,
                  password.count >= 8, password == confirm else {
                account.errorMessage = "Use a 2+ character name, a 3–20 character username, and matching 8+ character passwords."
                return
            }
            Task { await account.signUp(displayName: name, username: user, password: password) }
        } else {
            guard !user.isEmpty, !password.isEmpty else { account.errorMessage = "Enter your username and password."; return }
            Task { await account.login(username: user, password: password) }
        }
    }
}

private struct WyrmDesignTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased()).font(.androidWyrm(9.5, .bold)).tracking(1.1).foregroundColor(ATheme.quiet)
            Group {
                if secure { SecureField(placeholder, text: $text) }
                else { TextField(placeholder, text: $text).textInputAutocapitalization(.never).disableAutocorrection(true) }
            }.font(.androidWyrm(15)).padding(.horizontal, 14).frame(height: 50).background(Color.white.opacity(0.9)).cornerRadius(13)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(ATheme.rule))
        }
    }
}

private struct WyrmDesignOnboarding: View {
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var engine: WyrmShellStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var direction = 1
    @State private var arenaName = ""
    @State private var steering = 0
    @State private var rightHand = true
    @State private var skin = 0
    @State private var assist = true

    private let skinNames = ["Ivory", "Moss", "Clay", "Ink"]
    private let skinColours = [Color(red: 0.99, green: 0.98, blue: 0.96), Color(red: 0.62, green: 0.72, blue: 0.49), Color(red: 0.83, green: 0.60, blue: 0.48), ATheme.ink]

    var body: some View {
        ZStack {
            WyrmPaperBackground()
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("STEP \(step + 1) OF SIX").font(.androidWyrm(10, .bold)).tracking(1.3).foregroundColor(ATheme.quiet)
                    HStack(spacing: 5) { ForEach(0..<6) { index in Capsule().fill(index <= step ? ATheme.ink : ATheme.ink.opacity(0.12)).frame(height: 3) } }
                }.padding(.horizontal, 20).frame(height: 52).background(.ultraThinMaterial)
                ZStack {
                    onboardingPage.id(step).transition(pageTransition)
                }.clipped()
                HStack(spacing: 10) {
                    if step > 0 { WyrmOutlineAction(title: "Back") { move(to: step - 1) } }
                    WyrmPrimaryAction(title: step == 5 ? "Enter arena" : "Continue", icon: "arrow.right") { advance() }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
        }.onAppear { arenaName = account.player?.arenaName ?? "" }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity), removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity))
    }

    @ViewBuilder private var onboardingPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.androidWyrm(30, .bold)).tracking(-0.8).lineSpacing(-2).padding(.top, 22)
                if !note.isEmpty { Text(note).font(.androidWyrm(13)).foregroundColor(ATheme.mute).lineSpacing(4).padding(.top, 10) }
                Group {
                    switch step {
                    case 0: rules
                    case 1: nameStep
                    case 2: steeringStep
                    case 3: skinStep
                    case 4: assistStep
                    default: summaryStep
                    }
                }.padding(.top, 24)
                Spacer(minLength: 30)
            }.padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var title: String { ["Three rules, then you are in.", "What should the arena call you?", "How do you steer?", "Pick a skin.", "What is switched on.", "That is everything."][step] }
    private var note: String { ["", "Your profile name stays separate from the name above your snake.", "Both work. Joystick is steadier in a crowd.", "Four to start. The rest live on Skin once you are in.", "Assist is an on-screen button. Team is set up later from Play.", "Your choices are ready for the original engine."][step] }

    private var rules: some View {
        WyrmPaperCard {
            WyrmListRow(title: "Eat the orbs", detail: "Every orb is length, and length is score.", showsChevron: false)
            WyrmListRow(title: "Long snakes turn wide", detail: "The bigger you get, the more room a turn eats.", showsChevron: false)
            WyrmListRow(title: "Cut them off", detail: "Anything that hits your body is out, and drops its length as orbs.", showsChevron: false)
        }.padding(.horizontal, -16)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Wyrm Player", text: $arenaName).font(.androidWyrm(24, .bold)).padding(16).background(Color.white).cornerRadius(15)
            Text("3–20 characters. You can change it later from Profile.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
        }
    }

    private var steeringStep: some View {
        VStack(spacing: 12) {
            onboardingChoice("Joystick", note: "Thumb stays in one corner", selected: steering == 0) { steering = 0 }
            onboardingChoice("Swipe", note: "Drag anywhere on screen", selected: steering == 1) { steering = 1 }
            if steering == 0 {
                HStack(spacing: 0) {
                    onboardingSegment("Left", selected: !rightHand) { rightHand = false }
                    onboardingSegment("Right", selected: rightHand) { rightHand = true }
                }.padding(4).background(ATheme.track).cornerRadius(13).padding(.top, 8)
            }
        }
    }

    private var skinStep: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            ForEach(0..<4) { index in
                Button { skin = index } label: {
                    VStack(spacing: 12) {
                        HStack(spacing: -5) { ForEach(0..<5) { bead in Circle().fill(bead % 2 == 0 ? skinColours[index] : skinColours[index].opacity(0.72)).frame(width: CGFloat(27 - bead * 2), height: CGFloat(27 - bead * 2)) } }
                        Text(skinNames[index]).font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.ink)
                    }.frame(maxWidth: .infinity).frame(height: 112).background(Color.white).cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(skin == index ? ATheme.ink : ATheme.rule, lineWidth: skin == index ? 2 : 1))
                }.buttonStyle(.plain)
            }
        }
    }

    private var assistStep: some View {
        WyrmPaperCard {
            Toggle(isOn: $assist) {
                VStack(alignment: .leading, spacing: 3) { Text("Assist button").font(.androidWyrm(15.5)); Text("Show a helper action in the arena.").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet) }
            }.tint(ATheme.live).padding(.horizontal, 14).frame(minHeight: 62)
            WyrmListRow(title: "Team mode", detail: "Set it up later from Play.", value: "Off", showsChevron: false)
        }.padding(.horizontal, -16)
    }

    private var summaryStep: some View {
        WyrmPaperCard {
            WyrmListRow(title: "Handle", value: account.player?.handle ?? "", showsChevron: false)
            WyrmListRow(title: "Arena name", value: arenaName, showsChevron: false)
            WyrmListRow(title: "Steering", value: steering == 0 ? "Joystick, \(rightHand ? "right" : "left")" : "Swipe", showsChevron: false)
            WyrmListRow(title: "Skin", value: skinNames[skin], showsChevron: false)
            WyrmListRow(title: "Assist button", value: assist ? "On" : "Off", showsChevron: false)
        }.padding(.horizontal, -16)
    }

    private func onboardingChoice(_ title: String, note: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { VStack(alignment: .leading, spacing: 3) { Text(title).font(.androidWyrm(16, .semibold)); Text(note).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet) }; Spacer(); Circle().stroke(ATheme.ink.opacity(0.3), lineWidth: 1.5).background(Circle().fill(selected ? ATheme.ink : .clear).padding(4)).frame(width: 22, height: 22) }.foregroundColor(ATheme.ink).padding(16).background(Color.white).cornerRadius(15).overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? ATheme.ink : ATheme.rule)) }.buttonStyle(.plain)
    }

    private func onboardingSegment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.androidWyrm(13, .semibold)).foregroundColor(selected ? ATheme.ink : ATheme.quiet).frame(maxWidth: .infinity).frame(height: 42).background(selected ? Color.white : .clear).cornerRadius(10) }.buttonStyle(.plain)
    }

    private func move(to newStep: Int) {
        direction = newStep > step ? 1 : -1
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.32)) { step = newStep }
    }

    private func advance() {
        if step == 5 {
            let current = account.player?.arenaName ?? ""
            if arenaName.trimmingCharacters(in: .whitespacesAndNewlines) != current {
                Task {
                    _ = await account.update(displayName: account.player?.displayName ?? "Player", ingameName: arenaName, username: account.player?.username ?? "", bio: account.player?.bio ?? "", avatarKey: account.player?.avatarKey ?? "mono-ink")
                    account.finishOnboarding()
                }
            } else { account.finishOnboarding() }
            return
        }
        if step == 2, let row = engine.settings.first(where: { $0.id == "controls.joystick_mode" }) { engine.write(row, values: [Double(steering)]) }
        UserDefaults.standard.set(skin, forKey: "wyrm.ios.onboarding.skin")
        move(to: step + 1)
    }
}
