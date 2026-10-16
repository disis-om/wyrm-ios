import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import CoreImage
import UniformTypeIdentifiers

/*
 * Trails videos (OM, 2026-10-05): "a video editor like Instagram's", at most
 * 30 seconds, compressed in the app to 360p-720p.
 *
 * The studio's camera records (hold the shutter, or tap it on the Video page;
 * `WyrmTrailCamera.swift`) or a clip comes from the gallery. The editor is the
 * photo editor itself over the playing clip: the same text, drawing, stickers
 * and looks (`WyrmTrailLooks`), plus, since 2026-10-17, a professional cut
 * (`WyrmTrailTimeline.swift`): pieces split, trimmed and dropped, transitions
 * at the cuts, a crop, and a cover picked while the picture shows that frame.
 * Export is AVAssetReader + AVAssetWriter on the pieces as one composition:
 * every frame cropped, sized (short side 720, 540 or 360, the crop's own if
 * smaller), in the look, with its transition and the overlay, by Core Image;
 * H.264 + AAC, colours in Rec. 709 (HDR clips come out SDR), the index at the
 * front of the file. The player previews the same frames, so the editor shows
 * what goes up. The server takes it as it is (`backend/src/trail-video.mjs`).
 * Wyrm Android: `ui/TrailVideo.kt`.
 *
 * The feed plays one clip at a time, the one most in view, muted until the
 * player taps for sound (`WyrmTrailFeedPlayer`).
 */

let wyrmTrailVideoMaxMs: Int64 = 30_000
let wyrmTrailVideoMinMs: Int64 = 1_000

func wyrmClipTime(_ ms: Int64) -> String {
    let s = max(0, ms / 1000)
    return String(format: "%d:%02d", s / 60, s % 60)
}

private func wyrmTime(_ ms: Int64) -> CMTime { CMTime(value: ms, timescale: 1000) }

// MARK: - Clip

/// A clip from the camera or the phone.
struct WyrmTrailClip {
    let asset: AVAsset
    let durationMs: Int64
    /// The upright size (the track's turn applied).
    let size: CGSize
    /// A copy this app made (a recording, a picked file): removed when it is no longer needed.
    let ownedFile: URL?

    var aspect: CGFloat { size.height > 0 ? size.width / size.height : 1 }

    static func probe(_ asset: AVAsset, ownedFile: URL? = nil) async -> WyrmTrailClip? {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { done.resume() }
        }
        return await Task.detached(priority: .userInitiated) { () -> WyrmTrailClip? in
            guard let track = asset.tracks(withMediaType: .video).first else { return nil }
            let seconds = CMTimeGetSeconds(asset.duration)
            guard seconds.isFinite, seconds > 0.2 else { return nil }
            let turned = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
            let size = CGSize(width: abs(turned.width).rounded(), height: abs(turned.height).rounded())
            guard size.width > 1, size.height > 1 else { return nil }
            return WyrmTrailClip(asset: asset, durationMs: Int64(seconds * 1000), size: size, ownedFile: ownedFile)
        }.value
    }

    func removeOwnedFile() {
        if let ownedFile { try? FileManager.default.removeItem(at: ownedFile) }
    }
}

enum WyrmTrailFrames {
    /// One upright frame, at most `longest` px on its long side.
    static func frame(_ clip: WyrmTrailClip, atMs: Int64, longest: CGFloat) -> UIImage? {
        let generator = AVAssetImageGenerator(asset: clip.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: longest, height: longest)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
        guard let cg = try? generator.copyCGImage(at: wyrmTime(max(0, min(atMs, clip.durationMs - 1))), actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// `count` frames across the whole clip, for the trim and cover strips.
    static func strip(_ clip: WyrmTrailClip, count: Int, longest: CGFloat) async -> [UIImage] {
        await Task.detached(priority: .userInitiated) { () -> [UIImage] in
            let generator = AVAssetImageGenerator(asset: clip.asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: longest, height: longest)
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 4)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 4)
            var out: [UIImage] = []
            for i in 0..<count {
                let ms = Int64((Double(i) + 0.5) / Double(count) * Double(clip.durationMs))
                if let cg = try? generator.copyCGImage(at: wyrmTime(ms), actualTime: nil) { out.append(UIImage(cgImage: cg)) }
            }
            return out
        }.value
    }
}

