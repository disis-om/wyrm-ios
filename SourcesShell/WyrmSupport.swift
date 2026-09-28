import Foundation
import MetricKit
import SwiftUI
import UIKit

/*
 * Help & feedback, and the crash watch (OM, 2026-09-29).
 *
 * How the best apps do it, in Wyrm's own paper look:
 * - A crash is written to the phone the moment it happens and nothing leaves
 *   the phone on its own. On the next launch Wyrm says it closed unexpectedly
 *   and asks; "Always send" skips the question from then on.
 * - Settings › Help & feedback holds Report a problem, Suggest an idea, Ask for
 *   help, Crash reports, Your reports (with Wyrm's replies) and common
 *   questions.
 * - Every report carries what a developer needs (app and iOS version, device,
 *   the screen, recent Wyrm log lines, the stack) and never a password, a
 *   token, an auth key or a message body: those are redacted before sending.
 *
 * The backend is `backend/src/support.mjs`; OM reads and answers on the
 * Observatory's Support page. A reply comes back as a "support" alert.
 * Android: `SupportCenter.kt`.
 */

// MARK: - Redaction

enum WyrmRedact {
    private static let rules: [(String, String)] = [
        (#"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, "[token]"),
        (#"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [token]"),
        (#"(?i)\b(password|passwd|pwd|secret|auth[_-]?key|api[_-]?key|access[_-]?token|token|team[_-]?id|key)(["'\s]*[:=]\s*["']?)[^\s"',&;]+"#, "$1$2[hidden]"),
        (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, "[private key]"),
        (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "[email]"),
    ]

    /// For logs and stacks. A player's own message is sent as they wrote it.
    static func clean(_ text: String) -> String {
        rules.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1, options: .regularExpression) }
    }
}

// MARK: - What a report says about the phone

enum WyrmSupportContext {
    /// The model identifier, e.g. "iPhone15,2".
    static var model: String {
        var system = utsname()
        uname(&system)
        let machine = system.machine
        return withUnsafeBytes(of: machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    /// Short strings only: the server takes at most 40 keys of 300 characters.
    @MainActor
    static func current(screen: String) -> [String: String] {
        [
            "platform": "ios",
            "appVersion": appVersion,
            "build": build,
            "osVersion": "iOS \(UIDevice.current.systemVersion)",
            "device": model,
            "screen": String(screen.prefix(80)),
            "locale": Locale.current.identifier,
            "theme": WyrmThemeStore.shared.theme.displayName,
        ]
    }
}

// MARK: - Network

struct WyrmSupportReport: Codable, Identifiable, Equatable {
    let id: String
    let kind: String
    let status: String
    let message: String
    let reply: String
    let createdAt: String
    let updatedAt: String

    var kindTitle: String { WyrmSupportKind(rawValue: kind)?.title ?? "Report" }
}

enum WyrmSupportKind: String, CaseIterable, Identifiable {
    case bug, suggestion, help, other, crash
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bug: return "Problem"
        case .suggestion: return "Idea"
        case .help: return "Help"
        case .other: return "Other"
        case .crash: return "Crash"
        }
    }
    var pageTitle: String {
        switch self {
        case .bug: return "Report a problem"
        case .suggestion: return "Suggest an idea"
        case .help: return "Ask for help"
        case .other: return "Something else"
        case .crash: return "Crash report"
        }
    }
    var question: String {
        switch self {
        case .bug: return "What went wrong?"
        case .suggestion: return "What would make Wyrm better?"
        case .help: return "What do you need help with?"
        case .other: return "What's on your mind?"
        case .crash: return "What were you doing?"
        }
    }
    var placeholder: String {
        switch self {
        case .bug: return "What you did, what you expected, and what happened instead."
        case .suggestion: return "A feature, a skin, a mode, a small thing that bugs you. Every idea is read."
        case .help: return "Ask anything about Wyrm: your account, skins, arenas, backups."
        case .other: return "Tell us anything."
        case .crash: return "Optional"
        }
    }
    var icon: String {
        switch self {
        case .bug: return "exclamationmark.bubble.fill"
        case .suggestion: return "lightbulb.fill"
        case .help: return "questionmark.circle.fill"
        case .other: return "ellipsis.bubble.fill"
        case .crash: return "bandage.fill"
        }
    }
    /// Problems and help questions are hard to answer without the device.
    var attachesByDefault: Bool { self == .bug || self == .help || self == .crash }
}

enum WyrmSupportClient {
    private static let base = "https://wyrm-api.77-245-76-86.sslip.io"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private struct Mine: Decodable { let reports: [WyrmSupportReport] }
    private struct Posted: Decodable { let id: String }
    private struct Failure: Decodable { let error: String? }

