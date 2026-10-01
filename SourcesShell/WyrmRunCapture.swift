import UIKit

/*
 * "Share this run" (OM, 2026-09-30): the last finished run, in memory only,
 * for the lobby's Share run button and the Share editor.
 *
 * WyrmGameSync drains each run receipt from the engine ("score\tkills\tseconds",
 * HomeMailbox.inc) and calls `record`; the next receipt replaces it, and the
 * next match clears it (`runStarted`, engine screen 2). The engine also copies
 * the death frame out of the swapchain (AppleRunCapture.inc); `pollScreenshot`
 * takes that picture, shrinks it off the main thread to 1440 px on the long
 * side and adds it to the same run. No picture (unsupported, failed, late)
 * simply leaves `screenshot` nil.
 */
struct WyrmLastRun {
    let score: Int
    let kills: Int
    let seconds: Double
    let endedAt: Date
    let screenshot: UIImage?
}

enum WyrmRunCapture {
    /// Posted on the main thread whenever `lastRun` is set or cleared.
    static let didChange = Notification.Name("WyrmRunCaptureChanged")
    /// The long side of a kept screenshot, in pixels.
    static let maxScreenshotSide = 1440

    private static let lock = NSLock()
    private static var current: WyrmLastRun?
    /// Bumped on every change, so a picture that finishes late never lands on
    /// a newer run (or on none).
    private static var generation = 0

    static var lastRun: WyrmLastRun? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Main thread: a run receipt drained from the engine.
    static func record(score: Int, kills: Int, seconds: Double) {
        let run = WyrmLastRun(score: max(0, score), kills: max(0, kills),
                              seconds: seconds.isFinite ? max(0, seconds) : 0,
                              endedAt: Date(), screenshot: nil)
        set(run)
        WyrmDiagnostics.record("last run kept score=\(run.score) kills=\(run.kills) seconds=\(Int(run.seconds))", category: "STATS")
    }

    /// Main thread: a match began, so the last run is over.
    static func runStarted() {
        discardPendingScreenshot()
        guard lastRun != nil else { return }
        set(nil)
    }

    /// Main thread, on WyrmGameSync's tick after the runs are drained: takes
    /// the engine's picture if one is ready and adds it to the current run.
    static func pollScreenshot() {
        var pixels: UnsafeMutableRawPointer?
        var width: Int32 = 0, height: Int32 = 0, stride: Int32 = 0, bgra: Int32 = 1
        guard WyrmIOSTakeRunScreenshot(&pixels, &width, &height, &stride, &bgra),
              let taken = pixels else { return }
        lock.lock()
        let target: Int? = current != nil && current?.screenshot == nil ? generation : nil
        lock.unlock()
        guard let target = target else {
            // No run to hold it (a match already started): an old picture.
            WyrmIOSFreeRunScreenshot(taken)
            return
        }
        let w = Int(width), h = Int(height), rowBytes = Int(stride), blueFirst = bgra != 0
        DispatchQueue.global(qos: .userInitiated).async {
            let image = WyrmRunCapture.makeImage(taken, width: w, height: h, rowBytes: rowBytes,
                                                 blueFirst: blueFirst)
            DispatchQueue.main.async { WyrmRunCapture.attach(image, to: target) }
        }
    }

    private static func set(_ run: WyrmLastRun?) {
        lock.lock()
        current = run
        generation += 1
        lock.unlock()
        post()
    }

    private static func attach(_ image: UIImage?, to target: Int) {
        guard let image = image else {
            WyrmDiagnostics.record("run screenshot could not be made", category: "STATS")
            return
        }
        lock.lock()
        guard generation == target, let run = current else {
            lock.unlock()
            return
        }
        current = WyrmLastRun(score: run.score, kills: run.kills, seconds: run.seconds,
                              endedAt: run.endedAt, screenshot: image)
        generation += 1
        lock.unlock()
        WyrmDiagnostics.record("run screenshot kept \(Int(image.size.width))x\(Int(image.size.height))", category: "STATS")
        post()
    }

    private static func post() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: didChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: WyrmRunCapture.didChange, object: nil)
            }
        }
    }

    private static func discardPendingScreenshot() {
        var pixels: UnsafeMutableRawPointer?
        var width: Int32 = 0, height: Int32 = 0, stride: Int32 = 0, bgra: Int32 = 1
        if WyrmIOSTakeRunScreenshot(&pixels, &width, &height, &stride, &bgra) {
            WyrmIOSFreeRunScreenshot(pixels)
        }
    }

    /// Any thread. Owns `pixels` (the engine's malloc'd copy) and frees it on
    /// every path: through the data provider once it exists, by hand before.
    /// The swapchain bytes are sRGB-encoded; alpha is ignored.
    private static func makeImage(_ pixels: UnsafeMutableRawPointer, width: Int, height: Int,
                                  rowBytes: Int, blueFirst: Bool) -> UIImage? {
        guard width > 0, height > 0, rowBytes >= width * 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(dataInfo: nil, data: pixels, size: rowBytes * height,
                                            releaseData: { _, data, _ in
                                                WyrmIOSFreeRunScreenshot(UnsafeMutableRawPointer(mutating: data))
                                            }) else {
            WyrmIOSFreeRunScreenshot(pixels)
            return nil
        }
        // B,G,R,A bytes = a little-endian XRGB word; R,G,B,A = big-endian RGBX.
        let layout: UInt32 = blueFirst
            ? CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
            : CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        guard let full = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: rowBytes, space: space, bitmapInfo: CGBitmapInfo(rawValue: layout),
                                 provider: provider, decode: nil, shouldInterpolate: true,
                                 intent: .defaultIntent) else { return nil }
        let scale = min(1, Double(maxScreenshotSide) / Double(max(width, height)))
        let outWidth = max(1, Int((Double(width) * scale).rounded()))
        let outHeight = max(1, Int((Double(height) * scale).rounded()))
        // Always redrawn, so the kept image owns its memory and the engine's
        // full-size copy is released as soon as this returns.
        guard let context = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                          | CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
        guard let small = context.makeImage() else { return nil }
        return UIImage(cgImage: small)
    }
}
