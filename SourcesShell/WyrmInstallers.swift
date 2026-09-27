import SwiftUI
import UIKit

/*
 * The sideloaders a Wyrm update can be installed with.
 *
 * iOS cannot install an IPA from inside an app, so an update is handed to one
 * of these. Each card knows whether its app is on this iPhone (its URL scheme
 * is declared in LSApplicationQueriesSchemes) and what to do:
 *
 *   AltStore   altstore://install?url=<ipa>      (AltStore docs)
 *   SideStore  sidestore://install?url=<ipa>     (SideStore docs)
 *   KSign      ksign://install/<https ipa url>   (KSign source, FeatherApp.swift)
 *   ESign      no documented install link: the IPA link is copied and ESign
 *              opened, where it is pasted into ESign's downloader.
 *
 * A missing app opens a sheet with that app's own setup steps. Icons load from
 * each project's official source feed (ESign publishes none, so it gets a mark).
 */
struct WyrmInstaller: Identifiable, Equatable {
    let id: String
    let name: String
    let scheme: String
    let icon: URL?
    let tagline: String
    let steps: [String]
    let website: URL?

    var installed: Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// The link that asks this app to fetch and install [ipa].
    func installURL(for ipa: URL) -> URL? {
        let encoded = ipa.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        switch id {
        case "altstore": return URL(string: "altstore://install?url=\(encoded)")
        case "sidestore": return URL(string: "sidestore://install?url=\(encoded)")
        case "ksign": return URL(string: "ksign://install/\(ipa.absoluteString)")
        default: return nil
        }
    }

    /// The first sideloader on this iPhone, in the order the cards show them.
    static var preferred: WyrmInstaller? { all.first { $0.installed } }

    /// Hands [update] to this app and says what happened, for the page's note.
    func hand(_ update: WyrmUpdateInfo, open: (URL) -> Void) -> String {
        WyrmDiagnostics.record("update handed to \(id) build=\(update.build)", category: "NETWORK")
        if let link = installURL(for: update.url) {
            open(link)
            return "Opening \(name) to install Wyrm \(update.version)."
        }
        UIPasteboard.general.string = update.url.absoluteString
        if let url = URL(string: "\(scheme)://") { open(url) }
        return "Download link copied. Paste it into \(name)'s downloader."
    }

    static let all: [WyrmInstaller] = [
        WyrmInstaller(
            id: "altstore", name: "AltStore", scheme: "altstore",
            icon: URL(string: "https://user-images.githubusercontent.com/705880/65270980-1eb96f80-dad1-11e9-9367-78ccd25ceb02.png"),
            tagline: "Signs with your Apple ID",
            steps: ["On your computer, install AltServer from altstore.io.",
                    "Connect this iPhone with a cable and tap Trust.",
                    "In AltServer choose Install AltStore, then this iPhone.",
                    "Come back here and tap AltStore again."],
            website: URL(string: "https://altstore.io")),
        WyrmInstaller(
            id: "sidestore", name: "SideStore", scheme: "sidestore",
            icon: URL(string: "https://sidestore.io/assets/icon.png"),
            tagline: "AltStore without a computer",
            steps: ["Follow the setup at sidestore.io once, with a computer, to pair this iPhone.",
                    "Open SideStore and let it refresh.",
                    "After that it needs no computer. Come back and tap SideStore."],
            website: URL(string: "https://sidestore.io")),
        WyrmInstaller(
            id: "ksign", name: "KSign", scheme: "ksign",
            icon: URL(string: "https://raw.githubusercontent.com/Nyasami/Ksign/v1.5/Ksign/Resources/Assets.xcassets/AppIcon.appiconset/Ksign-default.png"),
            tagline: "On-device signer",
            steps: ["Install KSign from its official download page.",
                    "In KSign, import a signing certificate (.p12 and .mobileprovision).",
                    "Come back and tap KSign: the update downloads inside KSign, then sign and install it."],
            website: URL(string: "https://github.com/Nyasami/Ksign/releases")),
        WyrmInstaller(
            id: "esign", name: "ESign", scheme: "esign", icon: nil,
            tagline: "On-device signer",
            steps: ["Install ESign from its official source.",
                    "In ESign, import a signing certificate.",
                    "Come back and tap ESign: Wyrm copies the download link, paste it into ESign's downloader."],
            website: nil),
    ]
}

