import SwiftUI
import UIKit

/*
 * Skin Studio (OM, 2026-10-12; iOS 2026-10-13): the Skin tab's default page.
 * Android twin: ui/SkinStudioScreen.kt. A stage where the snake being made
 * slithers, a shelf of the player's snakes, and three workshops: Snake (the
 * bead pattern), Beads (the bead library; each opens the bead editor) and
 * Eyes (opens the eye editor). "Default skin editor" opens the classic Skin
 * page (WyrmSkinRoot); a skin being tried always opens there. See
 * WyrmStudio.swift for what is stored and worn.
 */

/// The Skin tab: Skin Studio, or the classic page when asked for (or while a skin is tried).
struct WyrmSkinTab: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject private var studio = WyrmStudio.shared
    @ObservedObject private var trial = WyrmSkinTrial.shared

    var body: some View {
        if trial.skin != nil || studio.classicOpen {
            WyrmSkinRoot(engine: engine)
        } else {
            WyrmSkinStudioPage(engine: engine)
        }
    }
}

private enum StudioTab: Int, CaseIterable {
    case snake, beads, eyes
    var title: String { ["Snake", "Beads", "Eyes"][rawValue] }
}

/// A bead open in the editor, and what closing it does.
private struct StudioBeadEditing: Identifiable {
    let id: String
    /// Opened from the Snake tab: the bead goes on the snake when it is done.
    let append: Bool
    /// Made just now: closing with X removes it again.
    let fresh: Bool
}

