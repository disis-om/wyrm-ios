import SwiftUI
import UIKit
import ObjectiveC
import Combine

/*
 * Wyrm's own keyboard.
 *
 * The app stays portrait while the Ready Room is drawn sideways, so the system
 * keyboard would always rise from the phone's portrait bottom — sideways to a
 * player holding it landscape. Wyrm therefore draws its own keyboard, laid out
 * like the system one, everywhere.
 *
 * It is not a copy of the system keys: it is drawn in the Wyrm paper
 * language — card keys with a hairline, Manrope labels, an ink action key —
 * and follows the chosen theme.
 *
 * It is installed as the `inputView` of every UITextField and UITextView (that
 * is what SwiftUI's TextField, SecureField and vertical TextField are built
 * on), so focus, submit, secure entry and keyboard avoidance keep working
 * unchanged. In the Ready Room the input view is empty and the same keyboard
 * is drawn inside the landscape canvas instead.
 */

final class WyrmKeyboardController: ObservableObject {
    static let shared = WyrmKeyboardController()

    enum Layout { case letters, numbers, symbols, digits }
    enum Shift { case off, once, locked }

    /// The field being typed into. UITextField and UITextView both conform.
    private(set) weak var target: (UIResponder & UITextInput)?
    @Published private(set) var focused = false
    @Published var layout: Layout = .letters
    @Published var shift: Shift = .off
    /// Set while the Ready Room is on screen: keys are drawn in its canvas.
    @Published var embedded = false
    /// The gear key swaps the keys for size and transparency controls.
    @Published var showingSettings = false
    /// 0.8…1.3 of the standard key size; kept on the device.
    @Published private(set) var scale: Double
    /// 0.4…1.0; kept on the device.
    @Published private(set) var opacity: Double
    /// Where the landscape keyboard was dragged to, from its resting spot.
    @Published private(set) var landscapeOffset: CGSize

    init() {
        let defaults = UserDefaults.standard
        scale = min(1.3, max(0.8, defaults.object(forKey: "wyrm.ios.keyboard.scale") as? Double ?? 1))
        opacity = min(1, max(0.4, defaults.object(forKey: "wyrm.ios.keyboard.opacity") as? Double ?? 1))
        landscapeOffset = CGSize(width: defaults.double(forKey: "wyrm.ios.keyboard.offset-x"),
                                 height: defaults.double(forKey: "wyrm.ios.keyboard.offset-y"))
    }

    func setScale(_ value: Double) {
        scale = min(1.3, max(0.8, (value * 20).rounded() / 20))
        UserDefaults.standard.set(scale, forKey: "wyrm.ios.keyboard.scale")
    }

    func setOpacity(_ value: Double) {
        opacity = min(1, max(0.4, value))
        UserDefaults.standard.set(opacity, forKey: "wyrm.ios.keyboard.opacity")
    }

    func setLandscapeOffset(_ value: CGSize) {
        landscapeOffset = value
        UserDefaults.standard.set(Double(value.width), forKey: "wyrm.ios.keyboard.offset-x")
        UserDefaults.standard.set(Double(value.height), forKey: "wyrm.ios.keyboard.offset-y")
    }

    func resetLook() {
        setScale(1)
        setOpacity(1)
        setLandscapeOffset(.zero)
    }

    /// Height of the key area for a layout at the current size.
    func keysHeight(compact: Bool) -> CGFloat {
        let key = (compact ? 36.0 : 44.0) * scale
        let gap = (compact ? 8.0 : 11.0) * scale
        return CGFloat(4 * key + 3 * gap + (compact ? 12 : 16))
    }

