import SwiftUI
import UIKit

/*
 * The screens of Help & feedback and the crash prompt (OM, 2026-09-29). The
 * engine behind them is WyrmSupport.swift.
 */

// MARK: - Crash prompt

/// Raised on the launch after a crash: a paper card from the bottom, one clear
/// ask, the note optional, what is sent one tap away. Nothing is sent until the
/// player says so (or has chosen "Always send").
struct WyrmCrashPrompt: View {
    let record: WyrmCrashRecord
    @ObservedObject private var watch = WyrmCrashWatch.shared
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    @State private var note = ""
    @State private var showDetails = false
    @State private var phase = Phase.asking
    @State private var appeared = false

    private enum Phase { case asking, sending, sent, failed }

    var body: some View {
        ZStack(alignment: keyboard.focused ? .top : .bottom) {
            ATheme.ink.opacity(appeared ? 0.34 : 0)
                .ignoresSafeArea()
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            card
                .padding(.horizontal, 12)
                .padding(.top, keyboard.focused ? 12 : 0)
                .padding(.bottom, 12)
                .offset(y: appeared ? 0 : 520)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: keyboard.focused)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if phase == .sent {
                sentView
            } else {
                askingView
            }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(ATheme.rule))
        .shadow(color: Color.black.opacity(0.18), radius: 30, y: 12)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: phase)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showDetails)
    }

    @ViewBuilder private var askingView: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(ATheme.badge.opacity(0.12))
                Image(systemName: "bandage.fill").font(.system(size: 21, weight: .semibold)).foregroundColor(ATheme.badge)
            }.frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text("CRASH DETECTED").font(.androidWyrm(10, .bold)).tracking(1.1).foregroundColor(ATheme.badge)
                Text("Wyrm \(record.appVersion) · build \(record.build)").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
            }
            Spacer(minLength: 0)
        }
        Text("Wyrm closed unexpectedly").font(.androidWyrm(22, .bold)).foregroundColor(ATheme.ink).padding(.top, 16)
        Text("Send the crash report to the developer and we'll see exactly what went wrong. You're helping make Wyrm better for every player.")
            .font(.androidWyrm(13.5)).foregroundColor(ATheme.mute).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 6)

        TextField("What were you doing? (optional)", text: $note)
            .font(.androidWyrm(14)).foregroundColor(ATheme.ink)
            .padding(.horizontal, 14).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ATheme.well))
            .padding(.top, 16)
            .disabled(phase == .sending)

        Button { showDetails.toggle() } label: {
            HStack(spacing: 6) {
                Text("What's included").font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.link)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.link)
                    .rotationEffect(.degrees(showDetails ? 180 : 0))
                Spacer()
            }.frame(height: 38).contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.top, 6)
        if showDetails {
            VStack(alignment: .leading, spacing: 7) {
                WyrmIncludedLine(icon: "iphone", text: "Your iPhone model, iOS and Wyrm version")
                WyrmIncludedLine(icon: "chevron.left.forwardslash.chevron.right", text: "Where in Wyrm's code it stopped")
                WyrmIncludedLine(icon: "text.alignleft", text: "The last few minutes of Wyrm's own log")
                WyrmIncludedLine(icon: "lock.fill", text: "Never your password, keys, Team ID or messages", tint: ATheme.live)
            }
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        HStack(spacing: 12) {
            WSRowText(title: "Always send crash reports", detail: "Skip this question next time")
                .frame(maxWidth: .infinity, alignment: .leading)
            WSInkSwitch(on: watch.autoSend) { watch.autoSend = $0 }
        }.padding(.vertical, 6)

        if phase == .failed {
            Text("Couldn't send it. Try again, or send it later from Settings › Help & feedback.")
                .font(.androidWyrm(12)).foregroundColor(ATheme.badge)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }

        Button(action: send) {
            HStack(spacing: 8) {
                if phase == .sending { ProgressView().tint(ATheme.onInk) }
                Text(phase == .sending ? "Sending…" : phase == .failed ? "Try again" : "Send report")
                    .font(.androidWyrm(15.5, .bold))
            }
            .foregroundColor(ATheme.onInk)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Capsule().fill(ATheme.ink))
        }
        .buttonStyle(WSPressStyle()).disabled(phase == .sending).padding(.top, 12)

        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.easeIn(duration: 0.22)) { appeared = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { watch.dismissPrompt() }
        } label: {
            Text("Not now").font(.androidWyrm(15, .semibold)).foregroundColor(ATheme.mute)
                .frame(maxWidth: .infinity).frame(height: 46).contentShape(Rectangle())
        }
        .buttonStyle(WSPressStyle()).disabled(phase == .sending).padding(.top, 2)
    }

    private var sentView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(ATheme.live.opacity(0.14)).frame(width: 64, height: 64)
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundColor(ATheme.live)
            }
            .transition(.scale.combined(with: .opacity))
            Text("Thank you").font(.androidWyrm(21, .bold)).foregroundColor(ATheme.ink)
            Text("The report is with the developer. You just made Wyrm a little better.")
                .font(.androidWyrm(13)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    private func send() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        phase = .sending
        Task {
            // `send` clears the prompt itself; keep the card up to say thanks.
            let ok = await watch.send(record, note: note)
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                phase = .sent
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                phase = .failed
            }
        }
    }
}

