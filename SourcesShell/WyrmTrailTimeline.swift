import SwiftUI
import UIKit
import AVFoundation
import CoreImage

/*
 * The video editor's timeline (OM, 2026-10-17): "professional, like
 * Instagram's editor". A trail video is one clip from the phone cut into
 * pieces:
 *
 *   - pieces (`WyrmTrailSegment`) in order, each a stretch of the clip; Split
 *     cuts the piece under the playhead in two, Delete drops one (so a middle
 *     part can go), and the ends of the chosen piece are dragged to trim it.
 *     The whole video is at most 30 s, a piece at least half a second;
 *   - a transition after each piece but the last: None, Fade (through black),
 *     Flash (through white) or Zoom (a punch in), 0.2 s on each side of the cut;
 *   - a crop (`WyrmTrailCrop`): a shape (the clip's own, 9:16, 4:5, 1:1, 16:9)
 *     and where it sits on the clip, dragged and pinched;
 *   - the cover, a time in the finished video, chosen on a strip while the
 *     picture above shows that very frame.
 *
 * The pieces become one AVMutableComposition; every frame of it, in the
 * editor and in the export alike, is drawn by `WyrmTrailCutBox.render`: crop,
 * size, look, transition. What the editor plays is what goes up. Android:
 * `ui/TrailTimeline.kt`, the same rules and numbers.
 */

let wyrmTrailSegmentMinMs: Int64 = 500
/// Each side of a cut: the transition runs this long before it and this long after.
let wyrmTrailTransitionHalfMs: Int64 = 200

enum WyrmTrailTransition: String, CaseIterable { case none = "None", fade = "Fade", flash = "Flash", zoom = "Zoom" }

/// One piece of the clip, in its own milliseconds, and how it hands over to the next.
struct WyrmTrailSegment: Identifiable, Equatable {
    let id: Int
    var startMs: Int64
    var endMs: Int64
    var after: WyrmTrailTransition = .none
    var lengthMs: Int64 { endMs - startMs }
}

enum WyrmTrailCropAspect: String, CaseIterable {
    case original = "Original", story = "9:16", portrait = "4:5", square = "1:1", wide = "16:9"
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .story: return 9.0 / 16.0
        case .portrait: return 0.8
        case .square: return 1
        case .wide: return 16.0 / 9.0
        }
    }
}

/// The crop: a shape, a zoom (1 = the largest such shape that fits the clip)
/// and the middle of what is shown, in 0...1 of the clip's upright frame.
struct WyrmTrailCrop: Equatable {
    var aspect: WyrmTrailCropAspect = .original
    var zoom: CGFloat = 1
    var cx: CGFloat = 0.5
    var cy: CGFloat = 0.5

    func ratio(_ clip: WyrmTrailClip) -> CGFloat { aspect.ratio ?? clip.aspect }

    /// What is shown, in 0...1 of the clip, the top left first.
    func rect(_ clip: WyrmTrailClip) -> CGRect {
        let source = clip.aspect
        let target = ratio(clip)
        var w: CGFloat = target < source ? target / source : 1
        var h: CGFloat = target < source ? 1 : source / target
        w /= max(zoom, 1)
        h /= max(zoom, 1)
        let left = min(max(cx - w / 2, 0), 1 - w)
        let top = min(max(cy - h / 2, 0), 1 - h)
        return CGRect(x: left, y: top, width: w, height: h)
    }

    func clamped(_ clip: WyrmTrailClip) -> WyrmTrailCrop {
        var next = self
        next.zoom = min(max(zoom, 1), 4)
        let r = next.rect(clip)
        next.cx = r.midX
        next.cy = r.midY
        return next
    }

    /// A drag of `pan` canvas points on a canvas of `size`, and a pinch by `scale`.
    func moved(_ clip: WyrmTrailClip, pan: CGSize, scale: CGFloat, canvas size: CGSize) -> WyrmTrailCrop {
        let r = rect(clip)
        var next = self
        next.zoom = min(max(zoom * scale, 1), 4)
        next.cx = cx - pan.width / max(size.width, 1) * r.width
        next.cy = cy - pan.height / max(size.height, 1) * r.height
        return next.clamped(clip)
    }