    private var observers: [NSObjectProtocol] = []
    private var installed = false
    let placeholder: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        view.autoresizingMask = []
        return view
    }()

    var returnTitle: String {
        switch (target as? UITextInputTraits)?.returnKeyType ?? .default {
        case .done: return "done"
        case .send: return "send"
        case .go, .join: return "go"
        case .search: return "search"
        case .next: return "next"
        default: return "return"
        }
    }

    var returnIsAction: Bool { returnTitle != "return" }
    var wantsEmail: Bool { (target as? UITextInputTraits)?.keyboardType == .emailAddress }

    // MARK: Installation

    func install() {
        guard !installed else { return }
        installed = true
        Self.swizzle(UITextField.self, #selector(getter: UITextField.inputView), #selector(UITextField.wyrm_inputView))
        Self.swizzle(UITextView.self, #selector(getter: UITextView.inputView), #selector(UITextView.wyrm_inputView))
        let center = NotificationCenter.default
        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let field = note.object as? (UIResponder & UITextInput) else { return }
                self?.begin(field)
            })
        }
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let field = note.object as AnyObject?, field === self.target else { return }
                self.target = nil
                self.focused = false
            })
        }
    }

    /// Adds the replacement to the class itself first, so a getter it only
    /// inherits from UIResponder is never exchanged for every responder.
    private static func swizzle(_ type: AnyClass, _ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(type, original),
              let replacementMethod = class_getInstanceMethod(type, replacement) else { return }
        if class_addMethod(type, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod)) {
            class_replaceMethod(type, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }

    private func begin(_ field: UIResponder & UITextInput) {
        target = field
        let traits = field as? UITextInputTraits
        switch traits?.keyboardType ?? .default {
        case .numberPad, .phonePad, .asciiCapableNumberPad: layout = .digits
        case .numbersAndPunctuation, .decimalPad: layout = .numbers
        default: layout = .letters
        }
        shift = (traits?.autocapitalizationType ?? .sentences) == UITextAutocapitalizationType.none ? .off : autoShift()
        focused = true
    }

    /// The view UIKit shows in place of the system keyboard for this field.
    func inputView(for field: UIResponder) -> UIView {
        if embedded { return placeholder }
        if let cached = objc_getAssociatedObject(field, &Self.hostKey) as? WyrmKeyboardHostView { return cached }
        let host = WyrmKeyboardHostView()
        objc_setAssociatedObject(field, &Self.hostKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return host
    }
    private static var hostKey = 0

    // MARK: Typing

    func insert(_ text: String) {
        guard let target else { return }
        let value = shift == .off ? text : text.uppercased()
        target.insertText(value)
        if shift == .once { shift = .off }
        if text == " " || text == "." { refreshAutoShift() }
    }

    func deleteBackward() {
        target?.deleteBackward()
        refreshAutoShift()
    }

    func returnKey() {
        if let field = target as? UITextField {
            if field.delegate?.textFieldShouldReturn?(field) ?? true { field.sendActions(for: .editingDidEndOnExit) }
        } else {
            target?.insertText("\n")
        }
    }

    func toggleShift(doubleTap: Bool) {
        if doubleTap { shift = .locked; return }
        shift = shift == .off ? .once : .off
    }

    func dismiss() { target?.resignFirstResponder() }

    private func autoShift() -> Shift {
        guard let target, let range = target.textRange(from: target.beginningOfDocument, to: target.selectedTextRange?.start ?? target.endOfDocument),
              let before = target.text(in: range) else { return .once }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") ? .once : .off
    }

    private func refreshAutoShift() {
        guard shift != .locked, layout == .letters,
              (target as? UITextInputTraits)?.autocapitalizationType != UITextAutocapitalizationType.none else { return }
        shift = autoShift()
    }
}

extension UITextField {
    @objc func wyrm_inputView() -> UIView? {
        // After swizzling this name holds the original getter.
        if let own = wyrm_inputView() { return own }
        return WyrmKeyboardController.shared.inputView(for: self)
    }
}

extension UITextView {
    @objc func wyrm_inputView() -> UIView? {
        if let own = wyrm_inputView() { return own }
        guard isEditable else { return nil }
        return WyrmKeyboardController.shared.inputView(for: self)
    }
}

/// The UIKit container UIKit slides up. It enables the system key click.
final class WyrmKeyboardHostView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
    private let host: UIHostingController<WyrmKeyboardView>
    private var height: NSLayoutConstraint!
    private var sizing: AnyCancellable?

    init() {
        host = UIHostingController(rootView: WyrmKeyboardView(compact: false))
        let controller = WyrmKeyboardController.shared
        let bottom = WyrmLandscapeStage<EmptyView>.windowInsets.bottom
        let initial = controller.keysHeight(compact: false) + bottom
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: initial),
                   inputViewStyle: .default)
        allowsSelfSizing = true
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        height = heightAnchor.constraint(equalToConstant: initial)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            height,
        ])
        // A new size re-seats the input view, and the page above it follows.
        sizing = controller.$scale.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.height.constant = controller.keysHeight(compact: false) + bottom
            controller.target?.reloadInputViews()
        }
    }

    required init?(coder: NSCoder) { nil }
}

