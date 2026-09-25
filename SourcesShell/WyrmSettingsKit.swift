import SwiftUI
import UIKit

/*
 * The paper settings language, ported from Android's SettingsDrill.kt.
 *
 * Sizes, radii and type follow the Compose originals one for one (dp → pt), so
 * a page reads the same on both phones. Every control writes straight into the
 * engine mailbox through WyrmShellStore, which keeps an optimistic local copy
 * until the engine echoes the value back.
 */

struct WSPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// `SettingsDrillScaffold`: back link on the left, title centred, an optional
/// trailing action and an optional strip of section tabs under the header.
struct WSScaffold<Content: View>: View {
    let title: String
    var parent = "Settings"
    var trailing: String? = nil
    var trailingEnabled = true
    var onTrailing: (() -> Void)? = nil
    var sectionTabs: AnyView? = nil
    let onBack: () -> Void
    let content: Content
    @ObservedObject private var focus = WyrmSettingsFocus.shared

    init(title: String, parent: String = "Settings", trailing: String? = nil, trailingEnabled: Bool = true,
         onTrailing: (() -> Void)? = nil, sectionTabs: AnyView? = nil,
         onBack: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title; self.parent = parent; self.trailing = trailing; self.trailingEnabled = trailingEnabled
        self.onTrailing = onTrailing; self.sectionTabs = sectionTabs; self.onBack = onBack; self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(action: onBack) {
                        Text("‹ \(parent)").font(.androidWyrm(16)).foregroundColor(ATheme.link)
                            .padding(.horizontal, 6).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Spacer()
                    if let trailing, let onTrailing {
                        Button(action: onTrailing) {
                            Text(trailing).font(.androidWyrm(15.5))
                                .foregroundColor(trailingEnabled ? ATheme.link : ATheme.tabIdle)
                                .padding(.horizontal, 8).padding(.vertical, 8)
                        }.buttonStyle(.plain).disabled(!trailingEnabled)
                    }
                }
                Text(title).font(.androidWyrm(16, .semibold)).foregroundColor(ATheme.ink).lineLimit(1)
                    .padding(.horizontal, 96)
            }
            .frame(height: 40).padding(.horizontal, 14).padding(.bottom, 10)
            .background(ATheme.paper.opacity(0.94))
            if let sectionTabs { sectionTabs }
            Rectangle().fill(ATheme.rule).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        content
                        Spacer().frame(height: 40)
                    }
                }
                .onAppear { reveal(proxy) }
                .onChange(of: focus.pulse) { _ in reveal(proxy) }
            }
        }
        .foregroundColor(ATheme.ink)
        .background(ATheme.paper.ignoresSafeArea())
    }

    /// Settings search opened this page for one setting: once the page has
    /// slid in and any fold holding it has opened, bring it to the middle.
    private func reveal(_ proxy: ScrollViewProxy) {
        guard let target = focus.target else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
        }
        // A row that never showed up (say, a hidden fold) must not stay targeted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { focus.finish(target) }
    }
}

struct WSSectionLabel: View {
    let text: String
    var top: CGFloat = 22
    init(_ text: String, top: CGFloat = 22) { self.text = text; self.top = top }
    var body: some View {
        Text(text.uppercased()).font(.androidWyrm(11.5, .semibold)).tracking(0.92).foregroundColor(ATheme.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, top).padding(.bottom, 8)
    }
}

struct WSCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .padding(.horizontal, 16)
    }
}

struct WSHairline: View {
    var body: some View { Rectangle().fill(ATheme.rowRule).frame(height: 1) }
}

struct WSCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
    }
}

