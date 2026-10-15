import SwiftUI
import UIKit

/*
 * Shed (OM, 2026-10-15): Home › Shed, the skin generator page. A one-to-one
 * port of Android's ui/ShedScreen.kt (itself the HTML prototype,
 * Desktop/thinking-orbs/generator.html): same words, sizes, timings and
 * curves.
 *   rest: one W breathes in 3D in the middle; a floating Liquid Glass
 *         composer at the bottom holds the recipe (a sentence of tappable
 *         words) and Shed.
 *   Shed: the composer slides away, everything else dissolves into blur, the
 *         same W grows to the middle and its own dots become the snake's face
 *         (no cut) while the steps are read out; then it dissolves, the batch
 *         scrolls under the composer card by card (each snake drawn head first
 *         as it scrolls in) and the composer slides back up.
 *   A word tap morphs the composer itself into that word's choices (no
 *   drawer, no dim): the content dissolves, the glass grows upward and the
 *   choices materialise; Done, a pick or a tap outside runs it backwards.
 *   A tapped card opens underneath with its code and Copy code.
 * The theme is the app's (Settings); nothing here is synced (OM): the recipe
 * and the skins already shown live under `wyrm.ios.shed.` (wiped on log out).
 */

/// Android's ShedEase, CubicBezierEasing(0.2, 0.8, 0.2, 1).
private func shedEase(_ seconds: Double) -> Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: seconds) }
/// Compose's default tween easing (FastOutSlowIn).
private func shedTween(_ seconds: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: seconds) }
/// Compose blur radii are given as Android RenderEffect radii; SwiftUI's is a
/// Gaussian radius, about 0.58 of it for the same look.
private let shedBlur: CGFloat = 0.58
private let shedStageW: CGFloat = 380
private let shedStageH: CGFloat = 296
private let shedCountMin = 1
private let shedCountMax = 40

/// The steps read out under the W, one every 1.4 s over its whole journey.
private let shedSteps: [(Double, String)] = [
    (0.0, "Reading your recipe"),
    (1.4, "Choosing colours that belong together"),
    (2.8, "Weaving the bands"),
    (4.2, "Fitting every arena · \(WyrmShedGenerator.maxRuns) runs"),
    (5.6, "Letting go of look-alikes"),
]

private let shedMoodText: [String: String] = [
    "cute": "Soft colours, candy pairs",
    "danger": "Dark body, one glowing colour",
    "random": "Anything goes, still matching",
    "pattern": "Clean repeats you can spot",
    "unique": "Rare mixes, stars, odd rhythms",
]
private let shedStyleText: [String: String] = [
    "stripes": "Equal bands, one after another",
    "thickThin": "A wide band, a thin line",
    "ramp": "Colour to colour and back",
    "rainbow": "Colours in rainbow order",
    "pulse": "A long body with a spark",
    "band": "A body with a ringed band",
    "duo": "Two colours, side by side",
    "fib": "Bands grow 2, 3, 5, 8, 13",
    "weave": "Two bands knitted with a line",
    "chaos": "Random bands, no repeats",
    "starry": "Plain bands with star beads",
]
private let shedSizeText: [String: String] = ["short": "Narrow bands", "medium": "Balanced bands", "long": "Wide bands"]

// MARK: - Storage

/// The recipe and the skins already shown, on this phone only (OM: not synced).
enum WyrmShedStore {
    private static let prefix = "wyrm.ios.shed."
    private static let historyMax = 3000
    private static var d: UserDefaults { .standard }

    static func recipe() -> WyrmShedRecipe {
        let base = WyrmShedRecipe()
        var r = WyrmShedRecipe()
        if let v = d.object(forKey: prefix + "count") as? Int { r.count = min(max(v, shedCountMin), shedCountMax) }
        if let v = d.string(forKey: prefix + "mood"), WyrmShedGenerator.moods.contains(v) { r.mood = v }
        if let v = d.string(forKey: prefix + "tone"), ["auto", "light", "dark", "mix"].contains(v) { r.tone = v }
        if let v = d.string(forKey: prefix + "theme"), v.isEmpty || WyrmShedGenerator.themes.contains(v) { r.theme = v }
        var colours: [Character] = []
        for c in d.string(forKey: prefix + "colours") ?? "" where WyrmShedBeads.isOfficial(c) && !colours.contains(c) { colours.append(c) }
        r.colours = colours
        if let v = d.string(forKey: prefix + "style"), v == "auto" || WyrmShedGenerator.styles.contains(v) { r.style = v }
        if let v = d.string(forKey: prefix + "size"), WyrmShedGenerator.sizes.contains(v) { r.size = v }
        if let v = d.string(forKey: prefix + "symmetry"), ["auto", "on", "off"].contains(v) { r.symmetry = v }
        if let v = d.object(forKey: prefix + "wildness") as? Double { r.wildness = min(max(v, 0), 1) } else { r.wildness = base.wildness }
        r.seed = Int32(1 + Int.random(in: 0..<999999))
        return r
    }

    static func save(_ r: WyrmShedRecipe) {
        d.set(r.count, forKey: prefix + "count")
        d.set(r.mood, forKey: prefix + "mood")
        d.set(r.tone, forKey: prefix + "tone")
        d.set(r.theme, forKey: prefix + "theme")
        d.set(String(r.colours), forKey: prefix + "colours")
        d.set(r.style, forKey: prefix + "style")
        d.set(r.size, forKey: prefix + "size")
        d.set(r.symmetry, forKey: prefix + "symmetry")
        d.set(r.wildness, forKey: prefix + "wildness")
    }

