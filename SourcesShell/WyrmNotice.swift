import Foundation
import SwiftUI

/// The developer's notice (OM, 2026-10-25; backend notices.mjs): one popup in the middle of the
/// screen when Wyrm starts. Android twin: data/Notices.kt and ui/NoticePopup.kt.
///
/// Asked once per start (`GET /v1/notice`, no account needed). Per notice id this phone keeps
/// how many starts showed it and whether the player chose "Don't show again": the first start
/// shows OK only, every later start shows "Don't show again" too, and once that is ticked the
/// notice never shows again. A new notice has a new id, so it starts over. Defaults under
/// `wyrm.ios.notice.`, phone only (kept by WyrmAccountSync: a log out does not bring a dismissed
/// notice back).
struct WyrmAppNotice: Equatable {
    let id: String
    let kind: String
    let label: String
    let title: String
    let markdown: String
    /// The Observatory builder's layout (2026-10-30); empty = the Markdown message.
    var blocks: [WyrmNoticeBlock] = []

    /// The small line above the heading.
    var kicker: String {
        switch kind {
        case "developer": return "FROM THE DEVELOPER"
        case "message": return "MESSAGE"
        case "update": return "UPDATE"
        case "custom": return label.isEmpty ? "NOTICE" : label.uppercased()
        default: return "NOTICE"
        }
    }
}

final class WyrmNoticeCenter: ObservableObject {
    static let shared = WyrmNoticeCenter()
    private static let url = URL(string: "https://wyrm-api.165-99-223-123.sslip.io/v1/notice")!
    // The single-notice keys of 2026-10-25, still read for the notice they named.
    private static let keyID = "wyrm.ios.notice.id"
    private static let keyShown = "wyrm.ios.notice.shown"
    private static let keyNever = "wyrm.ios.notice.never"
    private static func shownKey(_ id: String) -> String { "wyrm.ios.notice.n.\(id).shown" }
    private static func neverKey(_ id: String) -> String { "wyrm.ios.notice.n.\(id).never" }

    /// The notice on screen now, or nil.
    @Published private(set) var shown: WyrmAppNotice?
    /// From the second start: "Don't show again" is offered.
    @Published private(set) var offerNeverAgain = false
    /// "2 of 3" when several notices are live (OM, 2026-10-30), else empty.
    @Published private(set) var position = ""
    private var asked = false
    /// Several notices can be live at once (2026-10-30): the ones this start still shows.
    private var queue: [WyrmAppNotice] = []
    private var index = 0

    private func shownCount(_ id: String) -> Int {
        let d = UserDefaults.standard
        if d.object(forKey: Self.shownKey(id)) != nil { return d.integer(forKey: Self.shownKey(id)) }
        return d.string(forKey: Self.keyID) == id ? d.integer(forKey: Self.keyShown) : 0
    }
    private func isNever(_ id: String) -> Bool {
        let d = UserDefaults.standard
        if d.object(forKey: Self.neverKey(id)) != nil { return d.bool(forKey: Self.neverKey(id)) }
        return d.string(forKey: Self.keyID) == id && d.bool(forKey: Self.keyNever)
    }

    private static func notice(_ raw: [String: Any]) -> WyrmAppNotice? {
        guard let id = raw["id"] as? String, !id.isEmpty else { return nil }
        return WyrmAppNotice(id: id, kind: raw["kind"] as? String ?? "notice",
                             label: raw["label"] as? String ?? "",
                             title: raw["title"] as? String ?? "",
                             markdown: raw["markdown"] as? String ?? "",
                             blocks: (raw["blocks"] as? [[String: Any]] ?? []).compactMap(WyrmNoticeBlock.from))
    }

    /// Once per start.
    func check() {
        guard !asked else { return }
        asked = true
        var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let all: [WyrmAppNotice]
            if let list = root["notices"] as? [[String: Any]] { all = list.compactMap(Self.notice) }
            else if let one = root["notice"] as? [String: Any], let n = Self.notice(one) { all = [n] }
            else { all = [] }
            DispatchQueue.main.async { WyrmNoticeCenter.shared.offer(all) }
        }.resume()
    }

    private func offer(_ notices: [WyrmAppNotice]) {
        queue = notices.filter { !isNever($0.id) }
        index = 0
        showNext()
    }

    private func showNext() {
        guard index < queue.count else { shown = nil; position = ""; return }
        let notice = queue[index]
        offerNeverAgain = shownCount(notice.id) >= 1
        position = queue.count > 1 ? "\(index + 1) of \(queue.count)" : ""
        withAnimation(.easeOut(duration: 0.22)) { shown = notice }
    }

    /// OK: counts this start; with `never` ticked the notice is done for good. Then the next one.
    func close(never: Bool) {
        guard let notice = shown else { return }
        let d = UserDefaults.standard
        d.set(shownCount(notice.id) + 1, forKey: Self.shownKey(notice.id))
        d.set(never && offerNeverAgain, forKey: Self.neverKey(notice.id))
        withAnimation(.easeIn(duration: 0.18)) { shown = nil }
        index += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { self.showNext() }
    }
}

/// The card in the middle of the screen: two thirds of its height, in the app's theme, the
/// message in full Markdown and scrolling when it is long.
struct WyrmNoticeHost: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var center = WyrmNoticeCenter.shared
    @State private var never = false

    var body: some View {
        if let notice = center.shown {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .contentShape(Rectangle()).onTapGesture {}
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(notice.kicker).font(.androidWyrm(11, .bold)).tracking(1.4).foregroundColor(wyrmScopedColours.mute)
                            Spacer()
                            if !center.position.isEmpty {
                                Text(center.position).font(.androidWyrm(11, .regular)).foregroundColor(wyrmScopedColours.quiet)
                            }
                        }
                        if !notice.title.isEmpty {
                            // The heading is Markdown too (OM, 2026-10-30); plain words keep the old look.
                            if notice.title.contains(where: { "*_`[]#!~<>".contains($0) }) {
                                WyrmMarkdown(source: notice.title, size: 21, ink: wyrmScopedColours.ink, images: true)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            } else {
                                Text(notice.title).font(.androidWyrm(24, .bold)).foregroundColor(wyrmScopedColours.ink)
                                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                            }
                        }
                        ScrollView(showsIndicators: true) {
                            // The builder's layout when the notice has one (OM, 2026-10-30), else its
                            // Markdown; pictures show in both, at the width the Observatory set.
                            if !notice.blocks.isEmpty {
                                WyrmNoticeBlocksView(blocks: notice.blocks)
                            } else if !notice.markdown.isEmpty {
                                WyrmMarkdown(source: notice.markdown, size: 14, ink: wyrmScopedColours.ink, images: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 12)
                        if center.offerNeverAgain {
                            Button { never.toggle() } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(never ? wyrmScopedColours.ink : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(never ? wyrmScopedColours.ink : wyrmScopedColours.quiet, lineWidth: 1.5))
                                        .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                            .foregroundColor(wyrmScopedColours.onInk).opacity(never ? 1 : 0))
                                        .frame(width: 22, height: 22)
                                    Text("Don't show again").font(.androidWyrm(14, .semibold)).foregroundColor(wyrmScopedColours.ink)
                                    Spacer()
                                }
                                .padding(.vertical, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 10)
                        }
                        WSPrimaryButton(label: "OK") { center.close(never: never) }
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 18)
                    .frame(width: min(geo.size.width * 0.88, 520), height: geo.size.height * 2 / 3)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(wyrmScopedColours.card))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(wyrmScopedColours.rule, lineWidth: 1))
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onChange(of: notice.id) { _ in never = false }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(notice.kicker)
        }
    }
}