/// `AdvancedFold`: a quiet card that opens a block of rarely touched rows.
struct WSAdvancedFold: View {
    let label: String
    let open: Bool
    let onToggle: () -> Void
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 0) {
                Text(label.uppercased()).font(.androidWyrm(11, .semibold)).tracking(0.78).foregroundColor(ATheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(open ? "HIDE" : "SHOW").font(.androidWyrm(9, .semibold)).tracking(0.7).foregroundColor(ATheme.quiet)
                Spacer().frame(width: 9)
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(open ? ATheme.paper : ATheme.ink)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .frame(width: 30, height: 30)
                    .background(open ? ATheme.ink : ATheme.ink.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(.leading, 15).padding(.trailing, 11).frame(minHeight: 52)
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(open ? ATheme.chevron : ATheme.rowRule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(WSPressStyle())
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.24), value: open)
    }
}

/// The system switch, so iOS 26 gives it the Liquid Glass thumb that lifts
/// while it is held and dragged. Tinted with the theme's live colour.
struct WSInkSwitch: View {
    let on: Bool
    var onToggle: ((Bool) -> Void)? = nil
    var body: some View {
        Toggle("", isOn: Binding(get: { on }, set: { onToggle?($0) }))
            .labelsHidden()
            .tint(ATheme.live)
            .fixedSize()
    }
}

/// Android's `PaperSegmented`, drawn by the system segmented control: at rest
/// a plain thumb, and on iOS 26 a Liquid Glass lens that lifts under the
/// finger, can be dragged across segments and settles with a bounce — the
/// same control the leaderboard uses.
struct WSSegmented: View {
    let options: [String]
    let selected: Int
    var height: CGFloat = 38
    var fontSize: CGFloat = 13.5
    let onSelect: (Int) -> Void

    var body: some View {
        Picker("", selection: Binding(get: { min(max(selected, 0), max(options.count - 1, 0)) },
                                      set: { next in if next != selected { onSelect(next) } })) {
            ForEach(options.indices, id: \.self) { index in Text(options[index]).tag(index) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct WSRowText: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.androidWyrm(15.5)).foregroundColor(ATheme.ink)
            if !detail.isEmpty {
                Text(detail).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WSBoolRow: View {
    let title: String
    var detail = ""
    let on: Bool
    var first = false
    let onToggle: (Bool) -> Void
    var body: some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            HStack(spacing: 12) {
                // The words toggle too, like a settings row; the switch itself
                // stays a live system control so its glass thumb can be dragged.
                WSRowText(title: title, detail: detail).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onToggle(!on) }
                WSInkSwitch(on: on, onToggle: onToggle)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 58)
        }
    }
}

struct WSSliderRow: View {
    let title: String
    let valueText: String
    var detail = ""
    let value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var first = false
    let onChange: (Double) -> Void
    var body: some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    Text(title).font(.androidWyrm(15.5)).foregroundColor(ATheme.ink)
                    Spacer()
                    Text(valueText).font(.androidWyrm(14)).monospacedDigit().foregroundColor(ATheme.mute)
                }
                if !detail.isEmpty {
                    Text(detail).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                slider.tint(ATheme.ink).padding(.top, 4)
            }.padding(14)
        }
    }
    @ViewBuilder private var slider: some View {
        let binding = Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: onChange)
        if let step, step > 0, range.upperBound > range.lowerBound {
            Slider(value: binding, in: range, step: step)
        } else if range.upperBound > range.lowerBound {
            Slider(value: binding, in: range)
        } else {
            Slider(value: .constant(range.lowerBound), in: 0...1).disabled(true)
        }
    }
}

struct WSEnumBlock: View {
    let title: String
    var detail = ""
    let options: [String]
    let selected: Int
    var first = false
    let onSelect: (Int) -> Void
    var body: some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.androidWyrm(15.5)).foregroundColor(ATheme.ink)
                if !detail.isEmpty {
                    Text(detail).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WSSegmented(options: options, selected: selected, onSelect: onSelect).padding(.top, 11)
            }.padding(14)
        }
    }
}

struct WSValueRow: View {
    let title: String
    let value: String
    var first = false
    var onOpen: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            Button { onOpen?() } label: {
                HStack(spacing: 6) {
                    Text(title).font(.androidWyrm(15.5)).foregroundColor(ATheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !value.isEmpty {
                        Text(value).font(.androidWyrm(14)).foregroundColor(ATheme.quiet).multilineTextAlignment(.trailing)
                    }
                    if onOpen != nil { Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron) }
                }
                .padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 54).contentShape(Rectangle())
            }
            .buttonStyle(WSPressStyle()).disabled(onOpen == nil)
        }
    }
}