/// Holds the prompt on screen through its "Thank you", then lets it go.
struct WyrmCrashPromptHost: View {
    @ObservedObject private var watch = WyrmCrashWatch.shared
    @State private var shown: WyrmCrashRecord?

    var body: some View {
        ZStack {
            if let record = shown {
                WyrmCrashPrompt(record: record)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if !watch.toast.isEmpty {
                Text(watch.toast)
                    .font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.onInk)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Capsule().fill(ATheme.ink))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { watch.clearToast() }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: watch.toast)
        .onAppear {
            watch.launchCheck()
            shown = watch.prompt
        }
        .onChange(of: watch.prompt) { next in
            if let next {
                shown = next
            } else if shown != nil {
                // Sent: leave the thanks up for a moment. Dismissed: already slid away.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if watch.prompt == nil { withAnimation(.easeOut(duration: 0.25)) { shown = nil } }
                }
            }
        }
    }
}

// MARK: - Arena drop prompt

/// Raised when the player is back from a match the arena dropped (OM,
/// 2026-09-29): the crash card's look, with the likeliest cause in plain words.
/// Over the Ready Room it is drawn in the landscape canvas the player holds.
struct WyrmDropPrompt: View {
    let record: WyrmDropRecord
    /// The landscape canvas over the Ready Room, or nil in the portrait app.
    let stage: CGSize?
    let safe: EdgeInsets
    @ObservedObject private var watch = WyrmDropWatch.shared
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    @State private var note = ""
    @State private var showDetails = false
    @State private var phase = Phase.asking
    @State private var appeared = false

    private enum Phase { case asking, sending, sent, failed }

    /// A warning, not a failure: amber rather than the crash card's red.
    private static let tint = Color(red: 0.86, green: 0.53, blue: 0.13)

    private var landscape: Bool { stage != nil }
    private var typing: Bool { keyboard.focused }
    private var keyboardWidth: CGFloat {
        let width: CGFloat = stage?.width ?? 0
        return min(width - safe.leading - safe.trailing - 24, 640 * CGFloat(keyboard.scale))
    }

