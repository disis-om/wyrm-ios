import SwiftUI
import UIKit

/*
 * Wyrm in the player's language (OM, 2026-10-31). Twin of Wyrm Android's
 * i18n/WyrmLanguage.kt, with the same words: Scripts/generate-localizations.py
 * turns Android's tables into Resources/Localization/<code>.lproj.
 *
 * - SwiftUI finds a `Text("...")` literal in those tables by itself; the shared
 *   design pieces look their String titles up through `Text(wyrm:)`.
 * - The language is "auto" (the phone's) or a code: `wyrm.ios.language.choice`
 *   (account sync, platform document). A pick shows at once (the root's
 *   environment locale) and is also kept as the app's own language for later
 *   starts (AppleLanguages), so everything follows after a restart too.
 * - The one-time "Choose your language" sheet: `wyrm.ios.language-prompt.shown`
 *   (kept on this phone, never again, logged out or not).
 */
final class WyrmLanguage: ObservableObject {
    static let shared = WyrmLanguage()
    static let auto = "auto"
    private static let choiceKey = "wyrm.ios.language.choice"
    private static let promptKey = "wyrm.ios.language-prompt.shown"
    /// The phone's own languages, last seen on Auto (this phone only).
    private static let phoneKey = "wyrm.ios.language-prompt.phone"

    struct Choice: Identifiable, Equatable {
        let code: String
        let name: String
        var id: String { code }
    }

    /// Every language Wyrm has a table for, in the order the list shows them.
    let choices: [Choice]
    /// "auto" or a code.
    @Published private(set) var chosen: String
    /// The phone's own languages, read before Wyrm sets its own.
    private var phoneLanguages: [String]
    private var observer: NSObjectProtocol?

    private init() {
        if let url = Bundle.main.url(forResource: "WyrmLanguages", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            choices = rows.compactMap { row in
                guard let code = row["code"] as? String, let name = row["name"] as? String else { return nil }
                return Choice(code: code, name: name)
            }
        } else {
            choices = []
        }
        let stored = UserDefaults.standard.string(forKey: Self.choiceKey) ?? Self.auto
        chosen = stored
        // On Auto the preferred list is the phone's own, and it is kept; with a
        // pick in place Wyrm's own AppleLanguages hides it, so the kept copy is used.
        if stored == Self.auto {
            let preferred = Locale.preferredLanguages
            phoneLanguages = preferred
            UserDefaults.standard.set(preferred, forKey: Self.phoneKey)
        } else {
            phoneLanguages = UserDefaults.standard.stringArray(forKey: Self.phoneKey) ?? Locale.preferredLanguages
        }
        // An account restore writes the choice: the shown language follows it.
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let stored = UserDefaults.standard.string(forKey: Self.choiceKey) ?? Self.auto
            if stored != self.chosen { self.apply(stored, save: false) }
        }
    }

    /// The language shown now ("en" for English).
    var active: String {
        if chosen == Self.auto { return phoneLanguage }
        return chosen == "en" || choices.contains(where: { $0.code == chosen }) ? chosen : "en"
    }

    var locale: Locale { Locale(identifier: active) }

    /// The shown language's string table (the app's own for English).
    var bundle: Bundle {
        if active == "en" { return .main }
        if let cached = bundleCache, cached.code == active { return cached.bundle }
        let found = Bundle.main.path(forResource: active, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        bundleCache = (active, found)
        return found
    }
    private var bundleCache: (code: String, bundle: Bundle)?

    /// What "Auto" means on this phone, as a code ("en" when Wyrm has none for it).
    var phoneLanguage: String {
        let have = Set(choices.map(\.code))
        for raw in phoneLanguages {
            let parts = raw.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
            guard let lang = parts.first?.lowercased() else { continue }
            var code = lang
            if lang == "pt" { code = "pt-BR" }
            else if lang == "zh" {
                code = parts.contains("Hant") || parts.contains("TW") || parts.contains("HK") || parts.contains("MO") ? "zh-Hant" : "zh-Hans"
            } else if lang == "tl" { code = "fil" }
            else if lang == "in" { code = "id" }
            if code == "en" { return "en" }
            if have.contains(code) { return code }
        }
        return "en"
    }

    func name(of code: String) -> String {
        code == "en" ? "English" : choices.first(where: { $0.code == code })?.name ?? code
    }

    /// The player picked `code` ("auto", "en" or one of `choices`).
    func choose(_ code: String) { apply(code, save: true) }

    private func apply(_ code: String, save: Bool) {
        chosen = code
        if save { UserDefaults.standard.set(code, forKey: Self.choiceKey) }
        if code == Self.auto {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    // MARK: the one-time sheet

    var promptOwed: Bool { !UserDefaults.standard.bool(forKey: Self.promptKey) }

    /// Shown once: never again on this phone (written as it opens).
    func promptShown() { UserDefaults.standard.set(true, forKey: Self.promptKey) }
}

/// A String in the player's language when the tables have it (for text that is
/// changed afterwards, such as upper-case labels), else as it is.
func wyrmLocalized(_ text: String) -> String {
    WyrmLanguage.shared.bundle.localizedString(forKey: text, value: text, table: nil)
}

extension Text {
    /// A title or line handed over as a String, in the player's language when
    /// the tables have it, else as it is (OM, 2026-10-31).
    init(wyrm text: String) {
        // A % would be read as a format: such text ("80%") is shown as it is.
        if text.contains("%") {
            self.init(verbatim: text)
        } else {
            self.init(LocalizedStringKey(text))
        }
    }
}

/// Auto first, then English, then every language in its own words.
private struct WyrmLanguageRows: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var language = WyrmLanguage.shared

    var body: some View {
        VStack(spacing: 6) {
            row(title: nil, code: WyrmLanguage.auto, icon: "iphone")
            row(title: "English", code: "en", icon: nil)
            ForEach(language.choices) { choice in
                row(title: choice.name, code: choice.code, icon: nil)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func row(title: String?, code: String, icon: String?) -> some View {
        let selected = language.chosen == code
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.18)) { language.choose(code) }
        } label: {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(wyrmScopedColours.ink)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(wyrmScopedColours.well))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        // A language's own name is never translated: it is how its speakers find it.
                        Text(verbatim: title).font(.androidWyrm(16, .bold)).foregroundColor(wyrmScopedColours.ink)
                    } else {
                        Text("Auto").font(.androidWyrm(16, .bold)).foregroundColor(wyrmScopedColours.ink)
                        Text("Same as your phone · \(language.name(of: language.phoneLanguage))")
                            .font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet)
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(wyrmScopedColours.rule, lineWidth: selected ? 0 : 1.5)
                    if selected {
                        Circle().fill(wyrmScopedColours.ink)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(wyrmScopedColours.onInk)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? wyrmScopedColours.ink : wyrmScopedColours.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? wyrmScopedColours.ink : wyrmScopedColours.rule, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Settings › Language.
struct WyrmLanguagePage: View {
    let close: () -> Void

    var body: some View {
        WyrmDetailChrome(title: "Language", onBack: close) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    WSCaption("Auto uses your phone's language. Pick one to keep Wyrm in it.")
                    WyrmLanguageRows()
                    WSCaption("Names, chat messages and the arena stay as players wrote them.")
                    Spacer().frame(height: 32)
                }
            }
        }
    }
}

