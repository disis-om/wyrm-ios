import Foundation

/// Wyrm's own beads (OM, 2026-09-28): 24 patterned and material beads painted
/// into free atlas cells by `Scripts/generate-wyrm-beads.py`.
///
/// A bead is stored like an AIR wheel bead: its alpha byte (`0xE0 + kind`)
/// names the texture and the low 24 bits carry its colour. Tinted beads are
/// grey and take the picked colour; fixed-colour beads are drawn as painted and
/// their colour only chooses the nearest slither colour group, which is all
/// the arena (and every other player) ever sees. The engine reads the same
/// bytes (`wyrm_bead_kind` in redraw.c). Android: `ui/WyrmBeads.kt`.
enum WyrmBead {
    static let count = 24
    static let tag: UInt32 = 0xE0

    static let names = [
        "India", "Star", "Heart", "Dragon scales", "Stripes", "Dots", "Lightning", "Flame",
        "Crescent", "Chrome", "Gold", "Galaxy", "Honeycomb", "Argyle", "Zigzag", "Carbon fibre",
        "Tiger", "Circuit", "Leopard", "Lava", "Ice", "Marble", "Holographic", "Camo",
    ]

    static let tinted: [Bool] = [
        false, true, true, true, true, true, true, true, true, false, false, false,
        true, true, true, true, true, true, false, false, false, false, false, false,
    ]

    /// Fixed-colour beads: the colour the arena's nearest group is picked from.
    static let fixedRGB: [Int: UInt32] = [
        0: 0xFF9933, 9: 0xC0C4CA, 10: 0xE0A838, 11: 0x3A2A7A, 18: 0xD6A048,
        19: 0xC8501A, 20: 0x96CDF0, 21: 0xECEAE4, 22: 0xE8A0E8, 23: 0x6A7A42,
    ]

    /// Atlas cells, four beads to a cell (row, column), as in the engine.
    private static let cells: [(row: Int, column: Int)] = [(7, 3), (7, 6), (8, 0), (8, 1), (8, 2), (8, 3)]

    static func kind(of rgba: UInt32) -> Int? {
        let byte = rgba >> 24
        return byte >= tag && byte < tag + UInt32(count) ? Int(byte - tag) : nil
    }

    /// The stored value for bead `kind`: tinted beads keep `tint`.
    static func rgba(_ kind: Int, tint: UInt32) -> UInt32 {
        let rgb = tinted[kind] ? tint & 0xFF_FFFF : (fixedRGB[kind] ?? 0x808080)
        return (tag + UInt32(kind)) << 24 | rgb
    }

    /// Normalised atlas rectangle (x, y, width, height).
    static func uv(_ kind: Int) -> (Double, Double, Double, Double) {
        let cell = cells[kind / 4]
        let qx = Double(kind % 2) * 0.5, qy = Double((kind % 4) / 2) * 0.5
        return ((Double(cell.column) + qx) / 7, (Double(cell.row) + qy) / 9, 0.5 / 7, 0.5 / 9)
    }
}
