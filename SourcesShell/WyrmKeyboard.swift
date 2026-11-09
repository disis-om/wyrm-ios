import SwiftUI
import UIKit

/// Observes Apple's keyboard and editing focus. Does not replace inputView,
/// swizzle responders, draw keys or persist keyboard appearance preferences.
final class WyrmKeyboardController: ObservableObject {
    static let shared = WyrmKeyboardController()
    @Published private(set) var focused = false
    @Published private(set) var keysTop: CGFloat?
    @Published private(set) var occlusion: CGFloat = 0
    @Published private(set) var animationDuration = 0.25
    private weak var target: UIView?
    private var observers: [NSObjectProtocol] = []
    private var installed = false
    private var dismissing = false

    func install() {
        guard !installed else { return }; installed = true
        WyrmInternalKeyboardController.shared.install()
        let center = NotificationCenter.default
        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let field = note.object as? UIView else { return }
                self?.dismissing = false
                self?.target = field; self?.focused = true
            })
        }
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let field = note.object as? UIView, field === self.target else { return }
                self.target = nil; self.focused = false
            })
        }
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] in self?.update($0) })
        }
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            if !WyrmIOSInternalRotationActive() { self?.setOverlap(nil, bounds: .zero) }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setOverlap(nil, bounds: .zero)
        })
    }

    /// Called before a route/overlay animation removes its editing field.
    func dismiss() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.dismiss() }; return }
        dismissing = true
        let field = target
        target = nil; focused = false
        setOverlap(nil, bounds: .zero)
        WyrmInternalKeyboardController.shared.dismiss()
        field?.resignFirstResponder()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            where scene.activationState == .foregroundActive {
            for window in scene.windows { window.endEditing(true) }
        }
    }

    func setInternalKeyboardHeight(_ height: CGFloat, canvasHeight: CGFloat? = nil) {
        let value = !dismissing && WyrmIOSInternalRotationActive() && height.isFinite ? max(0, height) : 0
        keysTop = value > 0 ? canvasHeight.map { max(0, $0 - value) } : nil
        occlusion = value
        WyrmIOSSetKeyboardOcclusion(Double(value))
    }
    private func update(_ note: Notification) {
        if WyrmIOSInternalRotationActive() || dismissing { return }
        guard let info = note.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let window = target?.window ?? Self.keyWindow else { return }
        let screen = (note.object as? UIScreen) ?? window.screen
        guard screen === window.screen else { return }
        if let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double, duration.isFinite {
            animationDuration = min(max(duration, 0), 1)
        }
        // Apple's notification frame is in this screen's current orientation.
        // Convert before intersecting: UIKit owns the actual landscape window.
        let local = window.convert(frame, from: screen.coordinateSpace)
        setOverlap(WyrmKeyboardGeometry.dockedOverlap(local, in: window.bounds), bounds: window.bounds)
    }
    private func setOverlap(_ frame: CGRect?, bounds: CGRect) {
        let next = frame.map { max(0, bounds.maxY - $0.minY) } ?? 0
        let top = frame?.minY
        guard top != keysTop || abs(next - occlusion) > 0.5 else { return }
        keysTop = top; occlusion = next
        WyrmIOSSetKeyboardOcclusion(Double(next))
    }
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

/// Native interactive dismissal plus a downward swipe for embedded keys/iOS15.
struct WyrmDismissKeyboardOnScroll: ViewModifier {
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    func body(content: Content) -> some View {
        interactive(content).simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
            if keyboard.focused && value.translation.height > 36 &&
                value.translation.height > abs(value.translation.width) * 1.5 {
                keyboard.dismiss()
            }
        })
    }
    @ViewBuilder private func interactive(_ content: Content) -> some View {
        if #available(iOS 16.0, *) { content.scrollDismissesKeyboard(.interactively) }
        else { content }
    }
}

/// Fallback for custom bottom docks. SwiftUI's native keyboard-safe layout
/// already avoids the keys; only a measured residual overlap adds padding.
struct WyrmAboveKeys: ViewModifier {
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    @State private var bottom: CGFloat = 0
    func body(content: Content) -> some View {
        let lift = WyrmKeyboardGeometry.lift(bottom: bottom, keysTop: keyboard.keysTop,
                                             occlusion: keyboard.occlusion, focused: keyboard.focused)
        content.padding(.bottom, lift)
            .animation(.easeOut(duration: keyboard.animationDuration), value: lift)
            .background(GeometryReader { proxy in
                let edge = proxy.frame(in: .global).maxY
                Color.clear.onAppear { bottom = edge }.onChange(of: edge) { bottom = $0 }
            })
    }
}

/// Smoke evidence measures actual UIKit rectangles after SwiftUI placement,
/// instead of treating focus or a successful build as visibility proof.
struct WyrmKeyboardLayoutProbe: UIViewRepresentable {
    let kind: String
    final class Probe: UIView {
        var kind = ""
        private var last = ""
        override func layoutSubviews() { super.layoutSubviews(); report() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { reportAfterLayout(attempts: 20) }
        }
        private func reportAfterLayout(attempts: Int) {
            guard ProcessInfo.processInfo.arguments.contains("--smoke-internal-rotation"),
                  window != nil, attempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, self.window != nil else { return }
                self.report()
                self.reportAfterLayout(attempts: attempts - 1)
            }
        }
        private func hostingView(in controller: UIViewController) -> UIView? {
            if controller is WyrmShellHostingController,
               isDescendant(of: controller.view) { return controller.view }
            if let presented = controller.presentedViewController,
               let host = hostingView(in: presented) { return host }
            for child in controller.children {
                if let host = hostingView(in: child) { return host }
            }
            return nil
        }
        func report() {
            guard ProcessInfo.processInfo.arguments.contains("--smoke-internal-rotation"),
                  window != nil, WyrmIOSInternalRotationActive() else { return }
            guard let controller = window?.rootViewController,
                  let root = hostingView(in: controller),
                  bounds.width > 0, bounds.height > 0 else { return }
            let rect = convert(bounds, to: root)
            let canvas = root.bounds
            let valid = rect.minX >= -1 && rect.minY >= -1 &&
                rect.maxX <= canvas.maxX + 1 && rect.maxY <= canvas.maxY + 1
            let line = String(format: "Wyrm internal layout kind=%@ canvas=%.1f,%.1f rect=%.1f,%.1f,%.1f,%.1f visible=%d", kind,
                canvas.width, canvas.height, rect.minX, rect.minY, rect.width, rect.height, valid ? 1 : 0)
            if line != last { last = line; NSLog("%@", line) }
        }
    }
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.kind = kind; view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ view: Probe, context: Context) { view.kind = kind; DispatchQueue.main.async { view.report() } }
}
