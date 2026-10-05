import SwiftUI
import UIKit
import AVFoundation

/*
 * Trails (OM, 2026-09-28): photos with a caption from the Wyrm community,
 * which others can like and reply to. Phase 1 is photos only.
 *
 * Wyrm's own, not a copy of any other app: a like is a bead that fills with the
 * theme's live colour, replies read like Wyrm chat, and every card is Wyrm's
 * paper and ink in the player's theme.
 *
 * All image work happens here, never on the server: the photo is resized and
 * re-encoded to JPEG (which also drops its location and camera metadata), plus
 * a small thumbnail. The player only ever sees "Preparing" and "Uploading".
 *
 * Videos (OM, 2026-10-05): up to 30 s, made and compressed in the app
 * (`WyrmTrailVideo.swift`); a video trail's `photo` is its poster, and the
 * feed plays one clip at a time, the card most in view.
 *
 * Speed: the feed pages 10 at a time, Instagram-style, and asks for the next
 * page three cards before the end (a profile grid pages 20); each photo shows its thumbnail at once
 * and swaps to the full image when it lands; decoded images are kept in memory
 * and the files on disk, and a like changes on screen before the server answers.
 * Backend: `Wyrm Android/backend/src/trails.mjs`.
 */

// MARK: - Feature switch

/// Trails were paused for build 79 and are back on (OM, 2026-09-29). The
/// switch stays; `enabled = false` hides every entry point again: the Social
/// teaser, the profile's Trails count, grid and trail badges, the trail routes,
/// trail alerts and banners, and the Trails group in Settings › Notifications.
/// Trails are switched off while they are finished (OM, 2026-10-02). `false`
/// hides the feed, trail, studio, Share run / Share this skin, trail badges and
/// trail alerts; the Social card still shows, looking as it did, and `.trails`
/// opens `WyrmTrailsComingSoon`. `true` brings everything back.
enum WyrmTrailsFeature {
    /// ON, and released ON (OM, 2026-10-05: photos and everything else,
    /// videos not yet). Android: TRAILS_ENABLED.
    static let enabled = true

    /// Video trails (OM, 2026-10-05): off for now, so nobody can post a video.
    /// `false` takes the Video page out of the studio's mode bar; the video
    /// code, the backend route and playback of any video trail stay. Android:
    /// TRAIL_VIDEO_ENABLED.
    static let videoEnabled = false

    /// Alert kinds that belong to Trails.
    static let alertKinds: Set<String> = ["trail_like", "trail_reply"]
    /// Badges that can only be earned with Trails (`backend/src/badges.mjs`).
    static let badgeIDs: Set<String> = ["trailblazer", "crowd-favourite"]

    static func shows(alertKind kind: String) -> Bool { enabled || !alertKinds.contains(kind) }
    static func shows(badgeID id: String) -> Bool { enabled || !badgeIDs.contains(id) }
    /// `.trails` always opens: the feed, or the "in development" page while off.
    static func shows(_ route: WyrmDesignRoute) -> Bool { enabled || !route.isTrails || route == .trails }

    /// The alerts a player may see: trail alerts drop out while Trails are paused.
    static func visible(_ alerts: [WyrmServiceAlert]) -> [WyrmServiceAlert] {
        enabled ? alerts : alerts.filter { !alertKinds.contains($0.kind) }
    }
}

extension WyrmDesignRoute {
    /// The Trails feed, one trail and the Trails studio.
    var isTrails: Bool {
        switch self {
        case .trails, .trail, .trailCompose: return true
        default: return false
        }
    }
}

// MARK: - Model

struct WyrmTrailAuthor: Codable, Equatable {
    let playerId: String
    let ingameName: String?
    let username: String?
    let displayName: String?
    let avatarUrl: String?

    var name: String {
        for candidate in [displayName, username, ingameName] {
            if let value = candidate?.trimmingCharacters(in: .whitespaces), !value.isEmpty { return value }
        }
        return "Wyrm player"
    }
    var handle: String { (username ?? "").isEmpty ? "" : "@\(username!)" }
    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "W" : letters.uppercased()
    }
    var avatarURL: String { WyrmTrailsClient.absolute(avatarUrl ?? "") }
}

struct WyrmTrailPhoto: Codable, Equatable {
    let url: String
    let width: Int
    let height: Int
}

/// A video trail's clip: its address, size and length. Its `photo` is the poster.
struct WyrmTrailVideo: Codable, Equatable {
    let url: String
    let width: Int
    let height: Int
    let durationMs: Int64
}

struct WyrmTrail: Codable, Identifiable, Equatable {
    let id: String
    /// "photo", "text" (a caption with no photo) or "video".
    let kind: String?
    let caption: String
    let photo: WyrmTrailPhoto?
    let thumbUrl: String?
    var likeCount: Int
    var commentCount: Int
    var liked: Bool
    let mine: Bool
    let createdAt: String
    let author: WyrmTrailAuthor
    /// The poster's look when they chose to share it (Try this skin); absent
    /// in older trails and older caches.
    let skin: WyrmTrailSkin?
    /// A video trail's clip (OM, 2026-10-05); absent in photo and text trails
    /// and in older caches.
    let video: WyrmTrailVideo?

    /// Width over height, held between a tall 4:5 and a wide 1.91:1 so no
    /// photo takes over the feed or shrinks to a strip.
    var aspect: CGFloat {
        let width = video?.width ?? photo?.width ?? 0
        let height = video?.height ?? photo?.height ?? 0
        guard width > 0, height > 0 else { return 1 }
        return min(max(CGFloat(width) / CGFloat(height), 0.8), 1.91)
    }
}

struct WyrmTrailComment: Decodable, Identifiable, Equatable {
    let id: String
    let body: String
    let createdAt: String
    let mine: Bool
    let author: WyrmTrailAuthor
}

private struct WyrmTrailPage: Decodable { let trails: [WyrmTrail]; let nextCursor: String? }
private struct WyrmTrailEnvelope: Decodable { let trail: WyrmTrail }
private struct WyrmTrailCommentPage: Decodable { let comments: [WyrmTrailComment]; let nextCursor: String? }
private struct WyrmTrailCommentPosted: Decodable { let comment: WyrmTrailComment; let commentCount: Int }
private struct WyrmTrailLike: Decodable { let liked: Bool; let likeCount: Int }
private struct WyrmTrailMedia: Decodable { let id: String }
private struct WyrmTrailOK: Decodable {}
private struct WyrmTrailError: Decodable { let error: String? }

enum WyrmTrailPostPhase: Equatable {
    case idle
    case preparing
    case uploading(Double)
    case posted
    case failed(String)

    var busy: Bool {
        switch self {
        case .preparing, .uploading: return true
        default: return false
        }
    }
}

// MARK: - Network

final class WyrmTrailsClient {
    static let shared = WyrmTrailsClient()
    static let base = "https://wyrm-api.77-245-76-86.sslip.io"
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    static func absolute(_ raw: String) -> String { raw.hasPrefix("/") ? base + raw : raw }

    private final class UploadProgress: NSObject, URLSessionTaskDelegate {
        let report: (Double) -> Void
        init(report: @escaping (Double) -> Void) { self.report = report }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            guard totalBytesExpectedToSend > 0 else { return }
            report(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        }
    }

