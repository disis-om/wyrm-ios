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
                ScrollViewReader { reader in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if services.globalChat.isEmpty {
                                WyrmPaperCard { WyrmEmptyPanel(title: "Quiet right now", note: "Messages stay here for 24 hours. Say hello.") }
                                    .padding(.top, 16)
                            }
                            ForEach(services.globalChat) { message in row(message).id(message.id) }
                        }
                        .padding(.vertical, 14)
                    }
                    .onChange(of: services.globalChat.last?.id) { last in
                        guard let last else { return }
                        withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo(last, anchor: .bottom) }
                    }
                }
                HStack(spacing: 10) {
                    TextField("Message everyone", text: $draft)
                        .font(.androidWyrm(14)).padding(.horizontal, 14).frame(height: 44)
                        .background(ATheme.card).cornerRadius(22)
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(ATheme.rule))
                        .submitLabel(.send).onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundColor(ATheme.onInk)
                            .frame(width: 44, height: 44).background(Circle().fill(canSend ? ATheme.ink : ATheme.ink.opacity(0.3)))
                    }.buttonStyle(.plain).disabled(!canSend)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(ATheme.paper)
                if !services.errorMessage.isEmpty {
                    Text(friendly(services.errorMessage)).font(.androidWyrm(11.5)).foregroundColor(ATheme.badge)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                }
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

    private var canSend: Bool { !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func row(_ message: WyrmChatItem) -> some View {
        let mine = message.authorID == account.player?.id
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            if !mine {
                Button { open(.profile(message.authorID)) } label: {
                    Text(message.authorUsername.isEmpty ? message.authorName : "\(message.authorName) · @\(message.authorUsername)")
                        .font(.androidWyrm(10.5, .semibold)).foregroundColor(ATheme.quiet)
                }.buttonStyle(.plain)
            }
            Text(message.body).font(.androidWyrm(13.5))
                .foregroundColor(mine ? ATheme.onInk : ATheme.ink)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(mine ? ATheme.ink : ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(mine ? Color.clear : ATheme.rule))
                .contextMenu { if !mine { Button("Report", role: .destructive) { reporting = message } } }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.horizontal, 16)
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        Task {
            if await services.sendGlobal(String(body.prefix(280))) { draft = "" }
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