    static func submit(kind: String, message: String, contact: String = "", context: [String: String],
                       stack: String = "", logs: String = "", token: String) async throws -> String {
        var body: [String: Any] = ["kind": kind, "message": String(message.prefix(4000)), "context": context]
        if !contact.isEmpty { body["contact"] = String(contact.prefix(200)) }
        if !stack.isEmpty { body["stack"] = String(WyrmRedact.clean(stack).suffix(60_000)) }
        if !logs.isEmpty { body["logs"] = String(WyrmRedact.clean(logs).suffix(120_000)) }
        let data = try await send("/v1/support/reports", method: "POST", body: body, token: token)
        return try JSONDecoder().decode(Posted.self, from: data).id
    }

    static func mine(token: String) async throws -> [WyrmSupportReport] {
        let data = try await send("/v1/me/support", token: token)
        return try JSONDecoder().decode(Mine.self, from: data).reports
    }

    private static func send(_ path: String, method: String = "GET", body: [String: Any]? = nil, token: String) async throws -> Data {
        guard let url = URL(string: base + path) else { throw WyrmServiceError.message("Invalid Wyrm address.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Signed in or not: a crash on the sign-in screen still counts.
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            WyrmDiagnostics.record("\(method) \(path) transport failure", category: "NETWORK")
            throw WyrmServiceError.message("Could not reach Wyrm. Check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        WyrmDiagnostics.record("\(method) \(path) status=\(status)", category: "NETWORK")
        guard 200..<300 ~= status else {
            let code = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "HTTP_\(status)"
            switch code {
            case "HTTP_429": throw WyrmServiceError.message("You've sent a lot in a short time. Try again in a little while.")
            case "EMPTY_REPORT": throw WyrmServiceError.message("Write a few words first.")
            case "HTTP_413", "INVALID_REPORT": throw WyrmServiceError.message("That report is too long. Shorten it and try again.")
            default: throw WyrmServiceError.message("Something went wrong. Try again.")
            }
        }
        return data
    }

    static func message(_ error: Error) -> String {
        if case WyrmServiceError.message(let text) = error { return text }
        return "Something went wrong. Try again."
    }
}

// MARK: - Crash watch

/// One crash the phone kept, waiting for the player's answer.
struct WyrmCrashRecord: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var at = Date()
    /// "exception", "signal", "metrickit" or "closed" (the app ended in the
    /// foreground without saying goodbye: memory, a watchdog, a native fault).
    var cause: String
    var title: String
    var stack: String
    var appVersion: String
    var build: String
    var sent = false
}

private func wyrmUncaughtException(_ exception: NSException) {
    WyrmCrashWatch.recordException(exception)
    WyrmCrashWatch.previousExceptionHandler?(exception)
}

/// Plain class, used on the main thread: it is armed from the shell's first
/// UIKit call, before SwiftUI, so it cannot be main-actor isolated.
final class WyrmCrashWatch: NSObject, ObservableObject {
    static let shared = WyrmCrashWatch()

    /// The crash the launch prompt is asking about.
    @Published private(set) var prompt: WyrmCrashRecord?
    /// The newest crash, kept so it can still be sent from Settings.
    @Published private(set) var last: WyrmCrashRecord?
    @Published private(set) var toast = ""

    /// The signed-in session, or "" (the report is then anonymous).
    var token: () -> String = { "" }
    /// Where the player is, for the report.
    var screen = "Launch"

    static var previousExceptionHandler: (@convention(c) (NSException) -> Void)?
    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WyrmCrash", isDirectory: true)
    }()
    private static let exceptionFile = folder.appendingPathComponent("exception.txt")
    private static let signalFile = folder.appendingPathComponent("signal.txt")
    private static let lastFile = folder.appendingPathComponent("last.json")
    private static let runningKey = "wyrm.crash.running"
    private static let versionKey = "wyrm.crash.runningVersion"
    static let autoSendKey = "wyrm.crash.autoSend"

    private var started = false
    private var observers: [NSObjectProtocol] = []

    var autoSend: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoSendKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoSendKey); objectWillChange.send() }
    }

    /// Once, before the first screen: read what the last run left, then arm.
    func install() {
        guard !started else { return }
        started = true
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        last = (try? Data(contentsOf: Self.lastFile)).flatMap { try? JSONDecoder().decode(WyrmCrashRecord.self, from: $0) }
        collectLeftovers()

        Self.signalFile.path.withCString { wyrm_crash_signals_install($0) }
        Self.previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(wyrmUncaughtException)

        // A run that ends while Wyrm is on screen, with no crash written, still
        // counts: iOS ends apps for memory or a frozen main thread silently.
        Self.setRunning(UIApplication.shared.applicationState != .background)
        let center = NotificationCenter.default
        // Written on the spot, not in a Task: the app may be suspended or
        // ended right after these arrive.
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                WyrmCrashWatch.setRunning(true)
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                WyrmCrashWatch.setRunning(false)
            },
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                WyrmCrashWatch.setRunning(false)
            },
        ]
        if #available(iOS 14.0, *) { MXMetricManager.shared.add(self) }
    }

    private static func setRunning(_ running: Bool) {
        UserDefaults.standard.set(running, forKey: Self.runningKey)
        if running { UserDefaults.standard.set(WyrmSupportContext.build, forKey: Self.versionKey) }
    }

    /// Called from the uncaught-exception handler, on the crashing thread.
    static func recordException(_ exception: NSException) {
        let text = "\(exception.name.rawValue): \(exception.reason ?? "")\n"
            + exception.callStackSymbols.joined(separator: "\n")
        try? text.data(using: .utf8)?.write(to: exceptionFile, options: .atomic)
        wyrm_crash_mark_exception_written()
    }

    private func collectLeftovers() {
        let files = FileManager.default
        let exception = try? String(contentsOf: Self.exceptionFile, encoding: .utf8)
        let signal = try? String(contentsOf: Self.signalFile, encoding: .utf8)
        let ranAway = UserDefaults.standard.bool(forKey: Self.runningKey)
        // The crashed run's build, not this one's: an update in between must
        // not blame the new build.
        let crashedBuild = UserDefaults.standard.string(forKey: Self.versionKey) ?? WyrmSupportContext.build
        try? files.removeItem(at: Self.exceptionFile)
        try? files.removeItem(at: Self.signalFile)
        UserDefaults.standard.set(false, forKey: Self.runningKey)

        var record: WyrmCrashRecord?
        if let exception, !exception.isEmpty {
            let first = exception.split(separator: "\n").first.map(String.init) ?? "Exception"
            record = WyrmCrashRecord(cause: "exception", title: String(first.prefix(160)), stack: exception,
                                     appVersion: WyrmSupportContext.appVersion, build: crashedBuild)
        } else if let signal, !signal.isEmpty {
            let first = signal.split(separator: "\n").first.map(String.init) ?? "signal"
            let name = first.replacingOccurrences(of: "signal ", with: "")
            record = WyrmCrashRecord(cause: "signal", title: "Stopped by \(name)", stack: signal,
                                     appVersion: WyrmSupportContext.appVersion, build: crashedBuild)
        } else if ranAway {
            record = WyrmCrashRecord(cause: "closed", title: "Wyrm closed while it was on screen", stack: "",
                                     appVersion: WyrmSupportContext.appVersion, build: crashedBuild)
        }
        guard let record else { return }
        WyrmDiagnostics.record("crash watch: last run ended by \(record.cause)", category: "CRASH")
        keep(record)
        prompt = record
    }

    private func keep(_ record: WyrmCrashRecord) {
        last = record
        if let data = try? JSONEncoder().encode(record) { try? data.write(to: Self.lastFile, options: .atomic) }
    }

    /// The launch prompt may show once the first screen is up; with "Always
    /// send" on it never shows and the report just goes.
    @MainActor
    func launchCheck() {
        guard let record = prompt else { return }
        if autoSend {
            prompt = nil
            Task { if await send(record, note: "") { toast = "Crash report sent. Thank you." } }
        }
    }

    @MainActor
    func dismissPrompt() { prompt = nil }

    @MainActor
    func clearToast() { toast = "" }

    /// Sends one record; true when the server has it.
    @MainActor
    func send(_ record: WyrmCrashRecord, note: String) async -> Bool {
        var context = WyrmSupportContext.current(screen: screen)
        context["crashCause"] = record.cause
        context["crashedBuild"] = record.build
        context["crashedAt"] = ISO8601DateFormatter().string(from: record.at)
        let logs = await Task.detached(priority: .utility) { WyrmDiagnostics.shared.recentLog() }.value
        let stack = record.stack.isEmpty ? record.title : record.stack
        do {
            _ = try await WyrmSupportClient.submit(kind: "crash", message: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   context: context, stack: stack, logs: logs, token: token())
            var sent = record
            sent.sent = true
            keep(sent)
            if prompt?.id == record.id { prompt = nil }
            return true
        } catch {
            WyrmDiagnostics.record("crash report not sent: \(WyrmSupportClient.message(error))", category: "CRASH")
            return false
        }
    }
}