    static func history() -> [String] {
        (d.string(forKey: prefix + "history") ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func saveHistory(_ list: [String]) {
        d.set(list.suffix(historyMax).joined(separator: "\n"), forKey: prefix + "history")
    }
}

// MARK: - Small helpers

private enum ShedPhase { case rest, run, leaving, results }
private enum ShedSheet: Equatable { case count, mood, tone, source, style, size, tune }

/// The W's clock: page time that pauses while the W is away (the breath never restarts).
private final class ShedClock {
    private var base = 0.0
    private var since: Date? = Date()
    func value(_ now: Date = Date()) -> Double { base + (since.map { now.timeIntervalSince($0) } ?? 0) }
    func pause() { base = value(); since = nil }
    func resume() { if since == nil { since = Date() } }
}

/// A cubic bezier easing, as CSS / Compose define it.
private func shedBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    func bx(_ t: Double) -> Double { let m = 1 - t; return 3 * m * m * t * x1 + 3 * m * t * t * x2 + t * t * t }
    func by(_ t: Double) -> Double { let m = 1 - t; return 3 * m * m * t * y1 + 3 * m * t * t * y2 + t * t * t }
    var lo = 0.0, hi = 1.0, t = x
    for _ in 0..<40 {
        let v = bx(t)
        if abs(v - x) < 1e-6 { break }
        if v < x { lo = t } else { hi = t }
        t = (lo + hi) / 2
    }
    return by(t)
}

/// The bottom of the screen the page host leaves to us (it ignores the container's safe area).
private func shedWindowBottomInset() -> CGFloat {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    return (windows.first { $0.isKeyWindow } ?? windows.first)?.safeAreaInsets.bottom ?? 0
}

/// One part of the composer's content: it dissolves and materialises; a blur
/// never wraps the glass surface itself.
private struct ShedPart: Equatable {
    var opacity = 1.0
    var blur: CGFloat = 0
    var scale: CGFloat = 1
}

private extension View {
    func shedMorph(_ part: ShedPart) -> some View {
        self.scaleEffect(part.scale).opacity(part.opacity).blur(radius: part.blur * shedBlur)
    }
}

private struct ShedFramePreference: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let n = nextValue(); if n != .zero { value = n } }
}
private struct ShedHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct ShedScrollHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Liquid Glass on iOS 26 (Android's tint: Card at 0.55), the themed card before it.
private struct ShedGlass: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(ATheme.card.opacity(0.55)), in: shape)
        } else {
            content.background(shape.fill(ATheme.card)).overlay(shape.stroke(ATheme.rule, lineWidth: 1))
        }
#else
        content.background(shape.fill(ATheme.card)).overlay(shape.stroke(ATheme.rule, lineWidth: 1))
#endif
    }
}

// MARK: - The page

struct WyrmShedPage: View {
    let close: () -> Void
    @StateObject private var textures = WyrmSkinTextureLibrary.acquire()
    @ObservedObject private var theme = WyrmThemeStore.shared

    @State private var recipe = WyrmShedStore.recipe()
    @State private var phase: ShedPhase = .rest
    @State private var skins: [WyrmShedSkin] = []
    @State private var shown: Set<String> = []
    @State private var openKey: String?
    @State private var sheet: ShedSheet?
    @State private var displayedSheet: ShedSheet?
    @State private var morphing = false
    @State private var parts = [ShedPart](repeating: ShedPart(), count: 4)
    @State private var morphTask: Task<Void, Never>?
    @State private var busy = false
    @State private var composerAway = false
    @State private var away = 0.0
    @State private var veil = 0.0
    @State private var sheds = 0
    @State private var ready = false
    @State private var scrollTop = 0

    // the W's clock, its run and where it stands
    @State private var clock = ShedClock()
    @State private var runStart: Double?
    @State private var stageOn = true
    @State private var stageY: CGFloat = 0
    @State private var stageScale: CGFloat = 0.68
    @State private var stageAlpha = 0.0
    @State private var rootSize: CGSize = .zero
    @State private var restY: CGFloat = -1
    @State private var restScale: CGFloat = 0.68
    @State private var composerH: CGFloat = 0
    @State private var measuredComposerH: CGFloat = 0
    @State private var insetBottom: CGFloat = 0

