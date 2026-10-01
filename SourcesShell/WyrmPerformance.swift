import SwiftUI
import UIKit

/// Settings › Performance (OM, 2026-10-01). Android twin: `data/WyrmPerformance.kt`
/// and `ui/SettingsPerformanceScreen.kt`.
///
/// Three modes and a frame limit. Only how often the engine draws changes:
/// never the protocol, never the game.
///
///  - **Performance**: the display's full rate (120 on ProMotion, with
///    `CADisableMinimumFrameDurationOnPhone` in Info.plist) and no step-down.
///  - **Balanced**: 60 FPS. Steady and cool.
///  - **Auto** (the default): the full rate while the phone is cool; 60 when
///    `ProcessInfo.thermalState` is serious or Low Power Mode is on; 30 when it
///    is critical (Apple: respond to thermal state changes by lowering the
///    frame rate).
///
/// iOS presents with vsync (FIFO) always. The cap reaches the engine as a
/// display-link interval (Main.m `WyrmIOSSetFrameCap`), so the choices are the
/// display's divisors: 30, 60 and, on ProMotion, 120.
final class WyrmPerformance: ObservableObject {
    static let shared = WyrmPerformance()

    enum Mode: String, CaseIterable {
        case auto, balanced, performance
        var title: String {
            switch self {
            case .auto: return "Auto"
            case .balanced: return "Balanced"
            case .performance: return "Performance"
            }
        }
    }

    enum Heat { case cool, warm, hot }

    static let limitAuto = 0
    private static let modeKey = "wyrm.ios.performance.mode"
    private static let limitKey = "wyrm.ios.performance.fps-limit"

    @Published private(set) var mode: Mode = .auto
    @Published private(set) var limit = WyrmPerformance.limitAuto
    @Published private(set) var heat: Heat = .cool
    @Published private(set) var lowPower = false
    /// What the engine draws at now.
    @Published private(set) var cap = 60
    @Published private(set) var reason = ""
    let displayMax: Int
    private var observers: [NSObjectProtocol] = []

    private init() {
        displayMax = max(30, Int(WyrmIOSDisplayMaxFPS()))
        read()
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.publish() })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                                object: nil, queue: .main) { [weak self] _ in self?.publish() })
        publish()
    }

    /// The limits this display can use: Auto, 30, 60 and its own maximum.
    var limitChoices: [Int] { [Self.limitAuto, 30, 60] + (displayMax > 60 ? [displayMax] : []) }

    func limitLabel(_ value: Int) -> String { value == Self.limitAuto ? "Auto" : "\(value)" }

    /// One line for the hub row: the mode and what it draws at right now.
    var summary: String { "\(mode.title) · \(cap) FPS" }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync).
    func reloadFromDefaults() {
        read()
        publish()
    }

    func choose(_ next: Mode) {
        guard next != mode else { return }
        mode = next
        UserDefaults.standard.set(next.rawValue, forKey: Self.modeKey)
        publish()
    }

    func chooseLimit(_ next: Int) {
        guard next != limit else { return }
        limit = next
        UserDefaults.standard.set(next, forKey: Self.limitKey)
        publish()
    }

    private func read() {
        let defaults = UserDefaults.standard
        mode = Mode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .auto
        let stored = defaults.object(forKey: Self.limitKey) as? Int ?? Self.limitAuto
        limit = stored == Self.limitAuto || stored == 30 || stored == 60 ? stored : (stored > 60 ? displayMax : Self.limitAuto)
    }

    private func publish() {
        let info = ProcessInfo.processInfo
        switch info.thermalState {
        case .critical: heat = .hot
        case .serious: heat = .warm
        default: heat = .cool
        }
        lowPower = info.isLowPowerModeEnabled
        let chosen: Int? = limit == Self.limitAuto ? nil : min(limit, displayMax)
        switch mode {
        case .performance:
            cap = chosen ?? displayMax
            reason = "The display's full \(displayMax) Hz with no step-down: the most frames and the least input delay. The phone runs warmer."
        case .balanced:
            cap = chosen ?? 60
            reason = "\(cap) FPS: steady frames, a cooler phone and a longer battery."
        case .auto:
            let wanted = chosen ?? displayMax
            let ceiling = heat == .hot ? 30 : (heat == .warm || lowPower ? 60 : displayMax)
            cap = min(wanted, ceiling)
            if cap < wanted && heat == .hot {
                reason = "The iPhone is hot, so Auto holds \(cap) FPS until it cools down."
            } else if cap < wanted && heat == .warm {
                reason = "The iPhone is warming up, so Auto holds \(cap) FPS for now."
            } else if cap < wanted && lowPower {
                reason = "Low Power Mode is on, so Auto holds \(cap) FPS."
            } else {
                reason = "The iPhone is cool: \(cap) FPS. Auto steps down by itself if it warms up or Low Power Mode comes on."
            }
        }
        WyrmIOSSetFrameCap(Int32(cap))
    }
}