struct WyrmSkinStudioPage: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject private var studio = WyrmStudio.shared
    @StateObject private var textures = WyrmSkinTextureLibrary.acquire()
    @State private var tab = StudioTab.snake
    @State private var editingBead: StudioBeadEditing?
    @State private var editingEyes = false
    @State private var skinMenu: String?
    @State private var beadMenu: String?
    @State private var renaming: String?
    @State private var notice = ""
    @State private var noticeGeneration = 0

    var body: some View {
        let skin = studio.skin(studio.selected) ?? studio.skins.first
        let _ = studio.paintRevision
        let pictures = studioPictures(studio.beads.map(\.id), white: textures.beads[40])
        let image: (String) -> CGImage? = { pictures[$0] }
        return ZStack {
            VStack(spacing: 0) {
                WyrmScreenHeader(kicker: "WYRM", title: "Skin Studio", trailing: AnyView(
                    StudioCapsule(label: "Default skin editor", icon: "tshirt", filled: false) {
                        withAnimation(.easeOut(duration: 0.2)) { studio.classicOpen = true }
                    }))
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if let skin {
                            StudioStage(skin: skin, image: image, worn: studio.worn == skin.id,
                                        onWear: { studio.wear(skin.id) }, onTakeOff: { studio.takeOff() },
                                        onRename: { renaming = skin.id })
                        }
                        shelf(skin: skin, image: image)
                        StudioCaption("Touch and hold a snake to rename, copy or delete it.").padding(.bottom, 12)
                        WSSegmented(options: StudioTab.allCases.map(\.title), selected: tab.rawValue) { next in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { tab = StudioTab(rawValue: next) ?? .snake }
                        }
                        .padding(.horizontal, 16)
                        Spacer().frame(height: 14)
                        if !notice.isEmpty {
                            Text(notice).font(.androidWyrm(12)).foregroundColor(ATheme.badge)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20).padding(.vertical, 4)
                        }
                        Group {
                            switch tab {
                            case .snake:
                                if let skin {
                                    StudioPatternWorkshop(skin: skin, beads: studio.beads, image: image,
                                                          onTooMany: { show("A snake can wear \(WyrmStudio.maxDistinct) different beads.") },
                                                          onNewBead: {
                                                              let bead = studio.newBead()
                                                              editingBead = StudioBeadEditing(id: bead.id, append: true, fresh: true)
                                                          })
                                }
                            case .beads:
                                StudioBeadWorkshop(beads: studio.beads, image: image, textures: textures,
                                                   onOpen: { editingBead = StudioBeadEditing(id: $0, append: false, fresh: false) },
                                                   onLongPress: { beadMenu = $0 },
                                                   onNew: {
                                                       let bead = studio.newBead()
                                                       editingBead = StudioBeadEditing(id: bead.id, append: false, fresh: true)
                                                   })
                            case .eyes:
                                if let skin { StudioEyeWorkshop(skin: skin, image: image) { editingEyes = true } }
                            }
                        }
                        .id(tab)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        Spacer().frame(height: 108)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ATheme.paper)

            if let id = skinMenu, let item = studio.skin(id) {
                StudioActionSheet(title: item.name, subtitle: "\(item.pattern.count) beads · \(item.eyes.count) eyes",
                                  actions: [
                                      StudioAction(title: "Rename", icon: "pencil") { renaming = id },
                                      StudioAction(title: "Duplicate", icon: "doc.on.doc") { studio.duplicateSkin(id) },
                                      StudioAction(title: "Delete", icon: "trash", destructive: true) { studio.deleteSkin(id) },
                                  ],
                                  onDismiss: { skinMenu = nil })
                    .zIndex(5)
            }
            if let id = beadMenu {
                StudioActionSheet(title: "Bead",
                                  subtitle: WyrmStudioArt.finishes[safeIndex: studio.bead(id)?.finish ?? 0] ?? "",
                                  actions: [
                                      StudioAction(title: "Edit", icon: "paintbrush.pointed") {
                                          editingBead = StudioBeadEditing(id: id, append: false, fresh: false)
                                      },
                                      StudioAction(title: "Duplicate", icon: "doc.on.doc") {
                                          if let bead = studio.bead(id) { studio.newBead(from: bead) }
                                      },
                                      StudioAction(title: "Delete", icon: "trash", destructive: true) {
                                          if !studio.deleteBead(id) { show("This bead is on a snake. Take it off the snake first.") }
                                      },
                                  ],
                                  onDismiss: { beadMenu = nil })
                    .zIndex(5)
            }
            if let id = renaming {
                StudioRenameDialog(start: studio.skin(id)?.name ?? "") { name in
                    if let name { studio.renameSkin(id, name) }
                    renaming = nil
                }
                .zIndex(6)
            }
        }
        .onAppear { textures.prepare() }
        // The editors rise over the whole page.
        .fullScreenCover(item: $editingBead) { editing in
            StudioBeadEditor(beadID: editing.id, textures: textures) { saved in
                if saved, editing.append, let skin = studio.skin(studio.selected) ?? studio.skins.first, studio.bead(editing.id) != nil {
                    if !studio.setPattern(skin.id, skin.pattern + [editing.id]) {
                        show("A snake can wear \(WyrmStudio.maxDistinct) different beads.")
                    }
                }
                if !saved, editing.fresh { studio.deleteBead(editing.id) }
                editingBead = nil
            }
        }
        .fullScreenCover(isPresented: $editingEyes) {
            if let skin {
                StudioEyeEditor(skin: skin, image: image) { editingEyes = false }
            }
        }
    }

    private func show(_ text: String) {
        notice = text
        noticeGeneration += 1
        let mine = noticeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { if noticeGeneration == mine { notice = "" } }
    }

    /// The shelf: every snake, then a new one.
    private func shelf(skin: WyrmStudioSkin?, image: @escaping (String) -> CGImage?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StudioShelfCard(selected: false, onTap: {
                    studio.newSkin()
                    tab = .snake
                }, onHold: {}) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 19, weight: .semibold)).foregroundColor(ATheme.ink)
                        Text("New snake").font(.androidWyrm(11, .bold)).foregroundColor(ATheme.ink)
                    }
                }
                ForEach(studio.skins) { item in
                    StudioShelfCard(selected: item.id == skin?.id, onTap: { studio.select(item.id) },
                                    onHold: { skinMenu = item.id }) {
                        VStack(spacing: 0) {
                            Canvas { context, size in
                                drawStudioStrip(context, size: size, skin: item, image: image)
                            }
                            HStack(spacing: 4) {
                                Text(item.name).font(.androidWyrm(11, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
                                Spacer(minLength: 0)
                                if studio.worn == item.id { Circle().fill(ATheme.live).frame(width: 7, height: 7) }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6).padding(.bottom, 8)
    }
}

extension Array {
    subscript(safeIndex index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Every bead's picture for one body pass (cached by its revision in WyrmStudioArt).
@MainActor
func studioPictures(_ ids: [String], white: CGImage?) -> [String: CGImage] {
    var out: [String: CGImage] = [:]
    for id in ids {
        if let bead = WyrmStudio.shared.bead(id), let image = WyrmStudioArt.beadImage(bead, white: white) { out[id] = image }
    }
    return out
}

private struct StudioShelfCard<Content: View>: View {
    let selected: Bool
    let onTap: () -> Void
    let onHold: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: 132, height: 78)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onHold()
            }
    }
}

// MARK: - the stage

private struct StudioStage: View {
    let skin: WyrmStudioSkin
    let image: (String) -> CGImage?
    let worn: Bool
    let onWear: () -> Void
    let onTakeOff: () -> Void
    let onRename: () -> Void
    @State private var clock = StudioClock()
    @State private var appear: CGFloat = 0

    var body: some View {
        // The stage's light takes the snake's own colour.
        let glow = Color(studio: skin.pattern.first.flatMap(image).map(WyrmStudioArt.averageRGB) ?? 0x3F_EE96)
        let picture = self.image
        let clock = self.clock
        let skin = self.skin
        return ZStack(alignment: .bottomLeading) {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let time = clock.advance(to: timeline.date)
                    let boost = clock.boost
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                        Gradient(colors: [glow.opacity(0.30 + 0.15 * boost), .clear]),
                        center: CGPoint(x: size.width * 0.6, y: size.height * 0.48), startRadius: 0,
                        endRadius: size.width * 0.62))
                    let bead = size.height * 0.2
                    let step = bead * studioBeadStep
                    let count = min(max(Int((size.width + bead * 2) / step), 8), 256)
                    let head = CGPoint(x: size.width * 0.82, y: size.height * 0.48)
                    let wave = bead * 0.75
                    // The wave per bead follows the bead spacing, so the body bends as before.
                    let k = 0.32 * studioBeadStep / 0.36
                    let look = CGPoint(x: 1.4 + 0.6 * cos(time * 0.9), y: 1.8 * sin(time * 0.7))
                    drawStudioSnake(context, skin: skin, count: count, bead: bead, place: { i in
                        let fi = CGFloat(i)
                        return CGPoint(x: head.x - fi * step,
                                       y: head.y + sin(time * 3.2 - fi * k) * wave * (0.25 + 0.75 * min(fi / 30, 1)))
                    }, image: picture, look: look)
                }
            }
            .opacity(appear)
            .offset(x: (1 - appear) * -60)

            VStack(alignment: .leading, spacing: 1) {
                Text(worn ? "WORN" : "STUDIO SNAKE").font(.androidWyrm(9.5, .bold)).tracking(1.2)
                    .foregroundColor(worn ? ATheme.live : ATheme.quiet)
                Text(skin.name).font(.androidWyrm(26, .bold)).foregroundColor(ATheme.ink).lineLimit(1)
                    .onTapGesture(perform: onRename)
            }
            .padding(.leading, 18).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 120)

            HStack(spacing: 8) {
                if worn {
                    StudioCapsule(label: "Take off", filled: false, action: onTakeOff)
                } else {
                    StudioCapsule(label: "Wear", icon: "sparkles", action: onWear)
                }
            }
            .padding(.trailing, 14).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ATheme.card))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { clock.boost = 1 }
        .padding(.horizontal, 16)
        .onAppear { arrive() }
        .onChange(of: skin.id) { _ in arrive() }
    }

    private func arrive() {
        appear = 0
        withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) { appear = 1 }
    }
}