    var untouched: Bool { aspect == .original && zoom <= 1.001 }
}

/// Everything the export needs, fixed at the moment Post is tapped.
struct WyrmTrailEditSpec {
    let clip: WyrmTrailClip
    let segments: [WyrmTrailSegment]
    let crop: WyrmTrailCrop
    let muted: Bool
    /// In the finished video's own time.
    let coverMs: Int64

    var totalMs: Int64 { segments.reduce(0) { $0 + $1.lengthMs } }

    /// The clip's own time at `editedMs` of the finished video.
    func sourceAt(_ editedMs: Int64) -> Int64 {
        var left = max(editedMs, 0)
        for s in segments {
            if left < s.lengthMs { return s.startMs + left }
            left -= s.lengthMs
        }
        return max((segments.last?.endMs ?? 1) - 1, 0)
    }
}

/// How strong a transition is at a moment: which kind, and 0...1 (1 at the cut itself).
enum WyrmTrailTransitions {
    static let zoom: CGFloat = 0.22

    static func halfAfter(_ segments: [WyrmTrailSegment], _ index: Int) -> Int64 {
        guard index >= 0, index + 1 < segments.count else { return 0 }
        return min(wyrmTrailTransitionHalfMs, min(segments[index].lengthMs, segments[index + 1].lengthMs) / 2)
    }

    /// In the finished video's time: the nearest cut with a transition.
    static func at(_ segments: [WyrmTrailSegment], _ editedMs: Int64) -> (WyrmTrailTransition, CGFloat) {
        var start: Int64 = 0
        for i in 0..<max(segments.count - 1, 0) {
            start += segments[i].lengthMs
            let kind = segments[i].after
            guard kind != .none else { continue }
            let d = abs(editedMs - start)
            let half = halfAfter(segments, i)
            if half > 0 && d < half { return (kind, 1 - CGFloat(d) / CGFloat(half)) }
        }
        return (.none, 0)
    }
}

/// The cut being edited: pieces, crop, cover and sound.
@MainActor
final class WyrmTrailEdit: ObservableObject {
    let clip: WyrmTrailClip
    @Published private(set) var segments: [WyrmTrailSegment]
    @Published var crop = WyrmTrailCrop() { didSet { if crop != oldValue { onCrop?() } } }
    @Published var coverMs: Int64 = 0
    @Published var muted = false
    /// The chosen piece: its ends can be trimmed, Delete removes it.
    @Published var selected: Int? = 1
    /// The cut whose transition is being picked (the index of the piece before it), or -1.
    @Published var transitionAt = -1
    private var nextId = 2
    /// The session's: the pieces or the crop changed.
    var onCrop: (@MainActor () -> Void)?

    init(clip: WyrmTrailClip) {
        self.clip = clip
        segments = [WyrmTrailSegment(id: 1, startMs: 0, endMs: min(clip.durationMs, wyrmTrailVideoMaxMs))]
    }

    var totalMs: Int64 { segments.reduce(0) { $0 + $1.lengthMs } }

    func startOf(_ index: Int) -> Int64 { segments.prefix(max(0, min(index, segments.count))).reduce(0) { $0 + $1.lengthMs } }

    /// The piece at `editedMs` of the finished video and how far into it.
    func locate(_ editedMs: Int64) -> (Int, Int64) {
        var left = min(max(editedMs, 0), max(totalMs - 1, 0))
        for (i, s) in segments.enumerated() {
            if left < s.lengthMs { return (i, left) }
            left -= s.lengthMs
        }
        return (max(segments.count - 1, 0), segments.last?.lengthMs ?? 0)
    }

    func spec() -> WyrmTrailEditSpec {
        WyrmTrailEditSpec(clip: clip, segments: segments, crop: crop.clamped(clip), muted: muted, coverMs: min(max(coverMs, 0), totalMs))
    }

