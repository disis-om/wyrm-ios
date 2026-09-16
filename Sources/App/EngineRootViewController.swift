import Metal
import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class EngineStatusModel: ObservableObject {
    enum State: Equatable {
        case preparing
        case ready
        case failed
    }

    enum GameMode: Equatable {
        case menu
        case playing
        case paused
        case ended
    }

    @Published var state: State = .preparing
    @Published var detail = "Preparing the Apple GPU surface"
    @Published var gameMode: GameMode = .menu
    @Published var score = 0
    var onStart: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
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
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0

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

        status.onStart = { [weak self] in self?.startOfflineGame() }
        status.onPause = { [weak self] in self?.pauseOfflineGame() }
        status.onResume = { [weak self] in self?.resumeOfflineGame() }

        let drag = UIPanGestureRecognizer(target: self, action: #selector(aimAtTouch(_:)))
        drag.cancelsTouchesInView = false
        view.addGestureRecognizer(drag)
        let tap = UITapGestureRecognizer(target: self, action: #selector(aimAtTouch(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
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

        status.detail = "\(String(cString: WyrmEngineStatus())). \(count)/17 original assets verified."
        status.state = .ready

        let link = CADisplayLink(target: self, selector: #selector(drawOfflineFrame(_:)))
        link.preferredFramesPerSecond = 30
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func startOfflineGame() {
        guard status.state == .ready else { return }
        WyrmOfflineReset()
        status.score = 0
        status.gameMode = .playing
        lastFrameTime = 0
        if !WyrmEngineFrame() {
            status.detail = String(cString: WyrmEngineStatus())
            status.state = .failed
            return
        }
        displayLink?.isPaused = false
    }

    private func pauseOfflineGame() {
        guard status.gameMode == .playing else { return }
        status.gameMode = .paused
        displayLink?.isPaused = true
    }

    private func resumeOfflineGame() {
        guard status.gameMode == .paused else { return }
        status.gameMode = .playing
        lastFrameTime = 0
        displayLink?.isPaused = false
    }

    @objc private func aimAtTouch(_ gesture: UIGestureRecognizer) {
        guard status.gameMode == .playing else { return }
        let point = gesture.location(in: engineView)
        guard engineView.bounds.width > 0, engineView.bounds.height > 0 else { return }
        WyrmOfflineAim(Float(point.x / engineView.bounds.width),
                       Float(point.y / engineView.bounds.height))
    }

    @objc private func drawOfflineFrame(_ link: CADisplayLink) {
        guard status.gameMode == .playing else { return }
        let dt = lastFrameTime == 0 ? 1.0 / 30.0 : min(0.05, link.timestamp - lastFrameTime)
        lastFrameTime = link.timestamp
        WyrmOfflineStep(Float(dt))
        if !WyrmEngineFrame() {
            status.detail = String(cString: WyrmEngineStatus())
            status.state = .failed
            displayLink?.isPaused = true
            return
        }
        var snapshot = WyrmOfflineSnapshot()
        WyrmOfflineGetSnapshot(&snapshot)
        if status.score != Int(snapshot.score) { status.score = Int(snapshot.score) }
        if !snapshot.alive {
            status.gameMode = .ended
            displayLink?.isPaused = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pauseOfflineGame()
    }

    deinit {
        displayLink?.invalidate()
        WyrmEngineShutdown()
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