    private func send<T: Decodable>(_ path: String, method: String = "GET", json: [String: Any]? = nil,
                                    jpeg: Data? = nil, mp4: URL? = nil, query: [URLQueryItem] = [], token: String,
                                    progress: ((Double) -> Void)? = nil) async throws -> T {
        var components = URLComponents(string: Self.base + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw WyrmServiceError.message("Invalid Wyrm address.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            if let jpeg {
                request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
                (data, response) = try await session.upload(for: request, from: jpeg,
                                                            delegate: progress.map { UploadProgress(report: $0) })
            } else if let mp4 {
                // A video goes up from its file, never whole in memory.
                request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
                (data, response) = try await session.upload(for: request, fromFile: mp4,
                                                            delegate: progress.map { UploadProgress(report: $0) })
            } else {
                if let json {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: json)
                }
                (data, response) = try await session.data(for: request)
            }
        } catch {
            // A pull-to-refresh that ends, or a page that closes, cancels its
            // request: that is not a connection problem and says nothing.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            WyrmDiagnostics.record("\(method) \(path) transport failure", category: "NETWORK")
            throw WyrmServiceError.message("Could not reach Wyrm. Check your connection.")
        }
        guard let http = response as? HTTPURLResponse else { throw WyrmServiceError.message("Wyrm sent an invalid response.") }
        WyrmDiagnostics.record("\(method) \(path) status=\(http.statusCode)", category: "NETWORK")
        guard 200..<300 ~= http.statusCode else {
            let code = (try? JSONDecoder().decode(WyrmTrailError.self, from: data).error) ?? "HTTP_\(http.statusCode)"
            throw WyrmServiceError.message(Self.friendly(code))
        }
        if T.self == WyrmTrailOK.self { return WyrmTrailOK() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func friendly(_ code: String) -> String {
        switch code {
        case "IMAGE_TOO_LARGE": return "That photo is too large."
        case "UNSUPPORTED_IMAGE": return "That photo could not be read."
        case "VIDEO_TOO_LONG": return "Videos can be up to 30 seconds."
        case "VIDEO_TOO_LARGE": return "That video is too large."
        case "UNSUPPORTED_VIDEO", "EMPTY_VIDEO": return "That video could not be read."
        case "STORAGE_FULL": return "Trails is full right now. Try again later."
        case "NOT_FOUND": return "This trail is no longer here."
        case "BLOCKED": return "You can't reply to this trail."
        case "INVALID_SKIN": return "Your skin could not be shared. Try again without it."
        case "HTTP_429": return "Slow down a little and try again soon."
        default: return "Something went wrong. Try again."
        }
    }

    fileprivate func feed(cursor: String?, author: String?, token: String) async throws -> WyrmTrailPage {
        // The feed: 10 a page, so the server never sends the whole world at
        // once (OM, 2026-10-05). A profile grid takes 20 (small thumbnails).
        var query = [URLQueryItem(name: "limit", value: author == nil ? "10" : "20")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let author { query.append(URLQueryItem(name: "author", value: author)) }
        return try await send("/v1/trails", query: query, token: token)
    }

    fileprivate func trail(_ id: String, token: String) async throws -> WyrmTrail {
        let envelope: WyrmTrailEnvelope = try await send("/v1/trails/\(id)", token: token)
        return envelope.trail
    }

    fileprivate func upload(_ jpeg: Data, token: String, progress: @escaping (Double) -> Void) async throws -> String {
        let media: WyrmTrailMedia = try await send("/v1/trails/media", method: "PUT", jpeg: jpeg, token: token, progress: progress)
        return media.id
    }

    /// A finished clip (`video/mp4`, at most 30 s, 16 MB).
    fileprivate func uploadVideo(_ file: URL, token: String, progress: @escaping (Double) -> Void) async throws -> String {
        let media: WyrmTrailMedia = try await send("/v1/trails/video", method: "PUT", mp4: file, token: token, progress: progress)
        return media.id
    }

    /// `skin` goes only with `shareSkin` on; the server keeps nothing otherwise.
    /// A video trail sends its clip's `videoId` with its poster as the photo.
    fileprivate func create(caption: String, photoId: String?, thumbId: String?, skin: WyrmTrailSkin? = nil,
                            shareSkin: Bool = false, videoId: String? = nil, token: String) async throws -> WyrmTrail {
        var body: [String: Any] = ["caption": caption, "shareSkin": shareSkin && skin != nil]
        if let photoId, let thumbId { body["photoId"] = photoId; body["thumbId"] = thumbId }
        if let videoId { body["videoId"] = videoId }
        if shareSkin, let skin { body["skin"] = skin.json }
        let envelope: WyrmTrailEnvelope = try await send("/v1/trails", method: "POST", json: body, token: token)
        return envelope.trail
    }

    fileprivate func like(_ id: String, _ liked: Bool, token: String) async throws -> WyrmTrailLike {
        try await send("/v1/trails/\(id)/like", method: liked ? "PUT" : "DELETE", token: token)
    }

    fileprivate func delete(_ id: String, token: String) async throws {
        let _: WyrmTrailOK = try await send("/v1/trails/\(id)", method: "DELETE", token: token)
    }

    fileprivate func report(_ id: String, reason: String, token: String) async throws {
        let _: WyrmTrailOK = try await send("/v1/trails/\(id)/report", method: "POST", json: ["reason": reason], token: token)
    }

    fileprivate func comments(_ id: String, cursor: String?, token: String) async throws -> WyrmTrailCommentPage {
        var query = [URLQueryItem(name: "limit", value: "40")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send("/v1/trails/\(id)/comments", query: query, token: token)
    }

    fileprivate func comment(_ id: String, body: String, token: String) async throws -> WyrmTrailCommentPosted {
        try await send("/v1/trails/\(id)/comments", method: "POST", json: ["body": body], token: token)
    }

    fileprivate func deleteComment(_ id: String, commentId: String, token: String) async throws {
        let _: WyrmTrailOK = try await send("/v1/trails/\(id)/comments/\(commentId)", method: "DELETE", token: token)
    }
}

// MARK: - Images

/// Decoded photos in memory, files on disk. A trail's image address never
/// changes meaning, so nothing here ever needs to be refreshed.
final class WyrmTrailImages {
    static let shared = WyrmTrailImages()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 96 * 1024 * 1024
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024,
                                          diskPath: "wyrm-trails")
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(_ url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard let loaded = try? await session.data(from: url), let raw = UIImage(data: loaded.0) else { return nil }
        let ready = await Task.detached(priority: .userInitiated) { raw.preparingForDisplay() ?? raw }.value
        memory.setObject(ready, forKey: url as NSURL, cost: Int(ready.size.width * ready.size.height * 4))
        return ready
    }

    /// Warm the next page's photos while the player is still reading this one.
    func prefetch(_ urls: [URL]) {
        for url in urls where cached(url) == nil {
            Task.detached(priority: .utility) { _ = await self.image(url) }
        }
    }
}

/// A trail photo: its thumbnail at once, the full image when it lands.
struct WyrmTrailImage: View {
    let full: String
    let thumb: String
    let aspect: CGFloat
    @State private var image: UIImage?
    @State private var preview: UIImage?

    var body: some View {
        // The frame takes its shape from `aspect` alone; the photo fits
        // inside it, so a very wide or tall photo shrinks instead of
        // stretching the card.
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(ATheme.well)
            .overlay(Group {
                if let shown = image ?? preview {
                    Image(uiImage: shown).resizable().scaledToFit().transition(.opacity)
                }
            })
            .clipped()
        .task(id: full) {
            let fullURL = URL(string: WyrmTrailsClient.absolute(full))
            let thumbURL = URL(string: WyrmTrailsClient.absolute(thumb))
            if let fullURL, let hit = WyrmTrailImages.shared.cached(fullURL) { image = hit; return }
            if let thumbURL, let small = await WyrmTrailImages.shared.image(thumbURL), image == nil {
                withAnimation(.easeOut(duration: 0.18)) { preview = small }
            }
            if let fullURL, let big = await WyrmTrailImages.shared.image(fullURL) {
                withAnimation(.easeOut(duration: 0.22)) { image = big }
            }
        }
    }
}

/// Resizes and re-encodes in the app, off the main thread: the full photo at
/// most 1440 px on its long side, and a 540 px thumbnail for the feed's first paint.
enum WyrmTrailEncoder {
    static func prepare(_ image: UIImage) async -> (full: Data, thumb: Data)? {
        await Task.detached(priority: .userInitiated) {
            guard var full = encode(image, longest: 1440, quality: 0.82),
                  let thumb = encode(image, longest: 540, quality: 0.72) else { return nil }
            var quality: CGFloat = 0.72
            while full.count > 2_800_000, quality > 0.4 {
                guard let smaller = encode(image, longest: 1440, quality: quality) else { break }
                full = smaller
                quality -= 0.1
            }
            return (full, thumb)
        }.value
    }

    private static func encode(_ image: UIImage, longest: CGFloat, quality: CGFloat) -> Data? {
        let side = max(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let scale = min(1, longest / side)
        let size = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return drawn.jpegData(compressionQuality: quality)
    }
}

// MARK: - Store

/// One profile's trail grid: what is loaded, and where the next page starts.
struct WyrmAuthorTrails: Equatable {
    var trails: [WyrmTrail] = []
    var cursor: String?
    var reachedEnd = false
    var loaded = false
    var loading = false
    var failed = false
}

@MainActor
final class WyrmTrailsStore: ObservableObject {
    static let shared = WyrmTrailsStore()

    @Published private(set) var trails: [WyrmTrail] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var reachedEnd = false
    @Published private(set) var loaded = false
    @Published var error = ""
    @Published private(set) var posting: WyrmTrailPostPhase = .idle
    /// The trail being posted, shown at the top of the feed until it lands:
    /// the player is back in the feed the moment they tap Post.
    @Published private(set) var pendingImage: UIImage?
    @Published private(set) var pendingCaption = ""
    @Published private(set) var pendingActive = false
    /// The pending post's shared skin (Share run), kept for a retry.
    private var pendingSkin: WyrmTrailSkin?
    private var pendingShareSkin = false
    /// A video post's "Try again": the whole export and upload once more.
    private var pendingVideoRetry: (() -> Void)?
    /// The clip being posted, whose own copy goes once it is posted or dropped.
    private var pendingClip: WyrmTrailClip?
    @Published private(set) var comments: [String: [WyrmTrailComment]] = [:]
    @Published var toast = ""

    /// Trails opened from somewhere other than the feed (a profile grid, an
    /// alert): kept aside so an old trail never jumps to the top of the feed.
    @Published private(set) var loose: [String: WyrmTrail] = [:]
    /// Each profile's trail grid, by player id.
    @Published private(set) var authors: [String: WyrmAuthorTrails] = [:]

    var token: () -> String = { "" }
    private var cursor: String?
    private var liking: Set<String> = []
    private static let feedCacheKey = "trails-feed"
    private static func authorCacheKey(_ id: String) -> String { "trails-author-\(id)" }

    /// Stale-while-revalidate (OM, 2026-09-29): the last first page paints at
    /// once from disk, the network answer replaces it in place (same ids keep
    /// their spot, so nothing jumps), and a skeleton is only ever seen on the
    /// very first open.
    func refresh() async {
        guard !loading else { return }
        if !loaded, trails.isEmpty, let cached = WyrmCache.load(Self.feedCacheKey, as: [WyrmTrail].self), !cached.isEmpty {
            trails = cached
            loaded = true
        }
        loading = true
        defer { loading = false }
        do {
            // Its own task: pull-to-refresh cancels the gesture's task when it
            // ends, and the feed must still arrive.
            let token = token()
            let page = try await Task { try await WyrmTrailsClient.shared.feed(cursor: nil, author: nil, token: token) }.value
            withAnimation(.easeOut(duration: 0.2)) { trails = page.trails }
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
            error = ""
            prefetch(page.trails)
            persistFeed()
        } catch is CancellationError {
        } catch { self.error = message(error) }
        loaded = true
    }

    /// A player's trails for their profile grid, cached per player.
    func loadAuthor(_ id: String) async {
        guard !id.isEmpty else { return }
        if authors[id] == nil {
            var seed = WyrmAuthorTrails()
            if let cached = WyrmCache.load(Self.authorCacheKey(id), as: [WyrmTrail].self) {
                seed.trails = cached
                seed.loaded = true
            }
            authors[id] = seed
        }
        guard authors[id]?.loading != true else { return }
        authors[id]?.loading = true
        do {
            let token = token()
            let page = try await Task { try await WyrmTrailsClient.shared.feed(cursor: nil, author: id, token: token) }.value
            var entry = authors[id] ?? WyrmAuthorTrails()
            entry.trails = page.trails
            entry.cursor = page.nextCursor
            entry.reachedEnd = page.nextCursor == nil
            entry.loaded = true
            entry.loading = false
            entry.failed = false
            withAnimation(.easeOut(duration: 0.2)) { authors[id] = entry }
            WyrmCache.save(Self.authorCacheKey(id), Array(page.trails.prefix(30)))
            WyrmTrailImages.shared.prefetch(page.trails.compactMap { $0.thumbUrl.flatMap { URL(string: WyrmTrailsClient.absolute($0)) } })
        } catch {
            authors[id]?.loading = false
            if error is CancellationError { return }
            authors[id]?.failed = authors[id]?.trails.isEmpty == true
            authors[id]?.loaded = true
        }
    }

    func loadMoreAuthor(_ id: String, after trail: WyrmTrail) async {
        guard let entry = authors[id], trail.id == entry.trails.last?.id, !entry.reachedEnd,
              !entry.loading, let next = entry.cursor else { return }
        authors[id]?.loading = true
        do {
            let page = try await WyrmTrailsClient.shared.feed(cursor: next, author: id, token: token())
            let known = Set(authors[id]?.trails.map(\.id) ?? [])
            authors[id]?.trails += page.trails.filter { !known.contains($0.id) }
            authors[id]?.cursor = page.nextCursor
            authors[id]?.reachedEnd = page.nextCursor == nil
        } catch { }
        authors[id]?.loading = false
    }

    /// Sign-out: "liked" and "mine" belong to the account that signed out.
    func reset() {
        trails = []
        loose = [:]
        authors = [:]
        comments = [:]
        cursor = nil
        reachedEnd = false
        loaded = false
        error = ""
        liking = []
        WyrmTrailFeedPlayer.shared.stop()
        if !posting.busy { posting = .idle; pendingImage = nil; pendingActive = false; dropPendingVideo() }
    }

    private func persistFeed() {
        WyrmCache.save(Self.feedCacheKey, Array(trails.prefix(20)))
    }

    /// One change, applied wherever this trail is shown.
    private func patch(_ id: String, _ change: (inout WyrmTrail) -> Void) {
        if let i = trails.firstIndex(where: { $0.id == id }) { change(&trails[i]) }
        if var single = loose[id] { change(&single); loose[id] = single }
        for key in Array(authors.keys) {
            if let i = authors[key]?.trails.firstIndex(where: { $0.id == id }) { change(&authors[key]!.trails[i]) }
        }
    }

    func loadMoreIfNeeded(after trail: WyrmTrail) async {
        // Three cards before the end, so the next page is there when the thumb gets there.
        guard let at = trails.firstIndex(where: { $0.id == trail.id }), at >= trails.count - 3,
              !reachedEnd, !loadingMore, !loading, let cursor else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await WyrmTrailsClient.shared.feed(cursor: cursor, author: nil, token: token())
            let known = Set(trails.map(\.id))
            trails += page.trails.filter { !known.contains($0.id) }
            self.cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
            prefetch(page.trails)
        } catch is CancellationError {
        } catch { self.error = message(error) }
    }

    func trail(_ id: String) -> WyrmTrail? {
        if let hit = trails.first(where: { $0.id == id }) { return hit }
        if let hit = loose[id] { return hit }
        for entry in authors.values { if let hit = entry.trails.first(where: { $0.id == id }) { return hit } }
        return nil
    }

    /// The trail fresh from the server, wherever it is shown. One that is not
    /// in the feed stays out of it.
    func reload(_ id: String) async {
        guard let fresh = try? await WyrmTrailsClient.shared.trail(id, token: token()) else { return }
        let shown = trails.contains { $0.id == id } || authors.values.contains { $0.trails.contains { $0.id == id } }
        if !shown { loose[id] = fresh }
        patch(id) { $0 = fresh }
    }

    /// On screen at once; the server's count wins when it answers.
    func toggleLike(_ id: String) {
        guard let current = trail(id), !liking.contains(id) else { return }
        let next = !current.liked
        patch(id) {
            $0.liked = next
            $0.likeCount = max(0, $0.likeCount + (next ? 1 : -1))
        }
        liking.insert(id)
        Task {
            defer { liking.remove(id) }
            do {
                let result = try await WyrmTrailsClient.shared.like(id, next, token: token())
                patch(id) {
                    $0.liked = result.liked
                    $0.likeCount = result.likeCount
                }
                persistFeed()
            } catch {
                patch(id) {
                    $0.liked = !next
                    $0.likeCount = max(0, $0.likeCount + (next ? -1 : 1))
                }
            }
        }
    }

    /// A photo trail, or a text trail when `image` is nil. Share run adds the
    /// player's look (`skin`), sent only when `shareSkin` is on.
    func post(image: UIImage?, caption: String, skin: WyrmTrailSkin? = nil, shareSkin: Bool = false) async -> Bool {
        guard !posting.busy else { return false }
        let words = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let shared = shareSkin ? skin : nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            pendingImage = image
            pendingCaption = words
            pendingActive = true
        }
        pendingSkin = shared
        pendingShareSkin = shared != nil
        posting = .preparing
        guard let image else {
            posting = .uploading(0.5)
            do {
                let trail = try await Task {
                    try await WyrmTrailsClient.shared.create(caption: words, photoId: nil, thumbId: nil, skin: shared,
                                                             shareSkin: shared != nil, token: token())
                }.value
                landed(trail)
                return true
            } catch {
                posting = .failed(message(error))
                return false
            }
        }
        guard let files = await WyrmTrailEncoder.prepare(image) else {
            posting = .failed("That photo could not be read.")
            return false
        }
        posting = .uploading(0)
        let total = Double(files.full.count + files.thumb.count)
        let thumbShare = Double(files.thumb.count) / max(total, 1)
        do {
            let thumbId = try await WyrmTrailsClient.shared.upload(files.thumb, token: token()) { value in
                Task { @MainActor in self.posting = .uploading(value * thumbShare * 0.97) }
            }
            let photoId = try await WyrmTrailsClient.shared.upload(files.full, token: token()) { value in
                Task { @MainActor in self.posting = .uploading((thumbShare + value * (1 - thumbShare)) * 0.97) }
            }
            let trail = try await WyrmTrailsClient.shared.create(caption: words, photoId: photoId, thumbId: thumbId, skin: shared,
                                                                 shareSkin: shared != nil, token: token())
            landed(trail)
            return true
        } catch {
            posting = .failed(message(error))
            return false
        }
    }

    /**
     * A video trail (OM, 2026-10-05). The player is back in the feed at once;
     * then, on the phone, the clip is trimmed and compressed
     * (`WyrmTrailVideoExport`), sent, its poster sent as a photo and
     * thumbnail, and the trail made. The pending card shows the poster and one
     * progress for the whole way: the export is the first 45%, the clip the
     * next 45%, the poster the rest. `overlays[tier]` is everything drawn on
     * top, at each export size.
     */
    func postVideo(clip: WyrmTrailClip, startMs: Int64, endMs: Int64, muted: Bool, look: WyrmTrailLook,
                   adjust: WyrmTrailAdjust, overlays: [UIImage?], poster: UIImage?, caption: String) async -> Bool {
        guard !posting.busy else { return false }
        let words = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            pendingImage = poster
            pendingCaption = words
            pendingActive = true
        }
        pendingSkin = nil
        pendingShareSkin = false
        pendingClip = clip
        pendingVideoRetry = { [weak self] in
            Task { _ = await self?.postVideo(clip: clip, startMs: startMs, endMs: endMs, muted: muted, look: look,
                                             adjust: adjust, overlays: overlays, poster: poster, caption: caption) }
        }
        posting = .uploading(0)
        var made: URL?
        defer { if let made { try? FileManager.default.removeItem(at: made) } }
        do {
            let file = try await WyrmTrailVideoExport.export(clip, startMs: startMs, endMs: endMs, muted: muted, look: look,
                                                             adjust: adjust, overlays: overlays) { value in
                Task { @MainActor in if case .uploading = self.posting { self.posting = .uploading(value * 0.45) } }
            }
            made = file
            let still = poster ?? WyrmTrailFrames.frame(clip, atMs: startMs, longest: 1440)
            guard let still, let files = await WyrmTrailEncoder.prepare(still) else { throw WyrmTrailVideoError.unreadable }
            posting = .uploading(0.45)
            let token = token()
            let videoId = try await WyrmTrailsClient.shared.uploadVideo(file, token: token) { value in
                Task { @MainActor in if case .uploading = self.posting { self.posting = .uploading(0.45 + value * 0.45) } }
            }
            let thumbId = try await WyrmTrailsClient.shared.upload(files.thumb, token: token) { value in
                Task { @MainActor in if case .uploading = self.posting { self.posting = .uploading(0.9 + value * 0.03) } }
            }
            let photoId = try await WyrmTrailsClient.shared.upload(files.full, token: token) { value in
                Task { @MainActor in if case .uploading = self.posting { self.posting = .uploading(0.93 + value * 0.04) } }
            }
            let trail = try await WyrmTrailsClient.shared.create(caption: words, photoId: photoId, thumbId: thumbId,
                                                                 videoId: videoId, token: token)
            dropPendingVideo()
            landed(trail)
            return true
        } catch is CancellationError {
            posting = .failed("Posting stopped. Try again.")
            return false
        } catch {
            posting = .failed(message(error))
            return false
        }
    }

