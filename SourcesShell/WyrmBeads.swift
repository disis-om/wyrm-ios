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
    static let count = 54
    /// Beads 0-23 are tagged 0xE0 + k; beads 24-53 are tagged 0xC0 + k - 24.
    static let first = 24
    static let tag: UInt32 = 0xE0
    static let tag2: UInt32 = 0xC0

    static let names = [
        "India", "Star", "Heart", "Dragon scales", "Stripes", "Dots", "Lightning", "Flame",
        "Crescent", "Chrome", "Gold", "Galaxy", "Honeycomb", "Argyle", "Zigzag", "Carbon fibre",
        "Tiger", "Circuit", "Leopard", "Lava", "Ice", "Marble", "Holographic", "Camo",
        "Checker", "Tartan", "Rainbow", "Sakura", "Snowflake", "Skull", "Music", "Paw",
        "Diamond", "Ruby", "Emerald", "Pearl", "Copper", "Rose gold", "Neon grid", "Sunset",
        "Waves", "Zebra", "Cow", "Giraffe", "Python", "Peacock", "Wood", "Denim",
        "Bubblegum", "Aurora", "Sun", "Electric", "Watermelon", "Pixel",
    ]

    /// Every bead is painted in its own colours; none takes the wheel's colour.
    static let tinted = [Bool](repeating: false, count: count)

    /// Each bead's main colour: the arena's nearest slither colour group is picked from it.
    static let fixedRGB: [Int: UInt32] = [
        0: 0xFF9933, 1: 0x1F3A8A, 2: 0xF7B6C8, 3: 0x2FA45E, 4: 0xD7263D,
        5: 0x1F5FD6, 6: 0x4B2A8C, 7: 0xFF6A1A, 8: 0x16245A, 9: 0xC0C4CA,
        10: 0xE0A838, 11: 0x3A2A7A, 12: 0xFFC43A, 13: 0x1E2F5C, 14: 0xFF8A1E,
        15: 0x3A3E44, 16: 0xF28A1C, 17: 0x0E5A34, 18: 0xD6A048, 19: 0xC8501A,
        20: 0x96CDF0, 21: 0xECEAE4, 22: 0xE8A0E8, 23: 0x6A7A42,
        24: 0x202022, 25: 0xB21824, 26: 0x00A848, 27: 0xFCD6E0, 28: 0x8CC0EC,
        29: 0x16161A, 30: 0x1E9E98, 31: 0xECD0A8, 32: 0x78D2F0, 33: 0xC81432,
        34: 0x14A05A, 35: 0xF0E8EE, 36: 0xCE7440, 37: 0xE8AAA0, 38: 0x24083C,
        39: 0xFF783C, 40: 0x2A7AC0, 41: 0xF4F2EC, 42: 0xF8F6F0, 43: 0xC4782E,
        44: 0xA89650, 45: 0x148C78, 46: 0xB0703A, 47: 0x284C8C, 48: 0xFFB4D7,
        49: 0x0A1028, 50: 0xFFB428, 51: 0x0C143C, 52: 0xEC4052, 53: 0x3498DB,
    ]

    /// Atlas cells, nine beads to a cell (row, column), as in the engine.
    private static let cells: [(row: Int, column: Int)] = [(7, 3), (7, 6), (8, 0), (8, 1), (8, 2), (8, 3)]

    static func kind(of rgba: UInt32) -> Int? {
        let byte = rgba >> 24
        if byte >= tag && byte < tag + UInt32(first) { return Int(byte - tag) }
        if byte >= tag2 && byte < tag2 + UInt32(count - first) { return Int(byte - tag2) + first }
        return nil
    }

    /// The stored value for bead `kind`: its tag byte and its main colour.
    static func rgba(_ kind: Int, tint: UInt32) -> UInt32 {
        let rgb = tinted[kind] ? tint & 0xFF_FFFF : (fixedRGB[kind] ?? 0x808080)
        let byte = kind < first ? tag + UInt32(kind) : tag2 + UInt32(kind - first)
        return byte << 24 | rgb
    }

    /// Normalised atlas rectangle (x, y, width, height), nine beads to a cell.
    static func uv(_ kind: Int) -> (Double, Double, Double, Double) {
        let cell = cells[kind / 9]
        let qx = Double(kind % 3) / 3, qy = Double((kind % 9) / 3) / 3
        return ((Double(cell.column) + qx) / 7, (Double(cell.row) + qy) / 9, (1.0 / 3) / 7, (1.0 / 3) / 9)
    }
}