    /// Cuts the piece under `editedMs` in two; false when either half would be too short.
    func split(at editedMs: Int64) -> Bool {
        let (index, into) = locate(editedMs)
        guard index < segments.count else { return false }
        let s = segments[index]
        guard into >= wyrmTrailSegmentMinMs, s.lengthMs - into >= wyrmTrailSegmentMinMs else { return false }
        let cut = s.startMs + into
        let second = WyrmTrailSegment(id: nextId, startMs: cut, endMs: s.endMs, after: s.after)
        nextId += 1
        segments[index].endMs = cut
        segments[index].after = .none
        segments.insert(second, at: index + 1)
        selected = second.id
        return true
    }

    /// Drops a piece; the last one stays.
    func delete(_ id: Int) -> Bool {
        guard segments.count > 1, let index = segments.firstIndex(where: { $0.id == id }) else { return false }
        segments.remove(at: index)
        // The piece before a dropped last piece has no cut after it any more.
        if index == segments.count { segments[index - 1].after = .none }
        selected = segments[min(index, segments.count - 1)].id
        coverMs = min(max(coverMs, 0), totalMs)
        transitionAt = -1
        return true
    }

    /// New ends for a piece, kept inside the clip, at least half a second, the whole at most 30 s.
    func trim(_ id: Int, start: Int64, end: Int64) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        let s = segments[index]
        let others = totalMs - s.lengthMs
        let room = max(wyrmTrailVideoMaxMs - others, wyrmTrailSegmentMinMs)
        var a = min(max(start, 0), clip.durationMs - wyrmTrailSegmentMinMs)
        var b = min(max(end, a + wyrmTrailSegmentMinMs), clip.durationMs)
        if b - a > room {
            // The end that moved gives way.
            if a != s.startMs { a = b - room } else { b = a + room }
        }
        segments[index].startMs = a
        segments[index].endMs = b
        coverMs = min(max(coverMs, 0), totalMs)
    }

    func setTransition(_ index: Int, _ kind: WyrmTrailTransition) {
        guard index >= 0, index < segments.count - 1 else { return }
        segments[index].after = kind
    }
}

// MARK: - Frames

/// What every frame of the cut is drawn with, read from the video
/// composition's thread: the crop, the pieces (for the transitions) and the look.
final class WyrmTrailCutBox {
    private let lock = NSLock()
    private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var segments: [WyrmTrailSegment] = []
    private var matrix: WyrmLookMatrix?
    /// The export scales with Lanczos; the editor's preview with a plain transform.
    var lanczos = false

    func set(crop: CGRect) { lock.lock(); self.crop = crop; lock.unlock() }
    func set(segments: [WyrmTrailSegment]) { lock.lock(); self.segments = segments; lock.unlock() }
    func set(_ look: WyrmTrailLook, _ adjust: WyrmTrailAdjust) {
        let next = WyrmTrailLooks.isIdentity(look, adjust) ? nil : WyrmTrailLooks.matrix(look, adjust)
        lock.lock(); matrix = next; lock.unlock()
    }

    /// One frame: the upright source, cropped, scaled to `out`, the look, the transition at `ms`.
    func render(_ source: CIImage, atMs ms: Int64, out: CGSize) -> CIImage {
        lock.lock()
        let r = crop, pieces = segments, look = matrix
        lock.unlock()
        let extent = source.extent
        let w = extent.width, h = extent.height
        // Core Image counts from the bottom left; the crop from the top left.
        let region = CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: max(r.width * w, 1), height: max(r.height * h, 1))
        var image = source
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
        let sx = out.width / region.width, sy = out.height / region.height
        if lanczos {
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: sy, kCIInputAspectRatioKey: sx / sy,
            ])
        } else {
            image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        if let look { image = WyrmTrailLooks.apply(image, look) }
        let (kind, k) = WyrmTrailTransitions.at(pieces, ms)
        let frame = CGRect(origin: .zero, size: out)
        switch kind {
        case .fade, .flash:
            let keep = 1 - k
            let lift = kind == .flash ? k : 0
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: keep, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: keep, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: keep, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: lift, y: lift, z: lift, w: 0),
            ])
        case .zoom:
            let s = 1 + WyrmTrailTransitions.zoom * k
            image = image.transformed(by: CGAffineTransform(translationX: -out.width / 2, y: -out.height / 2)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: out.width / 2, y: out.height / 2)))
        case .none:
            break
        }
        return image.cropped(to: frame)
    }
}