    /// The pending video's retry and its own copy of the clip, gone.
    private func dropPendingVideo() {
        pendingVideoRetry = nil
        pendingClip?.removeOwnedFile()
        pendingClip = nil
    }

    private func landed(_ trail: WyrmTrail) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            trails.insert(trail, at: 0)
            if authors[trail.author.playerId] != nil { authors[trail.author.playerId]?.trails.insert(trail, at: 0) }
            pendingImage = nil
            pendingActive = false
            posting = .posted
        }
        persistFeed()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        toast = "Trail posted"
    }

    func resetPosting() { if !posting.busy && !pendingActive { posting = .idle } }

    func retryPending() {
        guard pendingActive, !posting.busy else { return }
        if let again = pendingVideoRetry {
            posting = .idle
            again()
            return
        }
        let image = pendingImage, caption = pendingCaption, skin = pendingSkin, share = pendingShareSkin
        Task { _ = await post(image: image, caption: caption, skin: skin, shareSkin: share) }
    }

    func discardPending() {
        guard !posting.busy else { return }
        dropPendingVideo()
        withAnimation(.easeOut(duration: 0.2)) { pendingImage = nil; pendingActive = false; posting = .idle }
    }

    /// Removes it from the server; the card has already scattered, so the
    /// trails around it close the gap with a spring.
    func delete(_ id: String) async -> Bool {
        do {
            try await Task { try await WyrmTrailsClient.shared.delete(id, token: token()) }.value
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                trails.removeAll { $0.id == id }
                loose[id] = nil
                for key in Array(authors.keys) { authors[key]?.trails.removeAll { $0.id == id } }
            }
            persistFeed()
            toast = "Trail deleted"
            return true
        } catch {
            toast = message(error)
            return false
        }
    }

    func report(_ id: String, reason: String) async {
        do {
            try await WyrmTrailsClient.shared.report(id, reason: reason, token: token())
            toast = "Thanks. We'll take a look."
        } catch { toast = message(error) }
    }

    func loadComments(_ id: String) async {
        guard let page = try? await WyrmTrailsClient.shared.comments(id, cursor: nil, token: token()) else { return }
        comments[id] = page.comments
    }

    func reply(_ id: String, body: String) async -> Bool {
        do {
            let posted = try await WyrmTrailsClient.shared.comment(id, body: body, token: token())
            comments[id, default: []].append(posted.comment)
            patch(id) { $0.commentCount = posted.commentCount }
            return true
        } catch {
            toast = message(error)
            return false
        }
    }

    func deleteReply(_ id: String, commentId: String) async {
        do {
            try await WyrmTrailsClient.shared.deleteComment(id, commentId: commentId, token: token())
            comments[id]?.removeAll { $0.id == commentId }
            patch(id) { $0.commentCount = max(0, $0.commentCount - 1) }
        } catch { toast = message(error) }
    }

    private func prefetch(_ page: [WyrmTrail]) {
        WyrmTrailImages.shared.prefetch(page.compactMap { $0.thumbUrl.flatMap { URL(string: WyrmTrailsClient.absolute($0)) } })
        WyrmTrailImages.shared.prefetch(page.prefix(4).compactMap { $0.photo.flatMap { URL(string: WyrmTrailsClient.absolute($0.url)) } })
    }

    private func message(_ error: Error) -> String {
        if case WyrmServiceError.message(let text) = error { return text }
        if error is WyrmTrailVideoError || (error as NSError).domain == AVFoundationErrorDomain {
            return "This phone could not prepare that video."
        }
        return "Something went wrong. Try again."
    }
}

