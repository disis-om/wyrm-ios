import Foundation
import SwiftUI
import UIKit

/// A deliberately small, privacy-aware diagnostics ledger. It is always
/// available so a failure that happens before Developer Mode is enabled is not
/// lost, but it never records bearer tokens, passwords, or message bodies.
final class WyrmDiagnostics: ObservableObject {
    static let shared = WyrmDiagnostics()
    static let retentionDays = 7
    static let maximumBytesPerStream = 1_048_576

    @Published private(set) var text = "Loading Wyrm diagnostics…"
    @Published private(set) var byteCount = 0
    @Published private(set) var updatedAt = Date()

    private let queue = DispatchQueue(label: "com.omrajput.wyrm.diagnostics", qos: .utility)
    private let directoryURL: URL
    private let appURL: URL
    private let engineURL: URL

    private init() {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)) ?? FileManager.default.temporaryDirectory
        directoryURL = support.appendingPathComponent("WyrmDiagnostics", isDirectory: true)
        appURL = directoryURL.appendingPathComponent("app.log")
        engineURL = directoryURL.appendingPathComponent("engine.log")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        Self.appendLine("diagnostics store opened", category: "APP", to: appURL)
        refresh()
    }

    static func record(_ message: String, category: String = "APP") {
        let clean = message.replacingOccurrences(of: "\n", with: " ")
        let store = shared
        store.queue.async {
            appendLine(clean, category: category, to: store.appURL)
            trim(store.appURL)
        }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self = self else { return }
            Self.trim(self.appURL)
            Self.trim(self.engineURL)
            let app = (try? String(contentsOf: self.appURL, encoding: .utf8)) ?? ""
            let engine = (try? String(contentsOf: self.engineURL, encoding: .utf8)) ?? ""
            let combined = Self.document(app: app, engine: engine)
            DispatchQueue.main.async {
                self.text = combined
                self.byteCount = combined.lengthOfBytes(using: .utf8)
                self.updatedAt = Date()
            }
        }
    }

    func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.appURL)
            try? FileManager.default.removeItem(at: self.engineURL)
            Self.appendLine("diagnostics cleared by user", category: "APP", to: self.appURL)
            self.refresh()
        }
    }

    /// Builds a fresh, self-contained text file for UIActivityViewController.
    /// The Keychain session and private chat bodies are intentionally absent.
    func exportFile() -> URL? {
        Self.trim(appURL)
        Self.trim(engineURL)
        let app = (try? String(contentsOf: appURL, encoding: .utf8)) ?? ""
        let engine = (try? String(contentsOf: engineURL, encoding: .utf8)) ?? ""
        let export = Self.document(app: app, engine: engine)
        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wyrm-diagnostics-\(stamp).txt")
        do {
            try export.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Self.record("diagnostics export failed: \(error.localizedDescription)", category: "ERROR")
            return nil
        }
    }

    private static func document(app: String, engine: String) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return """
        WYRM IOS DIAGNOSTICS
        version: \(version) (\(build))
        generated: \(ISO8601DateFormatter().string(from: Date()))
        retention: \(retentionDays) days, 1 MiB per stream
        device: \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)
        privacy: authentication secrets, passwords and message bodies are not logged

        --- APP / NETWORK ---
        \(app.isEmpty ? "No app events recorded." : app)

        --- ORIGINAL C ENGINE / SDL3 ---
        \(engine.isEmpty ? "No engine events recorded yet." : engine)
        """
    }

    private static func appendLine(_ message: String, category: String, to url: URL) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))][\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { }
    }

    private static func trim(_ url: URL) {
        guard var data = try? Data(contentsOf: url), !data.isEmpty else { return }
        if data.count > maximumBytesPerStream {
            data = data.suffix(maximumBytesPerStream)
            if let newline = data.firstIndex(of: 0x0A), newline < data.endIndex {
                data = data.suffix(from: data.index(after: newline))
            }
        }
        guard let raw = String(data: data, encoding: .utf8) else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        let formatter = ISO8601DateFormatter()
        let kept = raw.split(separator: "\n", omittingEmptySubsequences: true).filter { line in
            guard line.first == "[", let end = line.firstIndex(of: "]") else { return true }
            let stamp = String(line[line.index(after: line.startIndex)..<end])
            return formatter.date(from: stamp).map { $0 >= cutoff } ?? true
        }.joined(separator: "\n")
        let output = kept.isEmpty ? Data() : Data((kept + "\n").utf8)
        try? output.write(to: url, options: .atomic)
    }
}

struct WyrmShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = controller.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: 1, y: 1, width: 1, height: 1)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