enum WyrmTrailCut {
    /// The pieces, one after another, as one asset (video and sound).
    static func composition(_ clip: WyrmTrailClip, _ segments: [WyrmTrailSegment]) -> AVMutableComposition? {
        let comp = AVMutableComposition()
        guard let source = clip.asset.tracks(withMediaType: .video).first,
              let video = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        video.preferredTransform = source.preferredTransform
        let sourceAudio = clip.asset.tracks(withMediaType: .audio).first
        let audio = sourceAudio == nil ? nil : comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var at = CMTime.zero
        for s in segments {
            let range = CMTimeRange(start: CMTime(value: s.startMs, timescale: 1000), end: CMTime(value: s.endMs, timescale: 1000))
            do { try video.insertTimeRange(range, of: source, at: at) } catch { return nil }
            if let audio, let sourceAudio { try? audio.insertTimeRange(range, of: sourceAudio, at: at) }
            at = CMTimeAdd(at, range.duration)
        }
        return comp
    }

    /// The size of the cut's frame at a short side of at most `short`: even sides, the crop's shape, never scaled up.
    static func size(_ clip: WyrmTrailClip, _ crop: WyrmTrailCrop, short: CGFloat) -> CGSize {
        let r = crop.rect(clip)
        let cw = r.width * clip.size.width, ch = r.height * clip.size.height
        let side = max(min(cw, ch), 2)
        let target = max(min(short, side), 2)
        let k = target / side
        func even(_ v: CGFloat) -> CGFloat { max(2, (v * k / 2).rounded() * 2) }
        return CGSize(width: even(cw), height: even(ch))
    }
}

// MARK: - The bar

/// Under the playing clip: play and time, sound, the timeline of pieces with
/// a transition button at each cut, and Split / Delete. A drag on the
/// timeline scrubs; a drag on the chosen piece's ends trims it.
struct WyrmTrailTimelineBar: View {
    @ObservedObject var session: WyrmTrailVideoSession
    @ObservedObject var edit: WyrmTrailEdit
    @State private var frames: [UIImage] = []

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                iconButton(session.playing ? "pause.fill" : "play.fill") { session.togglePlay() }
                Text("\(wyrmTrailClock(session.playhead)) / \(wyrmTrailClock(edit.totalMs))")
                    .font(.androidWyrm(12.5, .bold)).monospacedDigit().foregroundColor(ATheme.ink)
                Spacer()
                iconButton(edit.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { session.toggleSound() }
            }
            WyrmTrailPieces(session: session, edit: edit, frames: frames)
            if edit.transitionAt >= 0 && edit.transitionAt < edit.segments.count - 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Transition").font(.androidWyrm(12, .bold)).foregroundColor(ATheme.mute)
                        ForEach(WyrmTrailTransition.allCases, id: \.self) { kind in
                            WyrmTrailPill(label: kind.rawValue, selected: edit.segments[edit.transitionAt].after == kind) {
                                UISelectionFeedbackGenerator().selectionChanged()
                                let at = edit.transitionAt
                                edit.setTransition(at, kind)
                                session.piecesChanged()
                                // Shows it: from just before the cut.
                                session.seekEdited(max(edit.startOf(at + 1) - 700, 0), play: true)
                            }
                        }
                        WyrmTrailPill(label: "Done", selected: true) { edit.transitionAt = -1 }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    WyrmTrailPill(label: "Split", selected: false, symbol: "scissors") {
                        if edit.split(at: session.playhead) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            session.reload()
                        } else {
                            WyrmTrailsStore.shared.toast = "Move the playhead into a longer piece to split it."
                        }
                    }
                    if edit.segments.count > 1, let chosen = edit.selected {
                        WyrmTrailPill(label: "Delete", selected: false, symbol: "trash") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if edit.delete(chosen) { session.reload() }
                        }
                    }
                    Spacer()
                    Text(String(format: "%.1f s of %d s", Double(edit.totalMs) / 1000, Int(wyrmTrailVideoMaxMs / 1000)))
                        .font(.androidWyrm(11.5, .semibold))
                        .foregroundColor(edit.totalMs >= wyrmTrailVideoMaxMs ? ATheme.badge : ATheme.quiet)
                }
            }
        }
        .padding(.horizontal, 14)
        .task { frames = await WyrmTrailFrames.strip(session.clip, count: 24, longest: 120) }
    }

    private func iconButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundColor(ATheme.ink)
                .frame(width: 36, height: 36).background(Circle().fill(ATheme.well))
        }
        .buttonStyle(.plain)
    }
}

