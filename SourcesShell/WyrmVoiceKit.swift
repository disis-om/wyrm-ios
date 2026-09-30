import SwiftUI

/*
 * Voice rooms, redesigned (OM, 2026-09-30: "kisi professional app ka ho").
 * The pieces the voice pages share, drawn as Android draws them
 * (`VoiceRoomsKit.kt`): the room's art (official rooms wear the real Wyrm
 * mark, `WyrmBrandStroke`, never a typed "W"), live bars, the room card,
 * the room-code boxes with their "Ask the creator" line, and the facts row.
 */

/// A room's picture: the Wyrm mark on ink for official rooms, else the creator's avatar.
struct WyrmVoiceRoomArt: View {
    let room: WyrmVoiceRoom
    let size: CGFloat
    var body: some View {
        if room.managedPublic {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous).fill(ATheme.ink)
                WyrmBrandStroke()
                    .stroke(ATheme.onInk, style: StrokeStyle(lineWidth: size * 0.60 * 0.16, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.60, height: size * 0.60)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("Wyrm")
        } else {
            WyrmAvatar(initials: room.creator.displayName.isEmpty ? String(room.name.prefix(1)) : String(room.creator.displayName.prefix(2)).uppercased(),
                       size: size, url: room.creator.avatarURL)
        }
    }
}

/// Three bars that dance while a room is live; still bars otherwise.
struct WyrmVoiceLiveBars: View {
    let colour: Color
    let playing: Bool
    var height: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule().fill(colour).frame(width: 3, height: height * level(index))
            }
        }
        .frame(height: height, alignment: .bottom)
        .onAppear(perform: start)
    }

    private static let still: [CGFloat] = [0.45, 0.8, 0.6]
    private static let high: [CGFloat] = [1, 0.35, 0.8]
    private static let low: [CGFloat] = [0.35, 1, 0.45]

    private func level(_ index: Int) -> CGFloat {
        guard playing && !reduceMotion else { return Self.still[index] }
        return up ? Self.high[index] : Self.low[index]
    }

    private func start() {
        guard playing && !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { up = true }
    }
}

/// "3 in" on green for a live room, "Quiet" otherwise.
struct WyrmVoiceLivePill: View {
    let room: WyrmVoiceRoom
    var body: some View {
        if room.active {
            HStack(spacing: 6) {
                WyrmVoiceLiveBars(colour: ATheme.live, playing: true, height: 11)
                Text("\(room.activeCount) in").font(.androidWyrm(12, .bold)).foregroundColor(ATheme.live)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(ATheme.live.opacity(0.13)))
        } else {
            Text("Quiet").font(.androidWyrm(12, .semibold)).foregroundColor(ATheme.quiet)
        }
    }
}

/// A room in the list: art, name, who made it and how to get in, and whether it is live.
struct WyrmVoiceRoomCard: View {
    let room: WyrmVoiceRoom
    let action: () -> Void
    private var subtitle: String {
        if room.managedPublic { return "Official · open to everyone" }
        if room.mine { return "Your room · \(room.gate == "open" ? "open" : "closed")" }
        if room.gate != "open" { return "by \(room.creator.displayName) · closed right now" }
        if !room.member { return "by \(room.creator.displayName) · code needed" }
        return "by \(room.creator.displayName) · you're a member"
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                WyrmVoiceRoomArt(room: room, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name).font(.androidWyrm(15.5, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
                    HStack(spacing: 5) {
                        if !room.managedPublic && !room.mine && !room.member {
                            Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold)).foregroundColor(ATheme.quiet)
                        }
                        Text(subtitle).font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                WyrmVoiceLivePill(room: room)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(room.active ? ATheme.live.opacity(0.35) : ATheme.rule, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(WSPressStyle())
        .padding(.horizontal, 16).padding(.vertical, 5)
    }
}

/// A section title for the voice pages, with an optional quiet note on the right.
struct WyrmVoiceSectionTitle: View {
    let title: String
    var note = ""
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(.androidWyrm(17, .bold)).foregroundColor(ATheme.ink)
            Spacer()
            if !note.isEmpty { Text(note).font(.androidWyrm(12)).foregroundColor(ATheme.quiet) }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 6)
    }
}

/// The private room's code in eight boxes, then how to get one:
/// "Don't have a code? Ask <creator> for it." (the name opens their profile).
struct WyrmVoiceRoomCodeField: View {
    @Binding var code: String
    let creator: String
    let error: String
    let askCreator: () -> Void
    let done: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            Text("Enter the room code").font(.androidWyrm(15, .bold)).foregroundColor(ATheme.ink)
            Text("This room is private. Its code has 8 letters and numbers.")
                .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet).multilineTextAlignment(.center).padding(.top, 4)
            ZStack {
                // The real field, unseen: focus, keyboard and paste. The boxes show the code.
                TextField("", text: Binding(get: { code }, set: { typed in
                    code = String(typed.filter { $0.isLetter || $0.isNumber }.uppercased().prefix(8))
                }))
                .textInputAutocapitalization(.characters).disableAutocorrection(true)
                .keyboardType(.asciiCapable).submitLabel(.join)
                .focused($focused).onSubmit(done)
                .opacity(0.02)
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { index in
                        let characters = Array(code)
                        let filled = index < characters.count
                        let current = focused && index == characters.count
                        Text(filled ? String(characters[index]) : "")
                            .font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundColor(ATheme.ink)
                            .frame(width: 36, height: 46)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(filled ? ATheme.card : ATheme.well))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(!error.isEmpty ? Color.red : current ? ATheme.ink : ATheme.rule, lineWidth: current || !error.isEmpty ? 1.5 : 1))
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .padding(.top, 14)
            if !error.isEmpty {
                Text(error).font(.androidWyrm(12)).foregroundColor(.red).multilineTextAlignment(.center).padding(.top, 8)
            }
            Button(action: askCreator) {
                (Text("Don't have a code? Ask ").foregroundColor(ATheme.mute)
                 + Text(creator.isEmpty ? "the room's creator" : creator).fontWeight(.bold).foregroundColor(ATheme.link)
                 + Text(" for it.").foregroundColor(ATheme.mute))
                    .font(.androidWyrm(13)).multilineTextAlignment(.center)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The room's facts in one quiet row: who can enter, how many are in, how many fit.
struct WyrmVoiceFacts: View {
    let room: WyrmVoiceRoom
    var body: some View {
        let access = room.managedPublic ? "Open" : room.gate != "open" ? "Closed" : "Code"
        let facts: [(String, String)] = [(access, "Access"), ("\(room.activeCount)", "Inside"), ("\(room.capacity)", "Fits")]
        HStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Rectangle().fill(ATheme.rule).frame(width: 1, height: 30) }
                VStack(spacing: 2) {
                    Text(fact.0).font(.androidWyrm(16, .bold)).foregroundColor(ATheme.ink)
                    Text(fact.1).font(.androidWyrm(11)).foregroundColor(ATheme.quiet)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
        }
        .frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 20)
    }
}

/// A round call control: filled while on, a quiet well otherwise; red for Leave.
struct WyrmVoiceDockButton: View {
    let symbol: String
    let label: String
    var on = false
    var danger = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                    .foregroundColor(danger || on ? .white : ATheme.ink)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(danger ? Color(red: 0.898, green: 0.282, blue: 0.302) : on ? ATheme.ink : ATheme.well))
                Text(label).font(.androidWyrm(11, .semibold)).foregroundColor(ATheme.mute)
            }
        }
        .buttonStyle(WSPressStyle())
        .accessibilityLabel(label)
    }
}