// MARK: - Editor session

/// The clip being edited (OM, 2026-10-17): its cut (`WyrmTrailEdit`: pieces,
/// transitions, crop, cover, sound) and the player that previews it. The
/// player plays the pieces as one composition, every frame drawn by the same
/// `WyrmTrailCutBox` the export uses; the look and the overlays live on the
/// studio's draft, shared with the photo editor. While a piece's end is
/// dragged the picture shows the clip itself at that moment.
@MainActor
final class WyrmTrailVideoSession: ObservableObject {
    let clip: WyrmTrailClip
    let edit: WyrmTrailEdit
    let player = AVPlayer()
    /// Where the player is in the finished video.
    @Published private(set) var playhead: Int64 = 0
    @Published private(set) var playing = false
    /// The clip itself while a piece's end is dragged; nil otherwise.
    @Published private(set) var sourceFrame: UIImage?
    private let box = WyrmTrailCutBox()
    private var renderAspect: WyrmTrailCropAspect?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rateObserver: NSKeyValueObservation?
    private var released = false
    private var frameTask: Task<Void, Never>?

    init(clip: WyrmTrailClip) {
        self.clip = clip
        edit = WyrmTrailEdit(clip: clip)
        player.actionAtItemEnd = .none
        box.set(crop: edit.crop.rect(clip))
        box.set(segments: edit.segments)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.sourceFrame == nil else { return }
                let now = Int64(CMTimeGetSeconds(time) * 1000)
                if now >= 0 { self.playhead = min(now, self.edit.totalMs) }
            }
        }
        rateObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let on = p.timeControlStatus != .paused
            Task { @MainActor in self?.playing = on }
        }
        edit.onCrop = { [weak self] in self?.cropChanged() }
    }

    /// The pieces into the player, from the playhead.
    func load(play: Bool = true) {
        guard !released, let comp = WyrmTrailCut.composition(clip, edit.segments) else { return }
        box.set(segments: edit.segments)
        box.set(crop: edit.crop.rect(clip))
        let item = AVPlayerItem(asset: comp)
        item.videoComposition = videoComposition(comp)
        renderAspect = edit.crop.aspect
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            // Round and round, as Instagram's editor plays.
            MainActor.assumeIsolated {
                guard let self, !self.released else { return }
                self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in self.player.play() }
            }
        }
        player.replaceCurrentItem(with: item)
        player.isMuted = edit.muted
        sourceFrame = nil
        player.seek(to: CMTime(value: min(playhead, max(edit.totalMs - 1, 0)), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        if play { player.play() } else { player.pause() }
    }

    /// The cut's frames at its preview size: what the export draws, smaller.
    private func videoComposition(_ comp: AVAsset) -> AVVideoComposition {
        let size = WyrmTrailCut.size(clip, WyrmTrailCrop(aspect: edit.crop.aspect), short: 720)
        let box = self.box
        let composition = AVMutableVideoComposition(asset: comp) { request in
            let ms = Int64(CMTimeGetSeconds(request.compositionTime) * 1000)
            request.finish(with: box.render(request.sourceImage, atMs: ms, out: size), context: nil)
        }
        composition.renderSize = size
        return composition
    }

    /// After a split, a delete or a trim: the same place, the new pieces.
    func reload() {
        playhead = min(max(playhead, 0), max(edit.totalMs - 1, 0))
        load(play: playing)
    }

    /// A transition picked: the frames see it at once.
    func piecesChanged() { box.set(segments: edit.segments); redraw() }

    private func cropChanged() {
        box.set(crop: edit.crop.rect(clip))
        if edit.crop.aspect != renderAspect, let item = player.currentItem {
            // A new shape is a new frame size.
            item.videoComposition = videoComposition(item.asset)
            renderAspect = edit.crop.aspect
        }
        redraw()
    }

    /// A paused frame is drawn again with what changed.
    private func redraw() {
        if player.rate == 0 { player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) }
    }

    func seekEdited(_ ms: Int64, play: Bool) {
        if sourceFrame != nil { sourceFrame = nil }
        playhead = min(max(ms, 0), edit.totalMs)
        player.seek(to: CMTime(value: playhead, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        if play { player.play() } else { player.pause() }
    }

    /// The clip itself at `sourceMs`, while a piece's end is dragged.
    func showSource(_ sourceMs: Int64) {
        player.pause()
        frameTask?.cancel()
        let clip = self.clip
        frameTask = Task { [weak self] in
            let frame = await Task.detached(priority: .userInitiated) { WyrmTrailFrames.frame(clip, atMs: sourceMs, longest: 900) }.value
            guard !Task.isCancelled, let frame else { return }
            self?.sourceFrame = frame
        }
    }

    func play() { if !released { if sourceFrame != nil { load(play: true) } else { player.play() } } }
    func pause() { player.pause() }
    func togglePlay() { if player.timeControlStatus == .paused { play() } else { pause() } }

    /// The look the export will burn in; a paused frame is drawn again with it.
    func setLook(_ look: WyrmTrailLook, _ adjust: WyrmTrailAdjust) {
        box.set(look, adjust)
        redraw()
    }

    func toggleSound() {
        edit.muted.toggle()
        player.isMuted = edit.muted
    }

    func release() {
        guard !released else { return }
        released = true
        frameTask?.cancel()
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        rateObserver = nil
        player.replaceCurrentItem(with: nil)
    }
}

/// The playing cut under the studio's canvas; the clip itself while a
/// piece's end is dragged (the crop applied the same way).
struct WyrmTrailVideoStage: View {
    @ObservedObject var session: WyrmTrailVideoSession
    var body: some View {
        ZStack {
            Color.black
            WyrmTrailPlayerView(player: session.player, fill: true)
            if let frame = session.sourceFrame {
                GeometryReader { proxy in
                    let r = session.edit.crop.rect(session.clip)
                    let fullW = proxy.size.width / max(r.width, 0.01)
                    let fullH = proxy.size.height / max(r.height, 0.01)
                    Image(uiImage: frame).resizable()
                        .frame(width: fullW, height: fullH)
                        .offset(x: -r.minX * fullW, y: -r.minY * fullH)
                }
                .clipped()
            }
        }
    }
}

/// An AVPlayer on screen; the picture fades in once its first frame is ready.
struct WyrmTrailPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    var fill = false

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var ready: NSKeyValueObservation?
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            playerLayer.opacity = 0
            ready = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                DispatchQueue.main.async {
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.18)
                    layer.opacity = layer.isReadyForDisplay ? 1 : 0
                    CATransaction.commit()
                }
            }
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.playerLayer.player = nil }
}