// MARK: - Shared pieces

enum WyrmTrailTime {
    private static let precise: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    static func short(_ raw: String) -> String {
        guard let date = precise.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        if seconds < 7 * 86_400 { return "\(seconds / 86_400)d" }
        return day.string(from: date)
    }
}

/// Wyrm's like: a bead that fills with the theme's live colour and pops.
struct WyrmTrailBead: View {
    let liked: Bool
    let count: Int
    let action: () -> Void
    @State private var pop = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: liked ? .light : .medium).impactOccurred()
            if !liked {
                pop = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { pop = false }
            }
            action()
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle().stroke(liked ? ATheme.live : ATheme.quiet, lineWidth: 1.6)
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.85), ATheme.live], center: UnitPoint(x: 0.35, y: 0.3),
                                             startRadius: 0, endRadius: 9))
                        .scaleEffect(liked ? 1 : 0.01)
                        .opacity(liked ? 1 : 0)
                }
                .frame(width: 17, height: 17)
                .scaleEffect(pop ? 1.35 : 1)
                Text(count == 0 ? "Like" : "\(count)")
                    .font(.androidWyrm(13, .semibold)).monospacedDigit()
                    .foregroundColor(liked ? ATheme.ink : ATheme.mute)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(Capsule().fill(liked ? ATheme.live.opacity(0.14) : ATheme.well))
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: liked)
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: pop)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(liked ? "Liked, \(count)" : "Like, \(count)")
    }
}

