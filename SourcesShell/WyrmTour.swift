import SwiftUI
import UIKit

/*
 * The app tour (OM, 2026-10-05): "Welcome to Wyrm", then a spotlight on each
 * main thing, the way apps introduce themselves after an install or an update.
 *
 * Standards it follows: one element lit at a time with the rest dimmed, a
 * short title and one or two compact sentences, "n of N" progress, Back /
 * Next, Skip always visible, shown once (an install, or the first update that
 * carries it), and replayable from Settings › Help & feedback.
 *
 * The tour walks the real app: each step names a place (Home, Play › Controls
 * on one of its tabs, the Settings tab) that `WyrmDesignMain` opens, and an
 * anchor id carried by the real control (`wyrmTourAnchor`). Anchors report
 * their frames and the scroll views around them bring them into view. Taps on
 * the dimmed app are held while the tour runs.
 *
 * Same steps, words and order as Wyrm Android (`ui/WyrmTour.kt`).
 */

enum WyrmTourPlace { case home, controls, buttons, arenaUI, settings }

struct WyrmTourStep {
    let place: WyrmTourPlace
    /// The control lit by this step; nil for the welcome and the last card.
    let anchor: String?
    let title: String
    let body: String
}

final class WyrmTour: ObservableObject {
    static let shared = WyrmTour()
    /// Raise to show the tour once more to everyone (a new tour).
    static let version = 1
    private static let seenKey = "wyrm.ios.tour.seen-version"

    static let steps: [WyrmTourStep] = [
        WyrmTourStep(place: .home, anchor: nil, title: "Welcome to Wyrm",
                     body: "A quick look at where everything is. It takes about a minute."),
        WyrmTourStep(place: .home, anchor: "home.team", title: "Team mode",
                     body: "Connect with your team here. It links you through NTL: teammates on your minimap, plus a team roster and team chat in the arena."),
        WyrmTourStep(place: .home, anchor: "home.near", title: "Near Original",
                     body: "Play like the original slither.io: its minimap, leaderboard, joystick, boost and arrow. Turn it off for Wyrm's own."),
        WyrmTourStep(place: .home, anchor: "home.controls", title: "Controls",
                     body: "How you play: steering, on-screen buttons and where everything sits in the arena."),
        WyrmTourStep(place: .controls, anchor: "controls.preview", title: "Steering",
                     body: "Choose Arrow or Joystick, how you boost, sizes, the arrow's look and movement, and the zoom bar. The preview shows it live."),
        WyrmTourStep(place: .buttons, anchor: "controls.tabs", title: "On-screen buttons",
                     body: "Pick which buttons appear in the arena, like zoom, auto restart and chat, and how each one fires."),
        WyrmTourStep(place: .arenaUI, anchor: "controls.tabs", title: "Arena UI",
                     body: "Set the size of the minimap, the leaderboard and the stats text."),
        WyrmTourStep(place: .arenaUI, anchor: "controls.arrange", title: "Arrange the layout",
                     body: "Opens the arena editor, sideways like a match. Drag the joystick, boost, buttons, minimap, leaderboard, stats, team roster and chat where you want them, then Save."),
        WyrmTourStep(place: .settings, anchor: "settings.arena", title: "Arena",
                     body: "Display: scores, names, minimap and text sizes. Controls: steering, boost and the zoom bar. On-screen buttons: which ones show and how they fire."),
        WyrmTourStep(place: .settings, anchor: "settings.help", title: "Playing help",
                     body: "Modes: Normal or Assist, helper lines and arena colours. Bot: when it circles and how wide it swings."),
        WyrmTourStep(place: .settings, anchor: "settings.performance", title: "Performance",
                     body: "Auto: full speed while the phone is cool, slower when it warms up or Low Power Mode is on. Balanced: a steady 60 FPS, cooler and easier on the battery. Performance: the highest frame rate and least delay; the phone runs warmer."),
        WyrmTourStep(place: .settings, anchor: "settings.account", title: "Account",
                     body: "Profile: name, username, photo and bio. Notifications: choose what reaches you. Privacy: who can reach you and what is stored."),
        WyrmTourStep(place: .settings, anchor: "settings.support", title: "Help & feedback",
                     body: "Report a problem, suggest an idea and read Wyrm's replies. You can replay this tour here too."),
        WyrmTourStep(place: .home, anchor: nil, title: "You're all set",
                     body: "Jump in and play. You can replay this tour any time from Settings › Help & feedback."),
    ]

