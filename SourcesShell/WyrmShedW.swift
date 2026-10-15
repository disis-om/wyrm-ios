import SwiftUI

/*
 * Shed's W (OM, 2026-10-15): one dotted Wyrm W that breathes in 3D at rest
 * and, on Shed, turns into the snake's head bead (facing up, two eyes) and
 * back. A port of Android's ui/ShedW.kt (itself the HTML prototype's
 * wyrmModes.js `shedFrame`): the W is the logo's exact stroke (WyrmMark's
 * three curves, stroke 0.16, round caps) as three nested breathing outlines;
 * the two middle peaks become the eyes, the arms wrap into the head's
 * border, every dot moves straight in at its own angle (nothing turns). Eyes
 * use the game's numbers (redraw.c / oef.c): head radius 14.5, eye 6 forward
 * 6.5 aside radius 6, pupil radius 3.5 looking up to 2.3; the pupil is dots
 * in clean rings (1 + 9 + 18), the rest of the eye stays empty. Dots are
 * painted like thinking-orbs' painter: matte, far to near, in the theme's ink.
 */
enum WyrmShedW {
    struct Dot { let x: Double; let y: Double; let z: Double; let r: Double; let white: Double; let a: Double }

    private static let tau = 2 * Double.pi
    private static let H = 0.78
    private static let HALF = 0.08
    private static let curves: [[Double]] = [
        [0.06, 0.10, 0.13, 0.92, 0.30, 0.96, 0.36, 0.38],
        [0.36, 0.38, 0.42, 0.94, 0.58, 0.94, 0.64, 0.38],
        [0.64, 0.38, 0.70, 0.96, 0.87, 0.92, 0.94, 0.10],
    ]

    private static func bez(_ c: [Double], _ t: Double) -> (Double, Double) {
        let m = 1 - t
        let a = m * m * m, b = 3 * m * m * t, d = 3 * m * t * t, e = t * t * t
        return (a * c[0] + b * c[2] + d * c[4] + e * c[6], (a * c[1] + b * c[3] + d * c[5] + e * c[7]) * H)
    }
    private static func bezD(_ c: [Double], _ t: Double) -> (Double, Double) {
        let m = 1 - t
        let dx = 3 * m * m * (c[2] - c[0]) + 6 * m * t * (c[4] - c[2]) + 3 * t * t * (c[6] - c[4])
        let dy = (3 * m * m * (c[3] - c[1]) + 6 * m * t * (c[5] - c[3]) + 3 * t * t * (c[7] - c[5])) * H
        var l = hypot(dx, dy)
        if !(l > 0) { l = 1 }
        return (dx / l, dy / l)
    }

    // logo coordinates -> plane: centred on the origin, y up
    private static let center: (Double, Double) = {
        var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
        for c in curves {
            for i in 0...200 {
                let p = bez(c, Double(i) / 200)
                x0 = min(x0, p.0); x1 = max(x1, p.0); y0 = min(y0, p.1); y1 = max(y1, p.1)
            }
        }
        return ((x0 + x1) / 2, (y0 + y1) / 2)
    }()
    private static func plane(_ p: (Double, Double)) -> (Double, Double) { (p.0 - center.0, -(p.1 - center.1)) }

    private struct End { let x, y, tx, ty, nx, ny: Double }

    // centreline, each curve resampled evenly by arc length
    private static let line: [(Double, Double)] = {
        var pts: [(Double, Double)] = []
        for (ci, c) in curves.enumerated() {
            let n = 600
            var ts = [Double](repeating: 0, count: n + 1), ls = [Double](repeating: 0, count: n + 1)
            var len = 0.0
            var prev = bez(c, 0)
            for i in 0...n {
                let t = Double(i) / Double(n)
                let p = bez(c, t)
                len += hypot(p.0 - prev.0, p.1 - prev.1)
                prev = p
                ts[i] = t; ls[i] = len
            }
            let per = 300
            var j = 0
            for k in 0...per {
                if ci > 0 && k == 0 { continue }
                let s = Double(k) / Double(per) * len
                while j < n - 1 && ls[j + 1] < s { j += 1 }
                let f = (s - ls[j]) / max(1e-9, ls[j + 1] - ls[j])
                let t = ts[j] + (ts[j + 1] - ts[j]) * f
                pts.append(plane(bez(c, t)))
            }
        }
        return pts
    }()