private struct WyrmTrailRepliesPill: View {
    let count: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").font(.system(size: 13, weight: .semibold))
                Text(count == 0 ? "Reply" : "\(count)").font(.androidWyrm(13, .semibold)).monospacedDigit()
            }
            .foregroundColor(ATheme.mute)
            .padding(.horizontal, 12).frame(height: 34)
            .background(Capsule().fill(ATheme.well))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replies, \(count)")
    }
}

/// One trail in the feed: who and when, the photo, then the caption and actions.
struct WyrmTrailCard: View {
    let trail: WyrmTrail
    var expanded = false
    let onOpen: () -> Void
    let onAuthor: () -> Void
    @ObservedObject var store = WyrmTrailsStore.shared
    @ObservedObject private var feed = WyrmTrailFeedPlayer.shared
    @State private var burst = false
    @State private var confirmDelete = false
    @State private var reporting = false
    @State private var dying = false
    @State private var food: [Color] = []
    @State private var cardSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onAuthor) {
                    HStack(spacing: 10) {
                        WyrmAvatar(initials: trail.author.initials, size: 34, url: trail.author.avatarURL)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(trail.author.name).font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.ink).lineLimit(1)
                            Text([trail.author.handle, WyrmTrailTime.short(trail.createdAt)].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.androidWyrm(11)).foregroundColor(ATheme.quiet).lineLimit(1)
                        }
                    }
                }.buttonStyle(.plain)
                Spacer(minLength: 6)
                Menu {
                    if trail.mine {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete trail", systemImage: "trash") }
                    } else {
                        Button { reporting = true } label: { Label("Report", systemImage: "flag") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundColor(ATheme.quiet)
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)

            ZStack {
                if let clip = trail.video, let photo = trail.photo {
                    // A video: only the card most in view plays (the open trail always does).
                    WyrmTrailVideoView(trailId: trail.id, video: clip, poster: photo.url, thumb: trail.thumbUrl ?? photo.url,
                                       aspect: trail.aspect, active: expanded || feed.activeId == trail.id)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if let photo = trail.photo {
                    WyrmTrailImage(full: photo.url, thumb: trail.thumbUrl ?? photo.url, aspect: trail.aspect)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    WyrmTrailTextBody(text: trail.caption)
                }
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.9), ATheme.live], center: UnitPoint(x: 0.35, y: 0.3),
                                         startRadius: 0, endRadius: 46))
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .scaleEffect(burst ? 1 : 0.2)
                    .opacity(burst ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if !trail.liked { store.toggleLike(trail.id) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { burst = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { withAnimation(.easeOut(duration: 0.25)) { burst = false } }
            }
            .onTapGesture(count: 1) { if !expanded { onOpen() } }

            if !trail.caption.isEmpty && trail.photo != nil {
                Text(trail.caption)
                    .font(.androidWyrm(14.5)).foregroundColor(ATheme.ink).lineSpacing(3)
                    .lineLimit(expanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.top, 12)
            }

            HStack(spacing: 8) {
                WyrmTrailBead(liked: trail.liked, count: trail.likeCount) { store.toggleLike(trail.id) }
                WyrmTrailRepliesPill(count: trail.commentCount, action: onOpen)
                Spacer(minLength: 0)
                // The poster shared their look: preview it in the Skin tab.
                if let skin = trail.skin {
                    WyrmTrySkinCapsule { WyrmSkinTrial.shared.start(skin, author: trail.author.name) }
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        }
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .background(GeometryReader { proxy in Color.clear.onAppear { cardSize = proxy.size }.onChange(of: proxy.size) { cardSize = $0 } })
        .opacity(dying ? 0 : 1)
        .scaleEffect(dying ? 0.92 : 1)
        .overlay(Group { if dying { WyrmTrailFoodBurst(colours: food, size: cardSize).frame(width: cardSize.width, height: cardSize.height) } })
        .padding(.horizontal, 14)
        .confirmationDialog("Delete this trail?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { scatter() }
        }
        .confirmationDialog("Report trail", isPresented: $reporting) {
            ForEach(["Spam", "Harassment or abuse", "Nudity or sexual content", "Hate or violence", "Something else"], id: \.self) { reason in
                Button(reason) { Task { await store.report(trail.id, reason: reason) } }
            }
        }
    }
}

extension WyrmTrailCard {
    /// The card breaks into food, then the trail is removed and the feed closes up.
    fileprivate func scatter() {
        let url = (trail.thumbUrl ?? trail.photo?.url).flatMap { URL(string: WyrmTrailsClient.absolute($0)) }
        food = WyrmTrailFoodBurst.colours(from: url.flatMap { WyrmTrailImages.shared.cached($0) })
        if food.isEmpty { food = [ATheme.live, ATheme.link, ATheme.badge, ATheme.ink] }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        withAnimation(.easeIn(duration: 0.22)) { dying = true }
        Task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            if !(await store.delete(trail.id)) { withAnimation(.easeOut(duration: 0.25)) { dying = false } }
        }
    }
}