    private var choicesOpen: Bool { sheet != nil || displayedSheet != nil || morphing }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ATheme.paper
                page
                    .opacity(1 - 0.75 * veil)
                    .scaleEffect(1 - 0.04 * veil)
                    .blur(radius: 16 * veil * shedBlur)
                if ready && stageOn { stage }
                // Transparent outside catcher, above the W and below the composer.
                if choicesOpen {
                    Color.clear.contentShape(Rectangle()).onTapGesture(perform: closeSheet)
                }
                composer(width: proxy.size.width)
            }
            .coordinateSpace(name: "shedRoot")
            .onAppear {
                rootSize = proxy.size
                insetBottom = shedWindowBottomInset()
            }
            .onChange(of: proxy.size) { rootSize = $0 }
        }
        .onAppear {
            textures.prepare()
            guard !ready else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                WyrmShedW.prepare()
                DispatchQueue.main.async { ready = true; settleRest() }
            }
        }
        .onChange(of: restY) { _ in settleRest() }
        .onChange(of: restScale) { _ in settleRest() }
        .onChange(of: sheet) { _ in startMorph() }
        .onDisappear { morphTask?.cancel() }
    }

    // ------------------------------------------------------------ the page (what the glass sees)

    private var page: some View {
        VStack(spacing: 0) {
            ShedHeader(onBack: close, sub: phase == .results || !skins.isEmpty ? "\(skins.count) skins · best first" : nil)
            if skins.isEmpty {
                restSlot.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                results
            }
        }
    }

    // rest: the slot the W breathes in
    private var restSlot: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: 260, height: 203)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ShedFramePreference.self, value: g.frame(in: .named("shedRoot")))
                })
            Text("What should your Wyrm shed into?")
                .font(.androidWyrm(19, .heavy)).foregroundColor(ATheme.ink).multilineTextAlignment(.center)
            Spacer().frame(height: 6)
            Text("Write your recipe below, then shed.")
                .font(.androidWyrm(13)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center)
        }
        .padding(.bottom, composerH + 24)
        .onPreferenceChange(ShedFramePreference.self) { frame in
            guard frame != .zero else { return }
            restY = frame.midY
            restScale = frame.width / shedStageW
        }
    }

    private var results: some View {
        let listWidth = rootSize.width
        return ScrollViewReader { reader in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    Color.clear.frame(height: 0).id("shed-top")
                    ForEach(Array(skins.enumerated()), id: \.element.key) { index, skin in
                        ShedCard(
                            skin: skin,
                            index: index,
                            textures: textures,
                            width: max(0, listWidth - 32),
                            open: openKey == skin.key,
                            alreadyShown: shown.contains(skin.key),
                            delayMs: index < 5 && !shown.contains(skin.key) ? 180 + index * 140 : 0,
                            onShown: { shown.insert(skin.key) },
                            onToggle: { withAnimation(shedEase(0.5)) { openKey = openKey == skin.key ? nil : skin.key } }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, composerH + 40 + insetBottom)
            }
            .onChange(of: scrollTop) { _ in reader.scrollTo("shed-top", anchor: .top) }
        }
    }

    // ------------------------------------------------------------ the one W and the steps

    private var stage: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !stageOn)) { context in
            let now = clock.value(context.date)
            let run = runStart.map { now - $0 }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    // full 3D at rest; it straightens out as the W grows to the middle
                    let depth = run.map { pow(max(0, 1 - $0 / 0.9), 2) } ?? 1
                    let dots = WyrmShedW.frame(w: Double(shedStageW), h: Double(shedStageH), tb: now, run: run, half: sheds % 2, depth: depth)
                    let ink = theme.palette.ink
                    var c = ctx
                    WyrmShedW.paint(dots, in: &c, ink: (ink.r, ink.g, ink.b), dark: theme.palette.dark)
                }
                .frame(width: shedStageW, height: shedStageH)
                .scaleEffect(stageScale)
                .opacity(stageAlpha)
                .blur(radius: 20 * (1 - stageAlpha) * shedBlur)
                .position(x: rootSize.width / 2, y: stageY)
                .allowsHitTesting(false)

                if phase == .run {
                    let t = run ?? 0
                    let step = max(0, shedSteps.lastIndex(where: { t >= $0.0 }) ?? 0)
                    ZStack {
                        Text(shedSteps[step].1)
                            .font(.androidWyrm(17, .bold)).foregroundColor(ATheme.mute)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .id(step)
                            .transition(.asymmetric(
                                insertion: AnyTransition.opacity.combined(with: .scale(scale: 1.06)).animation(shedEase(0.7)),
                                removal: AnyTransition.opacity.combined(with: .scale(scale: 0.94)).animation(shedTween(0.45))))
                    }
                    .frame(width: rootSize.width)
                    .offset(y: stageY + shedStageH * stageScale / 2 + 6)
                    .animation(shedEase(0.7), value: step)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: rootSize.width, height: rootSize.height, alignment: .topLeading)
        }
    }

    // ------------------------------------------------------------ the floating composer

    private func composer(width: CGFloat) -> some View {
        let maxBody = min(rootSize.height * 0.56, 520)
        let maxHeight = max(100, rootSize.height - insetBottom - 50)
        let innerWidth = min(416, width - 24) - 28
        return VStack(spacing: 0) {
            if let showing = displayedSheet {
                ShedComposerChoices(
                    sheet: showing,
                    recipe: recipe,
                    textures: textures,
                    parts: parts,
                    maxBodyHeight: maxBody,
                    maxHeight: maxHeight,
                    onRecipe: { if sheet == showing { setRecipe($0) } },
                    onClose: closeSheet
                )
                .transition(.identity)
            } else {
                VStack(spacing: 0) {
                    ShedSentence(recipe: recipe, textures: textures, width: innerWidth - 8, onOpen: openSheet)
                        .shedMorph(parts[0])
                    Spacer().frame(height: 10)
                    HStack(spacing: 0) {
                        Button { openSheet(.tune) } label: {
                            ShedSlidersIcon().stroke(ATheme.ink, style: StrokeStyle(lineWidth: 2 * 18 / 24, lineCap: .round))
                                .frame(width: 18, height: 18)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(ATheme.ink.opacity(0.07)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(WSPressStyle())
                        Spacer()
                        Button(action: shed) {
                            HStack(spacing: 8) {
                                Text(sheds > 0 ? "Shed again" : "Shed").font(.androidWyrm(16, .heavy)).foregroundColor(ATheme.onInk)
                                ShedArrowIcon().stroke(ATheme.onInk, style: StrokeStyle(lineWidth: 2.4 * 18 / 24, lineCap: .round, lineJoin: .round))
                                    .frame(width: 18, height: 18)
                            }
                            .padding(.leading, 24).padding(.trailing, 20)
                            .frame(height: 48)
                            .background(Capsule().fill(ATheme.ink))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(WSPressStyle())
                        .disabled(busy || morphing || sheet != nil || composerAway)
                    }
                    .shedMorph(parts[1])
                }
                .transition(.identity)
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .modifier(ShedGlass())
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture {}
        .background(GeometryReader { g in Color.clear.preference(key: ShedHeightPreference.self, value: g.size.height) })
        .onPreferenceChange(ShedHeightPreference.self) { h in
            measuredComposerH = h
            publishComposerHeight()
        }
        .frame(maxWidth: 416)
        .padding(.horizontal, 12)
        .padding(.bottom, 12 + insetBottom)
        .modifier(WyrmAboveKeys())
        // Slide/fade on the outer wrapper only, never a blur around the glass.
        .offset(y: CGFloat(away) * (measuredComposerH + 40))
        .opacity(1 - away)
        .allowsHitTesting(!composerAway)
    }

    // ------------------------------------------------------------ choices morph

    private func openSheet(_ value: ShedSheet) {
        if !morphing && !busy && !composerAway && sheet == nil { sheet = value }
    }
    private func closeSheet() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        sheet = nil
    }

    /// Sequential, like morph() in the prototype: dissolve, swap, resize and
    /// materialise. A close during the reveal cancels it and reverses smoothly.
    private func startMorph() {
        if sheet == displayedSheet && !morphing { return }
        morphTask?.cancel()
        let target = sheet
        morphTask = Task { @MainActor in
            morphing = true
            withAnimation(shedTween(0.24)) {
                for i in parts.indices { parts[i] = ShedPart(opacity: 0, blur: 20, scale: 0.94) }
            }
            do { try await Task.sleep(nanoseconds: 240_000_000) } catch { return }
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                for i in parts.indices { parts[i] = ShedPart(opacity: 0, blur: 20, scale: 1.06) }
            }
            withAnimation(shedEase(0.6)) { displayedSheet = target }
            // one frame so the new content starts from its blurred, enlarged state
            do { try await Task.sleep(nanoseconds: 17_000_000) } catch { return }
            for i in parts.indices {
                withAnimation(shedEase(0.55).delay(Double(i) * 0.04)) { parts[i] = ShedPart() }
            }
            do { try await Task.sleep(nanoseconds: 670_000_000) } catch { return }
            morphing = false
            publishComposerHeight()
        }
    }

    /// Opening choices must not push the feed or the resting W upward. Publish
    /// the new collapsed height only after the reverse morph has finished.
    private func publishComposerHeight() {
        if sheet == nil && displayedSheet == nil && !morphing { composerH = measuredComposerH }
    }

    // ------------------------------------------------------------ resting and shedding

    private func setRecipe(_ r: WyrmShedRecipe) { recipe = r; WyrmShedStore.save(r) }

    /// resting: the W sits in its slot; it fades in the first time
    private func settleRest() {
        guard ready, phase == .rest, restY >= 0 else { return }
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { stageY = restY; stageScale = restScale }
        if stageAlpha < 1 { withAnimation(shedEase(0.9)) { stageAlpha = 1 } }
    }

    private func setPhase(_ p: ShedPhase) {
        phase = p
        let veiled = p == .run || p == .leaving
        withAnimation(shedEase(0.6)) { veil = veiled ? 1 : 0 }
    }

    private func setAway(_ on: Bool) {
        composerAway = on
        withAnimation(shedEase(on ? 0.6 : 0.65)) { away = on ? 1 : 0 }
    }

    private func shed() {
        guard !busy, ready else { return }
        busy = true
        Task { @MainActor in
            let history = WyrmShedStore.history()
            let r = recipe
            let batch = await Task.detached(priority: .userInitiated) {
                WyrmShedGenerator.generate(r, history: Set(history)).skins
            }.value
            WyrmShedStore.saveHistory(history + batch.map { $0.key })
            let centreY = rootSize.height * 0.43
            let centreScale = min(1, rootSize.width * 0.9 / shedStageW)
            let fromRest = phase == .rest
            setAway(true)
            setPhase(.run)
            if !fromRest {
                // after a batch the W was away: it materialises in the middle
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) { stageY = centreY; stageScale = centreScale; stageAlpha = 0 }
                clock.resume()
                stageOn = true
                withAnimation(shedTween(0.7)) { stageAlpha = 1 }
            }
            withAnimation(shedEase(1.1)) { stageY = centreY; stageScale = centreScale }
            runStart = clock.value()
            try? await Task.sleep(nanoseconds: UInt64(WyrmShedW.run * 1_000_000_000))
            // the W (back as a W) and the last line dissolve
            setPhase(.leaving)
            withAnimation(shedTween(0.7)) { stageAlpha = 0 }
            try? await Task.sleep(nanoseconds: 700_000_000)
            clock.pause()
            stageOn = false
            runStart = nil
            skins = batch
            shown = []
            openKey = nil
            scrollTop += 1
            setPhase(.results)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                setAway(false)
            }
            var next = recipe
            next.seed = Int32(Int(WyrmShedGenerator.mixSeed(UInt32(bitPattern: recipe.seed), 77) % 999999) + 1)
            setRecipe(next)
            sheds += 1
            busy = false
        }
    }
}