    /// -1 while the tour is not running.
    @Published var step = -1

    var active: Bool { step >= 0 }
    var current: WyrmTourStep? { Self.steps.indices.contains(step) ? Self.steps[step] : nil }
    var target: String? { current?.anchor }
    /// The lit steps (everything but the welcome and the last card).
    var spotlightCount: Int { Self.steps.count - 2 }
    var pending: Bool { UserDefaults.standard.integer(forKey: Self.seenKey) < Self.version }

    func start() {
        WyrmTourFrames.shared.publishAll()
        step = 0
    }

    func next() {
        if step >= Self.steps.count - 1 { finish() } else { step += 1 }
    }

    func back() { if step > 0 { step -= 1 } }

    /// Finished or skipped: seen on this phone for this tour version.
    func finish() {
        UserDefaults.standard.set(Self.version, forKey: Self.seenKey)
        step = -1
    }
}

/// Where each anchor is, in global coordinates. Kept quietly all the time and
/// published only while the tour runs, so ordinary scrolling redraws nothing.
final class WyrmTourFrames: ObservableObject {
    static let shared = WyrmTourFrames()
    @Published private(set) var frames: [String: CGRect] = [:]
    private var latest: [String: CGRect] = [:]

    func report(_ id: String, _ frame: CGRect) {
        latest[id] = frame
        guard WyrmTour.shared.active else { return }
        if let old = frames[id], abs(old.minX - frame.minX) < 0.5, abs(old.minY - frame.minY) < 0.5,
           abs(old.width - frame.width) < 0.5, abs(old.height - frame.height) < 0.5 { return }
        frames[id] = frame
    }

    func forget(_ id: String) {
        latest[id] = nil
        if frames[id] != nil { frames[id] = nil }
    }

    func publishAll() { frames = latest }
}

extension View {
    /// Marks a control the tour can light: it reports its frame, and a scroll
    /// view around it can bring it into view by this id.
    func wyrmTourAnchor(_ id: String) -> some View {
        self.id(id)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { WyrmTourFrames.shared.report(id, geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global)) { WyrmTourFrames.shared.report(id, $0) }
                    .onDisappear { WyrmTourFrames.shared.forget(id) }
            })
    }

    /// Scrolls the tour's current anchor into view when its step comes up.
    func wyrmTourScroll(_ proxy: ScrollViewProxy) -> some View {
        onReceive(WyrmTour.shared.$step) { _ in
            DispatchQueue.main.async {
                guard let target = WyrmTour.shared.target else { return }
                // Let a page that just slid in settle before scrolling it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    guard WyrmTour.shared.target == target else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }
}

/// The tour over everything: the dim with its lit window, and the card.
/// `safeTop` / `safeBottom` come from the page, as this view ignores the safe area.
struct WyrmTourOverlay: View {
    let safeTop: CGFloat
    let safeBottom: CGFloat
    @ObservedObject var tour = WyrmTour.shared
    @ObservedObject var frames = WyrmTourFrames.shared

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let step = tour.current
            let lit: CGRect? = step?.anchor.flatMap { frames.frames[$0] }
                .map { $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8) }
                .flatMap { $0.width > 2 && $0.height > 2 ? $0 : nil }
            let closed = CGRect(x: geo.size.width / 2, y: geo.size.height / 2, width: 0, height: 0)
            ZStack(alignment: .topLeading) {
                // Holds every tap and drag on the app beneath while the tour runs.
                // A layer under the card, so it never competes with the card's buttons.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .gesture(DragGesture(minimumDistance: 0))
                // The dim, with the lit window cut out of it; the window glides between steps.
                WyrmTourDim(hole: lit ?? closed)
                    .fill(Color.black.opacity(step?.anchor == nil ? 0.55 : 0.62), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                if let lit {
                    WyrmTourRing(rect: lit)
                }
                if let step {
                    WyrmTourCardBody(step: step, index: tour.step, total: tour.spotlightCount,
                                     onNext: { tour.next() }, onBack: { tour.back() }, onSkip: { tour.finish() })
                        .frame(width: min(geo.size.width - 32, 420))
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { card in
                            Color.clear.preference(key: WyrmTourCardHeight.self, value: card.size.height)
                        })
                        .modifier(WyrmTourCardPlacement(lit: lit, top: safeTop + 12,
                                                        bottom: geo.size.height - safeBottom - 12, size: geo.size))
                        .id(tour.step)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.32), value: lit)
            .animation(.easeOut(duration: 0.22), value: tour.step)
        }
        .ignoresSafeArea()
    }
}