    // the six stroke ends (round caps)
    private static let ends: [End] = {
        var out: [End] = []
        for c in curves {
            for (t, sgn) in [(0.0, -1.0), (1.0, 1.0)] {
                let p = plane(bez(c, t))
                let d = bezD(c, t)
                let tx = d.0, ty = -d.1
                out.append(End(x: p.0, y: p.1, tx: tx * sgn, ty: ty * sgn, nx: -ty, ny: tx))
            }
        }
        return out
    }()

    // distance to the centreline, as a grid (only a band around the line)
    private static let dfRes = 0.005
    private static let dfX0 = -0.62
    private static let dfY0 = -0.5
    private static let dfNX = Int(ceil(1.24 / dfRes)) + 1
    private static let dfNY = Int(ceil(1.0 / dfRes)) + 1
    private static let df: [Float] = {
        var grid = [Float](repeating: 1, count: dfNX * dfNY)
        let rc = Int(ceil(0.16 / dfRes))
        var k = 0
        while k < line.count {
            let p = line[k]
            let ci = Int(((p.0 - dfX0) / dfRes).rounded()), cj = Int(((p.1 - dfY0) / dfRes).rounded())
            let jLo = max(0, cj - rc), jHi = min(dfNY - 1, cj + rc)
            let iLo = max(0, ci - rc), iHi = min(dfNX - 1, ci + rc)
            if jLo <= jHi && iLo <= iHi {
                for j in jLo...jHi {
                    let dy = dfY0 + Double(j) * dfRes - p.1
                    for i in iLo...iHi {
                        let dx = dfX0 + Double(i) * dfRes - p.0
                        let d = Float(sqrt(dx * dx + dy * dy))
                        if d < grid[j * dfNX + i] { grid[j * dfNX + i] = d }
                    }
                }
            }
            k += 2
        }
        return grid
    }()
    private static func distLine(_ x: Double, _ y: Double) -> Double {
        let gx = (x - dfX0) / dfRes, gy = (y - dfY0) / dfRes
        if gx < 0 || gy < 0 || gx >= Double(dfNX - 1) || gy >= Double(dfNY - 1) { return 1 }
        let i = Int(floor(gx)), j = Int(floor(gy)), fx = gx - Double(i), fy = gy - Double(j)
        let n = dfNX
        let a = Double(df[j * n + i]), b = Double(df[j * n + i + 1])
        let c = Double(df[(j + 1) * n + i]), d = Double(df[(j + 1) * n + i + 1])
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }

    /// The logo's outline (union of the three round-capped strokes), unordered.
    private static func outline(_ half: Double, _ spacing: Double) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for c in curves {
            for side in [1.0, -1.0] {
                var acc = spacing
                var prev: (Double, Double)? = nil
                for i in 0...400 {
                    let t = Double(i) / 400
                    let b = plane(bez(c, t))
                    let d = bezD(c, t)
                    let tx = d.0, ty = -d.1
                    let p = (b.0 - ty * half * side, b.1 + tx * half * side)
                    if let q = prev { acc += hypot(p.0 - q.0, p.1 - q.1) }
                    prev = p
                    if acc >= spacing { acc = 0; if distLine(p.0, p.1) >= half * 0.965 { out.append(p) } }
                }
            }
        }
        let n = max(3, Int((Double.pi * half / spacing).rounded()))
        for e in ends {
            for k in 1..<n {
                let a = Double(k) / Double(n) * Double.pi
                let p = (e.x + (e.nx * cos(a) + e.tx * sin(a)) * half, e.y + (e.ny * cos(a) + e.ty * sin(a)) * half)
                if distLine(p.0, p.1) >= half * 0.965 { out.append(p) }
            }
        }
        return out
    }

    /// Outline dots as one closed loop, resampled to exactly `m`, counter-clockwise from the top left.
    private static func contour(_ m: Int, _ half: Double) -> [(Double, Double)] {
        let pts = outline(half, 0.006)
        var curIndex = 0
        for (i, p) in pts.enumerated() where p.1 - p.0 > pts[curIndex].1 - pts[curIndex].0 { curIndex = i }
        var used = [Bool](repeating: false, count: pts.count)
        used[curIndex] = true
        var usedCount = 1
        var loop = [pts[curIndex]]
        var cur = pts[curIndex]
        while usedCount < pts.count {
            var best = -1
            var bd = 1e9
            for (i, p) in pts.enumerated() where !used[i] {
                let d = (p.0 - cur.0) * (p.0 - cur.0) + (p.1 - cur.1) * (p.1 - cur.1)
                if d < bd { bd = d; best = i }
            }
            if best < 0 || bd > 0.05 * 0.05 { break }
            used[best] = true; usedCount += 1; loop.append(pts[best]); cur = pts[best]
        }
        var area = 0.0
        for i in loop.indices { let a = loop[i], b = loop[(i + 1) % loop.count]; area += a.0 * b.1 - b.0 * a.1 }
        if area < 0 { loop.reverse() }
        var len = [Double](repeating: 0, count: loop.count + 1)
        for i in 1...loop.count { let a = loop[i - 1], b = loop[i % loop.count]; len[i] = len[i - 1] + hypot(b.0 - a.0, b.1 - a.1) }
        let total = len[loop.count]
        var out: [(Double, Double)] = []
        var j = 0
        for k in 0..<m {
            let s = Double(k) / Double(m) * total
            while len[j + 1] < s { j += 1 }
            let f = (s - len[j]) / max(1e-9, len[j + 1] - len[j])
            let a = loop[j], b = loop[(j + 1) % loop.count]
            out.append((a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f))
        }
        return out
    }

    // ---------------------------------------------------------- the face

    private static let headX = 0.0
    private static let headY = -0.02
    private static let headR = 0.31
    private static let U = headR / 14.5
    private static let eyeR = 6 * U
    private static let pupilR = 3.5 * U
    private static let lookR = 2.3 * U
    private static let eyeC: [(Double, Double)] = [(headX - 6.5 * U, headY + 6 * U), (headX + 6.5 * U, headY + 6 * U)]
    private static let pupilC: [(Double, Double)] = [(headX - 6 * U, headY + 6.5 * U), (headX + 6 * U, headY + 6.5 * U)]

    // the pupil in clean rings so it reads as a round disc: centre, 9, 18
    private static let pupilDisk: [(Double, Double)] = {
        var out: [(Double, Double)] = [(0, 0)]
        for (n, r, off) in [(9, 0.47, 0.0), (18, 0.94, Double.pi / 18)] {
            for i in 0..<n {
                let a = off + Double(i) / Double(n) * tau
                out.append((cos(a) * r, sin(a) * r))
            }
        }
        return out
    }()

    private static let laneHalf = [1.0, 0.7, 0.4]
    private static let laneN = [240, 200, 160]
    private static let breath = [0.9, 1.06]
    private static let headRing = [1.0, 0.93, 0.86]
    private static let ringSlots = [150, 138, 126]
    private static let eyeSlots = 40

    private enum Kind { case ring, eye, pupil }
    private struct Move { let i: Int; let kind: Kind; let toX, toY: Double; let eye: Int; let pj: Int; let fade: Bool; let delay: Double }
    private struct Born { let kind: Kind; let x, y: Double; let eye: Int; let pj: Int }
    private struct Lane { let lo: [(Double, Double)]; let hi: [(Double, Double)]; let moves: [Move]; let born: [Born] }

    private static func inEye(_ x: Double, _ y: Double) -> Bool { eyeC.contains { hypot(x - $0.0, y - $0.1) < eyeR * 1.12 } }
    /// Java's Math.round (half up), then wrapped into 0..<n.
    private static func slotOf(_ a: Double, _ n: Int) -> Int {
        let v = Int(floor((a + Double.pi) / tau * Double(n) + 0.5))
        return ((v % n) + n) % n
    }
    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    private static let lanes: [Lane] = {
        let peaks: [(Double, Double)] = [(ends[1].x, ends[1].y), (ends[3].x, ends[3].y)]
        return laneHalf.indices.map { L -> Lane in
            let lh = laneHalf[L]
            let lo = contour(laneN[L], HALF * lh * breath[0])
            let hi = contour(laneN[L], HALF * lh * breath[1])
            var moves: [Move] = []
            var born: [Born] = []
            var ringFill = [Bool](repeating: false, count: ringSlots[L])
            var eyeFill = [[Bool]](repeating: [Bool](repeating: false, count: eyeSlots), count: 2)
            var pupilFill = [[Bool]](repeating: [Bool](repeating: false, count: pupilDisk.count), count: 2)
            func ringPos(_ k: Int) -> (Double, Double) {
                let a = -Double.pi + Double(k) / Double(ringSlots[L]) * tau
                let r = headR * headRing[L]
                return (headX + cos(a) * r, headY + sin(a) * r)
            }
            func eyePos(_ e: Int, _ k: Int) -> (Double, Double) {
                let a = -Double.pi + Double(k) / Double(eyeSlots) * tau
                return (eyeC[e].0 + cos(a) * eyeR, eyeC[e].1 + sin(a) * eyeR)
            }
            for (i, p) in lo.enumerated() {
                let x = p.0, y = p.1
                var e = -1
                for k in 0..<2 where hypot(x - peaks[k].0, y - peaks[k].1) < HALF * lh * 1.1 + 0.075 { e = k }
                let delay = clamp01(0.55 - hypot(x - headX, y - headY)) * 0.2
                if e < 0 {
                    let k = slotOf(atan2(y - headY, x - headX), ringSlots[L])
                    let to = ringPos(k)
                    ringFill[k] = true
                    moves.append(Move(i: i, kind: .ring, toX: to.0, toY: to.1, eye: -1, pj: -1, fade: inEye(to.0, to.1), delay: delay))
                } else if L == 0 {
                    let k = slotOf(atan2(y - peaks[e].1, x - peaks[e].0), eyeSlots)
                    eyeFill[e][k] = true
                    let to = eyePos(e, k)
                    moves.append(Move(i: i, kind: .eye, toX: to.0, toY: to.1, eye: e, pj: -1, fade: false, delay: delay))
                } else {
                    let span = HALF * lh * 1.1 + 0.075
                    let rx = (x - peaks[e].0) / span, ry = (y - peaks[e].1) / span
                    var j = 0
                    var bd = 1e9
                    for (n, q) in pupilDisk.enumerated() {
                        let d = (q.0 - rx) * (q.0 - rx) + (q.1 - ry) * (q.1 - ry)
                        if d < bd { bd = d; j = n }
                    }
                    pupilFill[e][j] = true
                    moves.append(Move(i: i, kind: .pupil, toX: 0, toY: 0, eye: e, pj: j, fade: false, delay: delay))
                }
            }
            for k in 0..<ringSlots[L] {
                let p = ringPos(k)
                if !ringFill[k] && !inEye(p.0, p.1) { born.append(Born(kind: .ring, x: p.0, y: p.1, eye: -1, pj: -1)) }
            }
            if L == 0 {
                for e in 0..<2 { for k in 0..<eyeSlots where !eyeFill[e][k] { let p = eyePos(e, k); born.append(Born(kind: .eye, x: p.0, y: p.1, eye: e, pj: -1)) } }
            }
            if L == 1 {
                for e in 0..<2 { for j in pupilDisk.indices where !pupilFill[e][j] { born.append(Born(kind: .pupil, x: 0, y: 0, eye: e, pj: j)) } }
            }
            return Lane(lo: lo, hi: hi, moves: moves, born: born)
        }
    }()

    /// Build the geometry (a few hundred ms the first time); call off the main thread.
    static func prepare() { _ = lanes.count }

    // ---------------------------------------------------------- one frame

    private static let tW = 0.9
    private static let tM = 1.3
    private static let tF = 3.6
    /// One W -> face -> W journey, seconds.
    static let run = tW + tM + tF + tM
    private static let lookTL = (-0.5.squareRoot(), 0.5.squareRoot())
    private static let lookTR = (0.5.squareRoot(), 0.5.squareRoot())

    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    private static func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }

    /// One frame in a `w` x `h` box (points). `tb` = page clock (the breath
    /// never restarts); `run` = seconds into a shed, nil at rest; `half` =
    /// which look order (0: top-left then top-right); `depth` = 3D sway 0..1.
    static func frame(w: Double, h: Double, tb: Double, run: Double?, half: Int, depth: Double) -> [Dot] {
        let lt = run.map { min($0, Self.run) }
        let span = w * 0.8
        let rs = pow(w / 300.0, 0.6)
        var hd = 0.0
        if let lt {
            if lt < tW { hd = 0 }
            else if lt < tW + tM { hd = (lt - tW) / tM }
            else if lt < tW + tM + tF { hd = 1 }
            else { hd = clamp01(1 - (lt - tW - tM - tF) / tM) }
        }
        let from = half == 0 ? lookTL : lookTR
        let to = half == 0 ? lookTR : lookTL
        let fl = (lt ?? 0) - tW - tM
        let g = fl < 1.4 ? 0.0 : smooth(clamp01((fl - 1.4) / 0.6))
        let lx = from.0 + (to.0 - from.0) * g, ly = from.1 + (to.1 - from.1) * g
        var ll = hypot(lx, ly)
        if !(ll > 0) { ll = 1 }
        func pupilX(_ e: Int, _ j: Int) -> Double { pupilC[e].0 + lx / ll * lookR + pupilDisk[j].0 * pupilR }
        func pupilY(_ e: Int, _ j: Int) -> Double { pupilC[e].1 + ly / ll * lookR + pupilDisk[j].1 * pupilR }

        // the 3D sway: a slow turn and nod; outer outline in front (thinking-orbs makeProj)
        let yaw = 0.34 * depth * sin(tb * 0.45)
        let tilt = 0.2 * depth * sin(tb * 0.31 + 1.1)
        let sy = sin(yaw), cyw = cos(yaw), st = sin(tilt), ct = cos(tilt)
        let cx = w / 2, cy = h / 2
        var dots: [Dot] = []
        dots.reserveCapacity(700)
        func put(_ x: Double, _ y: Double, _ L: Int, _ rBase: Double, _ rDepth: Double, _ white: Double, _ a: Double) {
            if a < 0.02 { return }
            let z = Double(1 - L) * 0.045 * depth
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            let d = clamp01(0.5 + z2 * 7)
            let r = (rBase + rDepth * (0.4 + depth) * d) * rs
            dots.append(Dot(x: cx + x1 * span, y: cy - y1 * span, z: z2, r: max(0.3, r), white: white - 0.14 * depth * (d - 0.5), a: a))
        }

        for L in 0..<3 {
            let lane = lanes[L]
            let b = 0.5 + 0.5 * sin(tb * 0.8 - Double(L) * 0.7)
            let laneA = (1 - 0.28 * Double(L)) * (0.75 + 0.25 * b)
            let ringR = 0.75 + 0.35 * b - 0.15 * Double(L)
            let ringW = 0.2 + 0.18 * Double(L)
            for mv in lane.moves {
                let p = ease(clamp01((hd - mv.delay) / 0.8))
                let lo = lane.lo[mv.i], hi = lane.hi[mv.i]
                let wx = lo.0 + (hi.0 - lo.0) * b
                let wy = lo.1 + (hi.1 - lo.1) * b
                let fx = mv.kind == .pupil ? pupilX(mv.eye, mv.pj) : mv.toX
                let fy = mv.kind == .pupil ? pupilY(mv.eye, mv.pj) : mv.toY
                var x = wx + (fx - wx) * p
                var y = wy + (fy - wy) * p
                // compact: everything squeezes towards the centre mid-way (straight in)
                let sq = 1 - 0.12 * sin(Double.pi * p)
                x = headX + (x - headX) * sq
                y = headY + (y - headY) * sq
                var a = laneA
                if mv.fade { a *= 1 - p }
                switch mv.kind {
                case .eye: put(x, y, L, 0.85, 0.4, 0.2 - 0.1 * p, a)
                case .pupil: put(x, y, L, 0.75 + 0.25 * p, 0.4, 0.2 + 0.18 * Double(L) * (1 - p) - 0.1 * p, laneA + (1 - laneA) * p)
                case .ring: put(x, y, L, ringR, 0.4, ringW, a)
                }
            }
            // places nobody reached: a dot fades in where it stands
            let grow = clamp01((hd - 0.45) / 0.55)
            if grow > 0.01 {
                for bn in lane.born {
                    switch bn.kind {
                    case .ring: put(bn.x, bn.y, L, ringR, 0.4, ringW, laneA * grow)
                    case .eye: put(bn.x, bn.y, L, 0.85, 0.4, 0.1, grow)
                    case .pupil: put(pupilX(bn.eye, bn.pj), pupilY(bn.eye, bn.pj), L, 1.0, 0.4, 0.1, grow)
                    }
                }
            }
        }
        // Kotlin's sortBy: stable, far to near.
        return dots.enumerated().sorted { $0.element.z != $1.element.z ? $0.element.z < $1.element.z : $0.offset < $1.offset }.map { $0.element }
    }

    /// thinking-orbs' painter: matte dots far to near, in `ink`; on dark themes
    /// the ink value is mirrored so near dots read bright.
    static func paint(_ dots: [Dot], in context: inout GraphicsContext, ink: (r: Double, g: Double, b: Double), dark: Bool) {
        for d in dots {
            let w = min(1, max(0, d.white))
            let a = min(1, max(0, d.a))
            let c = dark
                ? Color(.sRGB, red: ink.r * (1 - w), green: ink.g * (1 - w), blue: ink.b * (1 - w), opacity: a)
                : Color(.sRGB, red: ink.r + (1 - ink.r) * w, green: ink.g + (1 - ink.g) * w, blue: ink.b + (1 - ink.b) * w, opacity: a)
            context.fill(Path(ellipseIn: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2)), with: .color(c))
        }
    }
}