// MARK: - Header

private struct ShedHeader: View {
    let onBack: () -> Void
    let sub: String?
    var body: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    ShedChevronIcon().stroke(ATheme.ink, style: StrokeStyle(lineWidth: 2.2 * 20 / 24, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 20)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(ATheme.card))
                        .overlay(Circle().strokeBorder(ATheme.rule, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(WSPressStyle())
                .accessibilityLabel("Back")
                Spacer()
            }
            VStack(spacing: 0) {
                Text("WYRM").font(.androidWyrm(10, .heavy)).tracking(2.6).foregroundColor(ATheme.quiet)
                Text("Shed").font(.androidWyrm(24, .heavy)).tracking(-0.6).foregroundColor(ATheme.ink)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if let sub {
                Text(sub).font(.androidWyrm(11, .semibold)).foregroundColor(ATheme.quiet)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
}

// MARK: - The recipe sentence

private enum ShedPiece: Identifiable {
    case word(String, [Character], ShedSheet)
    case text(String, Int)
    var id: String {
        switch self {
        case .word(_, _, let sheet): return "w-\(sheet)"
        case .text(let s, let n): return "t-\(n)-\(s)"
        }
    }
}

private struct ShedSentence: View {
    let recipe: WyrmShedRecipe
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let width: CGFloat
    let onOpen: (ShedSheet) -> Void

    private var pieces: [ShedPiece] {
        let sourceLabel: String
        let sourceBeads: [Character]
        if !recipe.colours.isEmpty {
            sourceLabel = "my \(recipe.colours.count)"; sourceBeads = recipe.colours
        } else if let t = WyrmShedGenerator.themes[recipe.theme], !recipe.theme.isEmpty {
            sourceLabel = t.label.lowercased(); sourceBeads = Array(t.chars)
        } else {
            sourceLabel = "any colour"; sourceBeads = []
        }
        var out: [ShedPiece] = []
        var n = 0
        // Plain words, each its own piece so the line wraps between words.
        func plain(_ s: String) { for w in s.split(separator: " ") { out.append(.text("\(w) ", n)); n += 1 } }
        func text(_ s: String) { out.append(.text(s, n)); n += 1 }
        out.append(.word(String(recipe.count), [], .count))
        text(" ")
        out.append(.word((WyrmShedGenerator.moods[recipe.mood]?.label ?? "").lowercased(), [], .mood))
        plain(" skins in ")
        out.append(.word(recipe.tone == "mix" ? "mixed" : recipe.tone, [], .tone))
        plain(" tones,")
        out.append(.word(sourceLabel, sourceBeads, .source))
        text(", ")
        out.append(.word(recipe.style == "auto" ? "any" : (WyrmShedGenerator.styles[recipe.style] ?? "").lowercased(), [], .style))
        plain(" style,")
        out.append(.word(recipe.size, [], .size))
        text(" bands.")
        return out
    }

    var body: some View {
        ShedFlow(width: width, rowSpacing: 2, items: pieces) { piece in
            switch piece {
            case .word(let label, let beads, let sheet):
                ShedWord(label: label, beads: beads, textures: textures) { onOpen(sheet) }
            case .text(let s, _):
                Text(s).font(.androidWyrm(19, .semibold)).tracking(-0.3).foregroundColor(ATheme.quiet)
                    .frame(height: 30)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Compose's FlowRow: items left to right, wrapping into rows.
private struct ShedFlow<Content: View>: View {
    let width: CGFloat
    let rowSpacing: CGFloat
    let items: [ShedPiece]
    @ViewBuilder let content: (ShedPiece) -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            ShedFlowLayout(rowSpacing: rowSpacing) {
                ForEach(items) { content($0) }
            }
            .frame(width: width, alignment: .leading)
        } else {
            legacy
        }
    }

    /// iOS 15: the alignment-guide wrap.
    private var legacy: some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let last = items.last?.id
        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if x != 0 && x + d.width > width { x = 0; y += rowHeight + rowSpacing; rowHeight = 0 }
                        let result = -x
                        rowHeight = max(rowHeight, d.height)
                        if item.id == last { x = 0 } else { x += d.width }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = -y
                        if item.id == last { y = 0; rowHeight = 0 }
                        return result
                    }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }
}

@available(iOS 16.0, *)
private struct ShedFlowLayout: Layout {
    let rowSpacing: CGFloat

    private func rows(_ maxWidth: CGFloat, _ subviews: Subviews) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, size))
            x += size.width
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let all = rows(maxWidth, subviews)
        var height: CGFloat = 0
        var width: CGFloat = 0
        for (k, row) in all.enumerated() {
            width = max(width, row.reduce(0) { $0 + $1.1.width })
            height += (row.map { $0.1.height }.max() ?? 0) + (k > 0 ? rowSpacing : 0)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x = bounds.minX
            let h = row.map { $0.1.height }.max() ?? 0
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width
            }
            y += h + rowSpacing
        }
    }
}