// MARK: - Snake: the pattern

private struct StudioPatternWorkshop: View {
    let skin: WyrmStudioSkin
    let beads: [WyrmStudioBead]
    let image: (String) -> CGImage?
    let onTooMany: () -> Void
    let onNewBead: () -> Void
    @ObservedObject private var studio = WyrmStudio.shared
    @State private var history: [[String]] = []
    @State private var historyFor = ""
    @State private var selected: Int?

    var body: some View {
        let pattern = skin.pattern
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("\(pattern.count) / \(WyrmStudio.maxPattern) beads · \(Set(pattern).count) kinds")
                    .font(.androidWyrm(11.5, .semibold)).foregroundColor(ATheme.quiet)
                Spacer()
                StudioRoundButton(icon: "arrow.uturn.backward", enabled: !history.isEmpty, size: 34) {
                    guard let last = history.popLast() else { return }
                    studio.setPattern(skin.id, last)
                }
                StudioRoundButton(icon: "repeat", enabled: pattern.count * 2 <= WyrmStudio.maxPattern, size: 34) {
                    change(pattern + pattern)
                }
                StudioRoundButton(icon: "arrow.left.arrow.right", enabled: pattern.count > 1, size: 34) {
                    change(pattern.reversed())
                }
            }
            .padding(.horizontal, 20)
            Spacer().frame(height: 10)
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pattern.enumerated()), id: \.offset) { index, id in
                            let chosen = selected == index
                            VStack(spacing: 0) {
                                StudioPicture(image: image(id)).frame(width: 38, height: 38)
                                    .frame(width: 44, height: 44)
                                    .overlay(Circle().stroke(chosen ? ATheme.ink : Color.clear, lineWidth: 2.5))
                                    .contentShape(Circle())
                                    .onTapGesture { selected = chosen ? nil : index }
                                Text("\(index + 1)").font(.androidWyrm(8.5, .bold)).foregroundColor(chosen ? ATheme.ink : ATheme.quiet)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 62)
                .onChange(of: pattern.count) { count in
                    if selected == nil && count > 0 { withAnimation { reader.scrollTo(count - 1, anchor: .trailing) } }
                }
            }
            if let at = selected, at < pattern.count {
                HStack(spacing: 8) {
                    StudioCapsule(label: "Remove", icon: "trash", filled: false, enabled: pattern.count > 1) {
                        change(pattern.enumerated().filter { $0.offset != at }.map(\.element)); selected = nil
                    }
                    StudioCapsule(label: "Copy", icon: "doc.on.doc", filled: false, enabled: pattern.count < WyrmStudio.maxPattern) {
                        var next = pattern; next.insert(pattern[at], at: at + 1); change(next)
                    }
                    StudioCapsule(label: "◀", filled: false, enabled: at > 0) {
                        var next = pattern; let v = next.remove(at: at); next.insert(v, at: at - 1); change(next); selected = at - 1
                    }
                    StudioCapsule(label: "▶", filled: false, enabled: at < pattern.count - 1) {
                        var next = pattern; let v = next.remove(at: at); next.insert(v, at: at + 1); change(next); selected = at + 1
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .transition(.opacity)
            }
            StudioCaption("Tap a bead in the snake to remove, copy or move it.").padding(.top, 4)
            WyrmSectionLabel("Tap a bead to add it")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                Button(action: onNewBead) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundColor(ATheme.ink)
                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                        .background(Circle().fill(ATheme.card)).overlay(Circle().stroke(ATheme.rule, lineWidth: 1))
                        .contentShape(Circle())
                }.buttonStyle(WSPressStyle())
                ForEach(beads) { bead in
                    // A tap always adds the bead to the snake (OM, 2026-10-13).
                    Color.clear.aspectRatio(1, contentMode: .fit)
                        .overlay(StudioPicture(image: image(bead.id)))
                        .contentShape(Circle())
                        .onTapGesture {
                            if pattern.count < WyrmStudio.maxPattern { change(pattern + [bead.id]) }
                        }
                }
            }
            .padding(.horizontal, 16)
        }
        .onAppear { resetIfOtherSkin() }
        .onChange(of: skin.id) { _ in resetIfOtherSkin() }
    }

    private func resetIfOtherSkin() {
        guard historyFor != skin.id else { return }
        historyFor = skin.id
        history = []
        selected = nil
    }

    private func change(_ next: [String]) {
        guard next != skin.pattern else { return }
        let before = skin.pattern
        if studio.setPattern(skin.id, next) {
            history.append(before)
            if history.count > 40 { history.removeFirst() }
        } else {
            onTooMany()
        }
    }
}

