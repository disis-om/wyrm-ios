import SwiftUI
import UIKit

/*
 * Where an alert leads, and the in-app banner (OM, 2026-09-29).
 *
 * Wyrm iOS has no push service yet, so a bead on your trail, a reply to it, a
 * new follower and Wyrm's answer to your report show up as a banner at the top
 * while the app is open, and wait in Alerts. Tapping either opens the trail,
 * the profile or Your reports. On Android the same kinds come by FCM.
 */

enum WyrmAlertRouting {
    /// Kinds that raise the banner.
    static let banners: Set<String> = ["trail_like", "trail_reply", "support", "follow"]
    /// Kinds whose extra fields are ids for the app, not words for the player.
    static let social: Set<String> = ["trail_like", "trail_reply", "support", "follow", "voice_invite", "invite", "dm"]
    static let hiddenMeta: Set<String> = ["actorId", "actorName", "trailId", "reportId", "reportKind", "roomId", "inviteId", "playerId"]

    static func label(_ kind: String) -> String {
        switch kind {
        case "trail_like": return "BEAD ON YOUR TRAIL"
        case "trail_reply": return "TRAIL REPLY"
        case "support": return "FROM WYRM"
        case "voice_invite": return "VOICE INVITE"
        default: return kind.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    static func actionTitle(_ kind: String) -> String? {
        switch kind {
        case "trail_like", "trail_reply": return "View trail"
        case "support": return "See your reports"
        case "follow": return "View profile"
        default: return nil
        }
    }

    static func route(for alert: WyrmServiceAlert) -> WyrmDesignRoute? {
        switch alert.kind {
        case "trail_like", "trail_reply":
            guard let id = alert.meta["trailId"], !id.isEmpty else { return nil }
            return .trail(id)
        case "support":
            return .supportReports
        case "follow":
            guard let id = alert.meta["actorId"], !id.isEmpty else { return nil }
            return .profile(id)
        default:
            return nil
        }
    }
}

struct WyrmInAppBanner: View {
    let alert: WyrmServiceAlert
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var drag: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(alert.title).font(.androidWyrm(14, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("now").font(.androidWyrm(11)).foregroundColor(ATheme.quiet)
                }
                if !alert.body.isEmpty {
                    Text(alert.body).font(.androidWyrm(12.5)).foregroundColor(ATheme.mute).lineLimit(2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule))
        .shadow(color: Color.black.opacity(0.16), radius: 22, y: 10)
        .offset(y: min(0, drag))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onOpen)
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                if value.translation.height < -24 { onDismiss() }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { drag = 0 } }
            })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ATheme.well)
            switch alert.kind {
            case "trail_like":
                Circle().fill(ATheme.live).frame(width: 16, height: 16)
                    .overlay(Circle().fill(Color.white.opacity(0.45)).frame(width: 5, height: 5).offset(x: -3, y: -3))
            case "trail_reply":
                Image(systemName: "bubble.left.fill").font(.system(size: 16, weight: .semibold)).foregroundColor(ATheme.ink)
            case "support":
                WyrmBrandMark(size: 22)
            case "follow":
                Image(systemName: "person.badge.plus").font(.system(size: 16, weight: .semibold)).foregroundColor(ATheme.ink)
            default:
                Image(systemName: "bell.fill").font(.system(size: 15, weight: .semibold)).foregroundColor(ATheme.ink)
            }
        }
        .frame(width: 40, height: 40)
    }
}
