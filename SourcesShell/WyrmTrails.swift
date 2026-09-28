import SwiftUI
import UIKit

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
 * Speed: the feed pages 20 at a time; each photo shows its thumbnail at once
 * and swaps to the full image when it lands; decoded images are kept in memory
 * and the files on disk, and a like changes on screen before the server answers.
 * Backend: `Wyrm Android/backend/src/trails.mjs`.
 */

// MARK: - Model

struct WyrmTrailAuthor: Decodable, Equatable {
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

struct WyrmTrailPhoto: Decodable, Equatable {
    let url: String
    let width: Int
    let height: Int
}

struct WyrmTrail: Decodable, Identifiable, Equatable {
    let id: String
    let caption: String
    let photo: WyrmTrailPhoto
    let thumbUrl: String
    var likeCount: Int
    var commentCount: Int
    var liked: Bool
    let mine: Bool
    let createdAt: String
    let author: WyrmTrailAuthor

    /// Width over height, held between a tall 4:5 and a wide 1.91:1 so no
    /// photo takes over the feed or shrinks to a strip.
    var aspect: CGFloat {
        guard photo.width > 0, photo.height > 0 else { return 1 }
        return min(max(CGFloat(photo.width) / CGFloat(photo.height), 0.8), 1.91)
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
                                    jpeg: Data? = nil, query: [URLQueryItem] = [], token: String,
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
            } else {
                if let json {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: json)
                }
                (data, response) = try await session.data(for: request)
            }
        } catch {
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
        case "NOT_FOUND": return "This trail is no longer here."
        case "BLOCKED": return "You can't reply to this trail."
        case "HTTP_429": return "Slow down a little and try again soon."
        default: return "Something went wrong. Try again."
        }
    }

    fileprivate func feed(cursor: String?, author: String?, token: String) async throws -> WyrmTrailPage {
        var query = [URLQueryItem(name: "limit", value: "20")]
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

    fileprivate func create(caption: String, photoId: String, thumbId: String, token: String) async throws -> WyrmTrail {
        let envelope: WyrmTrailEnvelope = try await send("/v1/trails", method: "POST",
            json: ["caption": caption, "photoId": photoId, "thumbId": thumbId], token: token)
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
        ZStack {
            Rectangle().fill(ATheme.well)
            if let shown = image ?? preview {
                Image(uiImage: shown).resizable().scaledToFill()
                    .transition(.opacity)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
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
    @Published private(set) var comments: [String: [WyrmTrailComment]] = [:]
    @Published var toast = ""

    var token: () -> String = { "" }
    private var cursor: String?
    private var liking: Set<String> = []

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await WyrmTrailsClient.shared.feed(cursor: nil, author: nil, token: token())
            trails = page.trails
            cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
            error = ""
            prefetch(page.trails)
        } catch { self.error = message(error) }
        loaded = true
    }

    func loadMoreIfNeeded(after trail: WyrmTrail) async {
        guard trail.id == trails.last?.id, !reachedEnd, !loadingMore, !loading, let cursor else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await WyrmTrailsClient.shared.feed(cursor: cursor, author: nil, token: token())
            let known = Set(trails.map(\.id))
            trails += page.trails.filter { !known.contains($0.id) }
            self.cursor = page.nextCursor
            reachedEnd = page.nextCursor == nil
            prefetch(page.trails)
        } catch { self.error = message(error) }
    }

    func trail(_ id: String) -> WyrmTrail? { trails.first { $0.id == id } }

    func reload(_ id: String) async {
        guard let fresh = try? await WyrmTrailsClient.shared.trail(id, token: token()) else { return }
        if let index = trails.firstIndex(where: { $0.id == id }) { trails[index] = fresh } else { trails.insert(fresh, at: 0) }
    }

    /// On screen at once; the server's count wins when it answers.
    func toggleLike(_ id: String) {
        guard let index = trails.firstIndex(where: { $0.id == id }), !liking.contains(id) else { return }
        let next = !trails[index].liked
        trails[index].liked = next
        trails[index].likeCount = max(0, trails[index].likeCount + (next ? 1 : -1))
        liking.insert(id)
        Task {
            defer { liking.remove(id) }
            do {
                let result = try await WyrmTrailsClient.shared.like(id, next, token: token())
                if let i = trails.firstIndex(where: { $0.id == id }) {
                    trails[i].liked = result.liked
                    trails[i].likeCount = result.likeCount
                }
            } catch {
                if let i = trails.firstIndex(where: { $0.id == id }) {
                    trails[i].liked = !next
                    trails[i].likeCount = max(0, trails[i].likeCount + (next ? -1 : 1))
                }
            }
        }
    }

    func post(image: UIImage, caption: String) async -> Bool {
        guard !posting.busy else { return false }
        pendingImage = image
        pendingCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        posting = .preparing
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
            let trail = try await WyrmTrailsClient.shared.create(
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                photoId: photoId, thumbId: thumbId, token: token())
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                trails.insert(trail, at: 0)
                pendingImage = nil
                posting = .posted
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toast = "Trail posted"
            return true
        } catch {
            posting = .failed(message(error))
            return false
        }
    }

    func resetPosting() { if !posting.busy && pendingImage == nil { posting = .idle } }

    func retryPending() {
        guard let image = pendingImage, !posting.busy else { return }
        let caption = pendingCaption
        Task { _ = await post(image: image, caption: caption) }
    }

    func discardPending() {
        guard !posting.busy else { return }
        withAnimation(.easeOut(duration: 0.2)) { pendingImage = nil; posting = .idle }
    }

    func delete(_ id: String) async {
        do {
            try await WyrmTrailsClient.shared.delete(id, token: token())
            trails.removeAll { $0.id == id }
            toast = "Trail deleted"
        } catch { toast = message(error) }
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
            if let i = trails.firstIndex(where: { $0.id == id }) { trails[i].commentCount = posted.commentCount }
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
            if let i = trails.firstIndex(where: { $0.id == id }) { trails[i].commentCount = max(0, trails[i].commentCount - 1) }
        } catch { toast = message(error) }
    }

    private func prefetch(_ page: [WyrmTrail]) {
        WyrmTrailImages.shared.prefetch(page.compactMap { URL(string: WyrmTrailsClient.absolute($0.thumbUrl)) })
        WyrmTrailImages.shared.prefetch(page.prefix(4).compactMap { URL(string: WyrmTrailsClient.absolute($0.photo.url)) })
    }

    private func message(_ error: Error) -> String {
        if case WyrmServiceError.message(let text) = error { return text }
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
    @State private var burst = false
    @State private var confirmDelete = false
    @State private var reporting = false

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
                WyrmTrailImage(full: trail.photo.url, thumb: trail.thumbUrl, aspect: trail.aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            if !trail.caption.isEmpty {
                Text(trail.caption)
                    .font(.androidWyrm(14.5)).foregroundColor(ATheme.ink).lineSpacing(3)
                    .lineLimit(expanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.top, 12)
            }

            HStack(spacing: 8) {
                WyrmTrailBead(liked: trail.liked, count: trail.likeCount) { store.toggleLike(trail.id) }
                WyrmTrailRepliesPill(count: trail.commentCount, action: onOpen)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        }
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 14)
        .confirmationDialog("Delete this trail?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await store.delete(trail.id) } }
        }
        .confirmationDialog("Report trail", isPresented: $reporting) {
            ForEach(["Spam", "Harassment or abuse", "Nudity or sexual content", "Hate or violence", "Something else"], id: \.self) { reason in
                Button(reason) { Task { await store.report(trail.id, reason: reason) } }
            }
        }
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
    let image: UIImage
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(0.8)
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
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ATheme.well)
                        Capsule().fill(ATheme.live)
                            .frame(width: proxy.size.width * CGFloat(progress ?? 0.1))
                            .animation(.easeOut(duration: 0.25), value: progress)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(14)
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 14)
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