// MARK: - Drawing

/// The keyboard itself: the familiar key positions, drawn as Wyrm paper and
/// ink. `compact` is the shorter landscape version for the Ready Room.
struct WyrmKeyboardView: View {
    @ObservedObject var controller = WyrmKeyboardController.shared
    @ObservedObject var theme = WyrmThemeStore.shared
    let compact: Bool

    private var rows: [[String]] {
        switch controller.layout {
        case .letters: return [Array("qwertyuiop").map(String.init), Array("asdfghjkl").map(String.init), Array("zxcvbnm").map(String.init)]
        case .numbers: return [Array("1234567890").map(String.init), ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], [".", ",", "?", "!", "'"]]
        case .symbols: return [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"], [".", ",", "?", "!", "'"]]
        case .digits: return [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        }
    }

    var body: some View {
        let keyHeight = CGFloat((compact ? 36.0 : 44.0) * controller.scale)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                if controller.showingSettings {
                    WyrmKeyboardSettings(controller: controller)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)
                } else {
                    keys(width: proxy.size.width, keyHeight: keyHeight)
                        .transition(.opacity)
                }
            }
            .frame(height: controller.keysHeight(compact: compact))
            if compact { knob }
        }
        .padding(.bottom, compact ? 2 : WyrmLandscapeStage<EmptyView>.windowInsets.bottom)
        .background(keyboardBackground.opacity(controller.opacity).ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 0, style: .continuous))
        .opacity(0.35 + 0.65 * controller.opacity)
        .animation(.easeInOut(duration: 0.2), value: controller.showingSettings)
        .id(theme.identity)
    }

    /// Landscape only: a grab handle on the bottom edge to move the keyboard.
    private var knob: some View {
        Capsule().fill(ATheme.ink.opacity(0.35)).frame(width: 44, height: 5)
            .frame(maxWidth: .infinity).frame(height: 18)
            .contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if dragStart == nil { dragStart = controller.landscapeOffset }
                    let start = dragStart ?? .zero
                    // The canvas is turned a quarter; its x runs down the screen.
                    controller.setLandscapeOffset(CGSize(width: start.width + value.translation.height,
                                                         height: start.height - value.translation.width))
                }
                .onEnded { _ in dragStart = nil })
            .accessibilityLabel("Move keyboard")
    }
    @State var dragStart: CGSize? = nil

    private func keys(width fullWidth: CGFloat, keyHeight: CGFloat) -> some View {
            let width = fullWidth - 6
            let unit = controller.layout == .digits ? width / 3 : width / 10
            return VStack(spacing: CGFloat((compact ? 8.0 : 11.0) * controller.scale)) {
                if controller.layout == .digits {
                    ForEach(rows, id: \.self) { row in keyRow(row, unit: unit, height: keyHeight) }
                    HStack(spacing: 0) {
                        WyrmSpecialKey(symbol: "gearshape", width: unit, height: keyHeight) { controller.showingSettings = true }
                        WyrmKey(label: "0", width: unit, height: keyHeight) { controller.insert("0") }
                        WyrmSpecialKey(symbol: "delete.left", width: unit, height: keyHeight, repeats: true) { controller.deleteBackward() }
                    }
                } else {
                    keyRow(rows[0], unit: unit, height: keyHeight)
                    keyRow(rows[1], unit: unit, height: keyHeight)
                    HStack(spacing: 0) {
                        if controller.layout == .letters {
                            WyrmSpecialKey(symbol: controller.shift == .locked ? "capslock.fill" : (controller.shift == .once ? "shift.fill" : "shift"),
                                           width: unit * 1.45, height: keyHeight, highlighted: controller.shift != .off,
                                           onDoubleTap: { controller.toggleShift(doubleTap: true) }) { controller.toggleShift(doubleTap: false) }
                        } else {
                            WyrmSpecialKey(text: controller.layout == .numbers ? "#+=" : "123", width: unit * 1.45, height: keyHeight) {
                                controller.layout = controller.layout == .numbers ? .symbols : .numbers
                            }
                        }
                        Spacer(minLength: unit * 0.1)
                        ForEach(rows[2], id: \.self) { key in
                            WyrmKey(label: display(key), width: controller.layout == .letters ? unit : unit * 1.4, height: keyHeight) { controller.insert(key) }
                        }
                        Spacer(minLength: unit * 0.1)
                        WyrmSpecialKey(symbol: "delete.left", width: unit * 1.45, height: keyHeight, repeats: true) { controller.deleteBackward() }
                    }
                    HStack(spacing: 0) {
                        WyrmSpecialKey(text: controller.layout == .letters ? "123" : "ABC", width: unit * 1.3, height: keyHeight) {
                            controller.layout = controller.layout == .letters ? .numbers : .letters
                        }
                        WyrmSpecialKey(symbol: "gearshape", width: unit, height: keyHeight) { controller.showingSettings = true }
                        if controller.wantsEmail {
                            WyrmKey(label: "@", width: unit, height: keyHeight) { controller.insert("@") }
                            WyrmKey(label: "space", width: unit * 2.9, height: keyHeight, small: true) { controller.insert(" ") }
                            WyrmKey(label: ".", width: unit, height: keyHeight) { controller.insert(".") }
                        } else {
                            WyrmKey(label: "space", width: unit * 4.9, height: keyHeight, small: true) { controller.insert(" ") }
                        }
                        WyrmSpecialKey(text: controller.returnTitle, width: unit * 2.8, height: keyHeight,
                                       highlighted: controller.returnIsAction, accent: controller.returnIsAction) { controller.returnKey() }
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.top, compact ? 6 : 8)
            .frame(width: fullWidth, alignment: .top)
    }

    private var keyboardBackground: some View {
        ZStack(alignment: .top) {
            ATheme.paper
            LinearGradient(colors: [ATheme.well, ATheme.paper], startPoint: .top, endPoint: .bottom).opacity(0.7)
            Rectangle().fill(ATheme.rule).frame(height: 1)
        }
    }

    private func display(_ key: String) -> String {
        guard controller.layout == .letters, controller.shift != .off else { return key }
        return key.uppercased()
    }

    private func keyRow(_ keys: [String], unit: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(keys, id: \.self) { key in
                WyrmKey(label: controller.layout == .digits ? key : display(key), width: unit, height: height) { controller.insert(key) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A character key: rises into a pop-up bubble under the finger like the
/// system key, clicks and taps a light haptic.
struct WyrmKey: View {
    let label: String
    let width: CGFloat
    let height: CGFloat
    var small = false
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(pressed ? ATheme.well : ATheme.card)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .shadow(color: ATheme.ink.opacity(0.07), radius: 1, y: 1)
            Text(small ? label.uppercased() : label)
                .font(small ? .androidWyrm(11, .bold) : .androidWyrm(height > 40 ? 21 : 18, .semibold))
                .tracking(small ? 1.4 : 0)
                .foregroundColor(small ? ATheme.quiet : ATheme.ink)
        }
        .frame(width: max(width - 6, 10), height: height)
        .scaleEffect(pressed && small ? 0.97 : 1)
        .overlay(alignment: .bottom) {
            if pressed && !small {
                WyrmKeyPopup(label: label, width: width, height: height).offset(y: -height * 0.62).allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                UIDevice.current.playInputClick()
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
            }
            .onEnded { _ in
                pressed = false
                action()
            })
        .zIndex(pressed ? 5 : 0)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isKeyboardKey)
    }
}

struct WyrmKeyPopup: View {
    let label: String
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        Text(label).font(.androidWyrm(30, .bold)).foregroundColor(ATheme.ink)
            .frame(width: max(width + 12, 48), height: height * 1.3)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ATheme.card)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .shadow(color: ATheme.ink.opacity(0.18), radius: 8, y: 3))
            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
    }
}

