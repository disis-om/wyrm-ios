import SwiftUI

/*
 * The adjust preview (OM, 2026-09-28).
 *
 * The arrow, joystick, boost and zoom-bar sliders sit below the Controls
 * preview, so dragging one usually scrolls the thing being changed off screen.
 * While such a slider is held, this checks whether that exact control is fully
 * on screen inside the page's preview. When it is not, a card fades in at the
 * top of the page drawing the real control at its live size, opacity and
 * colour. It fades out one second after the finger lets go.
 *
 * "Fully" on purpose: a control only peeking under the header does not count
 * as seen. Android does the same in `ui/AdjustPreview.kt`.
 */
final class WyrmAdjustPreview: ObservableObject {
    static let shared = WyrmAdjustPreview()

    enum Subject { case arrow, joystick, boost, zoom }

    /// What the card draws. It stays set while the card fades out.
    @Published private(set) var subject: Subject?
    @Published private(set) var shown = false

    /// The scrolling part of the page, in global points (not published: only
    /// read when deciding).
    private var viewport: CGRect = .zero
    /// Each control drawn by the page preview, in global points.
    private var onPage: [Subject: CGRect] = [:]
    private var held = false
    private var hideWork: DispatchWorkItem?

    /// The slider for `subject` was touched (true) or let go (false).
    func editing(_ subject: Subject, _ active: Bool) {
        if active {
            hideWork?.cancel()
            held = true
            self.subject = subject
            decide()
        } else {
            held = false
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.held else { return }
                withAnimation(.easeOut(duration: 0.28)) { self.shown = false }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    func setViewport(_ frame: CGRect) {
        viewport = frame
        if held { decide() }
    }

    func place(_ subject: Subject, _ frame: CGRect?) {
        onPage[subject] = frame
        if held, subject == self.subject { decide() }
    }

    private func decide() {
        guard let subject else { return }
        let seen = onPage[subject].map { !viewport.isEmpty && viewport.contains($0) } ?? false
        let next = held && !seen
        guard next != shown else { return }
        withAnimation(.easeOut(duration: next ? 0.22 : 0.28)) { shown = next }
    }

    /// Which popup a setting's slider drives, if any.
    @MainActor
    static func subject(for id: String, engine: WyrmShellStore) -> Subject? {
        switch id {
        case "arrow.size", "arrow.separation", "arrow.smoothness", "arrow.color", "app.arrow-brightness": return .arrow
        case "controls.joystick_size": return .joystick
        case "controls.boost_size": return .boost
        case "controls.zoom_length": return .zoom
        case "controls.opacity": return engine.setting("controls.joystick_mode")?.index == 2 ? .arrow : .joystick
        default: return nil
        }
    }
}

extension View {
    /// Reports where the page preview drew one control.
    func wyrmAdjustPlace(_ subject: WyrmAdjustPreview.Subject) -> some View {
        background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { WyrmAdjustPreview.shared.place(subject, frame) }
                .onChange(of: frame) { WyrmAdjustPreview.shared.place(subject, $0) }
                .onDisappear { WyrmAdjustPreview.shared.place(subject, nil) }
        })
    }

    /// The scroll area whose visible part counts as "on screen".
    func wyrmAdjustViewport() -> some View {
        background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear
                .onAppear { WyrmAdjustPreview.shared.setViewport(frame) }
                .onChange(of: frame) { WyrmAdjustPreview.shared.setViewport($0) }
        })
    }

    /// The card itself, pinned to the top of the page.
    func wyrmAdjustPreviewCard(engine: WyrmShellStore) -> some View {
        overlay(alignment: .top) { WyrmAdjustPreviewCard(engine: engine) }
    }
}

struct WyrmAdjustPreviewCard: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var store = WyrmAdjustPreview.shared
    @ObservedObject var arrowSkins = WyrmArrowSkinStore.shared

    var body: some View {
        ZStack {
            if let subject = store.subject {
                VStack(spacing: 8) {
                    Text(title(subject)).font(.androidWyrm(9, .bold)).tracking(1.4).foregroundColor(ATheme.quiet)
                    control(subject).frame(minWidth: 150, minHeight: 70)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ATheme.well))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .shadow(color: .black.opacity(ATheme.dark ? 0.45 : 0.16), radius: 18, y: 8)
            }
        }
        .padding(.top, 58)
        .opacity(store.shown ? 1 : 0)
        .scaleEffect(store.shown ? 1 : 0.96, anchor: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func title(_ subject: WyrmAdjustPreview.Subject) -> String {
        switch subject {
        case .arrow: return "ARROW PREVIEW"
        case .joystick: return "JOYSTICK PREVIEW"
        case .boost: return "BOOST PREVIEW"
        case .zoom: return "ZOOM BAR PREVIEW"
        }
    }

    /// The same views, at the same scale, as `WyrmControlsPreview`.
    @ViewBuilder private func control(_ subject: WyrmAdjustPreview.Subject) -> some View {
        let opacity = engine.value("controls.opacity", 1)
        switch subject {
        case .arrow:
            let size = engine.value("arrow.size", 1)
            WyrmArrowGlyph(codeStyle: engine.setting("arrow.style")?.index ?? 0, imageSkin: arrowSkins.skin,
                           colour: engine.setting("arrow.color")?.channels ?? [1, 1, 1, 1],
                           brightness: arrowSkins.brightness)
                .frame(width: 104 * size, height: 74 * size)
                .opacity(min(max(opacity, 0), 1))
        case .joystick:
            WyrmPaperJoystick(diameter: 60 * engine.value("controls.joystick_size", 1), opacity: opacity)
        case .boost:
            WyrmPaperBoost(diameter: 46 * engine.value("controls.boost_size", 1), opacity: opacity)
        case .zoom:
            WyrmPaperZoomBar(length: 102 * engine.value("controls.zoom_length", 1),
                             vertical: engine.setting("controls.zoom_orientation")?.index == 1,
                             opacity: opacity, value: 0.45)
        }
    }
}
