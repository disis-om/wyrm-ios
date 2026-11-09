import Foundation

@main struct NativeKeyboardGeometryCheck {
    static func main() {
        var checks = 0
        func verify(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        for size in [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852),
                     CGSize(width: 667, height: 375), CGSize(width: 852, height: 393)] {
            let bounds = CGRect(origin: .zero, size: size)
            verify(WyrmKeyboardGeometry.visibleHeight(size.height, occlusion: 0) == size.height, "no keys retains full canvas")
            for height in [CGFloat(160), 216, 260] {
                let frame = CGRect(x: 0, y: size.height - height, width: size.width, height: height)
                let overlap = WyrmKeyboardGeometry.dockedOverlap(frame, in: bounds)
                verify(overlap == frame, "native docked keyboard in both orientations")
                let top = frame.minY
                verify(WyrmKeyboardGeometry.visibleHeight(size.height, occlusion: height) == top, "native/internal canvas reserves one keyboard")
                verify(WyrmKeyboardGeometry.lift(bottom: top, keysTop: top, occlusion: height, focused: true) == 0,
                       "system safe area already avoided: no double lift")
                verify(WyrmKeyboardGeometry.lift(bottom: top + 17, keysTop: top, occlusion: height, focused: true) == 17,
                       "only residual measured overlap is lifted")
                verify(WyrmKeyboardGeometry.lift(bottom: size.height, keysTop: top, occlusion: height, focused: false) == 0,
                       "unfocused dock never moves")
            }
            verify(WyrmKeyboardGeometry.dockedOverlap(CGRect(x: 0, y: size.height + 1, width: size.width, height: 260), in: bounds) == nil,
                   "offscreen/hardware keyboard has no docked overlap")
            verify(WyrmKeyboardGeometry.dockedOverlap(CGRect(x: 20, y: 50, width: 200, height: 100), in: bounds) == nil,
                   "floating keyboard does not lift the entire viewport")
        }
        verify(WyrmKeyboardGeometry.dockedOverlap(CGRect(x: 0, y: CGFloat.infinity, width: 393, height: 216),
                                                   in: CGRect(x: 0, y: 0, width: 393, height: 852)) == nil, "invalid geometry rejected")
        verify(WyrmKeyboardGeometry.visibleHeight(393, occlusion: 800) == 0, "oversized keyboard never produces negative canvas")
        verify(WyrmKeyboardGeometry.visibleHeight(393, occlusion: -10) == 393, "negative keyboard does not enlarge canvas")
        verify(WyrmKeyboardGeometry.visibleHeight(393, occlusion: .nan) == 393, "invalid occlusion ignored")
        print("Native keyboard geometry: \(checks) checks passed")
    }
}