/// Shift, delete, mode switches and return. Delete repeats while held.
struct WyrmSpecialKey: View {
    var symbol: String? = nil
    var text: String? = nil
    let width: CGFloat
    let height: CGFloat
    var highlighted = false
    var accent = false
    var repeats = false
    var onDoubleTap: (() -> Void)? = nil
    let action: () -> Void
    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var lastTap = Date.distantPast

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ATheme.rule, lineWidth: inked ? 0 : 1))
                .shadow(color: ATheme.ink.opacity(0.07), radius: 1, y: 1)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            } else if let text {
                Text(text.count > 3 ? text.uppercased() : text).font(.androidWyrm(text.count > 3 ? 11 : 14, .bold))
                    .tracking(text.count > 3 ? 1 : 0)
            }
        }
        .foregroundColor(inked ? ATheme.onInk : ATheme.ink)
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
        .frame(width: max(width - 6, 10), height: height)
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                UIDevice.current.playInputClick()
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                if repeats {
                    action()
                    repeatTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        while !Task.isCancelled {
                            action()
                            try? await Task.sleep(nanoseconds: 85_000_000)
                        }
                    }
                }
            }
            .onEnded { _ in
                pressed = false
                repeatTask?.cancel()
                repeatTask = nil
                guard !repeats else { return }
                let now = Date()
                if let onDoubleTap, now.timeIntervalSince(lastTap) < 0.3 { onDoubleTap() } else { action() }
                lastTap = now
            })
        .accessibilityLabel(text ?? symbol ?? "key")
        .accessibilityAddTraits(.isKeyboardKey)
    }

    /// The action key and a latched shift wear ink, like Wyrm's primary buttons.
    private var inked: Bool { accent || highlighted }

    private var fill: Color {
        if inked { return pressed ? ATheme.ink.opacity(0.82) : ATheme.ink }
        return pressed ? ATheme.card : ATheme.well
    }
}