// MARK: - Beads: the library

private struct StudioBeadWorkshop: View {
    let beads: [WyrmStudioBead]
    let image: (String) -> CGImage?
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let onOpen: (String) -> Void
    let onLongPress: (String) -> Void
    let onNew: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WyrmSectionLabel("Your beads")
            StudioCaption("Tap a bead to edit it. Touch and hold a bead to copy or delete it.").padding(.bottom, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                Button(action: onNew) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundColor(ATheme.ink)
                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                        .background(Circle().fill(ATheme.card)).overlay(Circle().stroke(ATheme.rule, lineWidth: 1))
                        .contentShape(Circle())
                }.buttonStyle(WSPressStyle())
                ForEach(beads) { bead in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                        .overlay(StudioPicture(image: image(bead.id)))
                        .contentShape(Circle())
                        .onTapGesture { onOpen(bead.id) }
                        .onLongPressGesture(minimumDuration: 0.45) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onLongPress(bead.id)
                        }
                }
            }
            .padding(.horizontal, 16)
            Spacer().frame(height: 18)
            WyrmSectionLabel("Start from a default skin")
            // slither's presets: each becomes Studio beads in the Slither finish and a new snake.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(WyrmSkinCatalog.presets.indices, id: \.self) { index in
                        let groups = WyrmSkinCatalog.presets[index]
                        VStack(alignment: .leading, spacing: 6) {
                            WyrmMiniSnake(textures: textures, groups: groups).frame(height: 30)
                            Text(String(format: "Preset %02d", index + 1)).font(.androidWyrm(10.5, .bold)).foregroundColor(ATheme.quiet)
                        }
                        .padding(10)
                        .frame(width: 150)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ATheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture { studioFromPreset(index, groups) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// A slither preset as Studio beads (one per colour) and a new snake wearing them.
    private func studioFromPreset(_ index: Int, _ groups: [Int]) {
        guard !groups.isEmpty else { return }
        let studio = WyrmStudio.shared
        var ids: [Int: String] = [:]
        let pattern = groups.prefix(WyrmStudio.maxPattern).map { group -> String in
            if let known = ids[group] { return known }
            let made = studio.newBead(from: WyrmStudioBead(id: "", color: 0xFF00_0000 | WyrmAirSkin.groupRGB(group),
                                                          finish: WyrmStudioArt.finishSlither)).id
            ids[group] = made
            return made
        }
        studio.newSkin(name: String(format: "Preset %02d", index + 1), pattern: Array(pattern))
    }
}