/// A tappable word: bold, with a dashed ink underline (and its beads for colours).
private struct ShedWord: View {
    let label: String
    let beads: [Character]
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let onTap: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            if !beads.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(beads.prefix(5).enumerated()), id: \.offset) { i, ch in
                        ShedBeadDot(ch: ch, textures: textures, size: 17).offset(x: CGFloat(-5 * i))
                    }
                }
                .padding(.trailing, 4)
            }
            Text(label).font(.androidWyrm(19, .heavy)).tracking(-0.3).foregroundColor(ATheme.ink)
                .frame(height: 30)
        }
        .overlay(alignment: .bottom) {
            ShedDash()
                .stroke(ATheme.ink.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(height: 2)
                .padding(.bottom, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct ShedDash: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// One official bead, drawn with the game's own art.
private struct ShedBeadDot: View {
    let ch: Character
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let size: CGFloat
    var body: some View {
        Group {
            if let image = textures.beads[WyrmShedBeads[ch].id] {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Cards

private struct ShedCard: View {
    let skin: WyrmShedSkin
    let index: Int
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let width: CGFloat
    let open: Bool
    let alreadyShown: Bool
    let delayMs: Int
    let onShown: () -> Void
    let onToggle: () -> Void

    @State private var appear = 0.0
    @State private var growStart: Date?
    @State private var grown = false
    @State private var copied = false

    var body: some View {
        let inner = max(0, width - 28)
        let bead = inner / (1 + 127 * (8.0 / 48.0))
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(String(format: "%02d", index + 1))
                        .font(.androidWyrm(26, .heavy)).tracking(-1)
                        .foregroundColor(open ? ATheme.ink : ATheme.quiet)
                        .frame(minWidth: 34, alignment: .leading)
                    Spacer().frame(width: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(WyrmShedGenerator.moods[skin.mood]?.label ?? "") \((WyrmShedGenerator.styles[skin.style] ?? "").lowercased())")
                            .font(.androidWyrm(15, .heavy)).foregroundColor(ATheme.ink)
                        Text("\(skin.colours.count) colours · \(skin.code.count) beads a pattern")
                            .font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        ForEach(Array(skin.colours.enumerated()), id: \.offset) { i, ch in
                            ShedBeadDot(ch: ch, textures: textures, size: 16).offset(x: CGFloat(-5 * i))
                        }
                    }
                }
                Spacer().frame(height: 8)
                snake
                    .frame(width: inner, height: bead * 2.16 + 24 + 6)
                    .background(ATheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if open {
                details
                    .transition(.asymmetric(
                        insertion: AnyTransition.opacity.animation(shedTween(0.4).delay(0.1)),
                        removal: AnyTransition.opacity.animation(shedTween(0.2))))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(ATheme.ink, lineWidth: open ? 2 : 0))
        .scaleEffect(0.97 + 0.03 * appear)
        .offset(y: (1 - appear) * 26)
        .opacity(appear)
        .blur(radius: 10 * (1 - appear) * shedBlur)
        .task(id: skin.key) { await reveal() }
    }

    private var snake: some View {
        TimelineView(.animation(minimumInterval: nil, paused: grown || growStart == nil)) { context in
            let progress: Double = {
                if grown || alreadyShown { return 1 }
                guard let start = growStart else { return 0 }
                return shedBezier(0.33, 1, 0.68, 1, context.date.timeIntervalSince(start) / 1.1)
            }()
            Canvas { ctx, size in
                guard textures.ready else { return }
                ShedSnake.draw(&ctx, size: size, textures: textures, code: skin.code, grow: progress)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(skin.code)
                .font(.androidWyrm(12.5)).lineSpacing(19 - 12.5 * 1.2).foregroundColor(ATheme.mute)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(ATheme.well)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .textSelection(.enabled)
            Spacer().frame(height: 10)
            HStack(spacing: 0) {
                Text("\(skin.runs) / \(WyrmShedGenerator.maxRuns) runs · fits")
                    .font(.androidWyrm(12, .bold)).foregroundColor(ATheme.mute)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Capsule().fill(ATheme.well))
                Spacer()
                Button {
                    UIPasteboard.general.string = skin.code
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        copied = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        ShedCopyIcon().stroke(ATheme.onInk, lineWidth: 2 * 15 / 24).frame(width: 15, height: 15)
                        Text(copied ? "Copied" : "Copy code").font(.androidWyrm(13, .heavy)).foregroundColor(ATheme.onInk)
                    }
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(Capsule().fill(ATheme.ink))
                    .contentShape(Capsule())
                }
                .buttonStyle(WSPressStyle())
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
    }

    private func reveal() async {
        if alreadyShown { appear = 1; grown = true; return }
        if delayMs > 0 { try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000) }
        if Task.isCancelled { return }
        onShown()
        withAnimation(shedEase(0.8)) { appear = 1 }
        try? await Task.sleep(nanoseconds: 120_000_000)
        growStart = Date()
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        grown = true
    }
}

/// The Skin tab's preview, exactly (as Android's drawShedSnake): 128 beads a
/// row, two rows, 8/48 of a bead apart, the head row turned half a
/// revolution, bead k (k = 0 the head) = code[k % length], drawn tail first so
/// nearer-the-head beads sit on top; eyes 12/29 of a bead, pupil 7/29, 2 units
/// forward. `grow` 0..1 lays the snake in from the head; the bead being laid
/// swells into place and the eyes come once the head bead is full size.
private enum ShedSnake {
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, textures: WyrmSkinTextureLibrary, code: String, grow: Double) {
        let row = 128
        let w = Double(size.width), h = Double(size.height)
        let nativeSpan = 1 + Double(row - 1) * (8.0 / 48.0)
        let scale = min((w - 28) / nativeSpan, (h - 24) / 2.16)
        guard scale > 0 else { return }
        let step = 8 * (scale / 48)
        let gap = scale * 0.16
        let bodyWidth = scale + step * Double(row - 1)
        let x = w * 0.5 - bodyWidth * 0.5
        let centreY = h * 0.48
        let headY = centreY - scale * 0.5 - gap * 0.5
        let tailY = centreY + scale * 0.5 + gap * 0.5
        let total = row * 2
        let ids = code.map { WyrmShedBeads[$0].id }
        guard !ids.isEmpty else { return }
        var resolved: [Int: GraphicsContext.ResolvedImage] = [:]
        func image(_ id: Int) -> GraphicsContext.ResolvedImage? {
            if let r = resolved[id] { return r }
            guard let cg = textures.beads[id] else { return nil }
            let r = ctx.resolve(Image(decorative: cg, scale: 1))
            resolved[id] = r
            return r
        }
        let done = grow >= 1
        let laid = done ? Double(total) : grow * Double(total)
        for segment in 0..<total {
            let codeIndex = total - 1 - segment
            if Double(codeIndex) >= laid { continue }
            let local = segment % row
            let headRow = segment >= row
            let slot = headRow ? local : row - 1 - local
            guard let img = image(ids[codeIndex % ids.count]) else { continue }
            let k = done ? 1 : min(1, (laid - Double(codeIndex)) / 6)
            let s = scale * (0.35 + 0.65 * k)
            let cx = x + scale * 0.5 + Double(slot) * step
            let cy = headRow ? headY : tailY
            if headRow {
                var c = ctx
                c.translateBy(x: cx, y: cy)
                c.rotate(by: .degrees(180))
                c.draw(img, in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
            } else {
                ctx.draw(img, in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s))
            }
        }
        if laid < 6 { return }
        guard let eyeImage = textures.beads[40] else { return }
        let eye = ctx.resolve(Image(decorative: eyeImage, scale: 1))
        let hx = x + scale * 0.5 + step * Double(row - 1)
        let unit = scale / 29
        let iris = 12 * unit
        let pupil = 7 * unit
        let cx = hx + 6 * unit
        for side in 0..<2 {
            let ey = side == 0 ? -6 * unit - 0.5 : 6 * unit
            ctx.draw(eye, in: CGRect(x: cx - iris / 2, y: headY + ey - iris / 2, width: iris, height: iris))
            let py = side == 0 ? -6 * unit : 6 * unit
            var dark = ctx
            dark.addFilter(.colorMultiply(.black))
            dark.draw(eye, in: CGRect(x: cx + 0.5 + 2 * unit - pupil / 2, y: headY + py - pupil / 2, width: pupil, height: pupil))
        }
    }
}

// MARK: - Choices inside the composer

private struct ShedComposerChoices: View {
    let sheet: ShedSheet
    let recipe: WyrmShedRecipe
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let parts: [ShedPart]
    let maxBodyHeight: CGFloat
    let maxHeight: CGFloat
    let onRecipe: (WyrmShedRecipe) -> Void
    let onClose: () -> Void

    private var titles: (String, String) {
        switch sheet {
        case .count: return ("How many skins", "From \(shedCountMin) to \(shedCountMax). Every one is checked before you see it.")
        case .mood: return ("Mood", "Sets the colours, the style and how they repeat.")
        case .tone: return ("Tones", "Light or dark beads. A theme or your own beads come first.")
        case .style: return ("Style", "How the colours are laid along the body.")
        case .size: return ("Band width", "How wide each colour band is.")
        case .source: return ("Colours", recipe.colours.isEmpty ? "Any colour, a theme, or tap beads to use only yours." : "\(recipe.colours.count) picked · only these will be used")
        case .tune: return ("Fine tune", "Small changes to how the skins come out.")
        }
    }

    var body: some View {
        let words = titles
        let title = words.0
        let sub = words.1
        let bodyCap = max(60, min(maxBodyHeight, maxHeight - 140))
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.androidWyrm(22, .heavy)).tracking(-0.4).foregroundColor(ATheme.ink)
                .shedMorph(parts[0])
            Spacer().frame(height: 4)
            Text(sub).font(.androidWyrm(13)).foregroundColor(ATheme.quiet).fixedSize(horizontal: false, vertical: true)
                .shedMorph(parts[1])
            Spacer().frame(height: 12)
            ShedSheetScroll(maxHeight: bodyCap) {
                ShedSheetBody(sheet: sheet, recipe: recipe, textures: textures, onRecipe: onRecipe, onClose: onClose)
                    .padding(.bottom, 4)
            }
            .shedMorph(parts[2])
            Spacer().frame(height: 12)
            Button(action: onClose) {
                Text("Done").font(.androidWyrm(16, .heavy)).foregroundColor(ATheme.onInk)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Capsule().fill(ATheme.ink))
                    .contentShape(Capsule())
            }
            .buttonStyle(WSPressStyle())
            .shedMorph(parts[3])
        }
        .padding(.horizontal, 2).padding(.top, 4).padding(.bottom, 2)
    }
}

/// The choices scroll inside the composer, no taller than their own content or the cap.
private struct ShedSheetScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    var body: some View {
        ScrollView(showsIndicators: false) {
            content()
                .background(GeometryReader { g in Color.clear.preference(key: ShedScrollHeightPreference.self, value: g.size.height) })
        }
        .onPreferenceChange(ShedScrollHeightPreference.self) { contentHeight = $0 }
        // its own measure stays here: the composer must not read it as its height
        .transformPreference(ShedScrollHeightPreference.self) { $0 = 0 }
        .frame(height: min(maxHeight, max(1, contentHeight)))
    }
}

private struct ShedOpt: Identifiable {
    let key: String
    let label: String
    let sub: String
    var id: String { key }
}

private struct ShedOptGrid: View {
    let options: [ShedOpt]
    let selected: (String) -> Bool
    var textures: WyrmSkinTextureLibrary? = nil
    var themeBeads = false
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(stride(from: 0, to: options.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: 8) {
                    cell(options[start])
                    if start + 1 < options.count { cell(options[start + 1]) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cell(_ o: ShedOpt) -> some View {
        let on = selected(o.key)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button { onPick(o.key) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(o.label).font(.androidWyrm(14, .heavy)).foregroundColor(ATheme.ink)
                if !o.sub.isEmpty {
                    Text(o.sub).font(.androidWyrm(12)).lineSpacing(16 - 12 * 1.2).foregroundColor(ATheme.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if themeBeads, let textures, let theme = WyrmShedGenerator.themes[o.key] {
                    HStack(spacing: 0) {
                        ForEach(Array(Array(theme.chars).enumerated()), id: \.offset) { i, ch in
                            ShedBeadDot(ch: ch, textures: textures, size: 16).offset(x: CGFloat(-4 * i))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(on ? ATheme.card : ATheme.well))
            .overlay(shape.strokeBorder(ATheme.ink, lineWidth: on ? 2 : 0))
            .contentShape(shape)
        }
        .buttonStyle(WSPressStyle())
    }
}

private struct ShedGroupTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.androidWyrm(11, .heavy)).tracking(1.6).foregroundColor(ATheme.quiet)
            .padding(.top, 16).padding(.bottom, 8)
    }
}

private struct ShedSheetBody: View {
    let sheet: ShedSheet
    let recipe: WyrmShedRecipe
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let onRecipe: (WyrmShedRecipe) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch sheet {
            case .count: count
            case .mood:
                ShedOptGrid(options: WyrmShedGenerator.moods.pairs.map { ShedOpt(key: $0.0, label: $0.1.label, sub: shedMoodText[$0.0] ?? "") },
                            selected: { $0 == recipe.mood }) { key in pick { $0.mood = key } }
            case .tone:
                ShedOptGrid(options: [ShedOpt(key: "auto", label: "Auto", sub: "The mood decides"), ShedOpt(key: "light", label: "Light", sub: "Bright, airy beads"),
                                      ShedOpt(key: "dark", label: "Dark", sub: "Deep, heavy beads"), ShedOpt(key: "mix", label: "Mixed", sub: "Light and dark together")],
                            selected: { $0 == recipe.tone }) { key in pick { $0.tone = key } }
            case .style:
                ShedOptGrid(options: [ShedOpt(key: "auto", label: "Any", sub: "The mood picks one")] + WyrmShedGenerator.styles.pairs.map { ShedOpt(key: $0.0, label: $0.1, sub: shedStyleText[$0.0] ?? "") },
                            selected: { $0 == recipe.style }) { key in pick { $0.style = key } }
            case .size:
                ShedOptGrid(options: WyrmShedGenerator.sizes.pairs.map { ShedOpt(key: $0.0, label: $0.0.prefix(1).uppercased() + $0.0.dropFirst(), sub: "\($0.1[0])–\($0.1[1]) beads · \(shedSizeText[$0.0] ?? "")") },
                            selected: { $0 == recipe.size }) { key in pick { $0.size = key } }
            case .source: source
            case .tune: tune
            }
        }
    }

    private func pick(_ change: (inout WyrmShedRecipe) -> Void) {
        var r = recipe
        change(&r)
        onRecipe(r)
        onClose()
    }

    private var count: some View {
        VStack(spacing: 0) {
            Text("\(recipe.count) \(recipe.count == 1 ? "skin" : "skins")")
                .font(.androidWyrm(40, .heavy)).tracking(-1.5).foregroundColor(ATheme.ink)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 14)
            Slider(value: Binding(get: { Double(recipe.count) }, set: { v in
                var r = recipe
                r.count = min(max(Int(v.rounded()), shedCountMin), shedCountMax)
                if r.count != recipe.count { onRecipe(r) }
            }), in: Double(shedCountMin)...Double(shedCountMax), step: 1)
            .tint(ATheme.ink)
            HStack {
                Text("\(shedCountMin)").font(.androidWyrm(12, .bold)).foregroundColor(ATheme.quiet)
                Spacer()
                Text("\(shedCountMax)").font(.androidWyrm(12, .bold)).foregroundColor(ATheme.quiet)
            }
            .padding(.top, 4)
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShedOptGrid(options: [ShedOpt(key: "any", label: "Any colour", sub: "Matched for you")],
                        selected: { _ in recipe.theme.isEmpty && recipe.colours.isEmpty }) { _ in
                pick { $0.theme = ""; $0.colours = [] }
            }
            ShedGroupTitle(text: "Themes")
            ShedOptGrid(options: WyrmShedGenerator.themes.pairs.map { ShedOpt(key: $0.0, label: $0.1.label, sub: "") },
                        selected: { recipe.colours.isEmpty && $0 == recipe.theme },
                        textures: textures, themeBeads: true) { key in pick { $0.theme = key; $0.colours = [] } }
            beadGroup("Light beads") { $0 >= 0.62 }
            beadGroup("Mid beads") { $0 >= 0.42 && $0 < 0.62 }
            beadGroup("Dark beads") { $0 < 0.42 }
        }
    }

    private func beadGroup(_ title: String, _ test: @escaping (Double) -> Bool) -> some View {
        let beads = WyrmShedBeads.all.filter { test($0.L) }.enumerated()
            .sorted { $0.element.L != $1.element.L ? $0.element.L > $1.element.L : $0.offset < $1.offset }
            .map { $0.element }
        let rows = stride(from: 0, to: beads.count, by: 8).map { Array(beads[$0..<min($0 + 8, beads.count)]) }
        return VStack(alignment: .leading, spacing: 0) {
            ShedGroupTitle(text: title)
            VStack(spacing: 6) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(rows[r], id: \.id) { b in beadCell(b) }
                        ForEach(0..<(8 - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit) }
                    }
                }
            }
        }
    }

    private func beadCell(_ b: WyrmShedBead) -> some View {
        let on = recipe.colours.contains(b.ch)
        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = textures.beads[b.id] {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(String(b.ch)).font(.androidWyrm(10, .heavy)).foregroundColor(ATheme.ink)
                .padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ATheme.card))
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay(Circle().strokeBorder(ATheme.ink, lineWidth: on ? 2.5 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            var r = recipe
            if on { r.colours.removeAll { $0 == b.ch } } else { r.colours.append(b.ch) }
            r.theme = ""
            onRecipe(r)
        }
    }

    private var tune: some View {
        VStack(spacing: 0) {
            ShedTuneRow(title: "Symmetry") {
                WSSegmented(options: ["Auto", "On", "Off"],
                            selected: max(0, ["auto", "on", "off"].firstIndex(of: recipe.symmetry) ?? 0)) { i in
                    var r = recipe
                    r.symmetry = ["auto", "on", "off"][i]
                    onRecipe(r)
                }
                .frame(width: 190)
            }
            ShedTuneRow(title: "Wildness") {
                HStack(spacing: 0) {
                    Slider(value: Binding(get: { recipe.wildness * 100 }, set: { v in
                        var r = recipe
                        r.wildness = min(max(Double(Int(v.rounded())) / 100, 0), 1)
                        if r.wildness != recipe.wildness { onRecipe(r) }
                    }), in: 0...100)
                    .tint(ATheme.ink)
                    .frame(width: 140)
                    Text("\(Int((recipe.wildness * 100).rounded()))").font(.androidWyrm(13, .bold)).foregroundColor(ATheme.quiet)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            ShedTuneRow(title: "Lucky number", last: true) {
                ShedLuckyField(recipe: recipe, onRecipe: onRecipe)
            }
        }
    }
}

private struct ShedLuckyField: View {
    let recipe: WyrmShedRecipe
    let onRecipe: (WyrmShedRecipe) -> Void
    @State private var text = ""
    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: Binding(get: { text }, set: { v in
                text = String(v.filter { $0.isASCII && $0.isNumber }.prefix(9))
                if let n = Int32(text) {
                    var r = recipe
                    r.seed = n
                    onRecipe(r)
                }
            }))
            .keyboardType(.numberPad)
            .font(.androidWyrm(15, .heavy)).foregroundColor(ATheme.ink)
            .multilineTextAlignment(.center)
            .frame(width: 110, height: 36)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ATheme.well))
            Button {
                var r = recipe
                r.seed = Int32(1 + Int.random(in: 0..<999999))
                onRecipe(r)
            } label: {
                ShedDiceIcon(color: ATheme.ink).frame(width: 16, height: 16)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(ATheme.ink.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(WSPressStyle())
        }
        .onAppear { text = String(recipe.seed) }
        .onChange(of: recipe.seed) { seed in if Int32(text) != seed { text = String(seed) } }
    }
}

