import SwiftUI
import UIKit

/*
 * Settings › About Wyrm (OM, 2026-09-28).
 *
 * The one page that is not paper: a night canvas, whatever the theme, told
 * as a story in chapters down a lit thread — where Wyrm began, what it grew
 * into, who builds it — then the community, a coffee and a way to write.
 * Chapters rise into place as they scroll in. Android draws the same page in
 * `ui/AboutScreen.kt`; change both together.
 */

enum WyrmAboutInfo {
    static let upiID = "ommanav@fam"
    static let payee = "OM Rajput"
    static let email = "ommanav.mail@gmail.com"
    static let website = URL(string: "https://www.omrajput.in")!
    /// Not published yet: the button says so until a link is set here.
    static let discordInvite: URL? = nil

    static var upiPay: URL? {
        var parts = URLComponents()
        parts.scheme = "upi"
        parts.host = "pay"
        parts.queryItems = [URLQueryItem(name: "pa", value: upiID), URLQueryItem(name: "pn", value: payee),
                            URLQueryItem(name: "cu", value: "INR"), URLQueryItem(name: "tn", value: "Coffee for Wyrm")]
        return parts.url
    }

    static let ecosystem: [(name: String, detail: String, symbol: String)] = [
        ("Wyrm Android", "Where it all started", "iphone.gen3"),
        ("Wyrm iOS", "The same Wyrm on iPhone", "apple.logo"),
        ("Wyrm Desktop", "For the big screen", "desktopcomputer"),
        ("Wyrm Windows", "Native on Windows", "pc"),
        ("Wyrm Linux", "Native on Linux", "terminal"),
        ("NTL VANCED", "Browser extension, powered by Wyrm", "puzzlepiece.extension"),
        ("Slither for Android", "The original app, modded into Wyrm", "circle.hexagongrid"),
        ("Slither for iOS", "The original app, modded into Wyrm", "circle.hexagongrid.fill"),
    ]
}

/// The page's colours, from the player's theme (OM, 2026-09-28: the page must
/// follow the chosen theme). Gold is the page's accent, deeper on light themes
/// so it reads on paper; text on gold is always dark. `Night` on Android.
enum WyrmNight {
    static var sky: Color { ATheme.paper }
    static var deep: Color { ATheme.card }
    static var card: Color { ATheme.card }
    static var rule: Color { ATheme.rule }
    static var ink: Color { ATheme.ink }
    static var mute: Color { ATheme.mute }
    static var quiet: Color { ATheme.quiet }
    static var well: Color { ATheme.well }
    static var gold: Color {
        ATheme.dark ? Color(red: 0.89, green: 0.73, blue: 0.42) : Color(red: 0.69, green: 0.48, blue: 0.12)
    }
    static let onGold = Color(red: 0.11, green: 0.10, blue: 0.086)
    static var green: Color { ATheme.live }
    static let discord = Color(red: 0.345, green: 0.396, blue: 0.949)
}

struct WyrmAboutPage: View {
    let close: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var note = ""