struct WSActionRow: View {
    let title: String
    var first = false
    var danger = false
    let onClick: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            Button(action: onClick) {
                Text(title).font(.androidWyrm(15.5)).foregroundColor(danger ? ATheme.badge : ATheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(WSPressStyle())
        }
    }
}

struct WSLinkRow: View {
    let title: String
    var value = ""
    var first = false
    let onClick: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            Button(action: onClick) {
                HStack {
                    Text(title).font(.androidWyrm(15.5)).foregroundColor(ATheme.link)
                    Spacer()
                    if !value.isEmpty { Text(value).font(.androidWyrm(14)).foregroundColor(ATheme.quiet) }
                }
                .padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}

struct WSPrimaryButton: View {
    let label: String
    var enabled = true
    let onClick: () -> Void
    var body: some View {
        Button(action: onClick) {
            Text(label).font(.androidWyrm(15.5, .semibold)).foregroundColor(ATheme.onInk)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(enabled ? ATheme.ink : ATheme.ink.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(WSPressStyle()).disabled(!enabled)
    }
}

struct WSOutlineButton: View {
    let label: String
    var enabled = true
    let onClick: () -> Void
    var body: some View {
        Button(action: onClick) {
            Text(label).font(.androidWyrm(15)).foregroundColor(enabled ? ATheme.mute : ATheme.tabIdle)
                .frame(maxWidth: .infinity).frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(WSPressStyle()).disabled(!enabled)
    }
}

/// Radio mark used by Food shapes and Themes.
struct WSRadio: View {
    let selected: Bool
    var body: some View {
        ZStack {
            Circle().stroke(selected ? ATheme.ink : ATheme.chevron, lineWidth: 1.5)
            if selected { Circle().fill(ATheme.ink).frame(width: 12, height: 12) }
        }.frame(width: 22, height: 22)
    }
}

// MARK: - Colour

/// Hue first, then strength and brightness, exactly as the Android mixer.
struct WSColourRow: View {
    let setting: EngineSetting
    var first = false
    @ObservedObject var engine: WyrmShellStore
    @State var open = false
    @State var hsv: (h: Double, s: Double, v: Double) = (0, 0, 1)
    @State var alpha = 1.0
    @State var dragging = false

    var body: some View {
        let c = setting.channels
        VStack(spacing: 0) {
            if !first { WSHairline() }
            Button { withAnimation(.easeInOut(duration: 0.25)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    WSRowText(title: setting.label, detail: setting.hint).frame(maxWidth: .infinity, alignment: .leading)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: 1))
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                    Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 54).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    WSGradientTrack(fraction: hsv.h / 360,
                                    colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) },
                                    dragging: $dragging) { hsv.h = $0 * 360; emit() }
                    shade("Strength", hsv.s, [Color(hue: hsv.h / 360, saturation: 0, brightness: hsv.v),
                                              Color(hue: hsv.h / 360, saturation: 1, brightness: hsv.v)]) { hsv.s = $0; emit() }
                    shade("Brightness", hsv.v, [.black, Color(hue: hsv.h / 360, saturation: hsv.s, brightness: 1)]) { hsv.v = $0; emit() }
                    if setting.type == "color4" {
                        shade("Opacity", alpha, [Color.clear, Color(hue: hsv.h / 360, saturation: hsv.s, brightness: hsv.v)]) { alpha = $0; emit() }
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear(perform: sync)
        .onChange(of: setting.values) { _ in if !dragging { sync() } }
    }

    private func shade(_ label: String, _ value: Double, _ colors: [Color], _ pick: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.androidWyrm(11.5, .semibold)).tracking(0.6).foregroundColor(ATheme.quiet)
            WSGradientTrack(fraction: value, colors: colors, dragging: $dragging, onPick: pick)
        }
    }

