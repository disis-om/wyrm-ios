import SwiftUI
import CoreMotion

/// A preview-only rope. The game retains ownership of its own NTL physics.
struct WyrmGravityTag: View {
    let item: WyrmTagAsset
    let image: CGImage
    let head: CGPoint
    let headSize: CGFloat
    let bounds: CGSize
    let chain: Double
    let swing: Double
    let tagScale: Double
    let reduceMotion: Bool

    @State private var motion = CMMotionManager()
    @State private var points: [CGPoint] = []
    @State private var velocity: [CGVector] = []
    private let clock = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    private var unit: CGFloat { headSize / 29 }
    private var anchor: CGPoint { CGPoint(x: head.x - 8 * unit, y: head.y) }
    private var segment: CGFloat { 4 * CGFloat(max(1, chain)) * unit }

    var body: some View {
        let rope = points.count == 10 ? points : initialPoints
        let end = rope.last ?? anchor
        let before = rope.dropLast().last ?? anchor
        let angle = atan2(end.y - before.y, end.x - before.x)
        let rawWidth = CGFloat(item.width) * 0.285 * unit * CGFloat(tagScale)
        let rawHeight = CGFloat(item.height) * 0.285 * unit * CGFloat(tagScale)
        let fit = min(1, 108 / max(1, max(rawWidth, rawHeight)))
        let width = rawWidth * fit
        let height = rawHeight * fit
        let attachX = CGFloat(item.anchorX) * 0.285 * unit * CGFloat(tagScale) * fit
        let attachY = CGFloat(item.anchorY) * 0.285 * unit * CGFloat(tagScale) * fit
        let localX = attachX + width * 0.5
        let localY = attachY + height * 0.5
        let proposed = CGPoint(x: end.x + cos(angle) * localX - sin(angle) * localY,
                               y: end.y + sin(angle) * localX + cos(angle) * localY)
        let centre = CGPoint(x: min(max(width * 0.5, proposed.x), min(head.x - headSize * 0.1, bounds.width - width * 0.5)),
                             y: min(max(height * 0.5, proposed.y), bounds.height - height * 0.5))

        return ZStack {
            ropePath(rope, to: 1, close: false)
                .stroke(Color(rgb: item.accentA), style: StrokeStyle(lineWidth: 5 * unit, lineCap: .round, lineJoin: .round))
            for width in [CGFloat(4), 3, 2] {
                ropePath(rope, to: 2, close: true)
                    .stroke(Color(rgb: item.accentB).opacity(0.5), style: StrokeStyle(lineWidth: width * unit, lineCap: .round, lineJoin: .round))
            }
            Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                .frame(width: width, height: height)
                .rotationEffect(.radians(Double(angle)))
                .position(centre)
        }
        .onAppear {
            points = initialPoints
            velocity = Array(repeating: .zero, count: 10)
            if motion.isDeviceMotionAvailable && !reduceMotion {
                motion.deviceMotionUpdateInterval = 1.0 / 30.0
                motion.startDeviceMotionUpdates()
            }
        }
        .onDisappear { motion.stopDeviceMotionUpdates() }
        .onChange(of: reduceMotion) { reduced in
            if reduced { motion.stopDeviceMotionUpdates() }
            else if motion.isDeviceMotionAvailable { motion.startDeviceMotionUpdates() }
        }
        .onReceive(clock) { _ in step() }
    }

    private var initialPoints: [CGPoint] {
        (0..<10).map { CGPoint(x: anchor.x - CGFloat($0) * segment, y: anchor.y) }
    }

    private func step() {
        guard !reduceMotion else { return }
        if points.count != 10 || velocity.count != 10 {
            points = initialPoints
            velocity = Array(repeating: .zero, count: 10)
        }
        let gravity = motion.deviceMotion?.gravity
        let gx = CGFloat(gravity?.x ?? 0)
        let gy = CGFloat(-(gravity?.y ?? -1))
        let force = 0.17 * unit * CGFloat(max(1, min(2, swing)))
        let stiffness = 0.08333 + 0.01667 * CGFloat(swing - 1)
        let damping = min(0.985, 0.838 + 0.145 * CGFloat(swing - 1))
        points[0] = anchor
        for index in 1..<10 {
            let prior = points[index - 1]
            let dx = points[index].x - prior.x
            let dy = points[index].y - prior.y
            let direction = (dx == 0 && dy == 0) ? CGFloat.pi : atan2(dy, dx)
            let target = CGPoint(x: prior.x + segment * cos(direction),
                                 y: prior.y + segment * sin(direction))
            velocity[index].dx = (velocity[index].dx + stiffness * (target.x - points[index].x) + force * gx) * damping
            velocity[index].dy = (velocity[index].dy + stiffness * (target.y - points[index].y) + force * gy) * damping
            points[index].x += velocity[index].dx
            points[index].y += velocity[index].dy
            let deltaX = points[index].x - prior.x
            let deltaY = points[index].y - prior.y
            let distance = hypot(deltaX, deltaY)
            if distance > segment {
                points[index] = CGPoint(x: prior.x + segment * deltaX / distance,
                                        y: prior.y + segment * deltaY / distance)
            }
            points[index].x = min(max(0, points[index].x), anchor.x - segment * 0.25)
            points[index].y = min(max(0, points[index].y), bounds.height)
        }
    }

    private func ropePath(_ rope: [CGPoint], to: Int, close: Bool) -> Path {
        var path = Path()
        guard let last = rope.last, rope.count > to else { return path }
        path.move(to: last)
        for index in stride(from: rope.count - 2, through: to, by: -1) {
            path.addQuadCurve(to: CGPoint(x: (rope[index].x + rope[index - 1].x) * 0.5,
                                               y: (rope[index].y + rope[index - 1].y) * 0.5), control: rope[index])
        }
        if close { path.addQuadCurve(to: rope[0], control: rope[1]) }
        return path
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255)
    }
}