/// The gear panel: in place of the keys, size steps and transparency.
struct WyrmKeyboardSettings: View {
    @ObservedObject var controller: WyrmKeyboardController

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("KEYBOARD").font(.androidWyrm(11, .bold)).tracking(1.4).foregroundColor(ATheme.quiet)
                Spacer()
                Button("Reset") { withAnimation { controller.resetLook() } }
                    .font(.androidWyrm(12.5, .semibold)).foregroundColor(ATheme.link)
                Button { controller.showingSettings = false } label: {
                    Text("Done").font(.androidWyrm(13, .bold)).foregroundColor(ATheme.onInk)
                        .padding(.horizontal, 16).frame(height: 32).background(Capsule().fill(ATheme.ink))
                }.buttonStyle(WSPressStyle()).padding(.leading, 10)
            }
            HStack(spacing: 12) {
                Text("Size").font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.ink)
                Spacer()
                step("minus", enabled: controller.scale > 0.8) { controller.setScale(controller.scale - 0.05) }
                Text("\(Int((controller.scale * 100).rounded()))%").font(.androidWyrm(14, .bold)).monospacedDigit()
                    .foregroundColor(ATheme.ink).frame(width: 54)
                step("plus", enabled: controller.scale < 1.3) { controller.setScale(controller.scale + 0.05) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Transparency").font(.androidWyrm(14, .semibold)).foregroundColor(ATheme.ink)
                    Spacer()
                    Text("\(Int(((1 - controller.opacity) * 100).rounded()))%").font(.androidWyrm(13, .bold)).monospacedDigit()
                        .foregroundColor(ATheme.mute)
                }
                Slider(value: Binding(get: { 1 - controller.opacity }, set: { controller.setOpacity(1 - $0) }), in: 0...0.6)
                    .tint(ATheme.ink)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundColor(ATheme.ink)
                .frame(width: 40, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
        }
        .buttonStyle(WSPressStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}
