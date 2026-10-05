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
 * on one of its tabs, the Settings tab) that `WyrmDesignMain` opens with the
 * app's own page animations, and an anchor id carried by the real control
 * (`wyrmTourAnchor`). Anchors report their frames and the scroll views around
 * them bring the step's control to the middle.
 *
 * Smoothness (OM, 2026-10-06: the card flickered, jumping from top to bottom):
 * on Next the card fades away, the lit window glides from where it was to the
 * new control (it stays on the old one until the new one has been laid out),
 * and the new card only appears once that control has stopped moving, already
 * in its final place. The tour arrives and leaves cinematically.
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
                     body: "How you play. Three tabs inside: Controls, On-screen buttons and Arena UI."),
        WyrmTourStep(place: .controls, anchor: "controls.tabs", title: "Controls",
                     body: "Steer with the Arrow or the Joystick, choose how you boost, and set sizes, the arrow's look and movement, and the zoom bar."),
        WyrmTourStep(place: .buttons, anchor: "controls.tabs", title: "On-screen buttons",
                     body: "Pick which buttons appear in the arena, like zoom, auto restart and chat, and how each one fires."),
        WyrmTourStep(place: .arenaUI, anchor: "controls.tabs", title: "Arena UI",
                     body: "Size the minimap, the leaderboard and the stats text. Arrange arena UI moves them, the team roster and chat anywhere."),
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
    /// Finishing: the tour is easing out; it ends when the overlay is gone.
    @Published var closing = false

    var active: Bool { step >= 0 }
    var current: WyrmTourStep? { Self.steps.indices.contains(step) ? Self.steps[step] : nil }
    var target: String? { closing ? nil : current?.anchor }
    /// The lit steps (everything but the welcome and the last card).
    var spotlightCount: Int { Self.steps.count - 2 }
    var pending: Bool { UserDefaults.standard.integer(forKey: Self.seenKey) < Self.version }

    func start() {
        closing = false
        WyrmTourFrames.shared.publishAll()
        step = 0
    }

    func next() {
        guard !closing else { return }
        if step >= Self.steps.count - 1 { finish() } else { step += 1 }
    }

    func back() {
        guard !closing else { return }
        if step > 0 { step -= 1 }
    }

    /// Finished or skipped: seen on this phone for this tour version; the overlay eases out, then `end`.
    func finish() {
        UserDefaults.standard.set(Self.version, forKey: Self.seenKey)
        if active { closing = true }
    }

    /// Called by the overlay once it has eased out.
    func end() {
        step = -1
        closing = false
    }

    /// The window for step `index`: its own control once laid out; until then
    /// the last lit control before it, so the window glides instead of blinking.
    static func hole(for index: Int, in frames: [String: CGRect]) -> CGRect? {
        guard steps.indices.contains(index), let anchor = steps[index].anchor else { return nil }
        if let frame = frames[anchor] { return frame }
        var i = index - 1
        while i >= 0 {
            if let earlier = steps[i].anchor, let frame = frames[earlier] { return frame }
            i -= 1
        }
        return nil
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

    /// A control that left: while the tour runs its last frame stays, so the
    /// window can glide from it.
    func forget(_ id: String) {
        latest[id] = nil
        if !WyrmTour.shared.active, frames[id] != nil { frames[id] = nil }
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

    /// Scrolls the tour's current anchor to the middle when its step comes up
    /// (as far as the page scrolls: a control at the very end stays low).
    func wyrmTourScroll(_ proxy: ScrollViewProxy) -> some View {
        onReceive(WyrmTour.shared.$step) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                guard let target = WyrmTour.shared.target else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { proxy.scrollTo(target, anchor: .center) }
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
    /// The cinematic arrival and leaving of the whole tour, 0 to 1.
    @State private var presence: Double = 0
    /// The step whose card is on screen, and how far it has come in.
    @State private var shownIndex = 0
    @State private var cardIn: Double = 0
    @State private var cardHeight: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    private static let glide = Animation.spring(response: 0.55, dampingFraction: 0.9)

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let size = geo.size
            let hole = local(WyrmTour.hole(for: tour.step, in: frames.frames), origin)
            let closed = CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
            let shownAnchor = WyrmTour.steps.indices.contains(shownIndex) ? WyrmTour.steps[shownIndex].anchor : nil
            let shownHole = shownAnchor == nil ? nil : local(WyrmTour.hole(for: shownIndex, in: frames.frames), origin)
            let width = min(size.width - 32, 420)
            let centerY = cardCenterY(shownHole, size: size)
            let intro = shownIndex == 0
            let scale = (intro ? 0.86 + 0.14 * cardIn : 0.96 + 0.04 * cardIn) * (0.94 + 0.06 * presence)
            ZStack(alignment: .topLeading) {
                // Holds every tap and drag on the app beneath while the tour runs.
                // A layer under the card, so it never competes with the card's buttons.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .gesture(DragGesture(minimumDistance: 0))
                // The dim, with the lit window cut out of it; the window glides between steps.
                WyrmTourDim(hole: hole ?? closed)
                    .fill(Color.black.opacity((tour.current?.anchor == nil ? 0.58 : 0.64) * presence), style: FillStyle(eoFill: true))
                    .animation(Self.glide, value: hole)
                    .allowsHitTesting(false)
                if let hole {
                    WyrmTourRing(rect: hole)
                        .opacity(presence)
                        .animation(Self.glide, value: hole)
                }
                if WyrmTour.steps.indices.contains(shownIndex) {
                    WyrmTourCardBody(step: WyrmTour.steps[shownIndex], index: shownIndex, total: tour.spotlightCount,
                                     drawn: intro ? cardIn : 1,
                                     onNext: { tour.next() }, onBack: { tour.back() }, onSkip: { tour.finish() })
                        .frame(width: width)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { card in
                            Color.clear.preference(key: WyrmTourCardHeight.self, value: card.size.height)
                        })
                        .onPreferenceChange(WyrmTourCardHeight.self) { cardHeight = $0 }
                        .scaleEffect(scale)
                        .opacity(cardIn * presence)
                        .offset(y: (1 - cardIn) * 18 + (1 - presence) * 14)
                        .position(x: size.width / 2, y: centerY)
                        // Hidden it jumps to its place; showing it glides with a control that still nudges.
                        .animation(cardIn > 0.05 ? Animation.spring(response: 0.45, dampingFraction: 0.9) : nil, value: centerY)
                        .allowsHitTesting(cardIn > 0.5 && !tour.closing)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            shownIndex = max(tour.step, 0)
            withAnimation(.easeInOut(duration: 0.56)) { presence = 1 }
            settle(to: tour.step)
        }
        .onChange(of: tour.step) { settle(to: $0) }
        .onChange(of: tour.closing) { closing in
            guard closing else { return }
            settling?.cancel()
            withAnimation(.easeInOut(duration: 0.52)) { presence = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.54) { tour.end() }
        }
        .onDisappear { settling?.cancel() }
    }

    private func local(_ frame: CGRect?, _ origin: CGPoint) -> CGRect? {
        guard let frame else { return nil }
        let lit = frame.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
        return lit.width > 2 && lit.height > 2 ? lit : nil
    }

    /// Under the window when it is in the top half, over it otherwise, centred when nothing is lit.
    private func cardCenterY(_ lit: CGRect?, size: CGSize) -> CGFloat {
        let h = max(cardHeight, 1)
        guard let lit else { return size.height / 2 }
        let top = safeTop + 12
        let bottom = size.height - safeBottom - 12
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

    /// The new step's card waits until its control has stopped moving (page
    /// changes and scrolls), then rises in, already in its place.
    private func settle(to index: Int) {
        settling?.cancel()
        guard WyrmTour.steps.indices.contains(index) else { return }
        if cardIn > 0 && shownIndex != index {
            withAnimation(.easeOut(duration: 0.15)) { cardIn = 0 }
        }
        let before = WyrmTour.steps.indices.contains(shownIndex) ? WyrmTour.steps[shownIndex].place : .home
        let step = WyrmTour.steps[index]
        let minWait: Double = index == 0 ? 0.42 : (before != step.place ? 0.72 : 0.26)
        settling = Task { @MainActor in
            let started = Date()
            var last: CGRect?
            var still = 0
            while !Task.isCancelled {
                let now = step.anchor.flatMap { WyrmTourFrames.shared.frames[$0] }
                var settled = step.anchor == nil
                if let now, let last, abs(now.minX - last.minX) < 0.5, abs(now.minY - last.minY) < 0.5,
                   abs(now.width - last.width) < 0.5, abs(now.height - last.height) < 0.5 { settled = true }
                still = settled ? still + 1 : 0
                last = now
                let waited = Date().timeIntervalSince(started)
                if (waited >= minWait && still >= 4) || waited > 2.6 { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !Task.isCancelled else { return }
            shownIndex = index
            // A moment for the new card to be measured and placed before it shows.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { cardIn = 1 }
        }
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
                .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulse)
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

private struct WyrmTourCardBody: View {
    let step: WyrmTourStep
    let index: Int
    let total: Int
    /// How far the welcome's W has drawn itself, 0 to 1.
    let drawn: Double
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
            // The W draws itself as the welcome arrives.
            WyrmBrandStroke()
                .trim(from: 0, to: drawn)
                .stroke(ATheme.ink, style: StrokeStyle(lineWidth: 58 * 0.16, lineCap: .round, lineJoin: .round))
                .frame(width: 58, height: 58)
                .animation(.easeInOut(duration: 1.0), value: drawn)
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