private struct ShedTuneRow<Content: View>: View {
    let title: String
    var last = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 0) {
            Text(title).font(.androidWyrm(15, .bold)).foregroundColor(ATheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(ATheme.rule).frame(height: 1) } }
    }
}

// MARK: - Home's card

/// Home › Shed: a quiet explanation and a small ink capsule, without a W.
struct WyrmShedHomeCard: View {
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shed").font(.androidWyrm(17, .heavy)).foregroundColor(ATheme.ink)
                    Text("Pick a mood and shed fresh skins. Every one fits the arena.")
                        .font(.androidWyrm(13)).lineSpacing(18 - 13 * 1.2).foregroundColor(ATheme.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Shed →").font(.androidWyrm(13, .heavy)).foregroundColor(ATheme.onInk)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(ATheme.ink))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(WyrmPlainPressStyle())
        .accessibilityLabel("Open Shed")
    }
}

// MARK: - Icons (24-unit paths, as Android draws them)

private struct ShedChevronIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 15 * s, y: 5 * s)); p.addLine(to: CGPoint(x: 8 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 15 * s, y: 19 * s))
        return p
    }
}

private struct ShedArrowIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 17 * s, y: 12 * s))
        p.move(to: CGPoint(x: 13 * s, y: 6 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 13 * s, y: 18 * s))
        return p
    }
}