/// The pieces side by side, each as wide as it is long; a diamond at each cut.
private struct WyrmTrailPieces: View {
    @ObservedObject var session: WyrmTrailVideoSession
    @ObservedObject var edit: WyrmTrailEdit
    let frames: [UIImage]
    @State private var grab = 0 // 1 left end, 2 right end, 3 scrub, -1 decided nothing yet
    @State private var began = false
    @State private var startPiece: WyrmTrailSegment?
    @State private var scale: CGFloat = 1
    @State private var wasPlaying = false
    @State private var moved: CGFloat = 0

    private let gap: CGFloat = 16
    private let handle: CGFloat = 12
    private let gold = Color(red: 0.95, green: 0.72, blue: 0.29)

    var body: some View {
        GeometryReader { proxy in
            let count = edit.segments.count
            let usable = max(proxy.size.width - gap * CGFloat(count - 1), 1)
            let pxPerMs = usable / CGFloat(max(edit.totalMs, 1))
            let lefts: [CGFloat] = {
                var out: [CGFloat] = []
                var x: CGFloat = 0
                for s in edit.segments { out.append(x); x += CGFloat(s.lengthMs) * pxPerMs + gap }
                return out
            }()
            ZStack(alignment: .topLeading) {
                ForEach(Array(edit.segments.enumerated()), id: \.element.id) { i, s in
                    let w = CGFloat(s.lengthMs) * pxPerMs
                    piece(s, width: w)
                        .frame(width: max(w, 1), height: 48)
                        .offset(x: lefts[i], y: 5)
                }
                let px = xOf(session.playhead, lefts: lefts, pxPerMs: pxPerMs)
                Rectangle().fill(Color.white).frame(width: 3, height: 58)
                    .shadow(color: .black.opacity(0.35), radius: 1)
                    .offset(x: px - 1.5)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: 58, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !began {
                        began = true
                        moved = 0
                        wasPlaying = session.playing
                        scale = pxPerMs
                        grab = 0
                        startPiece = nil
                        if let i = edit.segments.firstIndex(where: { $0.id == edit.selected }) {
                            let l = lefts[i], r = l + CGFloat(edit.segments[i].lengthMs) * pxPerMs
                            let x = value.startLocation.x
                            if abs(x - l) < handle * 1.8 { grab = 1 } else if abs(x - r) < handle * 1.8 { grab = 2 }
                            if grab != 0 {
                                startPiece = edit.segments[i]
                                session.pause()
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                    }
                    moved = max(moved, abs(value.translation.width))
                    let dxMs = Int64(value.translation.width / max(scale, 0.0001))
                    if let s = startPiece, grab == 1 {
                        edit.trim(s.id, start: s.startMs + dxMs, end: s.endMs)
                        if let now = edit.segments.first(where: { $0.id == s.id }) { session.showSource(now.startMs) }
                    } else if let s = startPiece, grab == 2 {
                        edit.trim(s.id, start: s.startMs, end: s.endMs + dxMs)
                        if let now = edit.segments.first(where: { $0.id == s.id }) { session.showSource(now.endMs - 1) }
                    } else if moved > 6 {
                        if session.playing { session.pause() }
                        session.seekEdited(editedOf(value.location.x, lefts: lefts, pxPerMs: pxPerMs), play: false)
                    }
                }
                .onEnded { value in
                    if grab != 0 {
                        session.reload()
                    } else if moved <= 6 {
                        // A tap chooses the piece and puts the playhead there.
                        let at = editedOf(value.location.x, lefts: lefts, pxPerMs: pxPerMs)
                        let (i, _) = edit.locate(at)
                        edit.selected = edit.segments.indices.contains(i) ? edit.segments[i].id : nil
                        edit.transitionAt = -1
                        UISelectionFeedbackGenerator().selectionChanged()
                        session.seekEdited(at, play: wasPlaying)
                    } else if wasPlaying {
                        session.play()
                    }
                    began = false
                    grab = 0
                    startPiece = nil
                })
            // A diamond at each cut: its transition.
            ForEach(0..<max(count - 1, 0), id: \.self) { i in
                let kind = edit.segments[i].after
                let on = edit.transitionAt == i
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    edit.transitionAt = on ? -1 : i
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(on || kind != .none ? ATheme.ink : ATheme.card)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(ATheme.ink, lineWidth: 1.5))
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(45))
                        Text(kind == .none ? "+" : String(kind.rawValue.prefix(1)))
                            .font(.androidWyrm(11, .bold)).foregroundColor(on || kind != .none ? ATheme.onInk : ATheme.ink)
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: lefts[i + 1] - gap / 2, y: 29)
            }
        }
        .frame(height: 58)
    }

    @ViewBuilder
    private func piece(_ s: WyrmTrailSegment, width: CGFloat) -> some View {
        let chosen = s.id == edit.selected
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                let tiles = max(Int((width / 30).rounded(.up)), 1)
                ForEach(0..<tiles, id: \.self) { t in
                    let ms = s.startMs + Int64((CGFloat(t) + 0.5) / CGFloat(tiles) * CGFloat(s.lengthMs))
                    let index = frames.isEmpty ? -1 : min(max(Int(CGFloat(ms) / CGFloat(max(session.clip.durationMs, 1)) * CGFloat(frames.count)), 0), frames.count - 1)
                    Group {
                        if index >= 0 { Image(uiImage: frames[index]).resizable().scaledToFill() } else { ATheme.well }
                    }
                    .frame(width: width / CGFloat(tiles), height: 48)
                    .clipped()
                }
            }
            if chosen {
                Rectangle().stroke(gold, lineWidth: 3)
                gold.frame(width: handle)
                    .overlay(Capsule().fill(Color.black.opacity(0.55)).frame(width: 2, height: 16))
                gold.frame(width: handle).offset(x: width - handle)
                    .overlay(Capsule().fill(Color.black.opacity(0.55)).frame(width: 2, height: 16).offset(x: width - handle))
            } else {
                Color.black.opacity(0.18)
            }
        }
        .clipped()
    }

    private func xOf(_ ms: Int64, lefts: [CGFloat], pxPerMs: CGFloat) -> CGFloat {
        let (i, into) = edit.locate(ms)
        return (lefts.indices.contains(i) ? lefts[i] : 0) + CGFloat(into) * pxPerMs
    }

    private func editedOf(_ x: CGFloat, lefts: [CGFloat], pxPerMs: CGFloat) -> Int64 {
        for (i, s) in edit.segments.enumerated() where i < lefts.count {
            let l = lefts[i], r = l + CGFloat(s.lengthMs) * pxPerMs
            if x <= r + gap / 2 || i == edit.segments.count - 1 {
                let into = min(max(Int64((x - l) / max(pxPerMs, 0.0001)), 0), s.lengthMs - 1)
                return edit.startOf(i) + into
            }
        }
        return 0
    }
}