/// Deleting a trail: it breaks into glowing food, the way a snake's body
/// scatters into food when it dies in the arena, each piece coloured from the
/// photo where it lay. The food drifts out, glows and fades.
struct WyrmTrailFoodBurst: View {
    let colours: [Color]
    let size: CGSize
    private struct Piece { let start: CGPoint; let velocity: CGVector; let radius: CGFloat; let colour: Color; let delay: Double }
    @State private var pieces: [Piece] = []
    @State private var began = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let t = timeline.date.timeIntervalSince(began)
                for piece in pieces {
                    let local = max(0, t - piece.delay)
                    let ease = 1 - exp(-local * 3.2)
                    let x = piece.start.x + piece.velocity.dx * ease
                    let y = piece.start.y + piece.velocity.dy * ease
                    let life = max(0, 1 - local / 0.95)
                    guard life > 0 else { continue }
                    let pulse = 1 + 0.18 * sin(local * 18 + Double(piece.radius))
                    let r = piece.radius * pulse * (0.6 + 0.4 * life)
                    // The glow, then the bright core.
                    context.opacity = life * 0.55
                    context.fill(Path(ellipseIn: CGRect(x: x - r * 2.4, y: y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                                 with: .radialGradient(Gradient(colors: [piece.colour, piece.colour.opacity(0)]),
                                                       center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 2.4))
                    context.opacity = life
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .radialGradient(Gradient(colors: [Color.white, piece.colour]),
                                                       center: CGPoint(x: x - r * 0.3, y: y - r * 0.3), startRadius: 0, endRadius: r))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            began = Date()
            let columns = 7, rows = max(4, Int((size.height / max(size.width, 1)) * 7))
            var made: [Piece] = []
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = (CGFloat(column) + 0.5) / CGFloat(columns) * size.width
                    let y = (CGFloat(row) + 0.5) / CGFloat(rows) * size.height
                    let dx = x - size.width / 2, dy = y - size.height / 2
                    let spread = CGFloat.random(in: 40...120)
                    let length = max(hypot(dx, dy), 1)
                    let colour = colours.isEmpty ? ATheme.live : colours[(row * columns + column) % colours.count]
                    made.append(Piece(start: CGPoint(x: x, y: y),
                                      velocity: CGVector(dx: dx / length * spread + .random(in: -20...20),
                                                         dy: dy / length * spread + .random(in: -30...20)),
                                      radius: .random(in: 4...9), colour: colour, delay: .random(in: 0...0.12)))
                }
            }
            pieces = made
        }
    }

    /// Colours sampled on a grid across the photo, one per piece of food.
    static func colours(from image: UIImage?, columns: Int = 7, rows: Int = 9) -> [Color] {
        guard let cg = image?.cgImage else { return [] }
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        guard let context = CGContext(data: &pixels, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        var out: [Color] = []
        for row in (0..<rows).reversed() {
            for column in 0..<columns {
                let i = (row * columns + column) * 4
                // Pushed brighter so the food glows like the arena's.
                func lift(_ v: UInt8) -> Double { min(1, Double(v) / 255 * 1.25 + 0.08) }
                out.append(Color(red: lift(pixels[i]), green: lift(pixels[i + 1]), blue: lift(pixels[i + 2])))
            }
        }
        return out
    }
}

/// Upload progress as a snake of beads that fills with the live colour.
struct WyrmTrailBeadProgress: View {
    let progress: Double?
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let count = 18
                let gap = proxy.size.width / CGFloat(count)
                ZStack(alignment: .leading) {
                    ForEach(0..<count, id: \.self) { index in
                        let lit = progress.map { Double(index) < $0 * Double(count) } ?? (Int(t * 12) % count == index)
                        let wave = sin(t * 7 - Double(index) * 0.55) * 3
                        Circle()
                            .fill(lit ? ATheme.live : ATheme.well)
                            .frame(width: gap * 0.78, height: gap * 0.78)
                            .overlay(Circle().fill(Color.white.opacity(lit ? 0.35 : 0)).scaleEffect(0.4).offset(x: -gap * 0.12, y: -gap * 0.12))
                            .offset(x: CGFloat(index) * gap, y: CGFloat(wave))
                    }
                }
                .frame(height: proxy.size.height)
            }
        }
        .frame(height: 20)
    }
}

/// A text trail: the words themselves, set large, with the live colour's
/// trail mark beside them.
struct WyrmTrailTextBody: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(ATheme.live).frame(width: 4)
            Text(text)
                .font(.wyrmDisplay(text.count < 90 ? 26 : 20))
                .foregroundColor(ATheme.ink).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ATheme.well))
        .padding(.horizontal, 8)
    }
}

/// Grey blocks the shape of a trail while the first page loads.
private struct WyrmTrailPlaceholder: View {
    @State private var dim = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10).fill(ATheme.well).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(ATheme.well).frame(width: 120, height: 10)
                    Capsule().fill(ATheme.well).frame(width: 70, height: 8)
                }
            }
            RoundedRectangle(cornerRadius: 16).fill(ATheme.well).aspectRatio(1, contentMode: .fit)
            Capsule().fill(ATheme.well).frame(width: 200, height: 10)
        }
        .padding(14)
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 14)
        .opacity(dim ? 0.55 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true } }
    }
}

/// The trail being posted: its photo dimmed under the upload's progress,
/// or, if it failed, a way to try again.
struct WyrmTrailPendingCard: View {
    let image: UIImage?
    let caption: String
    let phase: WyrmTrailPostPhase
    let retry: () -> Void
    let discard: () -> Void

    private var progress: Double? {
        switch phase {
        case .preparing: return nil
        case .uploading(let value): return value
        case .posted: return 1
        default: return nil
        }
    }

    @State private var lastTick = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ZStack { ATheme.well; Image(systemName: "text.quote").font(.system(size: 20, weight: .semibold)).foregroundColor(ATheme.live) }
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(0.85)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.androidWyrm(14.5, .semibold)).monospacedDigit().foregroundColor(ATheme.ink)
                    Text(caption.isEmpty ? "Photo" : caption).font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if case .failed = phase {
                HStack(spacing: 10) {
                    WSOutlineButton(label: "Discard", onClick: discard)
                    WSPrimaryButton(label: "Try again", onClick: retry)
                }
            } else {
                WyrmTrailBeadProgress(progress: progress)
            }
        }
        .padding(14)
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .modifier(WyrmTrailWobble(active: phase.busy))
        .padding(.horizontal, 14)
        .onChange(of: progress) { value in
            // A tick of the Taptic Engine at every quarter uploaded.
            guard let value else { return }
            let tick = Int(value * 4)
            if tick != lastTick { lastTick = tick; UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }
        }
    }

    private var title: String {
        switch phase {
        case .preparing: return "Preparing…"
        case .uploading(let value): return "Uploading… \(Int((value * 100).rounded()))%"
        case .posted: return "Posted"
        case .failed(let message): return message
        case .idle: return "Waiting…"
        }
    }
}

/// While a trail uploads its card breathes and sways, like a snake at rest.
private struct WyrmTrailWobble: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            content
                .rotationEffect(.degrees(active ? sin(t * 5.2) * 0.9 : 0))
                .scaleEffect(active ? 1 + sin(t * 2.6) * 0.012 : 1)
        }
    }
}

// MARK: - Feed

