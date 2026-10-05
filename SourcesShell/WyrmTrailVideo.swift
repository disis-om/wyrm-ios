import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import CoreImage
import UniformTypeIdentifiers

/*
 * Trails videos (OM, 2026-10-05): "a video editor like Instagram's", clips of
 * at most 30 seconds, compressed in the app to 360p-720p.
 *
 * The studio's Video page records (at most 30 s) or takes a clip from the
 * phone. The editor is the photo editor itself over the playing clip: the same
 * text, drawing, stickers and looks (`WyrmTrailLooks`), plus a trim window, a
 * cover frame and sound on or off. Export is AVAssetReader + AVAssetWriter:
 * the trim, the size (short side 720, 540 or 360, the clip's own if smaller),
 * the look and the overlay drawn into every frame by Core Image, H.264 + AAC,
 * colours in Rec. 709 (HDR clips come out SDR), the index at the front of the
 * file. The player previews with the same look, so the editor shows what goes
 * up. The server takes it as it is (`backend/src/trail-video.mjs`). Wyrm
 * Android: `ui/TrailVideo.kt`.
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

/// The clip being edited: the player, the trim window (at most 30 s), the
/// cover frame and the sound. The look and the overlays live on the studio's
/// draft, shared with the photo editor.
final class WyrmTrailVideoSession: ObservableObject {
    let clip: WyrmTrailClip
    let player = AVPlayer()
    @Published private(set) var trimStart: Int64 = 0
    @Published private(set) var trimEnd: Int64
    /// Absolute time of the cover frame in the clip.
    @Published var coverMs: Int64 = 0
    @Published private(set) var muted = false
    /// Where the player is, relative to `trimStart`.
    @Published private(set) var playhead: Int64 = 0
    private let looks = WyrmLookBox()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var released = false

    var lengthMs: Int64 { trimEnd - trimStart }

    init(clip: WyrmTrailClip) {
        self.clip = clip
        trimEnd = min(clip.durationMs, wyrmTrailVideoMaxMs)
        let item = AVPlayerItem(asset: clip.asset)
        let box = looks
        item.videoComposition = AVVideoComposition(asset: clip.asset) { request in
            request.finish(with: box.apply(request.sourceImage).cropped(to: request.sourceImage.extent), context: nil)
        }
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 12), queue: .main) { [weak self] time in
            guard let self else { return }
            let now = Int64(CMTimeGetSeconds(time) * 1000)
            self.playhead = max(0, min(now - self.trimStart, self.lengthMs))
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            // Round and round inside the trim window, as Instagram's editor plays.
            guard let self, !self.released else { return }
            self.player.seek(to: wyrmTime(self.trimStart), toleranceBefore: .zero, toleranceAfter: .zero) { _ in self.player.play() }
        }
    }

    /// The trim window into the player, from its start.
    func load() {
        player.currentItem?.forwardPlaybackEndTime = wyrmTime(trimEnd)
        player.seek(to: wyrmTime(trimStart), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    func setTrim(_ start: Int64, _ end: Int64) {
        let s = min(max(start, 0), max(clip.durationMs - wyrmTrailVideoMinMs, 0))
        let lowest = s + min(wyrmTrailVideoMinMs, clip.durationMs - s)
        let e = min(max(end, lowest), min(clip.durationMs, s + wyrmTrailVideoMaxMs))
        trimStart = s
        trimEnd = e
        coverMs = min(max(coverMs, s), e)
    }

    /// Shows a time (relative to the trim start) while a handle is dragged.
    func scrub(_ relativeMs: Int64) {
        player.seek(to: wyrmTime(trimStart + max(0, relativeMs)), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func scrubAbsolute(_ ms: Int64) {
        player.seek(to: wyrmTime(ms), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// The look the export will burn in; a paused frame is drawn again with it.
    func setLook(_ look: WyrmTrailLook, _ adjust: WyrmTrailAdjust) {
        looks.set(look, adjust)
        if player.rate == 0 {
            player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func toggleSound() {
        muted.toggle()
        player.isMuted = muted
    }

    func play() { if !released { player.play() } }
    func pause() { player.pause() }

    func release() {
        guard !released else { return }
        released = true
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    deinit { release() }
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

/// The editor's video tools under the canvas: Trim, Cover and Sound, Instagram-style.
struct WyrmTrailVideoBar: View {
    @ObservedObject var session: WyrmTrailVideoSession
    @State private var tab = 0
    @State private var frames: [UIImage] = []

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                WyrmStudioChip(label: "Trim", selected: tab == 0) { UISelectionFeedbackGenerator().selectionChanged(); tab = 0 }
                WyrmStudioChip(label: "Cover", selected: tab == 1) { UISelectionFeedbackGenerator().selectionChanged(); tab = 1 }
                Spacer()
                WyrmStudioChip(label: session.muted ? "Sound off" : "Sound on", selected: !session.muted) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    session.toggleSound()
                }
            }
            if tab == 0 {
                WyrmTrailTrimStrip(session: session, frames: frames)
                Text(String(format: "%.1f s of %d s", Double(session.lengthMs) / 1000, Int(wyrmTrailVideoMaxMs / 1000)))
                    .font(.androidWyrm(11.5, .semibold)).foregroundColor(ATheme.quiet).frame(maxWidth: .infinity)
            } else {
                WyrmTrailCoverStrip(session: session, frames: frames)
                Text("The picture people see before it plays")
                    .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .task { frames = await WyrmTrailFrames.strip(session.clip, count: 10, longest: 160) }
    }
}

private struct WyrmTrailFrameRow: View {
    let frames: [UIImage]
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if frames.isEmpty {
                    ATheme.well
                } else {
                    ForEach(frames.indices, id: \.self) { i in
                        Image(uiImage: frames[i]).resizable().scaledToFill()
                            .frame(width: proxy.size.width / CGFloat(frames.count), height: proxy.size.height)
                            .clipped()
                    }
                }
            }
        }
    }
}

/// The trim window over the whole clip: drag either handle, or the window
/// itself; it never runs past 30 s nor under 1 s. The player restarts on the
/// new window when the finger lifts.
private struct WyrmTrailTrimStrip: View {
    @ObservedObject var session: WyrmTrailVideoSession
    let frames: [UIImage]
    @State private var grab = 0 // 1 left, 2 right, 3 window, -1 outside
    @State private var began = false
    @State private var startAt: Int64 = 0
    @State private var endAt: Int64 = 0

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let duration = CGFloat(max(session.clip.durationMs, 1))
            let left = CGFloat(session.trimStart) / duration * width
            let right = CGFloat(session.trimEnd) / duration * width
            let handle: CGFloat = 14
            let play = left + CGFloat(session.playhead) / CGFloat(max(session.lengthMs, 1)) * (right - left)
            let gold = Color(red: 0.95, green: 0.72, blue: 0.29)
            ZStack(alignment: .topLeading) {
                WyrmTrailFrameRow(frames: frames)
                Color.black.opacity(0.55).frame(width: max(left, 0))
                Color.black.opacity(0.55).frame(width: max(width - right, 0)).offset(x: right)
                Rectangle().stroke(gold, lineWidth: 3).frame(width: max(right - left, 1)).offset(x: left)
                gold.frame(width: handle).offset(x: left)
                gold.frame(width: handle).offset(x: right - handle)
                Color.white.frame(width: 2).offset(x: play - 1)
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    func ms(_ x: CGFloat) -> Int64 { Int64(min(max(x / width, 0), 1) * duration) }
                    if !began {
                        began = true
                        let x = value.startLocation.x
                        grab = abs(x - left) < handle * 1.6 ? 1 : abs(x - right) < handle * 1.6 ? 2 : (x >= left && x <= right ? 3 : -1)
                        startAt = session.trimStart
                        endAt = session.trimEnd
                        if grab > 0 {
                            session.pause()
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    let moved = ms(value.location.x) - ms(value.startLocation.x)
                    switch grab {
                    case 1: session.setTrim(startAt + moved, endAt)
                    case 2: session.setTrim(startAt, endAt + moved)
                    case 3:
                        let span = endAt - startAt
                        let s = min(max(startAt + moved, 0), session.clip.durationMs - span)
                        session.setTrim(s, s + span)
                    default: return
                    }
                    session.scrub(grab == 2 ? session.lengthMs : 0)
                }
                .onEnded { _ in
                    if grab > 0 { session.load() }
                    grab = 0
                    began = false
                })
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The cover: a frame inside the trim window, chosen by dragging along the strip.
private struct WyrmTrailCoverStrip: View {
    @ObservedObject var session: WyrmTrailVideoSession
    let frames: [UIImage]
    @State private var cover: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let duration = CGFloat(max(session.clip.durationMs, 1))
            let x = CGFloat(session.coverMs) / duration * width
            ZStack(alignment: .leading) {
                WyrmTrailFrameRow(frames: frames)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                ZStack {
                    ATheme.well
                    if let cover { Image(uiImage: cover).resizable().scaledToFill() }
                }
                .frame(width: 44, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white, lineWidth: 3))
                .offset(x: min(max(x - 22, -4), width - 40))
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let ms = Int64(min(max(value.location.x / width, 0), 1) * duration)
                session.coverMs = min(max(ms, session.trimStart), session.trimEnd)
                session.pause()
                session.scrubAbsolute(session.coverMs)
            })
        }
        .frame(height: 64)
        .task(id: session.coverMs) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            let clip = session.clip, at = session.coverMs
            let frame = await Task.detached(priority: .userInitiated) { WyrmTrailFrames.frame(clip, atMs: at, longest: 220) }.value
            if !Task.isCancelled { cover = frame }
        }
    }
}

// MARK: - Recording and picking

/// The Video page's camera: records at most 30 s with sound (when the
/// microphone is allowed; without it, silently).
final class WyrmTrailRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    enum State { case idle, running, denied, unavailable }
    @Published private(set) var state: State = .idle
    @Published private(set) var recording = false
    @Published private(set) var recordedMs: Int64 = 0
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "wyrm.trails.recorder")
    private var configured = false
    private var position: AVCaptureDevice.Position = .back
    private var timer: Timer?
    private var onClip: ((URL?) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: askMicrophone()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { if granted { self.askMicrophone() } else { self.state = .denied } }
            }
        default: state = .denied
        }
    }

    private func askMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { self.run() } }
        } else {
            run()
        }
    }

    private func run() {
        queue.async {
            if !self.configured { self.configure() }
            guard self.configured else { DispatchQueue.main.async { self.state = .unavailable }; return }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.state = .running }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(for: .audio),
           let audio = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audio) {
            session.addInput(audio)
        }
        session.addOutput(output)
        output.maxRecordedDuration = CMTime(value: wyrmTrailVideoMaxMs, timescale: 1000)
        orient()
        configured = true
    }

    private func orient() {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = position == .front }
    }

    func stop() {
        if recording { output.stopRecording() }
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func flip() {
        guard !recording else { return }
        queue.async {
            guard self.configured else { return }
            let next: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            for old in self.session.inputs {
                if let old = old as? AVCaptureDeviceInput, old.device.hasMediaType(.video) { self.session.removeInput(old) }
            }
            if self.session.canAddInput(input) { self.session.addInput(input); self.position = next }
            self.orient()
            self.session.commitConfiguration()
        }
    }

    /// Starts; the clip arrives in `done` when Stop is tapped or 30 s run out.
    func record(_ done: @escaping (URL?) -> Void) {
        guard state == .running, !recording else { return }
        onClip = done
        recording = true
        recordedMs = 0
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wyrm-rec-\(UUID().uuidString).mov")
        queue.async { self.output.startRecording(to: file, recordingDelegate: self) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordedMs = min(Int64(CMTimeGetSeconds(self.output.recordedDuration) * 1000), wyrmTrailVideoMaxMs)
        }
    }

    func finish() {
        guard recording else { return }
        queue.async { self.output.stopRecording() }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Reaching 30 s ends with an "error" whose file is complete.
        let finished = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
            self.recording = false
            if !finished { try? FileManager.default.removeItem(at: url) }
            self.onClip?(finished ? url : nil)
            self.onClip = nil
        }
    }
}

/// The phone's videos, newest first.
@MainActor
final class WyrmTrailVideoGallery: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    let manager = PHCachingImageManager()

    func load() {
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { next in
                Task { @MainActor in self.status = next; self.fetch() }
            }
        } else { fetch() }
    }

    private func fetch() {
        guard status == .authorized || status == .limited else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 200
        let result = PHAsset.fetchAssets(with: .video, options: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
    }

    /// The clip itself (from iCloud when needed).
    func asset(_ asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, _ in
                continuation.resume(returning: video)
            }
        }
    }
}

private struct WyrmVideoGalleryCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    @State private var image: UIImage?
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { ATheme.well } })
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                Text(wyrmClipTime(Int64(asset.duration * 1000)))
                    .font(.androidWyrm(10.5, .bold)).monospacedDigit().foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(5)
            }
            .onAppear {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = true
                manager.requestImage(for: asset, targetSize: CGSize(width: 260, height: 260), contentMode: .aspectFill,
                                     options: options) { picked, _ in if let picked { image = picked } }
            }
    }
}

/// The system picker for one video; the file is copied into the app first,
/// because the picker's own copy disappears when it returns.
struct WyrmVideoPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                DispatchQueue.main.async { self.onPick(nil) }
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                var copy: URL?
                if let url {
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent("wyrm-pick-\(UUID().uuidString).\(ext)")
                    if (try? FileManager.default.copyItem(at: url, to: target)) != nil { copy = target }
                }
                DispatchQueue.main.async { self.onPick(copy) }
            }
        }
    }
}

/// The Video page: a camera that records up to 30 s (the ring fills as the
/// time runs) and the phone's recent clips below.
struct WyrmTrailVideoPicker: View {
    @ObservedObject var recorder: WyrmTrailRecorder
    @ObservedObject var gallery: WyrmTrailVideoGallery
    let busy: Bool
    let onAsset: (AVAsset, URL?) -> Void
    @State private var picking = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    switch recorder.state {
                    case .running: WyrmCameraPreview(session: recorder.session)
                    case .denied: note("Camera is off for Wyrm", "Allow it in Settings, or pick a video below.")
                    case .unavailable: note("No camera", "Pick a video from your library below.")
                    case .idle: ATheme.well
                    }
                }
                .frame(maxWidth: .infinity).aspectRatio(0.8, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack {
                    HStack {
                        if recorder.recording {
                            HStack(spacing: 6) {
                                Circle().fill(Color(red: 0.95, green: 0.25, blue: 0.25)).frame(width: 8, height: 8)
                                Text(wyrmClipTime(recorder.recordedMs) + " / 0:30").font(.androidWyrm(12.5, .bold)).monospacedDigit()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                        Spacer()
                    }
                    Spacer()
                    if recorder.state == .running {
                        HStack {
                            Spacer().frame(width: 44)
                            Spacer()
                            Button {
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                if recorder.recording {
                                    recorder.finish()
                                } else {
                                    recorder.record { url in
                                        guard let url else { return }
                                        onAsset(AVURLAsset(url: url), url)
                                    }
                                }
                            } label: {
                                ZStack {
                                    Circle().stroke(Color.white.opacity(0.45), lineWidth: 5)
                                    Circle().trim(from: 0, to: CGFloat(recorder.recordedMs) / CGFloat(wyrmTrailVideoMaxMs))
                                        .stroke(Color(red: 0.95, green: 0.25, blue: 0.25), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    RoundedRectangle(cornerRadius: recorder.recording ? 6 : 26, style: .continuous)
                                        .fill(Color(red: 0.95, green: 0.25, blue: 0.25))
                                        .frame(width: recorder.recording ? 26 : 52, height: recorder.recording ? 26 : 52)
                                }
                                .frame(width: 70, height: 70)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recorder.recording)
                            }.buttonStyle(WSPressStyle())
                            Spacer()
                            WyrmStudioRoundButton(symbol: "arrow.triangle.2.circlepath") { recorder.flip() }
                                .opacity(recorder.recording ? 0.3 : 1)
                        }
                    }
                }
                .padding(14)
            }
            .aspectRatio(0.8, contentMode: .fit)
            .padding(.horizontal, 12)
            grid.padding(.top, 10)
        }
        .overlay(Group { if busy { ProgressView().padding(14).background(Circle().fill(ATheme.card)) } })
        .sheet(isPresented: $picking) {
            WyrmVideoPicker { url in
                picking = false
                if let url { onAsset(AVURLAsset(url: url), url) }
            }
            .ignoresSafeArea()
        }
    }

    private func note(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "video").font(.system(size: 26, weight: .semibold)).foregroundColor(ATheme.quiet)
            Text(title).font(.androidWyrm(15, .bold))
            Text(detail).font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(ATheme.well)
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            if gallery.status == .authorized || gallery.status == .limited {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                    Button { picking = true } label: {
                        ZStack {
                            ATheme.well
                            VStack(spacing: 4) {
                                Image(systemName: "film.stack").font(.system(size: 18, weight: .semibold))
                                Text("All videos").font(.androidWyrm(10.5, .bold))
                            }.foregroundColor(ATheme.mute)
                        }.aspectRatio(1, contentMode: .fit)
                    }.buttonStyle(.plain)
                    ForEach(gallery.assets, id: \.localIdentifier) { asset in
                        Button {
                            guard !busy else { return }
                            Task { if let video = await gallery.asset(asset) { onAsset(video, nil) } }
                        } label: { WyrmVideoGalleryCell(asset: asset, manager: gallery.manager) }
                            .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 12)
            } else {
                VStack(spacing: 10) {
                    Text("Your videos").font(.androidWyrm(15, .bold))
                    Text("Allow Wyrm to show your videos here, or pick one from the library.")
                        .font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
                    WSPrimaryButton(label: "Choose a video") { picking = true }
                }
                .padding(20)
            }
            Text("Up to 30 seconds. Longer videos start trimmed to their first 30.")
                .font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center)
                .padding(.horizontal, 24).padding(.top, 12)
            Spacer().frame(height: 40)
        }
    }
}

// MARK: - Export

enum WyrmTrailVideoError: Error { case unreadable, failed }

/// Trim, size, look and overlay into one small MP4, on the phone. Size tiers
/// by the short side: 720 (about 2.2 Mbit/s), 540 (1.5), 360 (0.9); a file
/// over 15 MB is made again one tier lower. Same tiers as Android.
enum WyrmTrailVideoExport {
    static let maxBytes = 15 * 1024 * 1024
    private static let tiers: [(short: CGFloat, bitrate: Int)] = [(720, 2_200_000), (540, 1_500_000), (360, 900_000)]

    static func outputSize(_ clip: WyrmTrailClip, tier: Int) -> CGSize {
        let short = min(clip.size.width, clip.size.height)
        let target = max(2, min(tiers[tier].short, short))
        let k = target / max(short, 1)
        func even(_ v: CGFloat) -> CGFloat { max(2, (v * k / 2).rounded() * 2) }
        return CGSize(width: even(clip.size.width), height: even(clip.size.height))
    }

    static var tierCount: Int { tiers.count }

    /// `overlays[tier]`: everything drawn on top at that tier's `outputSize`
    /// (nil: nothing on top), drawn by the caller on the main thread.
    static func export(_ clip: WyrmTrailClip, startMs: Int64, endMs: Int64, muted: Bool,
                       look: WyrmTrailLook, adjust: WyrmTrailAdjust, overlays: [UIImage?],
                       progress: @escaping (Double) -> Void) async throws -> URL {
        for tier in tiers.indices {
            let size = outputSize(clip, tier: tier)
            let top = tier < overlays.count ? overlays[tier] : nil
            let file = try await once(clip, startMs: startMs, endMs: endMs, muted: muted, look: look, adjust: adjust,
                                      overlay: top, size: size, bitrate: tiers[tier].bitrate, progress: progress)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            if bytes <= maxBytes || tier == tiers.count - 1 { return file }
            try? FileManager.default.removeItem(at: file)
        }
        throw WyrmTrailVideoError.failed
    }

    private static func once(_ clip: WyrmTrailClip, startMs: Int64, endMs: Int64, muted: Bool,
                             look: WyrmTrailLook, adjust: WyrmTrailAdjust, overlay: UIImage?, size: CGSize,
                             bitrate: Int, progress: @escaping (Double) -> Void) async throws -> URL {
        let asset = clip.asset
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("wyrm-trail-\(UUID().uuidString).mp4")
        let range = CMTimeRange(start: wyrmTime(startMs), end: wyrmTime(endMs))
        let videoTracks = asset.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw WyrmTrailVideoError.unreadable }

        // Every frame: upright (done by the composition), scaled, the look, the overlay.
        let matrix: WyrmLookMatrix? = WyrmTrailLooks.isIdentity(look, adjust) ? nil : WyrmTrailLooks.matrix(look, adjust)
        let top: CIImage? = overlay?.cgImage.map { CIImage(cgImage: $0) }
        let frame = CGRect(origin: .zero, size: size)
        let composition = AVMutableVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let extent = source.extent
            var image = source
                .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                .applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: size.height / max(extent.height, 1),
                    kCIInputAspectRatioKey: (size.width / max(extent.width, 1)) / (size.height / max(extent.height, 1)),
                ])
            if let matrix { image = WyrmTrailLooks.apply(image, matrix) }
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
        if !muted && !audioTracks.isEmpty {
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
        writer.startSession(atSourceTime: range.start)
        let total = max(CMTimeGetSeconds(range.duration), 0.001)
        let startSeconds = CMTimeGetSeconds(range.start)

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
                                let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) - startSeconds
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

    /// The poster: the cover frame in the look with everything drawn on top,
    /// at most 1440 px on its long side.
    static func poster(_ clip: WyrmTrailClip, atMs: Int64, look: WyrmTrailLook, adjust: WyrmTrailAdjust,
                       overlay: (CGSize) -> UIImage?) -> UIImage? {
        guard let raw = WyrmTrailFrames.frame(clip, atMs: atMs, longest: 1440) else { return nil }
        let base = WyrmTrailLooks.apply(raw, look, adjust)
        let size = CGSize(width: base.size.width.rounded(), height: base.size.height.rounded())
        guard let top = overlay(size) else { return base }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            top.draw(in: CGRect(origin: .zero, size: size))
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
