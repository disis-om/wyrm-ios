import CoreGraphics
import Foundation

/// Window-coordinate calculations shared by the native keyboard observer and
/// portable regression fixtures. Never assume screen and window axes coincide.
enum WyrmKeyboardGeometry {
    static func visibleHeight(_ height: CGFloat, occlusion: CGFloat) -> CGFloat {
        guard height.isFinite, height > 0 else { return 0 }
        guard occlusion.isFinite else { return height }
        return max(0, height - max(0, occlusion))
    }
    static func dockedOverlap(_ keyboard: CGRect, in bounds: CGRect) -> CGRect? {
        guard [keyboard.minX, keyboard.minY, keyboard.width, keyboard.height,
               bounds.width, bounds.height].allSatisfy(\.isFinite),
              bounds.width > 0, bounds.height > 0 else { return nil }
        let overlap = keyboard.intersection(bounds)
        guard !overlap.isNull, overlap.height > 0, overlap.width >= bounds.width * 0.5,
              overlap.maxY >= bounds.maxY - 1 else { return nil }
        return overlap
    }
    static func lift(bottom: CGFloat, keysTop: CGFloat?, occlusion: CGFloat, focused: Bool) -> CGFloat {
        guard focused, let top = keysTop, bottom.isFinite, top.isFinite, occlusion.isFinite else { return 0 }
        // Already keyboard-safe composers measure bottom <= top and get zero.
        return min(max(occlusion, 0), max(0, bottom - top))
    }
}