private struct ShedSlidersIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 4 * s, y: 7 * s)); p.addLine(to: CGPoint(x: 13.8 * s, y: 7 * s))
        p.move(to: CGPoint(x: 18.2 * s, y: 7 * s)); p.addLine(to: CGPoint(x: 20 * s, y: 7 * s))
        p.move(to: CGPoint(x: 4 * s, y: 17 * s)); p.addLine(to: CGPoint(x: 7.8 * s, y: 17 * s))
        p.move(to: CGPoint(x: 12.2 * s, y: 17 * s)); p.addLine(to: CGPoint(x: 20 * s, y: 17 * s))
        p.addEllipse(in: CGRect(x: (16 - 2.2) * s, y: (7 - 2.2) * s, width: 4.4 * s, height: 4.4 * s))
        p.addEllipse(in: CGRect(x: (10 - 2.2) * s, y: (17 - 2.2) * s, width: 4.4 * s, height: 4.4 * s))
        return p
    }
}

private struct ShedCopyIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 8 * s, y: 8 * s, width: 12 * s, height: 12 * s), cornerSize: CGSize(width: 3 * s, height: 3 * s))
        p.move(to: CGPoint(x: 16 * s, y: 8 * s)); p.addLine(to: CGPoint(x: 16 * s, y: 6 * s))
        p.addQuadCurve(to: CGPoint(x: 14 * s, y: 4 * s), control: CGPoint(x: 16 * s, y: 4 * s))
        p.addLine(to: CGPoint(x: 6 * s, y: 4 * s))
        p.addQuadCurve(to: CGPoint(x: 4 * s, y: 6 * s), control: CGPoint(x: 4 * s, y: 4 * s))
        p.addLine(to: CGPoint(x: 4 * s, y: 14 * s))
        p.addQuadCurve(to: CGPoint(x: 6 * s, y: 16 * s), control: CGPoint(x: 4 * s, y: 16 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 16 * s))
        return p
    }
}

private struct ShedDiceIcon: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            ctx.stroke(Path(roundedRect: CGRect(x: 4 * s, y: 4 * s, width: 16 * s, height: 16 * s), cornerRadius: 4 * s), with: .color(color), lineWidth: 2 * s)
            for (dx, dy) in [(9.0, 9.0), (15.0, 15.0), (15.0, 9.0), (9.0, 15.0)] {
                ctx.fill(Path(ellipseIn: CGRect(x: (dx - 1.4) * s, y: (dy - 1.4) * s, width: 2.8 * s, height: 2.8 * s)), with: .color(color))
            }
        }
    }
}
