import Metal
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class EngineStatusModel: ObservableObject {
    enum State {
        case preparing
        case ready
        case failed
    }

    @Published var state: State = .preparing
    @Published var detail = "Preparing the Apple GPU surface"
}

final class EngineMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer {
        guard let layer = layer as? CAMetalLayer else {
            preconditionFailure("EngineMetalView must own a CAMetalLayer")
        }
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = UIColor(red: 0.047, green: 0.055, blue: 0.051, alpha: 1)
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = UIScreen.main.scale
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

final class EngineRootViewController: UIViewController {
    private let engineView = EngineMetalView(frame: .zero)
    private let status = EngineStatusModel()
    private var didStartEngine = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        engineView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(engineView)
        NSLayoutConstraint.activate([
            engineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            engineView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            engineView.topAnchor.constraint(equalTo: view.topAnchor),
            engineView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let overlay = UIHostingController(rootView: PhaseOneOverlayView(status: status))
        overlay.view.backgroundColor = .clear
        overlay.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(overlay)
        view.addSubview(overlay.view)
        NSLayoutConstraint.activate([
            overlay.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.view.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        overlay.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartEngine else { return }
        didStartEngine = true

        view.layoutIfNeeded()
        engineView.layoutIfNeeded()

        let count: Int
        do {
            count = try EngineAssetBundle.verify()
        } catch {
            status.detail = error.localizedDescription
            status.state = .failed
            return
        }

        let started = WyrmEngineBootstrap(engineView.metalLayer)
        guard started else {
            status.detail = String(cString: WyrmEngineStatus())
            status.state = .failed
            return
        }

        status.detail = "\(String(cString: WyrmEngineStatus())). \(count)/17 original assets verified. Full engine integration is next."
        status.state = .ready
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
