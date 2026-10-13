import SwiftUI

/// Wyrm skins (OM, 2026-10-13): creatures and strip looks the engine draws
/// over a snake instead of its beads (game/wyrm_skins.c). The number is what
/// travels; never renumber, only append. Pictures: Resources/WyrmSkins.webp
/// (Wyrm Android tools/wyrm-skins/make.py), one cell per skin in `all`'s order.
///
/// The worn skin is the engine setting `skin.wyrm` (0 = none), so it is saved
/// with the engine's settings and goes to the account (shared key `wyrmSkin`).
/// While one is worn the arena gets no tag and no accessory: the skin's number
/// rides where a tag would. Same list as Android's WyrmSkins.kt.
struct WyrmSkinItem: Identifiable, Equatable {
    let number: Int
    let name: String
    var id: Int { number }
    var strip: Bool { number > 100 }
}

enum WyrmSkins {
    static let sheetColumns = 6
    static let sheetRows = 7
    static let setting = "skin.wyrm"

    static let creatures: [WyrmSkinItem] = [
        .init(number: 1, name: "Centipede"), .init(number: 2, name: "Dragon"), .init(number: 3, name: "Skeleton"),
        .init(number: 4, name: "Chinese Dragon"), .init(number: 5, name: "Electric Eel"), .init(number: 6, name: "Train"),
        .init(number: 7, name: "Robot Snake"), .init(number: 8, name: "Phoenix"), .init(number: 9, name: "Ice Serpent"),
        .init(number: 10, name: "Caterpillar"), .init(number: 11, name: "Zombie Snake"), .init(number: 12, name: "Cyclops"),
        .init(number: 13, name: "Evil Eye"), .init(number: 14, name: "Argus"), .init(number: 15, name: "Spider Eyes"),
        .init(number: 16, name: "Mega Eye"), .init(number: 17, name: "Bean"), .init(number: 18, name: "Owl"),
        .init(number: 19, name: "Third Eye"), .init(number: 20, name: "Snail"), .init(number: 21, name: "Mantis"),
        .init(number: 22, name: "Eyeball Chain"), .init(number: 23, name: "Jelly"),
    ]
    static let strips: [WyrmSkinItem] = [
        .init(number: 101, name: "Strip"), .init(number: 102, name: "Neon Strip"), .init(number: 103, name: "Glass Strip"),
        .init(number: 104, name: "Outline Strip"), .init(number: 105, name: "Pixel Strip"), .init(number: 106, name: "Rainbow Strip"),
        .init(number: 107, name: "Candy Strip"), .init(number: 108, name: "Tube Strip"), .init(number: 109, name: "Chrome Strip"),
        .init(number: 110, name: "Lava Strip"), .init(number: 111, name: "Ice Strip"), .init(number: 112, name: "Galaxy Strip"),
        .init(number: 113, name: "Ghost Strip"), .init(number: 114, name: "Bead Strip"), .init(number: 115, name: "Zigzag Strip"),
    ]
    /// The sheet's order.
    static let all = creatures + strips

    static func item(_ number: Int) -> WyrmSkinItem? { all.first { $0.number == number } }

    /// Each skin's picture, cut from the sheet, by number.
    static func pictures(_ sheet: CGImage) -> [Int: CGImage] {
        let cw = sheet.width / sheetColumns, ch = sheet.height / sheetRows
        var out: [Int: CGImage] = [:]
        for (cell, skin) in all.enumerated() {
            let rect = CGRect(x: (cell % sheetColumns) * cw, y: (cell / sheetColumns) * ch, width: cw, height: ch)
            if let part = sheet.cropping(to: rect) { out[skin.number] = part }
        }
        return out
    }
}

/// The worn skin's picture, filling the Skin page's preview.
struct WyrmSkinPicture: View {
    let image: CGImage?
    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One picker tile: the skin's picture and its name.
struct WyrmSkinTile: View {
    let selected: Bool
    let label: String
    let image: CGImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    } else {
                        Text("NONE").font(.androidWyrm(9, .bold)).tracking(0.7).foregroundColor(ATheme.ink)
                    }
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold))
                            .foregroundColor(ATheme.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(label).font(.androidWyrm(11.5, .semibold))
                    .foregroundColor(selected ? ATheme.ink : ATheme.quiet).lineLimit(1)
            }
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 8)
            .aspectRatio(1.45, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 15).fill(ATheme.card.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Wyrm skins page: None, the creatures, then the strip looks.
struct WyrmSkinsPanel: View {
    let pictures: [Int: CGImage]
    let selected: Int
    let onPick: (Int) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private func caption(_ text: String) -> some View {
        Text(text).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            caption("Your snake becomes this skin in the arena, moving and boosting with you. "
                    + "Other Wyrm players see it too; everyone else sees the nearest normal skin. "
                    + "While a Wyrm skin is on, accessories, tags and Wyrm accessories are off.")
            LazyVGrid(columns: columns, spacing: 10) {
                WyrmSkinTile(selected: selected == 0, label: "None", image: nil) { onPick(0) }
                ForEach(WyrmSkins.creatures) { skin in
                    WyrmSkinTile(selected: selected == skin.number, label: skin.name, image: pictures[skin.number]) {
                        onPick(skin.number)
                    }
                }
            }
            .padding(.horizontal, 16)
            WyrmSectionLabel("Strip looks")
            caption("A strip look keeps your own skin's colour.")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WyrmSkins.strips) { skin in
                    WyrmSkinTile(selected: selected == skin.number, label: skin.name, image: pictures[skin.number]) {
                        onPick(skin.number)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