@available(iOS 14.0, *)
extension WyrmCrashWatch: MXMetricManagerSubscriber {
    /// iOS's own crash diagnostics arrive on a later launch. One for a crash
    /// the watch already caught is added to that record; a new one (a crash
    /// the handlers could not see) becomes its own.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.flatMap { payload in (payload.crashDiagnostics ?? []).map { (payload, $0) } }
        guard let newest = crashes.last else { return }
        let payload = newest.0
        let crash = newest.1
        let json = String(decoding: crash.jsonRepresentation(), as: UTF8.self)
        let reason = [crash.exceptionType.map { "exception \($0)" }, crash.signal.map { "signal \($0)" }, crash.terminationReason]
            .compactMap { $0 }.joined(separator: " · ")
        let window = payload.timeStampBegin.addingTimeInterval(-60)...payload.timeStampEnd.addingTimeInterval(60)
        Task { @MainActor in
            if let current = self.prompt, window.contains(current.at) || current.cause == "closed" {
                var merged = current
                merged.stack = (current.stack.isEmpty ? "" : current.stack + "\n\n") + "--- iOS diagnostics ---\n" + String(json.prefix(40_000))
                if current.cause == "closed" { merged.cause = "metrickit"; merged.title = reason.isEmpty ? current.title : reason }
                self.keep(merged)
                self.prompt = merged
                return
            }
            if let last = self.last, last.sent, window.contains(last.at) { return }
            let record = WyrmCrashRecord(cause: "metrickit", title: reason.isEmpty ? "Wyrm crashed" : String(reason.prefix(160)),
                                         stack: "--- iOS diagnostics ---\n" + String(json.prefix(40_000)),
                                         appVersion: crash.metaData.applicationBuildVersion, build: crash.metaData.applicationBuildVersion)
            self.keep(record)
            self.prompt = record
            self.launchCheck()
        }
    }
}

