import ARKit
import RoomPlan
import SwiftUI

struct RoomPlanCaptureContainer: UIViewControllerRepresentable {
    @ObservedObject var viewModel: RoomPlanCaptureViewModel

    func makeUIViewController(context: Context) -> RoomPlanCaptureViewController {
        RoomPlanCaptureViewController(viewModel: viewModel)
    }

    func updateUIViewController(
        _ controller: RoomPlanCaptureViewController,
        context: Context
    ) {
        controller.handle(
            finishRequest: viewModel.finishRequest,
            cancelRequest: viewModel.cancelRequest
        )
    }

    static func dismantleUIViewController(
        _ controller: RoomPlanCaptureViewController,
        coordinator: Void
    ) {
        controller.stopForDismissal()
    }
}

@MainActor
final class RoomPlanCaptureViewController: UIViewController, @preconcurrency RoomCaptureViewDelegate {
    private let viewModel: RoomPlanCaptureViewModel
    private let captureView = RoomCaptureView(frame: .zero)
    private var hasStarted = false
    private var handledFinishRequest = 0
    private var handledCancelRequest = 0
    private var isFinishing = false

    init(viewModel: RoomPlanCaptureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        captureView.delegate = self
        // This is Apple's built-in live RoomPlan model. Its provisional
        // window/opening appearance is not styleable, but the scan preview is
        // useful enough to keep enabled while capture is active.
        captureView.isModelEnabled = true
        captureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureView)
        NSLayoutConstraint.activate([
            captureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            captureView.topAnchor.constraint(equalTo: view.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    func handle(finishRequest: Int, cancelRequest: Int) {
        startIfNeeded()
        if finishRequest != handledFinishRequest {
            handledFinishRequest = finishRequest
            finishCapture()
        }
        if cancelRequest != handledCancelRequest {
            handledCancelRequest = cancelRequest
            cancelCapture()
        }
    }

    func stopForDismissal() {
        guard hasStarted else { return }
        if isFinishing {
            captureView.captureSession.arSession.pause()
        } else {
            captureView.captureSession.stop(pauseARSession: true)
        }
        hasStarted = false
    }

    private func startIfNeeded() {
        guard view.window != nil, !hasStarted, viewModel.state == .scanning else { return }
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)
        hasStarted = true
        AppDebugLog.write("RoomPlan capture session started")
    }

    private func finishCapture() {
        guard hasStarted, !isFinishing else { return }
        isFinishing = true
        viewModel.processingDidBegin()
        // Keep the AR session alive long enough to archive its world map. That
        // map lets the later walkthrough relocalize into the scan coordinate system.
        captureView.captureSession.stop(pauseARSession: false)
        AppDebugLog.write("RoomPlan capture session stopped for processing")
    }

    private func cancelCapture() {
        guard hasStarted else { return }
        captureView.captureSession.stop(pauseARSession: true)
        hasStarted = false
        AppDebugLog.write("RoomPlan capture session cancelled")
    }

    func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: Error?
    ) -> Bool {
        if let error {
            viewModel.didFail(error)
            return false
        }
        viewModel.processingDidBegin()
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            viewModel.didFail(error)
            return
        }
        captureView.captureSession.arSession.getCurrentWorldMap { [weak self] worldMap, _ in
            Task { @MainActor in
                guard let self else { return }
                self.captureView.captureSession.arSession.pause()
                self.hasStarted = false
                self.viewModel.didCapture(processedResult, worldMap: worldMap)
            }
        }
    }
}
