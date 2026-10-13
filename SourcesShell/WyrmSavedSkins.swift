import SwiftUI
import UIKit

/*
 * Saved skins (OM, 2026-10-13; iOS 2026-10-13). Android twin: `SavedSkins`
 * in ui/IosSkinScreen.kt, the same rules and the same stored text.
 *
 * Every custom skin a match is started with is kept here, newest first
 * (playing one again moves it to the top), up to 40. Tap one to wear it;
 * touch and hold to select, then Edit (one) or Delete from the top bar. A
 * Studio skin's one black bead is never kept. Saved under
 * `wyrm.ios.skin.saved-skins` (a `wyrm.ios.skin.` key: synced with the
 * account, platform document): one skin a line, `code<TAB>colours` with the
 * colours as hex.
 */

struct WyrmSavedSkin: Equatable {
    let code: String
    let colors: [UInt32]
    var key: String { code + "|" + colors.map { String($0) }.joined(separator: ",") }
    var groups: [Int] { code.compactMap { WyrmSkinCatalog.group(for: $0) } }
}

@MainActor
final class WyrmSavedSkins: ObservableObject {
    static let shared = WyrmSavedSkins()
    static let storageKey = "wyrm.ios.skin.saved-skins"
    private static let maxCount = 40

    @Published private(set) var list: [WyrmSavedSkin] = []

    private init() { load() }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync).
    func reloadFromDefaults() { load() }

    /// A match starts: the custom skin worn now is kept (not a Studio skin's black bead).
    func recordWorn() {
        let d = UserDefaults.standard
        guard d.bool(forKey: "wyrm.ios.skin.custom-enabled"), WyrmStudio.shared.worn == nil else { return }
        let groups = Array((d.string(forKey: "wyrm.ios.skin.custom-groups") ?? "").split(separator: ",")
            .compactMap { Int($0) }.filter { WyrmSkinCatalog.validGroups.contains($0) }.prefix(256))
        guard !groups.isEmpty else { return }
        let code = WyrmSkinCatalog.code(for: groups)
        guard code != WyrmStudio.arenaCode else { return }
        let stored = (d.string(forKey: "wyrm.ios.skin.custom-colors") ?? "").split(separator: ",", omittingEmptySubsequences: false)
            .map { UInt32($0, radix: 16) ?? 0 }
        record(code: code, colors: groups.indices.map { $0 < stored.count ? stored[$0] : 0 })
    }

    func record(code: String, colors: [UInt32]) {
        guard !code.isEmpty else { return }
        let saved = WyrmSavedSkin(code: code, colors: (0..<code.count).map { $0 < colors.count ? colors[$0] : 0 })
        list = Array(([saved] + list.filter { $0.key != saved.key }).prefix(Self.maxCount))
        save()
    }

    func delete(_ keys: Set<String>) {
        list.removeAll { keys.contains($0.key) }
        save()
    }

    private func load() {
        let text = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        var seen = Set<String>()
        list = text.split(separator: "\n").compactMap { line -> WyrmSavedSkin? in
            guard let tab = line.firstIndex(of: "\t"), tab != line.startIndex else { return nil }
            let code = String(line[..<tab])
            guard code.allSatisfy({ WyrmSkinCatalog.group(for: $0) != nil }) else { return nil }
            let colours = line[line.index(after: tab)...].split(separator: ",", omittingEmptySubsequences: false)
                .map { UInt32($0, radix: 16) ?? 0 }
            let saved = WyrmSavedSkin(code: code, colors: (0..<code.count).map { $0 < colours.count ? colours[$0] : 0 })
            guard seen.insert(saved.key).inserted else { return nil }
            return saved
        }
        if list.count > Self.maxCount { list = Array(list.prefix(Self.maxCount)) }
    }

    private func save() {
        let text = list.map { s in s.code + "\t" + s.colors.map { String($0, radix: 16) }.joined(separator: ",") }
            .joined(separator: "\n")
        UserDefaults.standard.set(text, forKey: Self.storageKey)
    }
}

