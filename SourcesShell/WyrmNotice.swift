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
    private static let url = URL(string: "https://wyrm-api.77-245-76-86.sslip.io/v1/notice")!
    private static let keyID = "wyrm.ios.notice.id"
    private static let keyShown = "wyrm.ios.notice.shown"
    private static let keyNever = "wyrm.ios.notice.never"

    /// The notice on screen now, or nil.
    @Published private(set) var shown: WyrmAppNotice?
    /// From the second start: "Don't show again" is offered.
    @Published private(set) var offerNeverAgain = false
    private var asked = false

    /// Once per start.
    func check() {
        guard !asked else { return }
        asked = true
        var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = root["notice"] as? [String: Any],
                  let id = raw["id"] as? String, !id.isEmpty else { return }
            let notice = WyrmAppNotice(id: id, kind: raw["kind"] as? String ?? "notice",
                                       label: raw["label"] as? String ?? "",
                                       title: raw["title"] as? String ?? "",
                                       markdown: raw["markdown"] as? String ?? "")
            DispatchQueue.main.async { WyrmNoticeCenter.shared.offer(notice) }
        }.resume()
    }

    private func offer(_ notice: WyrmAppNotice) {
        let d = UserDefaults.standard
        if d.string(forKey: Self.keyID) != notice.id {
            d.set(notice.id, forKey: Self.keyID)
            d.set(0, forKey: Self.keyShown)
            d.set(false, forKey: Self.keyNever)
        }
        guard !d.bool(forKey: Self.keyNever) else { return }
        offerNeverAgain = d.integer(forKey: Self.keyShown) >= 1
        withAnimation(.easeOut(duration: 0.22)) { shown = notice }
    }

    /// OK: counts this start; with `never` ticked the notice is done for good.
    func close(never: Bool) {
        guard let notice = shown else { return }
        let d = UserDefaults.standard
        if d.string(forKey: Self.keyID) == notice.id {
            d.set(d.integer(forKey: Self.keyShown) + 1, forKey: Self.keyShown)
            d.set(never && offerNeverAgain, forKey: Self.keyNever)
        }
        withAnimation(.easeIn(duration: 0.18)) { shown = nil }
    }
}

/// The card in the middle of the screen: two thirds of its height, in the app's theme, the
/// message in full Markdown and scrolling when it is long.
struct WyrmNoticeHost: View {
    @ObservedObject var center = WyrmNoticeCenter.shared
    @State private var never = false

    var body: some View {
        if let notice = center.shown {
            GeometryReader { geo in
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .contentShape(Rectangle()).onTapGesture {}
                    VStack(alignment: .leading, spacing: 0) {
                        Text(notice.kicker).font(.androidWyrm(11, .bold)).tracking(1.4).foregroundColor(ATheme.mute)
                        if !notice.title.isEmpty {
                            Text(notice.title).font(.androidWyrm(24, .bold)).foregroundColor(ATheme.ink)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                        }
                        ScrollView(showsIndicators: true) {
                            if !notice.markdown.isEmpty {
                                WyrmMarkdown(source: notice.markdown, size: 14, ink: ATheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 12)
                        if center.offerNeverAgain {
                            Button { never.toggle() } label: {
                                HStack(spacing: 10) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(never ? ATheme.ink : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(never ? ATheme.ink : ATheme.quiet, lineWidth: 1.5))
                                        .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                            .foregroundColor(ATheme.onInk).opacity(never ? 1 : 0))
                                        .frame(width: 22, height: 22)
                                    Text("Don't show again").font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.ink)
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
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ATheme.card))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
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