// MARK: - Eyes

private struct StudioEyeWorkshop: View {
    let skin: WyrmStudioSkin
    let image: (String) -> CGImage?
    let onOpenEditor: () -> Void

    private static let presets: [(String, [WyrmStudioEye])] = {
        func styled(_ change: (inout WyrmStudioEye) -> Void) -> [WyrmStudioEye] {
            WyrmStudioEye.pair().map { var e = $0; change(&e); return e }
        }
        var spider: [WyrmStudioEye] = []
        for s: Float in [-8, -3.5, 3.5, 8] {
            spider.append(WyrmStudioEye(fwd: 8, side: s, white: 3, pupil: 2))
            spider.append(WyrmStudioEye(fwd: 2.5, side: s * 0.9, white: 2.6, pupil: 1.7))
        }
        return [
            ("Classic", WyrmStudioEye.pair()),
            ("Cyclops", [WyrmStudioEye(fwd: 5, side: 0, white: 8.5, pupil: 4.5)]),
            ("Three", [WyrmStudioEye(side: -7, white: 5, pupil: 3), WyrmStudioEye(fwd: 9, side: 0, white: 4.5, pupil: 2.8),
                       WyrmStudioEye(side: 7, white: 5, pupil: 3)]),
            ("Spider", Array(spider.prefix(8))),
            ("Cat", styled { $0.pupilShape = WyrmStudioArt.pupilCat; $0.whiteColor = 0xFFC8_F55A }),
            ("Hearts", styled { $0.pupilShape = 4; $0.pupil = 4.2 }),
            ("Stars", styled { $0.pupilShape = 5; $0.pupil = 4.4; $0.whiteColor = 0xFF1A_1A40; $0.pupilColor = 0xFFFF_E15A }),
            ("None", []),
        ]
    }()

    var body: some View {
        let picture = image
        let head = skin.pattern.first.flatMap(image)
        return VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Canvas { context, size in
                    let bead = size.height * 0.62
                    let headPoint = CGPoint(x: size.width * 0.62, y: size.height * 0.5)
                    drawStudioSnake(context, skin: skin, count: 30, bead: bead,
                                    place: { i in CGPoint(x: headPoint.x - CGFloat(i) * bead * studioBeadStep, y: headPoint.y) },
                                    image: picture, shadow: false)
                }
                StudioCapsule(label: "Edit eyes", icon: "eye", action: onOpenEditor).padding(12)
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ATheme.card))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenEditor)
            .padding(.horizontal, 16)
            WyrmSectionLabel("Quick eyes")
            StudioCaption("Tap one to give this snake those eyes.").padding(.bottom, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.presets.indices, id: \.self) { index in
                        let name = Self.presets[index].0
                        let eyes = Self.presets[index].1
                        let chosen = skin.eyes == eyes
                        // The snake's own head bead wearing those eyes.
                        Canvas { context, size in
                            let bead = min(size.width, size.height) * 0.62
                            let centre = CGPoint(x: size.width * 0.46, y: size.height * 0.5)
                            if let head {
                                context.draw(Image(decorative: head, scale: 1),
                                             in: CGRect(x: centre.x - bead / 2, y: centre.y - bead / 2, width: bead, height: bead))
                            }
                            drawStudioEyes(context, eyes: eyes, head: centre, angle: 0, unit: bead / 29, look: CGPoint(x: 1, y: 0))
                        }
                        .frame(width: 76, height: 76)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ATheme.card))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(chosen ? ATheme.ink : ATheme.rule, lineWidth: chosen ? 2 : 1))
                        .contentShape(Rectangle())
                        .onTapGesture { WyrmStudio.shared.setEyes(skin.id, eyes) }
                        .accessibilityLabel(name)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
