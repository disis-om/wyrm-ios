import Foundation

/// Portable AIR chooser physics. Android twin: WardrobeMotion.kt.
enum WyrmWardrobeGeometry {
    static let ticks = 125.0
    static func wrap(_ index: Int, _ count: Int) -> Int { count > 0 ? (index % count + count) % count : 0 }
    static func ease(_ p: Double) -> Double { (1 - cos(.pi * min(max(p, 0), 1))) * 0.5 }
    static func wave(_ seconds: Double, _ t: Double) -> Double {
        cos(seconds * 125 / 23 + t * 37 / 4) * 15 * (0.8 + 0.2 * (1 - t * 37 / 38))
    }
}

final class WyrmWardrobeMotion {
    private(set) var cursor: Double
    private(set) var selected: Int
    private(set) var dragging = false
    private var velocity = 0.0
    private var count = Int.max
    private var looping = true
    private var pendingDrag = 0.0
    private var dragSeconds = 0.0
    private var downSelected: Int
    private var captureSeconds = 0.0
    private var accumulator = 0.0
    var canScroll: Bool { count > 1 }

    init(_ initial: Int = 0) { cursor = Double(initial); selected = initial; downSelected = initial }
    func configure(_ size: Int, infinite: Bool) {
        count = max(size, 1); looping = infinite && size > 1
        if !looping { selected = bounded(selected); cursor = min(max(cursor, -0.22), Double(count) - 0.78) }
        if size <= 1 { rebase(0) }
    }
    func rebase(_ index: Int) {
        selected = bounded(index); cursor = Double(selected)
        velocity = 0; pendingDrag = 0; dragging = false; captureSeconds = 0; accumulator = 0
    }
    func show(_ index: Int, count: Int, immediate: Bool = false) {
        if dragging || (looping ? WyrmWardrobeGeometry.wrap(selected, count) : selected) == index { return }
        selected = looping ? index + Int(((cursor - Double(index)) / Double(max(count, 1))).rounded()) * count : bounded(index)
        if immediate { rebase(selected) }
    }
    func begin() {
        if dragging || !canScroll { return }
        dragging = true; pendingDrag = 0; dragSeconds = 0; downSelected = selected
        captureSeconds = 0; accumulator = 0
    }
    func drag(_ rows: Double) {
        guard dragging, rows.isFinite else { return }
        let before = cursor; cursor += rows
        if !looping { cursor = min(max(cursor, -0.22), Double(count) - 0.78) }
        pendingDrag += cursor - before; selected = nearest()
    }
    func release(_ rowsPerSecond: Double = .nan) {
        guard dragging else { return }
        dragging = false
        if abs(pendingDrag) > 0.00001 {
            velocity += (pendingDrag / 2.08 - velocity) * (1 - pow(0.88, 2.08)); pendingDrag = 0
        }
        if abs(velocity) < 0.00001 && rowsPerSecond.isFinite { velocity = rowsPerSecond / 125 }
        if dragSeconds < 0.160 && selected == downSelected && abs(velocity) * 100 > 0.3 {
            selected = bounded(downSelected + (velocity > 0 ? 1 : -1)); captureSeconds = 0
        } else { selected = nearest(); captureSeconds = 0.333 }
        accumulator = 0
    }
    func select(_ row: Int) { dragging = false; selected = bounded(row); captureSeconds = 0 }
    func settle() { dragging = false; selected = nearest(); captureSeconds = 0 }
    private func bounded(_ index: Int) -> Int { looping ? index : min(max(index, 0), count - 1) }
    private func nearest() -> Int { bounded(Int(floor(cursor + 0.5))) }
    func step(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        let dt = min(seconds, 0.1)
        if dragging {
            dragSeconds += dt
            let ticks = max(dt * 125, 0.001)
            velocity += (pendingDrag / ticks - velocity) * (1 - pow(0.88, ticks)); pendingDrag = 0
            return
        }
        accumulator += dt
        let tick = 1.0 / 125
        while accumulator + 0.0000001 >= tick {
            if captureSeconds > 0 { selected = nearest(); captureSeconds -= tick }
            let displacement = velocity * 0.925
            velocity = displacement * 0.925 - (cursor - Double(selected)) * 0.025
            cursor += displacement
            if !looping { cursor = min(max(cursor, -0.22), Double(count) - 0.78) }
            if abs(cursor - Double(selected)) < 0.00005 && abs(velocity) < 0.00005 { cursor = Double(selected); velocity = 0 }
            accumulator -= tick
        }
    }
}

final class WyrmWardrobeTouches {
    private var points: [Int64: Double] = [:]
    private var order: [Int64] = []
    private(set) var active: Int64?
    var pressed: Bool { !points.isEmpty }
    @discardableResult func down(_ id: Int64, _ y: Double) -> Bool {
        let first = points.isEmpty
        if points[id] == nil { order.append(id) }
        points[id] = y; active = id; return first
    }
    func move(_ id: Int64, _ y: Double) -> Double {
        let previous = points.updateValue(y, forKey: id) ?? y
        return active == id ? y - previous : 0
    }
    func up(_ id: Int64) {
        points[id] = nil; order.removeAll { $0 == id }
        if active == id { active = order.last }
    }
    func cancel() { points.removeAll(); order.removeAll(); active = nil }
}

struct WyrmWardrobePattern: Equatable { let groups: [Int]; let colors: [UInt32] }
final class WyrmWardrobeHistory {
    private var undoStack: [WyrmWardrobePattern] = []
    private var redoStack: [WyrmWardrobePattern] = []
    private(set) var current: WyrmWardrobePattern
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    init(_ initial: WyrmWardrobePattern) { current = initial }
    func push(_ next: WyrmWardrobePattern) {
        guard next != current else { return }
        undoStack.append(current); if undoStack.count > 256 { undoStack.removeFirst() }
        redoStack.removeAll(); current = next
    }
    @discardableResult func undo() -> WyrmWardrobePattern {
        if let value = undoStack.popLast() { redoStack.append(current); current = value }; return current
    }
    @discardableResult func redo() -> WyrmWardrobePattern {
        if let value = redoStack.popLast() { undoStack.append(current); current = value }; return current
    }
}