    var body: some View {
        ZStack(alignment: .top) {
            WyrmNight.sky.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    hero
                    chapter("I", "It began as a mod",
                            "Wyrm started as a simple slither.io mod for Android. A few tweaks for my own games, nothing more.")
                    chapter("II", "Then it grew a name",
                            "I kept building, one feature after another, until the mod was no longer a mod. It became Wyrm: my own brand, a small one, inside the slither community.")
                    chapter("III", "Then it became an ecosystem",
                            "Wyrm now runs on phones and computers, lives inside the browser, and even the original slither apps on Android and iOS were modded into it.")
                    ecosystem
                    chapter("IV", "Built by one person",
                            "I'm OM Rajput, and Wyrm is a one-person project. The backend, the apps, the engine work, the design and every release: I build and run all of it myself.", last: true)
                    roles
                    community
                    coffee
                    contact
                    footer
                }
                .padding(.bottom, 40)
            }
            header
            if !note.isEmpty {
                Text(note).font(.androidWyrm(12.5, .semibold)).foregroundColor(WyrmNight.sky)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(WyrmNight.ink))
                    .padding(.top, 58)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(5)
            }
        }
        .foregroundColor(WyrmNight.ink)
    }

    // MARK: Header and hero

    private var header: some View {
        HStack {
            Button(action: close) {
                Text("‹ Settings").font(.androidWyrm(16)).foregroundColor(WyrmNight.gold)
                    .padding(.horizontal, 6).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(LinearGradient(colors: [WyrmNight.sky, WyrmNight.sky.opacity(0)], startPoint: .top, endPoint: .bottom))
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(RadialGradient(colors: [WyrmNight.gold.opacity(0.35), .clear], center: .center,
                                             startRadius: 4, endRadius: 120))
                    .frame(width: 240, height: 240)
                Image("WyrmMark").resizable().scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: WyrmNight.gold.opacity(0.35), radius: 24)
            }
            .wyrmAboutRise(delay: 0.05)
            Text("THE STORY OF").font(.androidWyrm(11, .bold)).tracking(3).foregroundColor(WyrmNight.gold)
                .wyrmAboutRise(delay: 0.15)
            Text("Wyrm").font(.wyrmDisplay(58)).foregroundColor(WyrmNight.ink).padding(.top, 2)
                .wyrmAboutRise(delay: 0.22)
            Text("One developer. One snake game.\nA whole ecosystem.")
                .font(.androidWyrm(15)).foregroundColor(WyrmNight.mute).multilineTextAlignment(.center)
                .lineSpacing(3).padding(.top, 10)
                .wyrmAboutRise(delay: 0.3)
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                .foregroundColor(WyrmNight.quiet).padding(.top, 28)
                .wyrmAboutRise(delay: 0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36).padding(.bottom, 30)
    }

    // MARK: Story

    /// One chapter on the thread: a numeral on a lit node, the title, the text.
    private func chapter(_ numeral: String, _ title: String, _ text: String, last: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Text(numeral).font(.wyrmDisplay(15)).foregroundColor(WyrmNight.onGold)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(WyrmNight.gold))
                    .shadow(color: WyrmNight.gold.opacity(0.5), radius: 10)
                Rectangle()
                    .fill(LinearGradient(colors: [WyrmNight.gold.opacity(0.6), WyrmNight.gold.opacity(last ? 0 : 0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 1.5)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("CHAPTER \(numeral)").font(.androidWyrm(10, .bold)).tracking(2).foregroundColor(WyrmNight.quiet)
                Text(title).font(.wyrmDisplay(27)).foregroundColor(WyrmNight.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text).font(.androidWyrm(15)).foregroundColor(WyrmNight.mute).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4).padding(.bottom, 34)
        }
        .padding(.horizontal, 22)
        .wyrmAboutRise()
    }

    private var ecosystem: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(WyrmAboutInfo.ecosystem.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold))
                        .foregroundColor(index == 0 ? WyrmNight.gold : WyrmNight.ink)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WyrmNight.well))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.androidWyrm(14, .bold)).foregroundColor(WyrmNight.ink)
                        Text(item.detail).font(.androidWyrm(11.5)).foregroundColor(WyrmNight.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WyrmNight.card))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(index == 0 ? WyrmNight.gold.opacity(0.5) : WyrmNight.rule, lineWidth: 1))
                .wyrmAboutRise(delay: Double(index % 2) * 0.08)
            }
        }
        .padding(.horizontal, 22).padding(.leading, 50).padding(.bottom, 36)
    }

    private var roles: some View {
        let roles = ["Backend", "Apps", "Engine", "Design", "Releases", "Support"]
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(roles, id: \.self) { role in
                    Text(role).font(.androidWyrm(12.5, .semibold)).foregroundColor(WyrmNight.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Capsule().fill(WyrmNight.card))
                        .overlay(Capsule().stroke(WyrmNight.rule, lineWidth: 1))
                }
            }
            Text("From the first line of the server to the last pixel of this page.")
                .font(.androidWyrm(12.5)).foregroundColor(WyrmNight.quiet)
        }
        .padding(.horizontal, 22).padding(.leading, 50).padding(.bottom, 44)
        .wyrmAboutRise()
    }

    // MARK: Community, coffee, contact

    private var community: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionKicker("THE COMMUNITY")
            Text("Play with the people\nwho play Wyrm").font(.wyrmDisplay(28)).foregroundColor(WyrmNight.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Updates first, ideas heard, games together.")
                .font(.androidWyrm(14)).foregroundColor(WyrmNight.mute)
            Button {
                if let invite = WyrmAboutInfo.discordInvite { openURL(invite) } else { show("The Discord invite is coming soon") }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 16, weight: .semibold))
                    Text("Join the Wyrm Discord").font(.androidWyrm(15.5, .bold))
                    Spacer()
                    Text(WyrmAboutInfo.discordInvite == nil ? "SOON" : "›")
                        .font(.androidWyrm(WyrmAboutInfo.discordInvite == nil ? 10 : 18, .bold)).tracking(1)
                        .padding(.horizontal, WyrmAboutInfo.discordInvite == nil ? 8 : 0).padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(WyrmAboutInfo.discordInvite == nil ? 0.2 : 0)))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18).frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WyrmNight.discord))
                .shadow(color: WyrmNight.discord.opacity(0.45), radius: 16, y: 6)
            }
            .buttonStyle(WSPressStyle())
            .padding(.top, 6)
        }
        .padding(.horizontal, 22).padding(.bottom, 44)
        .wyrmAboutRise()
    }

    private var coffee: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionKicker("BUY ME A COFFEE")
            Text("Keep the servers warm").font(.wyrmDisplay(28)).foregroundColor(WyrmNight.ink)
            Text("Wyrm is free. If it made your games better, a coffee keeps it going. Scan with any UPI app.")
                .font(.androidWyrm(14)).foregroundColor(WyrmNight.mute).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 14) {
                Image("UpiQR").resizable().interpolation(.none).scaledToFit()
                    .frame(maxWidth: 230)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white))
                    .accessibilityLabel("UPI QR code for \(WyrmAboutInfo.upiID)")
                Button {
                    UIPasteboard.general.string = WyrmAboutInfo.upiID
                    show("UPI ID copied")
                } label: {
                    HStack(spacing: 8) {
                        Text(WyrmAboutInfo.upiID).font(.androidWyrm(16, .bold)).foregroundColor(WyrmNight.ink)
                        Image(systemName: "doc.on.doc").font(.system(size: 13, weight: .semibold)).foregroundColor(WyrmNight.gold)
                    }
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(Capsule().fill(WyrmNight.well))
                }
                .buttonStyle(WSPressStyle())
                Button {
                    guard let pay = WyrmAboutInfo.upiPay else { return }
                    openURL(pay) { opened in if !opened { show("No UPI app found. Scan the code instead.") } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 15, weight: .semibold))
                        Text("Pay with a UPI app").font(.androidWyrm(15.5, .bold))
                    }
                    .foregroundColor(WyrmNight.onGold)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(WyrmNight.gold))
                }
                .buttonStyle(WSPressStyle())
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(WyrmNight.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(WyrmNight.gold.opacity(0.35), lineWidth: 1))
            .padding(.top, 4)
        }
        .padding(.horizontal, 22).padding(.bottom, 44)
        .wyrmAboutRise()
    }

    private var contact: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionKicker("SAY HELLO")
            Text("Write to me").font(.wyrmDisplay(28)).foregroundColor(WyrmNight.ink)
            VStack(spacing: 0) {
                contactRow("envelope.fill", "Email", WyrmAboutInfo.email) {
                    if let mail = URL(string: "mailto:\(WyrmAboutInfo.email)") { openURL(mail) }
                }
                Rectangle().fill(WyrmNight.rule).frame(height: 1).padding(.leading, 58)
                contactRow("globe", "Website", "omrajput.in") { openURL(WyrmAboutInfo.website) }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WyrmNight.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(WyrmNight.rule, lineWidth: 1))
        }
        .padding(.horizontal, 22).padding(.bottom, 40)
        .wyrmAboutRise()
    }

    private func contactRow(_ symbol: String, _ title: String, _ value: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundColor(WyrmNight.gold)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.uppercased()).font(.androidWyrm(10, .bold)).tracking(1.2).foregroundColor(WyrmNight.quiet)
                    Text(value).font(.androidWyrm(15, .semibold)).foregroundColor(WyrmNight.ink).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundColor(WyrmNight.quiet)
            }
            .padding(.horizontal, 14).frame(height: 64).contentShape(Rectangle())
        }
        .buttonStyle(WSPressStyle())
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Image("WyrmMark").resizable().scaledToFill().frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).opacity(0.8)
            Text("Made with care by OM Rajput").font(.androidWyrm(12.5, .semibold)).foregroundColor(WyrmNight.mute)
            Text("Wyrm \(WyrmBuild.version)\(WyrmBuild.build.isEmpty ? "" : " (\(WyrmBuild.build))")")
                .font(.androidWyrm(11)).foregroundColor(WyrmNight.quiet)
        }
        .frame(maxWidth: .infinity).padding(.top, 10)
        .wyrmAboutRise()
    }

    private func sectionKicker(_ text: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(WyrmNight.gold).frame(width: 22, height: 1.5)
            Text(text).font(.androidWyrm(10.5, .bold)).tracking(2.4).foregroundColor(WyrmNight.gold)
        }
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { note = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.25)) { if note == text { note = "" } }
        }
    }
}

/// Rises and fades in the first time it scrolls into view.
private struct WyrmAboutRise: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 26)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

extension View {
    fileprivate func wyrmAboutRise(delay: Double = 0) -> some View { modifier(WyrmAboutRise(delay: delay)) }
}