    var body: some View {
        ZStack(alignment: typing ? .top : (landscape ? .center : .bottom)) {
            ATheme.ink.opacity(appeared ? 0.34 : 0)
                .ignoresSafeArea()
                .onTapGesture { Self.resign() }
            card
                .padding(.horizontal, landscape ? max(12, safe.leading) : 12)
                .padding(.top, typing ? (landscape ? max(8, safe.top) : 12) : 0)
                .padding(.bottom, landscape ? 0 : 12)
                .offset(y: appeared ? 0 : 520)
            // The phone stays portrait, so over the Ready Room the keys are
            // drawn here, in the canvas, the way the Ready Room draws them.
            if landscape && typing && keyboard.embedded {
                WyrmKeyboardView(compact: true)
                    .frame(width: keyboardWidth)
                    .shadow(color: ATheme.ink.opacity(0.18), radius: 18, y: 6)
                    .padding(.bottom, 8)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: keyboard.focused)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private var card: some View {
        Group {
            if phase == .sent {
                sentView
            } else if landscape {
                wideAsking
            } else {
                tallAsking
            }
        }
        .padding(landscape ? 18 : 20)
        .frame(maxWidth: landscape ? 720 : 520)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(ATheme.rule))
        .shadow(color: Color.black.opacity(0.18), radius: 30, y: 12)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: phase)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showDetails)
    }

    /// Portrait: one column, as the crash card.
    private var tallAsking: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            headline.padding(.top, 16)
            noteField.padding(.top, 16)
            detailsToggle.padding(.top, 6)
            if showDetails { details }
            switchRow
            failure
            buttons
        }
    }

    /// Landscape: the words on the left, the answer on the right. While the
    /// note is typed only the field stays, above the keys. The field keeps its
    /// place in the tree either way, so it never loses focus.
    private var wideAsking: some View {
        HStack(alignment: .top, spacing: 22) {
            if !typing {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    headline.padding(.top, 12)
                    detailsToggle.padding(.top, 4)
                    if showDetails { details }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 0) {
                noteField
                if !typing {
                    switchRow.padding(.top, 4)
                    failure
                    buttons
                }
            }
            .frame(maxWidth: typing ? .infinity : 290)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Self.tint.opacity(0.14))
                Image(systemName: "wifi.exclamationmark").font(.system(size: 20, weight: .semibold)).foregroundColor(Self.tint)
            }.frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text("ARENA DROP").font(.androidWyrm(10, .bold)).tracking(1.1).foregroundColor(Self.tint)
                Text(record.subtitle).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The arena dropped you").font(.androidWyrm(landscape ? 20 : 22, .bold)).foregroundColor(ATheme.ink)
            Text(record.hintText)
                .font(.androidWyrm(13.5)).foregroundColor(ATheme.mute).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noteField: some View {
        TextField("What happened? (optional)", text: $note)
            .font(.androidWyrm(14)).foregroundColor(ATheme.ink)
            .padding(.horizontal, 14).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ATheme.well))
            .disabled(phase == .sending)
    }

    private var detailsToggle: some View {
        Button { showDetails.toggle() } label: {
            HStack(spacing: 6) {
                Text("What's included").font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.link)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.link)
                    .rotationEffect(.degrees(showDetails ? 180 : 0))
                Spacer()
            }.frame(height: 38).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            WyrmIncludedLine(icon: "scope", text: "Arena, ping and how long you were in")
            WyrmIncludedLine(icon: "wifi", text: "Wi-Fi or mobile data, and whether it switched")
            WyrmIncludedLine(icon: "text.alignleft", text: "The last minutes of Wyrm's own log")
            WyrmIncludedLine(icon: "lock.fill", text: "Never your password, keys, Team ID or messages", tint: ATheme.live)
        }
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var switchRow: some View {
        HStack(spacing: 12) {
            WSRowText(title: "Always send drop reports", detail: "Skip this question next time")
                .frame(maxWidth: .infinity, alignment: .leading)
            WSInkSwitch(on: watch.autoSend) { watch.autoSend = $0 }
        }.padding(.vertical, 6)
    }

    @ViewBuilder private var failure: some View {
        if phase == .failed {
            Text("Couldn't send it. Check your connection and try again.")
                .font(.androidWyrm(12)).foregroundColor(ATheme.badge)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
    }

    private var buttons: some View {
        VStack(spacing: 0) {
            Button(action: send) {
                HStack(spacing: 8) {
                    if phase == .sending { ProgressView().tint(ATheme.onInk) }
                    Text(phase == .sending ? "Sending…" : phase == .failed ? "Try again" : "Send report")
                        .font(.androidWyrm(15.5, .bold))
                }
                .foregroundColor(ATheme.onInk)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(ATheme.ink))
            }
            .buttonStyle(WSPressStyle()).disabled(phase == .sending).padding(.top, landscape ? 8 : 12)

            Button {
                Self.resign()
                withAnimation(.easeIn(duration: 0.22)) { appeared = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { watch.dismissPrompt() }
            } label: {
                Text("Not now").font(.androidWyrm(15, .semibold)).foregroundColor(ATheme.mute)
                    .frame(maxWidth: .infinity).frame(height: 46).contentShape(Rectangle())
            }
            .buttonStyle(WSPressStyle()).disabled(phase == .sending).padding(.top, 2)
        }
    }

    private var sentView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(ATheme.live.opacity(0.14)).frame(width: 64, height: 64)
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundColor(ATheme.live)
            }
            .transition(.scale.combined(with: .opacity))
            Text("Thank you").font(.androidWyrm(21, .bold)).foregroundColor(ATheme.ink)
            Text("The report is with the developer. You just made Wyrm a little better.")
                .font(.androidWyrm(13)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    private static func resign() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func send() {
        Self.resign()
        phase = .sending
        Task {
            // `send` clears the prompt itself; keep the card up to say thanks.
            let ok = await watch.send(record, note: note)
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                phase = .sent
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                phase = .failed
            }
        }
    }
}

