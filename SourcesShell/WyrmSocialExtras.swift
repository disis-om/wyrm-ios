import SwiftUI
import UIKit
import PhotosUI

/// The system photo picker (iOS 14+): no photo-library permission is asked for,
/// and only the one image the player chooses ever reaches the app.
struct WyrmPhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                DispatchQueue.main.async { self.onPick(nil) }
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async { self.onPick(object as? UIImage) }
            }
        }
    }

    /// A square-ish JPEG no larger than 1024 px on its long side, which keeps
    /// every photo well under the backend's 3 MB limit.
    static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1024 ? 1024 / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        var quality: CGFloat = 0.86
        var data = resized.jpegData(compressionQuality: quality)
        while let current = data, current.count > 2_800_000, quality > 0.3 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }
}

/// Global chat, as on Android: the whole of Wyrm, the last 24 hours, read by
/// polling while the screen is open. A message can be reported from its menu.
struct WyrmGlobalChatDetail: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State var draft = ""
    @State var sending = false
    @State var reporting: WyrmChatItem?
    @State var replying: WyrmChatItem?
    @State var editing: WyrmChatItem?
    /// "{n} active" (OM, 2026-11-07): who has Wyrm open now, every 10 s.
    @State var activeCount: Int?
    @State var activePeople: [WyrmChatPerson] = []

    var body: some View {
        // Discord's layout in Wyrm's paper (OM, 2026-10-30): WyrmDiscordChat.swift.
        WyrmDiscordChat(direct: false, messages: services.shownGlobalChat, meID: account.player?.id ?? "",
                        meUsername: account.player?.username ?? "",
                        typing: services.typingNames(direct: nil), canPin: services.canPinChat, pins: services.chatPins,
                        hasOlder: services.globalHasOlder, loadingOlder: services.olderLoading,
                        limit: 280, placeholder: "Message everyone",
                        emptyTitle: "Quiet right now", emptyNote: "Messages stay here for 7 days. Say hello.",
                        draft: $draft, sending: sending,
                        error: services.errorMessage.isEmpty ? "" : friendly(services.errorMessage),
                        replying: replying, editing: editing, handlers: handlers,
                        activeTitle: activeCount.map { "\($0) active" } ?? "",
                        activePeople: activePeople) { bar in header(bar) }
        .task {
            WyrmLinkPreviewCache.shared.loader = { await services.linkPreview($0) }
            while !Task.isCancelled {
                if let now = await services.onlineNow() { activeCount = now.count; activePeople = now.people }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        // New messages, reactions and typing come on the live socket; this
        // quiet read every 20 s only catches what a dropped socket missed.
        .task {
            await services.refreshPins()
            while !Task.isCancelled {
                await services.refreshGlobalChat()
                services.noteGlobalSeen()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
        .onChange(of: services.globalChat.last?.id) { _ in services.noteGlobalSeen() }
        // Typing lines fall away after their 6 s (one loop, not a timer per redraw).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                services.pruneTyping()
            }
        }
        .confirmationDialog("Report message", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                            presenting: reporting) { message in
            ForEach(["Spam", "Harassment or abuse", "Hate or slurs", "Something else"], id: \.self) { reason in
                Button(reason) { Task { await services.report(message, reason: reason) } }
            }
        }
    }

    private var handlers: WyrmChatHandlers {
        WyrmChatHandlers(
            onSend: send,
            onSendGif: { url in
                let answering = replying
                replying = nil
                Task { _ = await services.sendGlobal(url, replyTo: answering) }
            },
            onTyping: { WyrmLiveInbox.shared.sendTyping(to: nil) },
            onAuthor: { id in if !id.isEmpty { open(.profile(id)) } },
            onReply: { editing = nil; replying = $0 },
            onEdit: { replying = nil; editing = $0; draft = $0.body },
            onCancelCompose: { if editing != nil { draft = "" }; editing = nil; replying = nil },
            onDelete: { message in Task { await services.deleteChatMessage(message, direct: false) } },
            onReport: { reporting = $0 },
            onReact: { message, emoji in Task { await services.react(message, emoji: emoji, direct: false) } },
            onPin: { message, pinned in Task { await services.setPinned(message, pinned: pinned) } },
            onLoadOlder: { Task { await services.loadOlder(playerID: nil) } },
            search: { await services.searchChat($0, playerID: nil) },
            gifs: { await services.gifs(stickers: $0, query: $1) },
            who: { await services.whoReacted($0, direct: false) },
            mentionSearch: { await services.mentionSearch($0) })
    }

    /// "Global chat" in Wyrm's display face (no "#"), search, and the pink pins button.
    private func header(_ bar: WyrmChatBarActions) -> some View {
        HStack(spacing: 4) {
            Button(action: close) {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                    .foregroundColor(wyrmScopedColours.ink).frame(width: 36, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 0) {
                Text("Global chat").font(.wyrmDisplay(22)).foregroundColor(wyrmScopedColours.ink).lineLimit(1)
                if let activeCount {
                    // Real time (OM, 2026-11-07); a tap shows who.
                    Button(action: bar.active) {
                        HStack(spacing: 5) {
                            Circle().fill(wyrmScopedColours.live).frame(width: 7, height: 7)
                            Text("\(activeCount) active").font(.androidWyrm(11.5, .semibold)).foregroundColor(wyrmScopedColours.mute).lineLimit(1)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(activeCount) players active, show them")
                } else {
                    Text("Everyone on Wyrm · messages stay 7 days").font(.androidWyrm(11)).foregroundColor(wyrmScopedColours.quiet).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Button(action: bar.search) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold))
                    .foregroundColor(wyrmScopedColours.ink).frame(width: 40, height: 40)
            }.buttonStyle(.plain).accessibilityLabel("Search")
            Button(action: bar.pins) {
                Image(systemName: "pin.fill").font(.system(size: 14, weight: .bold)).foregroundColor(wyrmReadableInk(on: WyrmChatKit.pink))
                    .frame(width: 34, height: 34).background(Circle().fill(WyrmChatKit.pink))
            }.buttonStyle(WSPressStyle()).accessibilityLabel("Pinned messages")
        }
        .padding(.leading, 6).padding(.trailing, 12).frame(height: 60).background(wyrmScopedColours.paper)
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        draft = ""
        let answering = replying, edit = editing
        replying = nil; editing = nil
        Task {
            if let edit {
                if !(await services.editChatMessage(edit, body: String(body.prefix(280)), direct: false)) && draft.isEmpty { draft = body; editing = edit }
            } else if !(await services.sendGlobal(String(body.prefix(280)), replyTo: answering)) && draft.isEmpty {
                // Cleared at once so the send feels immediate; put back if refused.
                draft = body; replying = answering
            }
            sending = false
        }
    }

    private func friendly(_ code: String) -> String {
        switch code {
        case "PROFILE_INCOMPLETE": return "Choose a username or arena name before chatting."
        case "MESSAGE_RATE_LIMITED": return "Slow down a little — try again in a moment."
        case "INVALID_MESSAGE": return "That message could not be sent."
        default: return code
        }
    }
}
