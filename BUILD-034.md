# Wyrm iOS 0.11.0 (34)

Build 34 is the first product-shell pass that joins the Play and Social surfaces
to their live data sources while preserving the original C engine as the only
gameplay authority.

## Added

- Full-bleed root layout with matching status-area colour and a tighter
  home-indicator treatment.
- Draggable, spring-driven glass tab selection with iOS 15-25 material fallback
  and an iOS 26 native Liquid Glass implementation when compiled with the iOS
  26 SDK.
- Stack-based detail navigation. A back action now removes one screen, and a
  child screen arrives over its parent without moving the parent away.
- Live arena directory refresh, player counts, four-digit arena codes and TCP
  latency measurements with green-to-red latency colour mapping.
- Profile access from the Play header and backend avatar rendering throughout
  profiles and leaderboards.
- Connections page with swipeable Followers and Following pages.
- Direct-message suggestions limited to backend-authorized mutual connections.
- Official Wyrm voice rooms separated from player rooms.
- Backend email-code voice-profile verification, resend and confirmation flow.

## Changed

- Enter Lobby now invokes the original native mailbox directly. The SwiftUI
  portrait lobby is no longer part of the Play path; the original landscape
  lobby remains code-rotated inside the portrait-owned UIKit container.
- Removed duplicate server selection from Rooms & Team and renamed the voice
  entry to Voice rooms.
- Detail chrome now uses the same paper surface as its content.

## Engine boundary

No gameplay renderer, protocol parser, arena simulation or snake behavior was
reimplemented in Swift. SwiftUI selects an endpoint and sends the request to
`WyrmIOSRequestLobby`; the shared native engine owns the lobby and arena from
that point onward.

## Verification contract

The Apple CI job must compile both device and Simulator targets, run the
existing original-engine lobby/offline/online smoke tests, and package an
unsigned IPA plus Simulator archive and checksums. A successful CI build is not
a physical-device acceptance claim.