    private func sync() {
        let c = setting.channels
        let next = Self.rgbToHsv(c[0], c[1], c[2])
        // Grey and black have no hue; keep the one the player last chose.
        hsv = (next.s < 0.001 || next.v < 0.001 ? hsv.h : next.h, next.s, next.v)
        alpha = c[3]
    }

    private func emit() {
        let rgb = Self.hsvToRgb(hsv.h, hsv.s, hsv.v)
        engine.write(setting, values: setting.type == "color4" ? [rgb.0, rgb.1, rgb.2, alpha] : [rgb.0, rgb.1, rgb.2])
    }

    static func rgbToHsv(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = 60 * ((b - r) / delta + 2) }
            else { h = 60 * ((r - g) / delta + 4) }
        }
        if h < 0 { h += 360 }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    static func hsvToRgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s, hp = (h.truncatingRemainder(dividingBy: 360)) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch hp {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        // Android packs through 8-bit ARGB; matching it keeps echoes identical.
        func q(_ value: Double) -> Double { (min(1, max(0, value + m)) * 255).rounded() / 255 }
        return (q(r), q(g), q(b))
    }
}

struct WSGradientTrack: View {
    let fraction: Double
    let colors: [Color]
    @Binding var dragging: Bool
    let onPick: (Double) -> Void
    var body: some View {
        GeometryReader { proxy in
            let knob: CGFloat = 20
            let run = max(proxy.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().stroke(ATheme.rule, lineWidth: 1))
                Circle().fill(ATheme.ink).frame(width: knob, height: knob)
                    .overlay(Circle().stroke(ATheme.card, lineWidth: 2))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: run * CGFloat(min(max(fraction, 0), 1)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragging = true
                    onPick(Double(min(max((value.location.x - knob / 2) / run, 0), 1)))
                }
                .onEnded { _ in dragging = false })
        }
        .frame(height: 22)
    }
}

// MARK: - Engine rows

/// `SettingTypedRow`: picks the control that suits the shape of the value.
struct WSTypedRow: View {
    let setting: EngineSetting
    var first = false
    @ObservedObject var engine: WyrmShellStore
    var body: some View { row.wyrmSettingAnchor(setting.id) }

    @ViewBuilder private var row: some View {
        switch setting.type {
        case "bool":
            WSBoolRow(title: setting.label, detail: setting.hint, on: setting.enabled, first: first) {
                engine.write(setting, values: [$0 ? 1 : 0])
            }
        case "enum":
            WSEnumBlock(title: setting.label, detail: setting.hint, options: setting.options,
                        selected: min(max(setting.index, 0), max(setting.options.count - 1, 0)), first: first) {
                engine.write(setting, values: [Double($0)])
            }
        case "color3", "color4":
            WSColourRow(setting: setting, first: first, engine: engine)
        default:
            let whole = setting.type == "int"
            WSSliderRow(title: setting.label, valueText: wsFormat(setting), detail: setting.hint,
                        value: setting.number, range: setting.minimum...max(setting.minimum, setting.maximum),
                        step: whole ? 1 : nil, first: first) { raw in
                engine.write(setting, values: [whole ? raw.rounded() : raw])
            }
        }
    }
}

/// A block of engine rows, each drawn by type with hairlines between them.
struct WSRows: View {
    let rows: [EngineSetting]
    @ObservedObject var engine: WyrmShellStore
    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            WSTypedRow(setting: row, first: index == 0, engine: engine)
        }
    }
}

func wsFormat(_ setting: EngineSetting) -> String {
    switch setting.type {
    case "bool": return setting.enabled ? "On" : "Off"
    case "enum": return setting.options.indices.contains(setting.index) ? setting.options[setting.index] : ""
    case "int": return "\(Int(setting.number.rounded()))"
    case "float": return setting.id == "general.death_hold"
        ? String(format: "%.2f s", setting.number) : String(format: "%.2f", setting.number)
    default: return ""
    }
}