// MARK: - Page

/// Laid out the way game settings explain a trade-off: what the phone is doing
/// right now on top, three mode cards that each say what they cost, then one
/// frame limit built from this display's own rates.
struct WyrmPerformancePage: View {
    @ObservedObject var store = WyrmPerformance.shared
    @ObservedObject var crashes = WyrmCrashWatch.shared
    @ObservedObject var drops = WyrmDropWatch.shared
    let close: () -> Void

    private struct ModeCopy: Identifiable {
        let mode: WyrmPerformance.Mode
        let icon: String
        let line: String
        var id: String { mode.rawValue }
    }

    private static let modes: [ModeCopy] = [
        ModeCopy(mode: .auto, icon: "wand.and.stars", line: "Full speed while the phone is cool. Steps down when it warms up or Low Power Mode is on."),
        ModeCopy(mode: .balanced, icon: "leaf", line: "Steady 60 FPS. A cooler phone and a longer battery."),
        ModeCopy(mode: .performance, icon: "bolt.fill", line: "The display's highest frame rate, never stepped down. The phone runs warmer."),
    ]

    var body: some View {
        WSScaffold(title: "Performance", onBack: close) {
            Spacer().frame(height: 18)
            nowCard

            WSSectionLabel("Mode")
            VStack(spacing: 10) {
                ForEach(Self.modes) { copy in
                    modeCard(copy.mode, icon: copy.icon, line: copy.line)
                }
            }
            .padding(.horizontal, 16)
            .wyrmSettingAnchor("app.performance")
            WSCaption("Only how often a frame is drawn changes. The arena, your snake and how you join stay exactly the same.")

            WSSectionLabel("Frame limit")
            WSSegmented(options: store.limitChoices.map(store.limitLabel),
                        selected: store.limitChoices.firstIndex(of: store.limit) ?? 0) { index in
                UISelectionFeedbackGenerator().selectionChanged()
                store.chooseLimit(store.limitChoices[index])
            }
            .padding(.horizontal, 16)
            .wyrmSettingAnchor("app.fps-limit")
            WSCaption("Auto lets the mode decide. A number holds Wyrm at that rate. In Auto mode, heat and Low Power Mode can still bring it lower. This display goes up to \(store.displayMax) Hz.")

            // OM, 2026-10-01: the "Always send" switches from the crash and
            // drop prompts, here too, so a choice made on a prompt can be undone.
            WSSectionLabel("Reports")
            WSCard {
                WSBoolRow(title: "Always send crash reports", detail: "If Wyrm closes unexpectedly, the report goes without asking.",
                          on: crashes.autoSend, first: true) { crashes.autoSend = $0 }
                WSBoolRow(title: "Always send drop reports", detail: "If the arena drops you mid-match, the report goes without asking.",
                          on: drops.autoSend, first: false) { drops.autoSend = $0 }
            }
            WSCaption("Off: Wyrm asks you each time, with Send and Not now. On: the report goes by itself and only a short note shows.")

            WSSectionLabel("Menus")
            WSCard {
                HStack(spacing: 14) {
                    iconWell("snowflake", filled: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The arena rests under menus").font(.androidWyrm(15, .semibold)).foregroundColor(ATheme.ink)
                        Text("Home, Social and Settings no longer draw the game underneath, so they barely use the graphics chip. The lobby wakes it up.")
                            .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            Spacer().frame(height: 22)
        }
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RIGHT NOW").font(.androidWyrm(10.5, .semibold)).tracking(1.2).foregroundColor(ATheme.quiet)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(store.cap)").font(.wyrmDisplay(50)).foregroundColor(ATheme.ink).monospacedDigit()
                Text("FPS").font(.androidWyrm(14, .bold)).foregroundColor(ATheme.mute)
            }
            .padding(.top, 4)
            WyrmFrameStrip(fps: store.cap).frame(height: 16).padding(.top, 6)
            WyrmPerformanceChips(store: store).padding(.top, 12)
            Text(store.reason).font(.androidWyrm(13)).foregroundColor(ATheme.mute)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func iconWell(_ symbol: String, filled: Bool) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            .foregroundColor(filled ? ATheme.onInk : ATheme.ink)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(filled ? ATheme.ink : ATheme.ink.opacity(0.08)))
    }