// MARK: - Export

enum WyrmTrailVideoError: Error { case unreadable, failed }

/// The cut, sized, in its look, with its transitions and the overlay, into
/// one small MP4, on the phone. Size tiers by the short side of the cropped
/// picture: 720 (about 3.5 Mbit/s since 2026-10-17, OM: 720p without losing
/// quality), 540 (2.0), 360 (1.0); never scaled up; a file over 15 MB is made
/// again one tier lower. Same tiers as Android.
enum WyrmTrailVideoExport {
    static let maxBytes = 15 * 1024 * 1024
    private static let tiers: [(short: CGFloat, bitrate: Int)] = [(720, 3_500_000), (540, 2_000_000), (360, 1_000_000)]

    static func outputSize(_ spec: WyrmTrailEditSpec, tier: Int) -> CGSize {
        WyrmTrailCut.size(spec.clip, spec.crop, short: tiers[tier].short)
    }

    static var tierCount: Int { tiers.count }

    /// `overlays[tier]`: everything drawn on top at that tier's `outputSize`
    /// (nil: nothing on top), drawn by the caller on the main thread.
    static func export(_ spec: WyrmTrailEditSpec, look: WyrmTrailLook, adjust: WyrmTrailAdjust, overlays: [UIImage?],
                       progress: @escaping (Double) -> Void) async throws -> URL {
        for tier in tiers.indices {
            let size = outputSize(spec, tier: tier)
            let top = tier < overlays.count ? overlays[tier] : nil
            let file = try await once(spec, look: look, adjust: adjust, overlay: top, size: size, bitrate: tiers[tier].bitrate, progress: progress)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            if bytes <= maxBytes || tier == tiers.count - 1 { return file }
            try? FileManager.default.removeItem(at: file)
        }
        throw WyrmTrailVideoError.failed
    }

