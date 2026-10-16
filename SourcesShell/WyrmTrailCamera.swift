import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import UniformTypeIdentifiers

/*
 * The studio's first page (OM, 2026-10-17, Instagram's camera): the camera
 * fills the screen; under it the modes PHOTO · VIDEO · TEXT · CANVAS slide
 * like Instagram's, and a swipe across the camera changes mode too.
 *
 *   - The shutter is a Wyrm bead. On Photo a tap takes a picture and a hold
 *     records (the ring fills green over 30 s); on Video a tap starts and
 *     stops. Video only while `WyrmTrailsFeature.videoEnabled`.
 *   - Bottom left: the newest picture of the phone; it opens the gallery
 *     (`WyrmTrailGalleryPage`): a big preview of the chosen item (a video
 *     plays) over a grid of photos and videos, Recents / Photos / Videos, Next.
 *   - Bottom right: front or back camera. Top: close and the flash.
 *
 * Android: `ui/TrailCamera.kt`, the same page.
 */

// MARK: - Camera

/// One camera for photos and videos: a photo output and a movie output on
/// the same session, so a hold on the shutter records at once.
final class WyrmStudioCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    enum State { case idle, running, denied, unavailable }
    @Published private(set) var state: State = .idle
    @Published private(set) var recording = false
    @Published private(set) var recordedMs: Int64 = 0
    @Published var flash = false
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "wyrm.trails.studio-camera")
    private var configured = false
    private var position: AVCaptureDevice.Position = .back
    private var onPhoto: ((UIImage?) -> Void)?
    private var onClip: ((URL?) -> Void)?
    private var timer: Timer?

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
        if WyrmTrailsFeature.videoEnabled && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
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
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(photoOutput) else { return }
        session.addInput(input)
        session.addOutput(photoOutput)
        if WyrmTrailsFeature.videoEnabled && session.canAddOutput(movieOutput) {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let mic = AVCaptureDevice.default(for: .audio),
               let audio = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audio) {
                session.addInput(audio)
            }
            session.addOutput(movieOutput)
            movieOutput.maxRecordedDuration = CMTime(value: wyrmTrailVideoMaxMs, timescale: 1000)
        }
        orient()
        configured = true
    }

    private func orient() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = position == .front }
    }

    var canRecord: Bool { WyrmTrailsFeature.videoEnabled && session.outputs.contains(movieOutput) }

    func stop() {
        if recording { movieOutput.stopRecording() }
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

    func capture(_ done: @escaping (UIImage?) -> Void) {
        guard state == .running else { done(nil); return }
        onPhoto = done
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(.on) { settings.flashMode = flash ? .on : .off }
        queue.async { self.photoOutput.capturePhoto(with: settings, delegate: self) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        if position == .front, let shot = image, let cg = shot.cgImage {
            image = UIImage(cgImage: cg, scale: shot.scale, orientation: .leftMirrored)
        }
        DispatchQueue.main.async {
            self.onPhoto?(image)
            self.onPhoto = nil
        }
    }

    /// Starts; the clip arrives in `done` when stopped or when 30 s run out.
    func record(_ done: @escaping (URL?) -> Void) {
        guard state == .running, !recording, canRecord else { return }
        onClip = done
        recording = true
        recordedMs = 0
        torch(flash)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wyrm-rec-\(UUID().uuidString).mov")
        queue.async { self.movieOutput.startRecording(to: file, recordingDelegate: self) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordedMs = min(Int64(CMTimeGetSeconds(self.movieOutput.recordedDuration) * 1000), wyrmTrailVideoMaxMs)
        }
    }

    func finish() {
        guard recording else { return }
        queue.async { self.movieOutput.stopRecording() }
    }

    private func torch(_ on: Bool) {
        queue.async {
            guard let device = (self.session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) })?.device,
                  device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Reaching 30 s ends with an "error" whose file is complete.
        let finished = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        torch(false)
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

/// The camera page; `mode` is Photo or Video.
struct WyrmTrailCameraPage: View {
    @ObservedObject var camera: WyrmStudioCamera
    @ObservedObject var gallery: WyrmTrailMediaGallery
    let mode: WyrmStudioMode
    let busy: Bool
    let close: () -> Void
    let swipe: (Int) -> Void
    let onPhoto: (UIImage) -> Void
    let onClip: (AVAsset, URL?) -> Void
    let openGallery: () -> Void
    let cameraApp: () -> Void

    var body: some View {
        ZStack {
            Color.black
            Group {
                switch camera.state {
                case .running: WyrmCameraPreview(session: camera.session)
                case .denied: note("Camera is off for Wyrm", "Allow it in Settings, or pick from your gallery.")
                case .unavailable: note("No camera", "Pick from your gallery.")
                case .idle: Color(white: 0.07)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                // A swipe across the camera: the next or the last mode.
                guard !camera.recording, abs(value.translation.width) > 70,
                      abs(value.translation.height) < abs(value.translation.width) * 0.7 else { return }
                swipe(value.translation.width < 0 ? 1 : -1)
            })
            VStack {
                HStack {
                    WyrmStudioRoundButton(symbol: "xmark") { if !camera.recording { close() } }
                    Spacer()
                    if camera.recording {
                        HStack(spacing: 6) {
                            Circle().fill(Color(red: 0.9, green: 0.28, blue: 0.3)).frame(width: 8, height: 8)
                            Text(wyrmClipTime(camera.recordedMs) + " / 0:30").font(.androidWyrm(12.5, .bold)).monospacedDigit()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        Spacer()
                    }
                    if camera.state == .running {
                        WyrmStudioRoundButton(symbol: camera.flash ? "bolt.fill" : "bolt.slash.fill", on: camera.flash) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            camera.flash.toggle()
                        }
                    } else {
                        Spacer().frame(width: 42)
                    }
                }
                Spacer()
                HStack {
                    Button(action: { if !camera.recording && !busy { openGallery() } }) {
                        ZStack {
                            Color.white.opacity(0.18)
                            if let newest = gallery.newest { Image(uiImage: newest).resizable().scaledToFill() }
                            else { Image(systemName: "photo.on.rectangle").font(.system(size: 18, weight: .semibold)).foregroundColor(.white) }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white, lineWidth: 2))
                    }
                    .buttonStyle(WSPressStyle())
                    Spacer()
                    WyrmTrailShutter(camera: camera, video: mode == .video, enabled: camera.state == .running && !busy,
                                     photo: {
                                         UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                         camera.capture { shot in if let shot { onPhoto(shot) } }
                                     },
                                     record: {
                                         UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                         camera.record { url in if let url { onClip(AVURLAsset(url: url), url) } }
                                     })
                    Spacer()
                    WyrmStudioRoundButton(symbol: "arrow.triangle.2.circlepath.camera") {
                        UISelectionFeedbackGenerator().selectionChanged()
                        camera.flip()
                    }
                    .opacity(camera.recording ? 0.3 : 1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .padding(14)
            if busy { ProgressView().tint(.white).padding(16).background(Circle().fill(Color.black.opacity(0.55))) }
        }
    }

    private func note(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.aperture").font(.system(size: 28, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            Text(title).font(.androidWyrm(15, .bold)).foregroundColor(.white)
            Text(detail).font(.androidWyrm(12.5)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
            if WyrmSystemCamera.available {
                Button(action: cameraApp) {
                    Text("Open the phone's camera").font(.androidWyrm(13, .bold)).foregroundColor(.white)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.07))
    }
}

/// The shutter, a Wyrm bead: a white glossy bead in a white ring. Recording,
/// the ring fills in Wyrm's own green and the bead shrinks to a rounded square.
/// On Photo a tap takes a picture and a hold records until let go; on Video a
/// tap starts and stops.
private struct WyrmTrailShutter: View {
    @ObservedObject var camera: WyrmStudioCamera
    let video: Bool
    let enabled: Bool
    let photo: () -> Void
    let record: () -> Void
    @State private var down = false
    @State private var hold: DispatchWorkItem?
    @State private var held = false

    var body: some View {
        let progress = CGFloat(camera.recordedMs) / CGFloat(wyrmTrailVideoMaxMs)
        ZStack {
            Circle().stroke(Color.white.opacity(camera.recording ? 0.35 : 1), lineWidth: 5)
            if camera.recording {
                Circle().trim(from: 0, to: progress)
                    .stroke(ATheme.live, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            RoundedRectangle(cornerRadius: camera.recording ? 9 : 30, style: .continuous)
                .fill(video && !camera.recording
                      ? RadialGradient(colors: [Color(red: 1, green: 0.55, blue: 0.55), Color(red: 0.9, green: 0.28, blue: 0.3)],
                                       center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 40)
                      : RadialGradient(colors: [.white, Color(white: 0.91), Color(white: 0.79)],
                                       center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 44))
                .frame(width: camera.recording ? 30 : 60, height: camera.recording ? 30 : 60)
        }
        .frame(width: 80, height: 80)
        .scaleEffect(camera.recording ? 1.1 : (down ? 0.94 : 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: camera.recording)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: down)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard enabled, !down else { return }
                down = true
                held = false
                if video || camera.recording { return }
                // Held past a moment: it records until let go.
                let work = DispatchWorkItem {
                    guard down, camera.canRecord else { return }
                    held = true
                    record()
                }
                hold = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
            }
            .onEnded { _ in
                guard down else { return }
                down = false
                hold?.cancel()
                hold = nil
                if video {
                    if camera.recording { camera.finish() } else { record() }
                } else if held {
                    camera.finish()
                } else if camera.recording {
                    camera.finish()
                } else {
                    photo()
                }
                held = false
            })
    }
}

/// PHOTO · VIDEO · TEXT · CANVAS under the camera; the chosen one sits in the middle.
struct WyrmStudioModeCarousel: View {
    let modes: [WyrmStudioMode]
    let mode: WyrmStudioMode
    let dark: Bool
    var enabled = true
    let pick: (WyrmStudioMode) -> Void
    private let slot: CGFloat = 86

    var body: some View {
        GeometryReader { proxy in
            let index = CGFloat(modes.firstIndex(of: mode) ?? 0)
            let ink = dark ? Color.white : ATheme.ink
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(modes, id: \.self) { m in
                        Button {
                            guard enabled, m != mode else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            pick(m)
                        } label: {
                            Text(m.rawValue.uppercased())
                                .font(.androidWyrm(13, m == mode ? .heavy : .semibold)).tracking(1.2)
                                .foregroundColor(ink.opacity(m == mode ? 1 : 0.45))
                                .frame(width: slot, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: proxy.size.width, height: 52, alignment: .leading)
                .offset(x: proxy.size.width / 2 - slot * index - slot / 2)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: mode)
                // A small bead under the chosen mode.
                Circle().fill(ink).frame(width: 5, height: 5).padding(.bottom, 4)
            }
        }
        .frame(height: 52)
        .clipped()
    }
}

// MARK: - Gallery

enum WyrmTrailMediaFilter: String, CaseIterable { case recents = "Recents", photos = "Photos", videos = "Videos" }

/// The phone's photos and videos, newest first.
@MainActor
final class WyrmTrailMediaGallery: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var newest: UIImage?
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
        options.fetchLimit = 400
        if WyrmTrailsFeature.videoEnabled {
            options.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        } else {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
        if let first = list.first {
            let o = PHImageRequestOptions()
            o.deliveryMode = .opportunistic
            o.isNetworkAccessAllowed = true
            manager.requestImage(for: first, targetSize: CGSize(width: 140, height: 140), contentMode: .aspectFill, options: o) { image, _ in
                if let image { Task { @MainActor in self.newest = image } }
            }
        }
    }

    func full(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            manager.requestImage(for: asset, targetSize: CGSize(width: 2400, height: 2400), contentMode: .aspectFit,
                                 options: options) { image, _ in continuation.resume(returning: image) }
        }
    }

    /// The clip itself (from iCloud when needed).
    func video(_ asset: PHAsset) async -> AVAsset? {
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

/// The gallery, Instagram's New post: the chosen item big on top (a video
/// plays, muted), the phone's photos and videos below, Recents / Photos /
/// Videos, and Next. Browse opens the phone's own picker.
struct WyrmTrailGalleryPage: View {
    @ObservedObject var gallery: WyrmTrailMediaGallery
    let busy: Bool
    let close: () -> Void
    let onPhoto: (UIImage) -> Void
    let onClip: (AVAsset, URL?) -> Void
    @State private var filter: WyrmTrailMediaFilter = .recents
    @State private var chosen: PHAsset?
    @State private var browsing = false
    @State private var opening = false

    private var shown: [PHAsset] {
        switch filter {
        case .recents: return gallery.assets
        case .photos: return gallery.assets.filter { $0.mediaType == .image }
        case .videos: return gallery.assets.filter { $0.mediaType == .video }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                WyrmStudioRoundButton(symbol: "xmark", action: close)
                Spacer()
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    let options: [WyrmTrailMediaFilter] = WyrmTrailsFeature.videoEnabled ? WyrmTrailMediaFilter.allCases : [.recents, .photos]
                    filter = options[((options.firstIndex(of: filter) ?? 0) + 1) % options.count]
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.rawValue).font(.androidWyrm(16, .bold))
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: next) {
                    Text("Next").font(.androidWyrm(14, .bold)).foregroundColor(.black)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(Capsule().fill(Color.white.opacity(chosen != nil && !busy && !opening ? 1 : 0.35)))
                }
                .buttonStyle(WSPressStyle())
                .disabled(chosen == nil || busy || opening)
            }
            .padding(.horizontal, 12).frame(height: 56)
            ZStack {
                Color(white: 0.055)
                if let chosen {
                    if chosen.mediaType == .video { WyrmGalleryVideo(asset: chosen, gallery: gallery).id(chosen.localIdentifier) }
                    else { WyrmGalleryPhoto(asset: chosen, manager: gallery.manager).id(chosen.localIdentifier) }
                }
                if !(gallery.status == .authorized || gallery.status == .limited) && gallery.status != .notDetermined {
                    VStack(spacing: 10) {
                        Text("Your gallery").font(.androidWyrm(15, .bold)).foregroundColor(.white)
                        Text("Allow Wyrm to show your photos and videos in Settings, or browse the phone.")
                            .font(.androidWyrm(12.5)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        WyrmStudioRoundButton(symbol: "square.stack") { browsing = true }
                    }
                }
                .padding(12)
                if busy || opening { ProgressView().tint(.white) }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                    ForEach(shown, id: \.localIdentifier) { asset in
                        let on = chosen?.localIdentifier == asset.localIdentifier
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            if on { next() } else { chosen = asset }
                        } label: {
                            WyrmMediaCell(asset: asset, manager: gallery.manager)
                                .overlay(on ? Color.white.opacity(0.28) : Color.clear)
                                .overlay(Rectangle().stroke(Color.white, lineWidth: on ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer().frame(height: 30)
            }
            .padding(.top, 2)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            gallery.load()
            if chosen == nil { chosen = gallery.assets.first }
        }
        .onChange(of: gallery.assets.count) { _ in if chosen == nil { chosen = gallery.assets.first } }
        .sheet(isPresented: $browsing) {
            WyrmMediaPicker { picked in
                browsing = false
                switch picked {
                case .photo(let image): onPhoto(image)
                case .video(let url): onClip(AVURLAsset(url: url), url)
                case .none: break
                }
            }
            .ignoresSafeArea()
        }
    }

    private func next() {
        guard let chosen, !opening else { return }
        opening = true
        Task {
            if chosen.mediaType == .video {
                if let video = await gallery.video(chosen) { onClip(video, nil) }
            } else if let image = await gallery.full(chosen) {
                onPhoto(image)
            }
            opening = false
        }
    }
}

private struct WyrmMediaCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    @State private var image: UIImage?
    var body: some View {
        Color(white: 0.1)
            .aspectRatio(1, contentMode: .fit)
            .overlay(Group { if let image { Image(uiImage: image).resizable().scaledToFill() } })
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(wyrmClipTime(Int64(asset.duration * 1000)))
                        .font(.androidWyrm(10.5, .bold)).monospacedDigit().foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(4)
                }
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

private struct WyrmGalleryPhoto: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } }
            .onAppear {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = true
                manager.requestImage(for: asset, targetSize: CGSize(width: 1200, height: 1200), contentMode: .aspectFit,
                                     options: options) { picked, _ in if let picked { image = picked } }
            }
    }
}

/// The chosen video, playing muted in its own shape.
private struct WyrmGalleryVideo: View {
    let asset: PHAsset
    let gallery: WyrmTrailMediaGallery
    @State private var player: AVPlayer?
    @State private var loop: NSObjectProtocol?
    var body: some View {
        WyrmTrailPlayerView(player: player, fill: false)
            .task {
                guard let video = await gallery.video(asset) else { return }
                let item = AVPlayerItem(asset: video)
                let next = AVPlayer(playerItem: item)
                next.isMuted = true
                next.actionAtItemEnd = .none
                loop = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                    next.seek(to: .zero)
                    next.play()
                }
                player = next
                next.play()
            }
            .onDisappear {
                player?.pause()
                if let loop { NotificationCenter.default.removeObserver(loop) }
            }
    }
}

/// The phone's own picker: one photo or one video. A video is copied into the
/// app first, because the picker's own copy disappears when it returns.
struct WyrmMediaPicker: UIViewControllerRepresentable {
    enum Picked { case photo(UIImage), video(URL) }
    let onPick: (Picked?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = WyrmTrailsFeature.videoEnabled ? .any(of: [.images, .videos]) : .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Picked?) -> Void
        init(onPick: @escaping (Picked?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                DispatchQueue.main.async { self.onPick(nil) }
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    var copy: URL?
                    if let url {
                        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                        let target = FileManager.default.temporaryDirectory.appendingPathComponent("wyrm-pick-\(UUID().uuidString).\(ext)")
                        if (try? FileManager.default.copyItem(at: url, to: target)) != nil { copy = target }
                    }
                    DispatchQueue.main.async { self.onPick(copy.map { .video($0) }) }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    let image = object as? UIImage
                    DispatchQueue.main.async { self.onPick(image.map { .photo($0) }) }
                }
            } else {
                DispatchQueue.main.async { self.onPick(nil) }
            }
        }
    }
}