struct WyrmTrailsFeed: View {
    @ObservedObject var account: WyrmAccountStore
    /// Nil on the Trails tab (OM, 2026-10-04): no Back there.
    var close: (() -> Void)? = nil
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var store = WyrmTrailsStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        header
                        if !store.loaded && store.trails.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in WyrmTrailPlaceholder() }
                        } else if store.trails.isEmpty && !store.pendingActive {
                            empty
                        } else {
                            if store.pendingActive {
                                WyrmTrailPendingCard(image: store.pendingImage, caption: store.pendingCaption, phase: store.posting,
                                                     retry: store.retryPending, discard: store.discardPending)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            ForEach(store.trails) { trail in
                                WyrmTrailCard(trail: trail, onOpen: { open(.trail(trail.id)) },
                                              onAuthor: { open(.profile(trail.author.playerId)) })
                                    .background(GeometryReader { proxy in
                                        Color.clear.preference(key: WyrmTrailVideoSpots.self,
                                                               value: trail.video == nil ? [:] : [trail.id: proxy.frame(in: .named("trailsFeed")).midY])
                                    })
                                    .task { await store.loadMoreIfNeeded(after: trail) }
                            }
                            if store.loadingMore { ProgressView().padding(.vertical, 18) }
                            if store.reachedEnd && store.trails.count > 3 {
                                Text("You're all caught up").font(.androidWyrm(11.5, .semibold)).foregroundColor(ATheme.quiet)
                                    .padding(.vertical, 18)
                            }
                        }
                        if !store.error.isEmpty && store.trails.isEmpty {
                            Text(store.error).font(.androidWyrm(12)).foregroundColor(ATheme.badge).padding(.horizontal, 20)
                        }
                        Spacer().frame(height: 110)
                    }
                    .padding(.top, 6)
                }
                .coordinateSpace(name: "trailsFeed")
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { feedHeight = proxy.size.height }.onChange(of: proxy.size.height) { feedHeight = $0 }
                })
                // One clip plays: the video card whose middle is nearest the middle of the feed (OM, 2026-10-05).
                .onPreferenceChange(WyrmTrailVideoSpots.self) { spots in
                    let middle = feedHeight / 2
                    let best = spots.filter { $0.value >= 0 && $0.value <= feedHeight }
                        .min { abs($0.value - middle) < abs($1.value - middle) }?.key
                    if WyrmTrailFeedPlayer.shared.activeId != best { WyrmTrailFeedPlayer.shared.activeId = best }
                }
                .refreshable { await store.refresh() }
            }
        }
        .background(WyrmPaperBackground().ignoresSafeArea())
        .foregroundColor(ATheme.ink)
        .onChange(of: scenePhase) { phase in
            if phase == .active { WyrmTrailFeedPlayer.shared.resume() } else { WyrmTrailFeedPlayer.shared.pause() }
        }
        .onDisappear {
            WyrmTrailFeedPlayer.shared.pause()
            WyrmTrailFeedPlayer.shared.activeId = nil
        }
        .onAppear { store.token = { [weak account] in account?.sessionToken ?? "" } }
        .task { if !store.loaded { await store.refresh() } }
        .overlay(alignment: .top) { WyrmTrailToast(store: store) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THE WYRM COMMUNITY").font(.androidWyrm(10.5, .bold)).tracking(1.15).foregroundColor(ATheme.quiet)
            Text("Trails").font(.wyrmDisplay(34)).foregroundColor(ATheme.ink)
            Text("Show off your skins, kills and best moments.").font(.androidWyrm(13)).foregroundColor(ATheme.mute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 30, weight: .semibold)).foregroundColor(ATheme.live)
            Text("No trails yet").font(.wyrmDisplay(22)).foregroundColor(ATheme.ink)
            Text("Be the first to leave one. Share a skin, a big run or a moment from the arena.")
                .font(.androidWyrm(13)).foregroundColor(ATheme.mute).multilineTextAlignment(.center)
            newButton(large: true).padding(.top, 10)
        }
        .padding(22)
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 14)
    }

    /// Back, the title, and the one way to post: top right once there are
    /// trails, in the middle of the page while there are none.
    private var topBar: some View {
        ZStack {
            HStack {
                if let close = close {
                    Button(action: close) {
                        HStack(spacing: 5) { Image(systemName: "chevron.left"); Text("Back") }
                            .font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.link)
                    }
                }
                Spacer()
                if !store.trails.isEmpty || store.pendingActive {
                    newButton(large: false).transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            Text("Trails").font(.androidWyrm(16, .semibold))
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(ATheme.paper)
        .overlay(Rectangle().fill(ATheme.rule).frame(height: 1), alignment: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.trails.isEmpty)
    }

    private func newButton(large: Bool) -> some View {
        Button { open(.trailCompose) } label: {
            HStack(spacing: large ? 8 : 6) {
                Image(systemName: "plus").font(.system(size: large ? 15 : 12, weight: .bold))
                Text(large ? "Leave a trail" : "New").font(.androidWyrm(large ? 15 : 13, .bold))
            }
            .foregroundColor(ATheme.onInk)
            .padding(.horizontal, large ? 22 : 14).frame(height: large ? 50 : 34)
            .background(Capsule().fill(ATheme.ink))
            .shadow(color: .black.opacity(large ? 0.18 : 0.12), radius: large ? 16 : 8, y: large ? 6 : 3)
        }
        .buttonStyle(WSPressStyle())
    }
}

struct WyrmTrailToast: View {
    @ObservedObject var store: WyrmTrailsStore
    var body: some View {
        Group {
            if !store.toast.isEmpty {
                Text(store.toast)
                    .font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.onInk)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(ATheme.ink))
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        let shown = store.toast
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.2)) { if store.toast == shown { store.toast = "" } }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.toast)
    }
}


// MARK: - Social tab teaser

/// Trails at the top of Social: the newest photos, so there is always a
/// reason to look, and one tap to leave your own.
struct WyrmTrailsTeaser: View {
    @ObservedObject var account: WyrmAccountStore
    let open: (WyrmDesignRoute) -> Void
    /// Unread likes and replies on your trails (the badge trail, OM 2026-10-01).
    var badge = 0
    @ObservedObject private var store = WyrmTrailsStore.shared
    private var trails: [WyrmTrail] { WyrmTrailsFeature.enabled ? store.trails : [] }

    var body: some View {
        Button { open(.trails) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trails").font(.wyrmDisplay(24)).foregroundColor(ATheme.ink)
                        Text(badge > 0 ? "\(badge) new on your trails" : trails.isEmpty ? "Show off your skins, kills and best moments." : "New from the Wyrm community")
                            .font(.androidWyrm(12.5)).foregroundColor(badge > 0 ? ATheme.badge : ATheme.mute)
                    }
                    Spacer()
                    WyrmCountBadge(count: badge)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(ATheme.chevron)
                }
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ATheme.well)
                            if index < trails.count, let thumb = trails[index].thumbUrl {
                                WyrmTrailImage(full: thumb, thumb: thumb, aspect: 1)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else if index < trails.count {
                                Text(trails[index].caption).font(.wyrmDisplay(11)).foregroundColor(ATheme.ink)
                                    .lineLimit(4).padding(6)
                            } else if index == 0 && trails.isEmpty {
                                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(ATheme.quiet)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(16)
            .background(ATheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .buttonStyle(WSPressStyle())
        .onAppear { store.token = { [weak account] in account?.sessionToken ?? "" } }
        // Switched off: the same card, empty, and no feed fetch.
        .task { if WyrmTrailsFeature.enabled && !store.loaded { await store.refresh() } }
    }
}

// MARK: - One trail, with its replies

struct WyrmTrailDetail: View {
    let trailID: String
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var store = WyrmTrailsStore.shared
    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        WyrmDetailChrome(title: "Trail", onBack: close) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if let trail = store.trail(trailID) {
                            WyrmTrailCard(trail: trail, expanded: true, onOpen: {}, onAuthor: { open(.profile(trail.author.playerId)) })
                                .padding(.top, 12)
                        } else {
                            WyrmTrailPlaceholder().padding(.top, 12)
                        }
                        WyrmSectionLabel("Replies")
                        let replies = store.comments[trailID] ?? []
                        if replies.isEmpty {
                            Text("No replies yet. Be the first to say something.")
                                .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(replies) { reply in replyRow(reply) }
                            }
                        }
                        Spacer().frame(height: 24)
                    }
                }
                WyrmChatComposer(text: $draft, placeholder: "Reply to this trail", limit: 300, sending: sending, onSend: send)
            }
        }
        .onAppear { store.token = { [weak account] in account?.sessionToken ?? "" } }
        .task {
            if store.trail(trailID) == nil { await store.reload(trailID) }
            await store.loadComments(trailID)
        }
        .overlay(alignment: .top) { WyrmTrailToast(store: store) }
    }

    private func replyRow(_ reply: WyrmTrailComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { open(.profile(reply.author.playerId)) } label: {
                WyrmAvatar(initials: reply.author.initials, size: 30, url: reply.author.avatarURL)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(reply.author.name).font(.androidWyrm(13, .semibold)).foregroundColor(ATheme.ink)
                    if reply.author.playerId == store.trail(trailID)?.author.playerId {
                        Text("AUTHOR").font(.androidWyrm(8.5, .bold)).tracking(0.8).foregroundColor(ATheme.live)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(ATheme.live.opacity(0.14)))
                    }
                    Text(WyrmTrailTime.short(reply.createdAt)).font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet)
                }
                Text(reply.body).font(.androidWyrm(13.5)).foregroundColor(ATheme.ink).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            if reply.mine || store.trail(trailID)?.mine == true {
                Button(role: .destructive) { Task { await store.deleteReply(trailID, commentId: reply.id) } } label: {
                    Label("Delete reply", systemImage: "trash")
                }
            }
        }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        Task {
            if await store.reply(trailID, body: body) { draft = "" }
            sending = false
        }
    }
}