    private static func once(_ spec: WyrmTrailEditSpec, look: WyrmTrailLook, adjust: WyrmTrailAdjust, overlay: UIImage?, size: CGSize,
                             bitrate: Int, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let asset = WyrmTrailCut.composition(spec.clip, spec.segments) else { throw WyrmTrailVideoError.unreadable }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("wyrm-trail-\(UUID().uuidString).mp4")
        let videoTracks = asset.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw WyrmTrailVideoError.unreadable }
        let range = CMTimeRange(start: .zero, duration: asset.duration)

        // Every frame: upright (done by the composition), cropped, sized, the look, the transition, the overlay.
        let box = WyrmTrailCutBox()
        box.lanczos = true
        box.set(crop: spec.crop.rect(spec.clip))
        box.set(segments: spec.segments)
        box.set(look, adjust)
        let top: CIImage? = overlay?.cgImage.map { CIImage(cgImage: $0) }
        let frame = CGRect(origin: .zero, size: size)
        let composition = AVMutableVideoComposition(asset: asset) { request in
            let ms = Int64(CMTimeGetSeconds(request.compositionTime) * 1000)
            var image = box.render(request.sourceImage, atMs: ms, out: size)
            if let top { image = top.composited(over: image) }
            request.finish(with: image.cropped(to: frame), context: nil)
        }
        composition.renderSize = size
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOutput.videoComposition = composition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw WyrmTrailVideoError.unreadable }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        let audioTracks = asset.tracks(withMediaType: .audio)
        if !spec.muted && !audioTracks.isEmpty {
            let pcm = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            if reader.canAdd(pcm) { reader.add(pcm); audioOutput = pcm }
        }

        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw WyrmTrailVideoError.failed }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let aac = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 96_000,
            ])
            aac.expectsMediaDataInRealTime = false
            if writer.canAdd(aac) { writer.add(aac); audioInput = aac }
        }

        guard reader.startReading() else { throw reader.error ?? WyrmTrailVideoError.unreadable }
        guard writer.startWriting() else { reader.cancelReading(); throw writer.error ?? WyrmTrailVideoError.failed }
        writer.startSession(atSourceTime: .zero)
        let total = max(CMTimeGetSeconds(range.duration), 0.001)

        await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                let group = DispatchGroup()
                func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, label: String, video: Bool) {
                    group.enter()
                    var finished = false
                    input.requestMediaDataWhenReady(on: DispatchQueue(label: "wyrm.trails.export.\(label)")) {
                        guard !finished else { return }
                        while input.isReadyForMoreMediaData {
                            guard reader.status == .reading, let sample = output.copyNextSampleBuffer() else {
                                finished = true
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                            if !input.append(sample) {
                                finished = true
                                reader.cancelReading()
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                            if video {
                                let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                                if t.isFinite { progress(min(max(t / total, 0), 1)) }
                            }
                        }
                    }
                }
                pump(videoInput, videoOutput, label: "video", video: true)
                if let audioInput, let audioOutput { pump(audioInput, audioOutput, label: "audio", video: false) }
                group.notify(queue: .global(qos: .userInitiated)) { done.resume() }
            }
        } onCancel: {
            reader.cancelReading()
        }

        if Task.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: out)
            throw CancellationError()
        }
        if reader.status == .failed || writer.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: out)
            throw reader.error ?? writer.error ?? WyrmTrailVideoError.failed
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in writer.finishWriting { done.resume() } }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw writer.error ?? WyrmTrailVideoError.failed
        }
        progress(1)
        return out
    }

    /// The poster: the cover frame, cropped, in the look with everything drawn
    /// on top, the size of the 720p tier.
    static func poster(_ spec: WyrmTrailEditSpec, look: WyrmTrailLook, adjust: WyrmTrailAdjust,
                       overlay: (CGSize) -> UIImage?) -> UIImage? {
        let size = outputSize(spec, tier: 0)
        let r = spec.crop.rect(spec.clip)
        let longest = min(max(max(size.width / max(r.width, 0.05), size.height / max(r.height, 0.05)), 256), 2400)
        guard let raw = WyrmTrailFrames.frame(spec.clip, atMs: spec.sourceAt(spec.coverMs), longest: longest) else { return nil }
        let base = WyrmTrailLooks.apply(raw, look, adjust)
        let top = overlay(size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // The crop of the frame fills the poster.
            let fullW = size.width / max(r.width, 0.01), fullH = size.height / max(r.height, 0.01)
            context.cgContext.interpolationQuality = .high
            base.draw(in: CGRect(x: -r.minX * fullW, y: -r.minY * fullH, width: fullW, height: fullH))
            top?.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Feed

/// One player for the whole feed: the video card most in view plays, muted
/// until the player taps for sound; every other card shows its poster.
final class WyrmTrailFeedPlayer: ObservableObject {
    static let shared = WyrmTrailFeedPlayer()
    let player = AVPlayer()
    /// The trail that should play (the card nearest the middle of the feed).
    @Published var activeId: String?
    @Published private(set) var current: String?
    @Published private(set) var muted = true
    private var endObserver: NSObjectProtocol?
    private var paused = false

    private init() {
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func attach(_ id: String, url: URL) {
        paused = false
        if current == id {
            player.play()
            return
        }
        current = id
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 4
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        player.replaceCurrentItem(with: item)
        player.isMuted = muted
        player.play()
    }

    func detach(_ id: String) {
        guard current == id else { return }
        player.pause()
    }

    func toggleSound() {
        muted.toggle()
        player.isMuted = muted
    }

    func pause() { paused = true; player.pause() }
    func resume() { if current != nil && current == activeId { paused = false; player.play() } }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        current = nil
        activeId = nil
    }
}

/// Where each video card sits in the feed, by trail id (its middle, in the
/// feed's own coordinates).
struct WyrmTrailVideoSpots: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A video trail in a card: the poster at once, the clip over it while this
/// card is the one playing, a sound button and its length.
struct WyrmTrailVideoView: View {
    let trailId: String
    let video: WyrmTrailVideo
    let poster: String
    let thumb: String
    let aspect: CGFloat
    let active: Bool
    @ObservedObject private var feed = WyrmTrailFeedPlayer.shared

    var body: some View {
        let playing = active && feed.current == trailId
        WyrmTrailImage(full: poster, thumb: thumb, aspect: aspect)
            .overlay(Group { if playing { WyrmTrailPlayerView(player: feed.player, fill: false) } })
            .overlay(alignment: .bottomTrailing) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    feed.toggleSound()
                } label: {
                    Image(systemName: feed.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                if !playing {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        Text(wyrmClipTime(video.durationMs)).font(.androidWyrm(11, .bold)).monospacedDigit()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).frame(height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(10)
                }
            }
            .onChange(of: active) { on in sync(on) }
            .onAppear { sync(active) }
            .onDisappear { feed.detach(trailId) }
    }

    private func sync(_ on: Bool) {
        if on, let url = URL(string: WyrmTrailsClient.absolute(video.url)) {
            feed.attach(trailId, url: url)
        } else {
            feed.detach(trailId)
        }
    }
}