    private func modeCard(_ mode: WyrmPerformance.Mode, icon: String, line: String) -> some View {
        let selected = store.mode == mode
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.2)) { store.choose(mode) }
        } label: {
            HStack(spacing: 14) {
                iconWell(icon, filled: selected)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(mode.title).font(.androidWyrm(16, .bold)).foregroundColor(ATheme.ink)
                        if mode == .auto {
                            Text("RECOMMENDED").font(.androidWyrm(8.5, .bold)).tracking(0.8).foregroundColor(ATheme.quiet)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(ATheme.well))
                        }
                    }
                    Text(line).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                ZStack {
                    Circle().stroke(ATheme.rule, lineWidth: 1.5).opacity(selected ? 0 : 1)
                    Circle().fill(ATheme.ink).opacity(selected ? 1 : 0)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(ATheme.onInk).opacity(selected ? 1 : 0)
                }
                .frame(width: 22, height: 22)
            }
            .padding(14)
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct WyrmPerformanceChips: View {
    @ObservedObject var store: WyrmPerformance

    var body: some View {
        // Two rows at most; wraps by itself on the narrowest phones.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                chip("display", "\(store.displayMax) Hz display")
                chip(store.heat == .cool ? "thermometer" : "thermometer.sun",
                     store.heat == .cool ? "iPhone cool" : (store.heat == .warm ? "iPhone warm" : "iPhone hot"),
                     alert: store.heat != .cool)
            }
            if store.lowPower { chip("battery.25", "Low Power Mode", alert: true) }
        }
    }

    private func chip(_ symbol: String, _ label: String, alert: Bool = false) -> some View {
        let tint = alert ? ATheme.badge : ATheme.ink
        return HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(label).font(.androidWyrm(11.5, .semibold)).lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.07)))
    }
}

/// 24 ticks; the lit one runs faster at a higher rate (a quarter of it, readable).
private struct WyrmFrameStrip: View {
    let fps: Int

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let ticks = 24
                let sweep = min(4.0, max(0.4, Double(ticks) * 4.0 / Double(max(fps, 1))))
                let t = timeline.date.timeIntervalSinceReferenceDate
                let head = (t.truncatingRemainder(dividingBy: sweep) / sweep) * Double(ticks)
                let gap: CGFloat = 3
                let w = (size.width - gap * CGFloat(ticks - 1)) / CGFloat(ticks)
                for i in 0..<ticks {
                    let behind = (head - Double(i) + Double(ticks)).truncatingRemainder(dividingBy: Double(ticks))
                    let glow = min(1, max(0, 1 - behind / 6))
                    let rect = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: size.height)
                    let colour = glow > 0 ? ATheme.ink.opacity(0.18 + 0.82 * glow) : ATheme.rule
                    context.fill(Path(roundedRect: rect, cornerRadius: w / 2), with: .color(colour))
                }
            }
        }
    }
}