/// The top bar while saved skins are selected (Gmail-style): close, the count, Edit (one), Delete.
struct WyrmSavedSelectionBar: View {
    let count: Int
    let onClose: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Text("✕").font(.androidWyrm(15, .bold)).foregroundColor(ATheme.ink)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(ATheme.card))
                    .overlay(Circle().stroke(ATheme.rule, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(WSPressStyle())
            .accessibilityLabel("Close selection")
            Spacer().frame(width: 12)
            Text("\(count) selected").font(.androidWyrm(22, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
            Spacer(minLength: 8)
            if let onEdit {
                action("Edit", ATheme.ink, onEdit)
                Spacer().frame(width: 8)
            }
            action("Delete", ATheme.badge, onDelete)
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.top, 6).padding(.bottom, 14)
        .background(ATheme.paper)
    }

    private func action(_ label: String, _ colour: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(.androidWyrm(13, .bold)).foregroundColor(colour)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(ATheme.card))
                .overlay(Capsule().stroke(ATheme.rule, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(WSPressStyle())
    }
}

/// The saved skins, two to a row, each its own snake; tap / touch and hold.
struct WyrmSavedSkinsBlock: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    @ObservedObject private var saved = WyrmSavedSkins.shared
    let selected: Set<String>
    let onTap: (WyrmSavedSkin) -> Void
    let onLongPress: (WyrmSavedSkin) -> Void

    var body: some View {
        if saved.list.isEmpty {
            Text("Play with a custom skin and it is saved here.").font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 4)
        } else {
            VStack(spacing: 0) {
                Text(selected.isEmpty ? "Tap a skin to wear it. Touch and hold a skin to select it."
                                      : "Tap more skins to select them. Edit works on one skin.")
                    .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 8)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(saved.list, id: \.key) { skin in
                        let chosen = selected.contains(skin.key)
                        WyrmSavedSkinStrip(textures: textures, skin: skin)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .aspectRatio(3.4, contentMode: .fit)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(chosen ? ATheme.ink.opacity(0.08) : ATheme.card.opacity(0.92)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(chosen ? ATheme.ink : ATheme.rule, lineWidth: chosen ? 2 : 1))
                            .overlay(alignment: .topTrailing) {
                                if chosen {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold))
                                        .foregroundColor(ATheme.ink).padding(6)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture { onTap(skin) }
                            .onLongPressGesture(minimumDuration: 0.45) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onLongPress(skin)
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// One saved skin laid out as a straight snake, head on the right, in its own colours.
private struct WyrmSavedSkinStrip: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let skin: WyrmSavedSkin

    var body: some View {
        let groups = skin.groups
        let colors = skin.colors
        return Canvas { context, size in
            guard !groups.isEmpty, textures.ready else { return }
            let bead = size.height * 0.86
            let step = bead * (8.0 / 48.0)
            let count = min(max(Int((size.width - bead) / step), 1), 128)
            for i in 0..<count {
                let codeIndex = (count - 1 - i) % groups.count
                let group = groups[codeIndex]
                let rgba = codeIndex < colors.count ? colors[codeIndex] : 0
                let air = WyrmAirSkin.kind(of: rgba)
                let wyrm = WyrmBead.kind(of: rgba)
                guard let image = wyrm.flatMap({ textures.wyrmBeads[$0] })
                        ?? air.flatMap({ textures.airBeads[$0] })
                        ?? textures.beads[rgba == 0 ? group : 40] else { continue }
                var inked = context
                if let wyrm {
                    if WyrmBead.tinted[wyrm] { inked.addFilter(.colorMultiply(Color(studio: rgba))) }
                } else if air != nil {
                    inked.addFilter(.colorMultiply(Color(studio: WyrmAirSkin.bodyTint(rgba))))
                } else if rgba != 0 {
                    inked.addFilter(.colorMultiply(Color(studio: rgba)))
                }
                inked.draw(Image(decorative: image, scale: 1),
                           in: CGRect(x: CGFloat(i) * step, y: (size.height - bead) / 2, width: bead, height: bead))
            }
        }
    }
}