/// Holds the drop card through its "Thank you", like the crash host, and
/// shows the short toast after a quiet "Always send" report.
struct WyrmDropPromptHost: View {
    /// True over the landscape Ready Room.
    let landscape: Bool
    @ObservedObject private var watch = WyrmDropWatch.shared
    @State private var shown: WyrmDropRecord?

    var body: some View {
        Group {
            if landscape {
                WyrmLandscapeStage { size, safe in
                    layer(stage: size, safe: safe)
                }
            } else {
                layer(stage: nil, safe: EdgeInsets())
            }
        }
        .onAppear { shown = watch.prompt }
        .onChange(of: watch.prompt) { next in
            if let next {
                shown = next
            } else if shown != nil {
                // Sent: leave the thanks up for a moment. Dismissed: already slid away.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if watch.prompt == nil { withAnimation(.easeOut(duration: 0.25)) { shown = nil } }
                }
            }
        }
    }

    private func layer(stage: CGSize?, safe: EdgeInsets) -> some View {
        ZStack {
            if let record = shown {
                WyrmDropPrompt(record: record, stage: stage, safe: safe)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if !watch.toast.isEmpty {
                Text(watch.toast)
                    .font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.onInk)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Capsule().fill(ATheme.ink))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, stage == nil ? 58 : max(12, safe.top))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { watch.clearToast() }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: watch.toast)
    }
}

private struct WyrmIncludedLine: View {
    let icon: String
    let text: String
    var tint = ATheme.quiet
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .semibold)).foregroundColor(tint).frame(width: 18)
            Text(text).font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Help & feedback

private struct WyrmFAQ: Identifiable {
    let id: Int
    let question: String
    let answer: String

    static let all: [WyrmFAQ] = [
        WyrmFAQ(id: 0, question: "My snake spawned and then dropped out of the arena",
                answer: "Another slither app on the same Wi-Fi (on a PC or another phone) can make the arena drop you. Close it, or switch to mobile data, and pick the arena again. Joining the same arena many times a minute also gets a short timeout; wait a minute and try once."),
        WyrmFAQ(id: 1, question: "How do I change my username or photo?",
                answer: "Open your profile and tap Edit profile. You can rename twice a month. Tap your photo on your profile to change or remove it."),
        WyrmFAQ(id: 2, question: "My skin or beads look different in the arena",
                answer: "Other players see the arena's own colours, not Wyrm beads; your Wyrm beads and looks are drawn on your own snake. If your snake draws blank, update Wyrm and choose the skin again."),
        WyrmFAQ(id: 3, question: "How do I keep my settings when I reinstall?",
                answer: "Settings › Backup & version › Create backup saves skins, controls and settings to a file. Restore from that file on the new install."),
        WyrmFAQ(id: 4, question: "I'm not getting notifications",
                answer: WyrmTrailsFeature.enabled
                    ? "Check Settings › Notifications, and that Wyrm is allowed in the iPhone's Settings. On iPhone, likes and replies on your trails arrive in Alerts while Wyrm is open."
                    : "Check Settings › Notifications, and that Wyrm is allowed in the iPhone's Settings. On iPhone, new followers and replies from Wyrm arrive in Alerts while Wyrm is open."),
        WyrmFAQ(id: 5, question: "How do I get Wyrm updates?",
                answer: "Wyrm tells you when a new build is out. Turn on Beta updates in Backup & version to get early builds."),
        WyrmFAQ(id: 6, question: "How do I delete my account?",
                answer: WyrmTrailsFeature.enabled
                    ? "Profile › Edit profile › Delete account. Your profile, trails and messages are removed from Wyrm's server."
                    : "Profile › Edit profile › Delete account. Your profile and messages are removed from Wyrm's server."),
    ]
}

struct WyrmHelpCenterPage: View {
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var watch = WyrmCrashWatch.shared
    @ObservedObject private var drops = WyrmDropWatch.shared
    @ObservedObject private var store = WyrmSupportStore.shared
    @State private var expanded: Int?
    @State private var sendingLast = false
    @State private var lastError = ""