/// The screen with a rounded window cut out of it (even-odd), animatable.
private struct WyrmTourDim: Shape {
    var hole: CGRect
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0.5 && hole.height > 0.5 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16), style: .continuous)
        }
        return path
    }
}

/// The lit window's white edge and a soft ring breathing out of it: "this one".
private struct WyrmTourRing: View {
    let rect: CGRect
    @State private var pulse = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(pulse ? 0 : 0.45), lineWidth: 2)
                .frame(width: rect.width + (pulse ? 20 : 0), height: rect.height + (pulse ? 20 : 0))
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
        }
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
        .onAppear { pulse = true }
    }
}

private struct WyrmTourCardHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Places the card once its height is known, so it never covers the lit window.
private struct WyrmTourCardPlacement: ViewModifier {
    let lit: CGRect?
    let top: CGFloat
    let bottom: CGFloat
    let size: CGSize
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(WyrmTourCardHeight.self) { height = $0 }
            .position(x: size.width / 2, y: centerY)
    }

    private var centerY: CGFloat {
        let h = max(height, 1)
        guard let lit else { return size.height / 2 }
        let gap: CGFloat = 14
        let below = lit.maxY + gap
        let above = lit.minY - gap - h
        let roomBelow = bottom - below - h
        let roomAbove = above - top
        var y: CGFloat
        if lit.midY < size.height / 2 && roomBelow >= 0 { y = below }
        else if roomAbove >= 0 { y = above }
        else if roomBelow >= 0 { y = below }
        else { y = bottom - h }
        y = min(max(y, top), max(top, bottom - h))
        return y + h / 2
    }
}

private struct WyrmTourCardBody: View {
    let step: WyrmTourStep
    let index: Int
    let total: Int
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if index == 0 {
                welcome
            } else if index == WyrmTour.steps.count - 1 {
                done
            } else {
                spotlight
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        // The card answers taps itself, so a tap on it never reaches the app.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            WyrmBrandMark(size: 58)
            Text(step.title).font(.wyrmDisplay(30)).foregroundColor(ATheme.ink)
                .multilineTextAlignment(.center).padding(.top, 14)
            Text(step.body).font(.androidWyrm(14.5)).foregroundColor(ATheme.mute)
                .multilineTextAlignment(.center).lineSpacing(3).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            primary("Show me around", wide: true, action: onNext).padding(.top, 20)
            plain("Skip for now", action: onSkip).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var done: some View {
        VStack(spacing: 0) {
            WyrmBrandMark(size: 46)
            Text(step.title).font(.wyrmDisplay(26)).foregroundColor(ATheme.ink)
                .multilineTextAlignment(.center).padding(.top, 12)
            Text(step.body).font(.androidWyrm(14)).foregroundColor(ATheme.mute)
                .multilineTextAlignment(.center).lineSpacing(3).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            primary("Let's play", wide: true, action: onNext).padding(.top, 18)
            plain("Back", action: onBack).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var spotlight: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("\(index) of \(total)").font(.androidWyrm(11.5, .semibold)).tracking(0.4).foregroundColor(ATheme.quiet)
                    .fixedSize()
                HStack(spacing: 4) {
                    ForEach(1...max(total, 1), id: \.self) { i in
                        Circle().fill(i <= index ? ATheme.live : ATheme.rule)
                            .frame(width: i == index ? 8 : 6, height: i == index ? 8 : 6)
                    }
                }
                .frame(maxWidth: .infinity)
                plain("Skip", action: onSkip)
            }
            Text(step.title).font(.androidWyrm(18, .bold)).foregroundColor(ATheme.ink).padding(.top, 8)
            Text(step.body).font(.androidWyrm(14)).foregroundColor(ATheme.mute).lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            HStack {
                if index > 1 { plain("Back", action: onBack) }
                Spacer()
                primary("Next", wide: false, action: onNext)
            }
            .padding(.top, 14)
        }
    }

    private func primary(_ label: String, wide: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.androidWyrm(14.5, .bold)).foregroundColor(ATheme.onInk)
                .padding(.horizontal, 20).frame(maxWidth: wide ? .infinity : nil).frame(height: 42)
                .background(Capsule().fill(ATheme.ink))
        }
        .buttonStyle(WSPressStyle())
    }

    private func plain(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.androidWyrm(13.5, .semibold)).foregroundColor(ATheme.mute)
                .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