/// The one-time sheet (OM, 2026-10-31): after an update, on a quiet Home. The
/// choice shows at once as the player taps; Continue closes it for good.
struct WyrmLanguagePrompt: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let onDone: () -> Void
    @State private var arrived = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(arrived ? 0.55 : 0).ignoresSafeArea()
                .onTapGesture {}
            if arrived {
                VStack(spacing: 0) {
                    Capsule().fill(wyrmScopedColours.chevron).frame(width: 38, height: 4).padding(.top, 9)
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(wyrmScopedColours.ink)
                            Image(systemName: "character.bubble").font(.system(size: 26, weight: .semibold)).foregroundColor(wyrmScopedColours.onInk)
                        }
                        .frame(width: 58, height: 58)
                        .padding(.bottom, 6)
                        Text("Choose your language").font(.wyrmDisplay(27)).foregroundColor(wyrmScopedColours.ink).multilineTextAlignment(.center)
                        Text("Wyrm now speaks your language. Auto follows your phone.")
                            .font(.androidWyrm(13.5)).foregroundColor(wyrmScopedColours.quiet).multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 20).padding(.bottom, 10)
                    ScrollView(showsIndicators: false) {
                        WyrmLanguageRows().padding(.vertical, 6)
                    }
                    VStack(spacing: 10) {
                        Text("You can change this later in Settings › Language.")
                            .font(.androidWyrm(12.5)).foregroundColor(wyrmScopedColours.quiet).multilineTextAlignment(.center)
                        Button {
                            withAnimation(.easeIn(duration: 0.3)) { arrived = false }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onDone() }
                        } label: {
                            Text("Continue").font(.androidWyrm(15, .bold)).foregroundColor(wyrmScopedColours.onInk)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(Capsule().fill(wyrmScopedColours.ink))
                        }
                        .buttonStyle(WSPressStyle())
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 18)
                }
                .frame(maxWidth: 560)
                .frame(maxHeight: UIScreen.main.bounds.height * 0.86)
                .background(
                    UnevenRoundedTop(radius: 26).fill(wyrmScopedColours.paper).ignoresSafeArea(edges: .bottom)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundColor(wyrmScopedColours.ink)
        .onAppear { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { arrived = true } }
    }
}

/// Rounded on the top corners only (iOS 15 has no UnevenRoundedRectangle).
private struct UnevenRoundedTop: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
