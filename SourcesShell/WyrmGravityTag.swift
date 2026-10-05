import SwiftUI

/// NTL 9.68's tag rope as its skin chooser runs it (N5 with `Ce`; OM,
/// 2026-10-05: "same to same original NTL"), the same numbers as the engine's
/// `tags.c` and Android's `NtlPreviewRope`: one step per drawn frame on NTL's
/// default path (mb = 6.94: push .2 mb, stiffness .005 mb, damping .05 mb,
/// advance mb/17), before it a pull of .3 back and a sway of
/// .14 cos(frame/23 - 7 i/9), angles from NTL's `Zu` table, sums in doubles
/// stored as floats, and the bobble turning .15 of the way to the last link
/// each frame. Units are preview points: `unit` is one snake-width (head 29).
final class WyrmNtlPreviewRope {
    private(set) var x = [Float](repeating: 0, count: 10)
    private(set) var y = [Float](repeating: 0, count: 10)
    private var vx = [Float](repeating: 0, count: 10)
    private var vy = [Float](repeating: 0, count: 10)
    /// The bobble's turn (NTL's `EA`).
    private(set) var angle: Double = 0
    private var seeded = false
    private var frame = 0
    /// The last frame stepped, so one drawn frame is one step.
    var lastDate: Date?

    private static func ntlAngle(_ dx: Double, _ dy: Double) -> Double {
        let s: Double
        if dx >= -4, dy >= -4, dx < 4, dy < 4 { s = 32 }
        else if dx >= -8, dy >= -8, dx < 8, dy < 8 { s = 16 }
        else if dx >= -16, dy >= -16, dx < 16, dy < 16 { s = 8 }
        else if dx >= -127, dy >= -127, dx < 127, dy < 127 { s = 1 }
        else { return Double(Float(atan2(dy, dx))) }
        let qx = Int(s * dx + 128) - 128
        let qy = Int(s * dy + 128) - 128
        return Double(Float(atan2(Double(qy), Double(qx))))
    }

    func step(anchor: CGPoint, unit: CGFloat, chain: Double) {
        let u = Double(unit)
        let links = max(1, chain)
        let segment = 4 * links * u
        if !seeded || x.contains(where: { !$0.isFinite }) || y.contains(where: { !$0.isFinite }) {
            // NTL (`Y3`): every point starts on the head, and the chooser never
            // lays the rope out, so it falls out of the head and hangs.
            for i in 0..<10 {
                x[i] = Float(Double(anchor.x) + 8 * u)
                y[i] = Float(anchor.y)
                vx[i] = 0
                vy[i] = 0
            }
            angle = 0
            seeded = true
        }
        x[0] = Float(anchor.x)
        y[0] = Float(anchor.y)
        frame += 1
        for i in 1..<10 {
            vx[i] = Float(Double(vx[i]) - 0.3 * u)
            vy[i] = Float(Double(vy[i]) + 0.14 * u * cos(Double(frame) / 23 - 7 * Double(i) / 9))
        }
        let mb = 6.94
        let push = 0.2 * mb * links
        let stiffness = 0.005 * mb
        let advance = mb / 17
        let damping = 0.05 * mb
        for i in 1..<10 {
            let px = Double(x[i - 1])
            let py = Double(y[i - 1])
            var dx = Double(x[i]) - px
            var dy = Double(y[i]) - py
            let a = (dx == 0 && dy == 0) ? 0 : Self.ntlAngle(dx, dy)
            let tx = px + push * cos(a) * u
            let ty = py + push * sin(a) * u
            vx[i] = Float(Double(vx[i]) + stiffness * (tx - Double(x[i])))
            vy[i] = Float(Double(vy[i]) + stiffness * (ty - Double(y[i])))
            x[i] = Float(Double(x[i]) + advance * Double(vx[i]))
            y[i] = Float(Double(y[i]) + advance * Double(vy[i]))
            vx[i] = Float(Double(vx[i]) * damping)
            vy[i] = Float(Double(vy[i]) * damping)
            dx = Double(x[i]) - Double(x[i - 1])
            dy = Double(y[i]) - Double(y[i - 1])
            if (dx * dx + dy * dy).squareRoot() > segment {
                let b = atan2(dy, dx)
                x[i] = Float(Double(x[i - 1]) + segment * cos(b))
                y[i] = Float(Double(y[i - 1]) + segment * sin(b))
            }
        }
        let he = 2 * Double.pi
        var d = atan2(Double(y[9]) - Double(y[8]), Double(x[9]) - Double(x[8])) - angle
        if d < 0 || d >= he { d = d.truncatingRemainder(dividingBy: he) }
        if d < -Double.pi { d += he } else if d > Double.pi { d -= he }
        angle = (angle + 0.15 * d).truncatingRemainder(dividingBy: he)
    }
}

/// The Skin preview's tag on NTL's own chooser rope (`WyrmNtlPreviewRope`),
/// stepped every drawn frame. The arena's tags are the engine's (`tags.c`).
struct WyrmSwingTag: View {
    let item: WyrmTagAsset
    let image: CGImage
    let head: CGPoint
    let headSize: CGFloat
    let bounds: CGSize
    let chain: Double
    let swing: Double   // NTL's chooser always takes the default path
    let tagScale: Double
    let reduceMotion: Bool

    @State private var rope = WyrmNtlPreviewRope()

    private var unit: CGFloat { headSize / 29 }
    private var anchor: CGPoint { CGPoint(x: head.x - 8 * unit, y: head.y) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, _ in
                if rope.lastDate != timeline.date {
                    rope.lastDate = timeline.date
                    rope.step(anchor: anchor, unit: unit, chain: chain)
                }
                let points = (0..<10).map { CGPoint(x: CGFloat(rope.x[$0]), y: CGFloat(rope.y[$0])) }
                context.stroke(ropePath(points, to: 1, close: false),
                               with: .color(Color(rgb: item.accentA)),
                               style: StrokeStyle(lineWidth: 5 * unit, lineCap: .round, lineJoin: .round))
                for width in [CGFloat(4), 3, 2] {
                    context.stroke(ropePath(points, to: 2, close: true),
                                   with: .color(Color(rgb: item.accentB).opacity(0.5)),
                                   style: StrokeStyle(lineWidth: width * unit, lineCap: .round, lineJoin: .round))
                }
                let rawWidth = CGFloat(item.width) * 0.285 * unit * CGFloat(tagScale)
                let rawHeight = CGFloat(item.height) * 0.285 * unit * CGFloat(tagScale)
                let fit = min(1, 108 / max(1, max(rawWidth, rawHeight)))
                let width = rawWidth * fit
                let height = rawHeight * fit
                let attachX = CGFloat(item.anchorX) * 0.285 * unit * CGFloat(tagScale) * fit
                let attachY = CGFloat(item.anchorY) * 0.285 * unit * CGFloat(tagScale) * fit
                let fitScale = min(width / CGFloat(image.width), height / CGFloat(image.height))
                let dw = CGFloat(image.width) * fitScale
                let dh = CGFloat(image.height) * fitScale
                // NTL: translate to the rope's end, turn by the bobble's angle,
                // draw the box at its anchor offset.
                var tag = context
                tag.translateBy(x: points[9].x, y: points[9].y)
                tag.rotate(by: .radians(rope.angle))
                tag.draw(Image(decorative: image, scale: 1),
                         in: CGRect(x: attachX + (width - dw) / 2, y: attachY + (height - dh) / 2,
                                    width: dw, height: dh))
            }
        }
        .allowsHitTesting(false)
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