    var body: some View {
        WSScaffold(title: "Help & feedback", onBack: close) {
            Group {
            VStack(alignment: .leading, spacing: 5) {
                Text("How can we help?").font(.androidWyrm(26, .bold)).foregroundColor(ATheme.ink)
                Text("Wyrm is made by one person, and every report is read.")
                    .font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)

            HStack(spacing: 10) {
                tile(.bug)
                tile(.suggestion)
                tile(.help)
            }
            .padding(.horizontal, 16)

            WSSectionLabel("Your reports")
            WSCard {
                WSValueRow(title: "Your reports", value: reportsSummary, first: true) { open(.supportReports) }
            }

            }
            Group {
            WSSectionLabel("Crash reports")
            WSCard {
                WSBoolRow(title: "Always send crash reports",
                          detail: "If Wyrm closes unexpectedly, the report goes without asking.",
                          on: watch.autoSend, first: true) { watch.autoSend = $0 }
                    .wyrmSettingAnchor("app.crash.auto")
                WSBoolRow(title: "Always send drop reports",
                          detail: "If the arena drops you mid-match, the report goes without asking.",
                          on: drops.autoSend) { drops.autoSend = $0 }
                    .wyrmSettingAnchor("app.drop.auto")
                if let last = watch.last {
                    WSHairline()
                    HStack(spacing: 12) {
                        WSRowText(title: "Last crash", detail: "\(Self.when(last.at)) · \(last.sent ? "Sent. Thank you" : "Not sent")")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !last.sent {
                            Button { sendLast(last) } label: {
                                Group {
                                    if sendingLast { ProgressView().tint(ATheme.onInk) } else { Text("Send") }
                                }
                                .font(.androidWyrm(13.5, .semibold)).foregroundColor(ATheme.onInk)
                                .frame(width: 74, height: 34).background(Capsule().fill(ATheme.ink))
                            }.buttonStyle(WSPressStyle()).disabled(sendingLast)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 58)
                }
            }
            if !lastError.isEmpty {
                Text(lastError).font(.androidWyrm(12)).foregroundColor(ATheme.badge).padding(.horizontal, 20).padding(.top, 8)
            }
            WSCaption("A crash report holds your iPhone model, iOS and Wyrm version, where in Wyrm it stopped and the last few minutes of Wyrm's log. Never your password, keys, Team ID or messages.")
            }
            Group {

            WSSectionLabel("Common questions")
            WSCard {
                ForEach(WyrmFAQ.all) { item in faqRow(item) }
            }

            WSSectionLabel("Something else")
            WSCard {
                WSValueRow(title: "Write to Wyrm", value: "", first: true) { open(.supportCompose(WyrmSupportKind.other.rawValue)) }
            }
            WSCaption("Replies from Wyrm arrive in Alerts and under Your reports.")
            }
        }
        .task {
            store.token = { [weak account] in account?.sessionToken ?? "" }
            watch.token = { [weak account] in account?.sessionToken ?? "" }
            await store.refresh()
        }
    }

    private var reportsSummary: String {
        let unseen = store.unseenReplies
        if unseen > 0 { return unseen == 1 ? "1 new reply" : "\(unseen) new replies" }
        if !store.loaded { return "" }
        if store.reports.isEmpty { return "None yet" }
        return "\(store.reports.count)"
    }

    private func tile(_ kind: WyrmSupportKind) -> some View {
        Button { open(.supportCompose(kind.rawValue)) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: kind.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(ATheme.ink)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(ATheme.well))
                Text(kind.pageTitle).font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.ink)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule))
        }
        .buttonStyle(WSPressStyle())
    }

    private func faqRow(_ item: WyrmFAQ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.id > 0 { WSHairline() }
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { expanded = expanded == item.id ? nil : item.id }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.question).font(.androidWyrm(14.5, .semibold)).foregroundColor(ATheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundColor(ATheme.quiet)
                        .rotationEffect(.degrees(expanded == item.id ? 45 : 0))
                }
                .padding(.horizontal, 14).padding(.vertical, 14).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded == item.id {
                Text(item.answer).font(.androidWyrm(13)).foregroundColor(ATheme.mute).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
    }

    private func sendLast(_ record: WyrmCrashRecord) {
        sendingLast = true
        lastError = ""
        Task {
            if !(await watch.send(record, note: "")) { lastError = "Couldn't send it. Check your connection and try again." }
            sendingLast = false
        }
    }

    static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Write a report