/// The cover (OM, 2026-10-17): a strip of the finished video and a window on
/// it. While the window is dragged the picture above shows that frame, and
/// the window itself shows it too.
struct WyrmTrailCoverBar: View {
    @ObservedObject var session: WyrmTrailVideoSession
    @ObservedObject var edit: WyrmTrailEdit
    let done: () -> Void
    @State private var frames: [UIImage] = []
    @State private var cover: UIImage?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Cover").font(.androidWyrm(14, .bold)).foregroundColor(ATheme.ink)
                Text("Drag to pick the picture people see first").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                WyrmTrailPill(label: "Done", selected: true, action: done)
            }
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let window: CGFloat = 48
                let total = CGFloat(max(edit.totalMs, 1))
                let x = CGFloat(edit.coverMs) / total * (width - window)
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        if frames.isEmpty { ATheme.well } else {
                            ForEach(frames.indices, id: \.self) { i in
                                Image(uiImage: frames[i]).resizable().scaledToFill()
                                    .frame(width: width / CGFloat(frames.count), height: 48).clipped()
                            }
                        }
                    }
                    .frame(height: 48)
                    .overlay(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    ZStack {
                        ATheme.well
                        if let shown = cover ?? nearest(total) { Image(uiImage: shown).resizable().scaledToFill() }
                    }
                    .frame(width: window, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white, lineWidth: 3))
                    .offset(x: x)
                }
                .frame(width: width, height: 70)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let f = min(max((value.location.x - window / 2) / max(width - window, 1), 0), 1)
                    let ms = Int64(f * (total - 1))
                    if ms != edit.coverMs {
                        edit.coverMs = ms
                        cover = nil
                        session.seekEdited(ms, play: false)
                    }
                })
            }
            .frame(height: 70)
        }
        .padding(.horizontal, 14)
        .onAppear {
            session.pause()
            session.seekEdited(edit.coverMs, play: false)
        }
        .task(id: edit.segments) {
            let spec = edit.spec()
            frames = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
                (0..<10).compactMap { i in
                    WyrmTrailFrames.frame(spec.clip, atMs: spec.sourceAt(Int64(Double(spec.totalMs) * (Double(i) + 0.5) / 10)), longest: 120)
                }
            }.value
        }
        .task(id: edit.coverMs) {
            try? await Task.sleep(nanoseconds: 90_000_000)
            let spec = edit.spec()
            let at = spec.sourceAt(spec.coverMs)
            let frame = await Task.detached(priority: .userInitiated) { WyrmTrailFrames.frame(spec.clip, atMs: at, longest: 200) }.value
            if !Task.isCancelled { cover = frame }
        }
    }

    private func nearest(_ total: CGFloat) -> UIImage? {
        guard !frames.isEmpty else { return nil }
        let i = min(max(Int(CGFloat(edit.coverMs) / total * CGFloat(frames.count)), 0), frames.count - 1)
        return frames[i]
    }
}

