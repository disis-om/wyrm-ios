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
    @ObservedObject var account: WyrmAccountStore
    @ObservedObject var services: WyrmServiceStore
    let close: () -> Void
    let open: (WyrmDesignRoute) -> Void
    @State var draft = ""
    @State var sending = false
    @State var reporting: WyrmChatItem?

    var body: some View {
        WyrmDetailChrome(title: "Global chat", onBack: close) {
            VStack(spacing: 0) {
                WyrmChatTranscript(messages: services.globalChat, myID: account.player?.id,
                                   emptyTitle: "Quiet right now", emptyNote: "Messages stay here for 24 hours. Say hello.",
                                   onAuthor: { open(.profile($0)) }, onReport: { reporting = $0 })
                if !services.errorMessage.isEmpty {
                    Text(friendly(services.errorMessage)).font(.androidWyrm(11.5)).foregroundColor(ATheme.badge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .transition(.opacity)
                }
                WyrmChatComposer(text: $draft, placeholder: "Message everyone", limit: 280, sending: sending, onSend: send)
            }
        }
        .task {
            while !Task.isCancelled {
                await services.refreshGlobalChat()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .confirmationDialog("Report message", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                            presenting: reporting) { message in
            ForEach(["Spam", "Harassment or abuse", "Hate or slurs", "Something else"], id: \.self) { reason in
                Button(reason) { Task { await services.report(message, reason: reason) } }
            }
        }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        draft = ""
        Task {
            // Cleared at once so the send feels immediate; put back if refused.
            if !(await services.sendGlobal(String(body.prefix(280)))) && draft.isEmpty { draft = body }
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