struct WyrmSupportComposePage: View {
    @ObservedObject var account: WyrmAccountStore
    let initialKind: String
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var store = WyrmSupportStore.shared
    @State private var kind: WyrmSupportKind
    @State private var message = ""
    @State private var attach: Bool
    @State private var sending = false
    @State private var sent = false
    @State private var error = ""

    private static let kinds: [WyrmSupportKind] = [.bug, .suggestion, .help, .other]

    init(account: WyrmAccountStore, initialKind: String, close: @escaping () -> Void, open: @escaping (WyrmDesignRoute) -> Void) {
        self.account = account
        self.initialKind = initialKind
        self.close = close
        self.open = open
        let start = WyrmSupportKind(rawValue: initialKind).flatMap { Self.kinds.contains($0) ? $0 : nil } ?? .bug
        _kind = State(initialValue: start)
        _attach = State(initialValue: start.attachesByDefault)
    }
    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { trimmed.count >= 3 && !sending }

    var body: some View {
        WSScaffold(title: sent ? "Sent" : kind.pageTitle, parent: "Help", trailing: sent ? nil : "Send",
                   trailingEnabled: canSend, onTrailing: sent ? nil : { send() }, onBack: close) {
            if sent {
                sentView
            } else {
                form
            }
        }
        .onAppear { store.token = { [weak account] in account?.sessionToken ?? "" } }
    }

    @ViewBuilder private var form: some View {
        WSSegmented(options: Self.kinds.map(\.title), selected: Self.kinds.firstIndex(of: kind) ?? 0) { index in
            withAnimation(.easeOut(duration: 0.2)) {
                kind = Self.kinds[index]
                attach = kind.attachesByDefault
            }
        }
        .padding(.horizontal, 16).padding(.top, 16)

        Text(kind.question).font(.androidWyrm(20, .bold)).foregroundColor(ATheme.ink)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)

        ZStack(alignment: .topLeading) {
            WyrmTextArea(text: $message, limit: 4000, editable: !sending)
                .frame(minHeight: 180)
            if message.isEmpty {
                Text(kind.placeholder).font(.androidWyrm(15)).foregroundColor(ATheme.quiet.opacity(0.8))
                    .padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.rule))
        .padding(.horizontal, 16)

        HStack {
            if !error.isEmpty {
                Text(error).font(.androidWyrm(12)).foregroundColor(ATheme.badge).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("\(message.count)/4000").font(.androidWyrm(11)).foregroundColor(message.count > 3800 ? ATheme.badge : ATheme.quiet)
        }
        .padding(.horizontal, 20).padding(.top, 8)

        WSSectionLabel("Include")
        WSCard {
            WSBoolRow(title: "Device info and recent log",
                      detail: "iPhone model, iOS and Wyrm version, the last few minutes of Wyrm's log. Makes problems much easier to fix.",
                      on: attach, first: true) { attach = $0 }
        }
        WSCaption(account.player == nil
                  ? "You're not signed in, so we can't reply in the app."
                  : "Sent as \(account.player?.handle ?? "you"). If we reply, you'll find it in Alerts and under Your reports. Never your password, keys or messages.")

        if sending {
            HStack(spacing: 10) {
                ProgressView().tint(ATheme.quiet)
                Text("Sending…").font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
            }.frame(maxWidth: .infinity).padding(.top, 14)
        }
    }

    private var sentView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(ATheme.live.opacity(0.14)).frame(width: 76, height: 76)
                Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundColor(ATheme.live)
            }
            .padding(.top, 60)
            Text("Thank you").font(.androidWyrm(26, .bold)).foregroundColor(ATheme.ink)
            Text(kind == .suggestion
                 ? "Your idea is with the developer. The best ones end up in Wyrm."
                 : "Your report is with the developer. If we reply, it arrives in Alerts and under Your reports.")
                .font(.androidWyrm(14)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 36)
            WSPrimaryButton(label: "Done", onClick: close).padding(.horizontal, 36).padding(.top, 18)
            Button("See your reports") { open(.supportReports) }
                .font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.link).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func send() {
        guard canSend else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sending = true
        error = ""
        let words = trimmed
        Task {
            // The screen the problem was on, not the help page it was typed on.
            let failure = await store.send(kind: kind, message: words, attach: attach,
                                           screen: WyrmCrashWatch.shared.lastRealScreen)
            sending = false
            if let failure {
                error = failure
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { sent = true }
            }
        }
    }
}