/// The crop shapes for a video, and Done.
struct WyrmTrailCropBar: View {
    @ObservedObject var edit: WyrmTrailEdit
    let done: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WyrmTrailCropAspect.allCases, id: \.self) { aspect in
                        WyrmTrailPill(label: aspect.rawValue, selected: edit.crop.aspect == aspect) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            edit.crop = WyrmTrailCrop(aspect: aspect).clamped(edit.clip)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                if !edit.crop.untouched { WyrmTrailPill(label: "Reset", selected: false) { edit.crop = WyrmTrailCrop() } }
                WyrmTrailPill(label: "Done", selected: true, action: done)
            }
            Text("Drag and pinch the video to frame it").font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet)
        }
    }
}

struct WyrmTrailPill: View {
    let label: String
    let selected: Bool
    var symbol: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
                Text(label).font(.androidWyrm(12.5, .bold))
            }
            .foregroundColor(selected ? ATheme.onInk : ATheme.ink)
            .padding(.horizontal, 13).frame(height: 32)
            .background(Capsule().fill(selected ? ATheme.ink : ATheme.well))
        }
        .buttonStyle(.plain)
    }
}

/// "0:04.2": the timeline's clock.
func wyrmTrailClock(_ ms: Int64) -> String {
    let t = max(ms, 0)
    return String(format: "%d:%02d.%d", t / 60_000, (t / 1000) % 60, (t / 100) % 10)
}