// MARK: - Trails, switched off

/// Trails while it is switched off (OM, 2026-10-02; `WyrmTrailsFeature.enabled
/// = false`). The Social card still looks the same and opens this page, which
/// says plainly that Trails is being finished and what it will bring. Android
/// twin: `TrailsComingSoonScreen` (TrailsComingSoon.kt), same copy.
struct WyrmTrailsComingSoon: View {
    /// Nil on the Trails tab (OM, 2026-10-04): no Back there.
    var close: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    if let close = close {
                        Button(action: close) {
                            HStack(spacing: 5) { Image(systemName: "chevron.left"); Text("Back") }
                                .font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.link)
                        }
                    }
                    Spacer()
                }
                Text("Trails").font(.androidWyrm(16, .semibold))
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(ATheme.paper)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 6)
                    WyrmTrailsComingHero()
                    Spacer().frame(height: 22)
                    WyrmCapsLabel("In development")
                    Spacer().frame(height: 6)
                    Text("Trails is still growing.").font(.wyrmDisplay(34)).foregroundColor(ATheme.ink)
                    Spacer().frame(height: 10)
                    Text("Trails is where your best runs will live: the moment, the skin and the numbers, shared with everyone who plays Wyrm. We've switched it off for a little while so we can finish it properly instead of handing you something half-baked.")
                        .font(.androidWyrm(15)).lineSpacing(4).foregroundColor(ATheme.mute)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: 24)
                    WyrmCapsLabel("Where it is")
                    Spacer().frame(height: 10)
                    WyrmTrailsStages()

                    Spacer().frame(height: 26)
                    WyrmCapsLabel("What's coming")
                    Spacer().frame(height: 10)
                    VStack(spacing: 0) {
                        row("square.and.arrow.up", "Share a run from the lobby",
                            "Your score, kills and time, right on top of the moment you went down.")
                        rule
                        row("tshirt", "Show off your skin",
                            "Anyone who likes it can try it on with one tap before they wear it.")
                        rule
                        row("sparkles", "Beads and replies",
                            "Drop a bead on a run you loved, and talk about it underneath.")
                        rule
                        row("square.grid.3x3", "Your trails on your profile",
                            "Every run you share, in one grid, so your profile tells your story.")
                    }
                    .background(ATheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ATheme.rule, lineWidth: 1))

                    Spacer().frame(height: 16)
                    HStack(spacing: 14) {
                        Image(systemName: "bell").font(.system(size: 18, weight: .semibold)).foregroundColor(ATheme.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("We'll tell you the moment it's ready.").font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.ink)
                            Text("Until then, go make a run worth sharing.").font(.androidWyrm(13)).foregroundColor(ATheme.mute)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(ATheme.well)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Spacer().frame(height: 110)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(ATheme.paper.ignoresSafeArea())
        .foregroundColor(ATheme.ink)
    }

    private var rule: some View {
        Rectangle().fill(ATheme.rowRule).frame(height: 1).padding(.leading, 66)
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(ATheme.ink)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ATheme.well))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.androidWyrm(15, .semibold)).foregroundColor(ATheme.ink)
                Text(detail).font(.androidWyrm(13)).foregroundColor(ATheme.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

/// A snake of beads gliding along a dotted trail, forever.
private struct WyrmTrailsComingHero: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let w = Double(size.width), h = Double(size.height)
                func at(_ p: Double) -> CGPoint {
                    let x: Double = -0.1 * w + p * 1.2 * w
                    let wave: Double = sin(p * 2.0 * Double.pi * 1.35)
                    let y: Double = h * 0.52 + wave * h * 0.22
                    return CGPoint(x: x, y: y)
                }
                var trail = Path()
                for i in 0...80 {
                    let p = at(Double(i) / 80)
                    if i == 0 { trail.move(to: p) } else { trail.addLine(to: p) }
                }
                context.stroke(trail, with: .color(ATheme.quiet.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 9]))
                for k in 0..<5 {
                    let a: Double = (Double(k) * 72.0 + 18.0) * Double.pi / 180.0
                    let fx: Double = w * (0.15 + 0.18 * Double(k))
                    let fy: Double = h * (0.2 + 0.12 * cos(a))
                    let f = CGPoint(x: fx, y: fy)
                    context.fill(Path(ellipseIn: CGRect(x: f.x - 3, y: f.y - 3, width: 6, height: 6)),
                                 with: .color(ATheme.quiet.opacity(0.22)))
                }
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5.2) / 5.2
                let bead: Double = h * 0.07
                for i in stride(from: 11, through: 0, by: -1) {
                    let p = t - Double(i) * 0.022
                    if p < -0.05 { continue }
                    let c = at(p)
                    let r: Double = bead * (1.0 - Double(i) * 0.025)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(ATheme.ink.opacity(1 - Double(i) / 14)))
                }
                let c = at(t), ahead = at(t + 0.01)
                let dx = Double(ahead.x - c.x), dy = Double(ahead.y - c.y)
                let len: Double = max(0.001, (dx * dx + dy * dy).squareRoot())
                let nx: Double = dx / len, ny: Double = dy / len
                for side in [-1.0, 1.0] {
                    let ex: Double = Double(c.x) + nx * bead * 0.35 - ny * side * bead * 0.42
                    let ey: Double = Double(c.y) + ny * bead * 0.35 + nx * side * bead * 0.42
                    let e = CGPoint(x: ex, y: ey)
                    let r: Double = bead * 0.26
                    context.fill(Path(ellipseIn: CGRect(x: e.x - r, y: e.y - r, width: r * 2, height: r * 2)),
                                 with: .color(ATheme.well))
                }
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .background(ATheme.well)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Sketched ✓ · Built ✓ · Polishing (now) · In your hands.
private struct WyrmTrailsStages: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            chip("Sketched", 2)
            chip("Built", 2)
            chip("Polishing", 1)
            chip("In your hands", 0).layoutPriority(1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func chip(_ name: String, _ state: Int) -> some View {
        HStack(spacing: 5) {
            if state == 2 {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(ATheme.onInk)
            } else if state == 1 {
                Circle().fill(ATheme.ink.opacity(pulse ? 1 : 0.35)).frame(width: 7, height: 7)
            }
            Text(name).font(.androidWyrm(11, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundColor(state == 2 ? ATheme.onInk : state == 1 ? ATheme.ink : ATheme.quiet)
        }
        .padding(.vertical, 9).padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(state == 2 ? ATheme.ink : ATheme.card))
        .overlay(Capsule().stroke(state == 1 ? ATheme.ink : ATheme.rule, lineWidth: 1))
    }
}