// MARK: - Store for Help & feedback

@MainActor
final class WyrmSupportStore: ObservableObject {
    static let shared = WyrmSupportStore()
    @Published private(set) var reports: [WyrmSupportReport] = []
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published var error = ""
    var token: () -> String = { "" }
    private static let cacheKey = "support-mine"
    private static let seenKey = "wyrm.support.seenReplies"

    /// Replies the player has not opened yet.
    var unseenReplies: Int {
        let seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        return reports.filter { !$0.reply.isEmpty && !seen.contains(Self.replyStamp($0)) }.count
    }

    private static func replyStamp(_ report: WyrmSupportReport) -> String { "\(report.id)|\(report.updatedAt)" }

    func markRepliesSeen() {
        let stamps = reports.filter { !$0.reply.isEmpty }.map(Self.replyStamp)
        UserDefaults.standard.set(Array(stamps.suffix(200)), forKey: Self.seenKey)
        objectWillChange.send()
    }

    /// Sign-out: the next account starts with its own reports.
    func reset() {
        reports = []
        loaded = false
        error = ""
    }

    func refresh() async {
        if !loaded, reports.isEmpty, let cached = WyrmCache.load(Self.cacheKey, as: [WyrmSupportReport].self) {
            reports = cached
            loaded = true
        }
        guard !token().isEmpty, !loading else { loaded = true; return }
        loading = true
        defer { loading = false }
        do {
            let token = token()
            let fresh = try await Task { try await WyrmSupportClient.mine(token: token) }.value
            withAnimation(.easeOut(duration: 0.2)) { reports = fresh }
            WyrmCache.save(Self.cacheKey, fresh)
            error = ""
        } catch is CancellationError {
        } catch { if reports.isEmpty { self.error = WyrmSupportClient.message(error) } }
        loaded = true
    }

    /// A report written in Help & feedback.
    func send(kind: WyrmSupportKind, message: String, attach: Bool, screen: String) async -> String? {
        let context = attach ? WyrmSupportContext.current(screen: screen)
            : ["platform": "ios", "appVersion": WyrmSupportContext.appVersion, "build": WyrmSupportContext.build]
        var logs = ""
        if attach { logs = await Task.detached(priority: .utility) { WyrmDiagnostics.shared.recentLog() }.value }
        do {
            let token = token()
            _ = try await Task {
                try await WyrmSupportClient.submit(kind: kind.rawValue, message: message, context: context, logs: logs, token: token)
            }.value
            Task { await refresh() }
            return nil
        } catch {
            return WyrmSupportClient.message(error)
        }
    }
}