/// The "Install with" cards under Settings › Backup › Version.
struct WyrmInstallersSection: View {
    let update: WyrmUpdateInfo?
    @Environment(\.openURL) private var openURL
    @State private var setup: WyrmInstaller?
    @State private var note = ""
    // Re-read on appear: a store installed while Wyrm was away shows at once.
    @State private var refresh = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WSSectionLabel("Install updates with")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(WyrmInstaller.all) { installer in
                    card(installer)
                }
            }
            .padding(.horizontal, 16)
            .id(refresh)
            Text(note.isEmpty ? caption : note)
                .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                .padding(.horizontal, 20).padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { refresh += 1 }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in refresh += 1 }
        .sheet(item: $setup) { installer in WyrmInstallerSetupSheet(installer: installer) }
    }

    private var caption: String {
        update == nil
            ? "When a new build is out, tap the app you use and it installs the update."
            : "Tap the app you use: it downloads Wyrm \(update!.version) and installs it."
    }

    private func card(_ installer: WyrmInstaller) -> some View {
        let installed = installer.installed
        return Button { tap(installer, installed: installed) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    WyrmInstallerIcon(installer: installer)
                    Spacer(minLength: 4)
                    Text(installed ? (update == nil ? "Installed" : "Update") : "Get")
                        .font(.androidWyrm(10.5, .bold)).tracking(0.4)
                        .foregroundColor(installed && update != nil ? ATheme.onInk : (installed ? ATheme.live : ATheme.ink))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(installed && update != nil ? ATheme.ink : (installed ? ATheme.live.opacity(0.14) : ATheme.well)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(installer.name).font(.androidWyrm(15, .semibold)).foregroundColor(ATheme.ink)
                    Text(installer.tagline).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(WSPressStyle())
        .accessibilityLabel("\(installer.name), \(installed ? "installed" : "not installed")")
    }

    private func tap(_ installer: WyrmInstaller, installed: Bool) {
        guard installed else { setup = installer; return }
        guard let update else {
            // Nothing new: just open the app.
            if let url = URL(string: "\(installer.scheme)://") { openURL(url) }
            note = "Wyrm is up to date."
            return
        }
        note = installer.hand(update) { openURL($0) }
    }
}

struct WyrmInstallerIcon: View {
    let installer: WyrmInstaller
    var body: some View {
        Group {
            if let icon = installer.icon {
                AsyncImage(url: icon) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { monogram }
                }
            } else {
                monogram
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ATheme.rule, lineWidth: 0.6))
    }
    private var monogram: some View {
        ZStack {
            ATheme.ink
            Text(String(installer.name.prefix(1))).font(.androidWyrm(20, .bold)).foregroundColor(ATheme.onInk)
        }
    }
}

/// Shown when the chosen app is not on this iPhone: its own setup, step by step.
struct WyrmInstallerSetupSheet: View {
    let installer: WyrmInstaller
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                WyrmInstallerIcon(installer: installer).scaleEffect(1.25).frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Install \(installer.name) first").font(.androidWyrm(19, .semibold)).foregroundColor(ATheme.ink)
                    Text("\(installer.name) isn't on this iPhone yet.").font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
                }
            }
            .padding(.top, 26)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(installer.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)").font(.androidWyrm(12, .bold)).foregroundColor(ATheme.onInk)
                            .frame(width: 24, height: 24).background(Circle().fill(ATheme.ink))
                        Text(step).font(.androidWyrm(14.5)).foregroundColor(ATheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 24)
            Spacer(minLength: 24)
            if let website = installer.website {
                WSPrimaryButton(label: "Open \(installer.name) page") { openURL(website) }
            }
            WSOutlineButton(label: "Done") { dismiss() }.padding(.top, 10)
        }
        .padding(.horizontal, 22).padding(.bottom, 18)
        .background(ATheme.paper.ignoresSafeArea())
        .presentationDetentsIfAvailable()
    }
}

private extension View {
    @ViewBuilder
    func presentationDetentsIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }
}
