import Foundation

@main struct WardrobeMotionCheck {
    static func main() {
        var checks = 0
        func verify(_ value: Bool, _ message: String) {
            precondition(value, message); checks += 1
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }
        let touches = WyrmWardrobeTouches()
        verify(touches.down(1, 400), "first touch starts")
        verify(near(touches.move(1, 350), -50), "first finger delta")
        verify(!touches.down(2, 650), "second finger does not restart")
        verify(near(touches.move(1, 300), 0), "inactive anchor updates")
        verify(near(touches.move(2, 600), -50), "second finger own origin")
        touches.up(2)
        verify(near(touches.move(1, 280), -20), "handoff uses latest first position")
        touches.up(1); verify(!touches.pressed, "all touches released")
        for fps in [30, 60, 90, 120, 144] {
            let motion = WyrmWardrobeMotion(2); motion.select(5)
            var y = 2.0, v = 0.0
            for _ in 0..<125 { let d = v * 0.925; v = d * 0.925 - (y - 5) * 0.025; y += d }
            for _ in 0..<fps { motion.step(1 / Double(fps)) }
            verify(near(motion.cursor, y), "AIR delayed spring trace at \(fps) Hz")
            for _ in 0..<(fps * 6) { motion.step(1 / Double(fps)) }
            verify(near(motion.cursor, 5), "settles at \(fps) Hz")
            motion.begin(); motion.drag(2.2)
            let cursor = motion.cursor; motion.show(33, count: 105, immediate: true)
            verify(near(motion.cursor, cursor), "engine echo cannot steal drag")
        }
        for size in 0...2 {
            let motion = WyrmWardrobeMotion(); motion.configure(size, infinite: false)
            motion.begin(); motion.drag(200); motion.release()
            for _ in 0..<1000 { motion.step(0.008) }
            verify(motion.selected == max(size - 1, 0), "finite end \(size)")
            verify(near(motion.cursor, Double(motion.selected)), "finite settle \(size)")
            motion.begin(); motion.drag(-200); motion.release()
            for _ in 0..<1000 { motion.step(0.008) }
            verify(motion.selected == 0 && near(motion.cursor, 0), "finite start \(size)")
        }
        let looping = WyrmWardrobeMotion(); looping.configure(3, infinite: true)
        looping.begin(); looping.drag(7.2)
        verify(looping.selected == 7 && WyrmWardrobeGeometry.wrap(looping.selected, 3) == 1, "three saved skins loop")
        let original = WyrmWardrobePattern(groups: [7], colors: [0xFE804020])
        let edited = WyrmWardrobePattern(groups: [7,9], colors: [0xFE804020,0xFD112233])
        let history = WyrmWardrobeHistory(original); history.push(edited)
        verify(history.canUndo && !history.canRedo, "history records edit")
        verify(history.undo() == original && history.canRedo, "undo keeps marker and RGB")
        verify(history.redo() == edited, "redo keeps exact pattern")
        history.undo(); history.push(.init(groups: [2], colors: [0]))
        verify(!history.canRedo, "new edit clears redo")
        print("Swift wardrobe motion: \(checks) checks passed")
    }
}
