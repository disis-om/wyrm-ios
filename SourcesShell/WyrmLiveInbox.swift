import Foundation

/// The live inbox (OM, 2026-10-01): `GET /v1/me/live` held open while Wyrm is
/// on screen. The server says only "something new for you" (`{type:"inbox",
/// kind, id}`); the shell refetches, so Notifications, the DM count and the
/// badges update without a refresh. Android twin: `data/LiveInbox.kt`.
@MainActor
final class WyrmLiveInbox {
    static let shared = WyrmLiveInbox()
    private static let url = URL(string: "wss://wyrm-api.77-245-76-86.sslip.io/v1/me/live")!

    /// Called with the kind ("" = catch up on everything after a reconnect).
    var onInbox: (String) -> Void = { _ in }
    private var task: URLSessionWebSocketTask?
    private var token = ""
    private var running = false
    private var failures = 0
    private var pending: Set<String> = []
    private var burst: Task<Void, Never>?

    func start(token: String) {
        guard !token.isEmpty else { return }
        if running && token == self.token { return }
        stop()
        self.token = token
        running = true
        failures = 0
        connect()
    }

    func stop() {
        running = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func connect() {
        guard running else { return }
        var request = URLRequest(url: Self.url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        task = socket
        socket.resume()
        receive(on: socket)
    }

    private func receive(on socket: URLSessionWebSocketTask) {
        socket.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === socket else { return }
                switch result {
                case .success(let message):
                    self.failures = 0
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: socket)
                case .failure:
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "live.ready":
            onInbox("")
        case "inbox":
            // A burst (a broadcast, several follows) becomes one refresh per kind.
            pending.insert(event["kind"] as? String ?? "")
            burst?.cancel()
            burst = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { return }
                let kinds = pending
                pending.removeAll()
                kinds.forEach { onInbox($0) }
            }
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard running else { return }
        task = nil
        failures += 1
        let wait = min(30.0, pow(2.0, Double(min(failures, 5))))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard self.running, self.task == nil else { return }
            self.connect()
        }
    }
}