// MARK: - Feed

struct WyrmTrailsFeed: View {
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @ObservedObject private var store = WyrmTrailsStore.shared

    var body: some View {
        WyrmDetailChrome(title: "Trails", actionTitle: "New", onBack: close, action: { open(.trailCompose) }) {
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        header
                        if !store.loaded && store.trails.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in WyrmTrailPlaceholder() }
                        } else if store.trails.isEmpty && store.pendingImage == nil {
                            empty
                        } else {
                            if let image = store.pendingImage {
                                WyrmTrailPendingCard(image: image, caption: store.pendingCaption, phase: store.posting,
                                                     retry: store.retryPending, discard: store.discardPending)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            ForEach(store.trails) { trail in
                                WyrmTrailCard(trail: trail, onOpen: { open(.trail(trail.id)) },
                                              onAuthor: { open(.profile(trail.author.playerId)) })
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
                .refreshable { await store.refresh() }

                composeButton
            }
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
            WyrmPrimaryAction(title: "Leave a trail", icon: "plus") { open(.trailCompose) }.padding(.top, 8)
        }
        .padding(22)
        .background(ATheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 14)
    }

    private var composeButton: some View {
        Button { open(.trailCompose) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                Text("Leave a trail").font(.androidWyrm(15, .bold))
            }
            .foregroundColor(ATheme.onInk)
            .padding(.horizontal, 22).frame(height: 50)
            .background(Capsule().fill(ATheme.ink))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
        .buttonStyle(WSPressStyle())
        .padding(.bottom, 28)
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
    @ObservedObject private var store = WyrmTrailsStore.shared

    var body: some View {
        Button { open(.trails) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trails").font(.wyrmDisplay(24)).foregroundColor(ATheme.ink)
                        Text(store.trails.isEmpty ? "Show off your skins, kills and best moments." : "New from the Wyrm community")
                            .font(.androidWyrm(12.5)).foregroundColor(ATheme.mute)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(ATheme.chevron)
                }
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ATheme.well)
                            if index < store.trails.count {
                                WyrmTrailImage(full: store.trails[index].thumbUrl, thumb: store.trails[index].thumbUrl, aspect: 1)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else if index == 0 && store.trails.isEmpty {
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
        .task { if !store.loaded { await store.refresh() } }
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

// MARK: - New trail

struct WyrmTrailCompose: View {
    @ObservedObject var account: WyrmAccountStore
    let close: () -> Void
    @ObservedObject private var store = WyrmTrailsStore.shared
    @State private var image: UIImage?
    @State private var caption = ""
    @State private var picking = false
    private let limit = 500

    var body: some View {
        WyrmDetailChrome(title: "New trail", onBack: { if !store.posting.busy { close() } }) {
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        photoArea.padding(.horizontal, 14).padding(.top, 14)
                        WyrmSectionLabel("Caption")
                        ZStack(alignment: .topLeading) {
                            if caption.isEmpty {
                                Text("Say something about it…").font(.androidWyrm(15)).foregroundColor(ATheme.quiet)
                                    .padding(.horizontal, 5).padding(.vertical, 8)
                            }
                            TextEditor(text: $caption)
                                .font(.androidWyrm(15)).foregroundColor(ATheme.ink)
                                .frame(minHeight: 110)
                                .onAppear { UITextView.appearance().backgroundColor = .clear }
                                .onChange(of: caption) { value in if value.count > limit { caption = String(value.prefix(limit)) } }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ATheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                        .padding(.horizontal, 14)
                        Text("\(caption.count)/\(limit)").font(.androidWyrm(11)).monospacedDigit().foregroundColor(ATheme.quiet)
                            .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 20).padding(.top, 6)
                        Spacer().frame(height: 150)
                    }
                }
                footer
            }
        }
        .onAppear {
            store.token = { [weak account] in account?.sessionToken ?? "" }
            store.resetPosting()
            if image == nil { picking = true }
        }
        .sheet(isPresented: $picking) {
            WyrmPhotoPicker { picked in
                picking = false
                if let picked { withAnimation(.easeOut(duration: 0.2)) { image = picked } }
            }
            .ignoresSafeArea()
        }

    }

    @ViewBuilder
    private var photoArea: some View {
        if let image {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image).resizable().scaledToFill()
                    .aspectRatio(min(max(image.size.width / max(image.size.height, 1), 0.8), 1.91), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !store.posting.busy {
                    Button { picking = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 12, weight: .bold))
                            Text("Change").font(.androidWyrm(12.5, .bold))
                        }
                        .foregroundColor(ATheme.ink)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(ATheme.card.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
        } else {
            Button { picking = true } label: {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30, weight: .semibold)).foregroundColor(ATheme.live)
                    Text("Choose a photo").font(.androidWyrm(16, .bold)).foregroundColor(ATheme.ink)
                    Text("A skin, a big run, a moment from the arena.").font(.androidWyrm(12.5)).foregroundColor(ATheme.mute)
                }
                .frame(maxWidth: .infinity).frame(height: 260)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ATheme.rule, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if store.posting.busy {
                Text("Your last trail is still uploading.").font(.androidWyrm(12.5)).foregroundColor(ATheme.mute)
            }
            WyrmPrimaryAction(title: "Post trail", icon: "arrow.up", disabled: image == nil || store.posting.busy) { post() }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        .background(ATheme.paper.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    /// Starts the post and returns to the feed at once: the trail waits at the
    /// top of the feed, showing Preparing and Uploading, until it lands.
    private func post() {
        guard let image, !store.posting.busy else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let text = caption
        Task { _ = await store.post(image: image, caption: text) }
        close()
    }
}