/// A multi-line field in Wyrm's font with a clear background (SwiftUI's
/// TextEditor paints its own on iOS 15). The Wyrm keyboard comes with it, as
/// with every text view in the app.
struct WyrmTextArea: UIViewRepresentable {
    @Binding var text: String
    var limit: Int
    var editable = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = UIFont(name: "Manrope", size: 15) ?? .systemFont(ofSize: 15)
        view.textColor = UIColor(ATheme.ink)
        view.tintColor = UIColor(ATheme.link)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.isScrollEnabled = true
        view.delegate = context.coordinator
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.isEditable = editable
        view.textColor = UIColor(ATheme.ink)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: WyrmTextArea
        init(_ parent: WyrmTextArea) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) {
            if view.text.count > parent.limit { view.text = String(view.text.prefix(parent.limit)) }
            parent.text = view.text
        }
    }
}

// MARK: - Your reports

struct WyrmSupportReportsPage: View {
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var store = WyrmSupportStore.shared

    var body: some View {
        WSScaffold(title: "Your reports", parent: "Help", trailing: "New", onTrailing: { open(.supportCompose(WyrmSupportKind.bug.rawValue)) }, onBack: close) {
            if !store.loaded {
                VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in WyrmReportSkeleton() } }.padding(.top, 16)
            } else if store.reports.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 28, weight: .semibold)).foregroundColor(ATheme.quiet)
                    Text(store.error.isEmpty ? "No reports yet" : store.error).font(.androidWyrm(17, .semibold)).foregroundColor(ATheme.ink)
                        .multilineTextAlignment(.center)
                    Text("Problems, ideas and questions you send appear here, with Wyrm's replies.")
                        .font(.androidWyrm(13)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 32).padding(.top, 70)
            } else {
                VStack(spacing: 12) {
                    ForEach(store.reports) { report in WyrmReportCard(report: report) }
                }.padding(.top, 16)
            }
        }
        .refreshable { await store.refresh() }
        .task {
            store.token = { [weak account] in account?.sessionToken ?? "" }
            await store.refresh()
            store.markRepliesSeen()
        }
    }
}

private struct WyrmReportCard: View {
    let report: WyrmSupportReport
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(report.kindTitle.uppercased()).font(.androidWyrm(9.5, .bold)).tracking(1).foregroundColor(ATheme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(ATheme.well))
                Text(status).font(.androidWyrm(11, .semibold)).foregroundColor(report.reply.isEmpty ? ATheme.quiet : ATheme.live)
                Spacer()
                Text(WyrmTrailTime.short(report.createdAt)).font(.androidWyrm(11)).foregroundColor(ATheme.quiet)
            }
            Text(report.message.isEmpty ? (report.kind == WyrmSupportKind.drop.rawValue ? "Arena drop report" : "Crash report") : report.message)
                .font(.androidWyrm(14)).foregroundColor(ATheme.ink).lineLimit(5).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !report.reply.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    WyrmBrandMark(size: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wyrm").font(.androidWyrm(12.5, .bold)).foregroundColor(ATheme.ink)
                        Text(report.reply).font(.androidWyrm(13.5)).foregroundColor(ATheme.ink).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.live.opacity(0.09)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(ATheme.rule))
        .padding(.horizontal, 16)
    }

    private var status: String {
        if !report.reply.isEmpty { return "Wyrm replied" }
        switch report.status {
        case "resolved": return "Resolved"
        case "read": return "Seen"
        default: return "Sent"
        }
    }
}

private struct WyrmReportSkeleton: View {
    @State private var dim = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 5).fill(ATheme.well).frame(width: 90, height: 12)
            RoundedRectangle(cornerRadius: 5).fill(ATheme.well).frame(height: 13)
            RoundedRectangle(cornerRadius: 5).fill(ATheme.well).frame(width: 190, height: 13)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(ATheme.rule))
        .padding(.horizontal, 16)
        .opacity(dim ? 0.55 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true } }
    }
}
