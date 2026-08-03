import CoreMotion
import Foundation
import PhotosUI
import SwiftUI

enum RoomVideoCaptureState: Equatable {
    case idle
    case preparing
    case ready
    case recording
    case finishing
    case interrupted(String)
    case unavailable(String)
    case simulatorTestInput
}

@MainActor
final class RoomVideoCaptureViewModel: ObservableObject {
    static let maximumDuration: TimeInterval = 90
    static let lowCoverageWarningThreshold = 0.70

    @Published private(set) var state: RoomVideoCaptureState = .idle
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var mockedCoverageProgress = 0.0
    @Published private(set) var guidanceWarning: String?
    @Published var isLowCoverageConfirmationPresented = false
    @Published var errorMessage: String?

    let captureService: RoomVideoCapturing
    let guidance = [
        "Move slowly",
        "Capture every wall",
        "Keep the floor and ceiling edges visible",
        "Walk around large furniture",
        "Avoid motion blur",
        "Return toward your starting view before finishing"
    ]

    var isRecording: Bool {
        state == .recording
    }

    var elapsedTimeText: String {
        let seconds = Int(elapsedTime.rounded(.down))
        return String(format: "%01d:%02d", seconds / 60, seconds % 60)
    }

    var isSimulatorTestMode: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private let motionManager = CMMotionManager()
    private let videoImporter: RoomVideoImporting
    private var timerTask: Task<Void, Never>?
    private var recordingStartDate: Date?
    private var accumulatedMotion = 0.0
    private var lastMotionUpdateDate: Date?
    private var videoReadyHandler: ((RoomScanVideo) -> Void)?

    init(
        captureService: RoomVideoCapturing = AVFoundationRoomVideoCaptureService(),
        videoImporter: RoomVideoImporting = LocalRoomVideoImportService()
    ) {
        self.captureService = captureService
        self.videoImporter = videoImporter

        captureService.onRecordingFinished = { [weak self] result in
            Task { @MainActor in
                self?.handleRecordingResult(result)
            }
        }
        captureService.onInterruptionChanged = { [weak self] interrupted, message in
            Task { @MainActor in
                self?.handleInterruption(interrupted: interrupted, message: message)
            }
        }
    }

    func prepare(onVideoReady: @escaping (RoomScanVideo) -> Void) async {
        videoReadyHandler = onVideoReady
        guard state == .idle else { return }

        if isSimulatorTestMode {
            state = .simulatorTestInput
            return
        }

        state = .preparing
        do {
            try await captureService.prepare()
            state = .ready
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func startRecording() async {
        guard state == .ready else { return }
        errorMessage = nil

        do {
            try await captureService.startRecording()
            elapsedTime = 0
            mockedCoverageProgress = 0
            accumulatedMotion = 0
            recordingStartDate = Date()
            state = .recording
            startMotionUpdates()
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestStopRecording() {
        guard isRecording else { return }
        if mockedCoverageProgress < Self.lowCoverageWarningThreshold {
            isLowCoverageConfirmationPresented = true
        } else {
            finishRecording()
        }
    }

    func finishLowCoverageRecording() {
        guard isRecording else { return }
        isLowCoverageConfirmationPresented = false
        finishRecording()
    }

    func continueScanning() {
        isLowCoverageConfirmationPresented = false
    }

    func cancelRecording() {
        timerTask?.cancel()
        timerTask = nil
        stopMotionUpdates()
        captureService.cancelRecording()
        state = isSimulatorTestMode ? .simulatorTestInput : .ready
        elapsedTime = 0
        mockedCoverageProgress = 0
        isLowCoverageConfirmationPresented = false
    }

    func stopSession() {
        timerTask?.cancel()
        timerTask = nil
        stopMotionUpdates()
        captureService.stopSession()
        videoReadyHandler = nil
    }

    func handleBackgrounding() {
        guard isRecording else {
            captureService.stopSession()
            return
        }
        // A file recording cannot be paused safely, so preserve the completed portion.
        finishRecording()
    }

    func resumeAfterBackgrounding() async {
        guard !isSimulatorTestMode, !isRecording else { return }
        do {
            try await captureService.prepare()
            state = .ready
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func acceptSimulatorVideo(_ video: RoomScanVideo) {
        guard isSimulatorTestMode else { return }
        deliver(video)
    }

    func importSimulatorVideo(from item: PhotosPickerItem) async {
        guard isSimulatorTestMode else { return }
        do {
            let video = try await videoImporter.importVideo(from: item)
            deliver(video)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    return
                }
                guard let self, let startDate = self.recordingStartDate else { return }
                self.elapsedTime = min(Date().timeIntervalSince(startDate), Self.maximumDuration)
                self.updateMockedCoverage()
                self.updateGuidanceWarning()

                if self.elapsedTime >= Self.maximumDuration {
                    self.finishRecording()
                    return
                }
            }
        }
    }

    private func finishRecording() {
        timerTask?.cancel()
        timerTask = nil
        stopMotionUpdates()
        state = .finishing
        isLowCoverageConfirmationPresented = false
        captureService.stopRecording()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        lastMotionUpdateDate = Date()
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor in
                self?.consume(motion)
            }
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        lastMotionUpdateDate = nil
        guidanceWarning = nil
    }

    private func consume(_ motion: CMDeviceMotion) {
        let now = Date()
        let delta = min(now.timeIntervalSince(lastMotionUpdateDate ?? now), 0.25)
        lastMotionUpdateDate = now

        let rotation = motion.rotationRate
        let rotationMagnitude = sqrt(
            rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z
        )
        accumulatedMotion += min(rotationMagnitude, 1.5) * delta

        let acceleration = motion.userAcceleration
        let accelerationMagnitude = sqrt(
            acceleration.x * acceleration.x
                + acceleration.y * acceleration.y
                + acceleration.z * acceleration.z
        )

        if rotationMagnitude > 2.2 {
            guidanceWarning = "Moving too fast"
        } else if accelerationMagnitude > 0.24 {
            guidanceWarning = "Hold the phone more steadily"
        } else if guidanceWarning == "Moving too fast"
                    || guidanceWarning == "Hold the phone more steadily" {
            guidanceWarning = nil
        }
    }

    private func updateMockedCoverage() {
        let timeContribution = min(elapsedTime / 65, 1) * 0.72
        let motionContribution = min(accumulatedMotion / 30, 1) * 0.23
        mockedCoverageProgress = min(timeContribution + motionContribution, 0.95)
    }

    private func updateGuidanceWarning() {
        if captureService.isSceneLikelyDark {
            guidanceWarning = "Scene may be too dark"
        } else if guidanceWarning == "Scene may be too dark" {
            guidanceWarning = nil
        }
    }

    private func handleRecordingResult(_ result: Result<RoomScanVideo, Error>) {
        switch result {
        case let .success(video):
            state = .ready
            deliver(video)
        case let .failure(error):
            state = .ready
            errorMessage = error.localizedDescription
        }
    }

    private func handleInterruption(interrupted: Bool, message: String?) {
        if interrupted {
            if isRecording {
                finishRecording()
            }
            state = .interrupted(message ?? "The camera session was interrupted.")
        } else if !isRecording {
            state = .ready
        }
    }

    private func deliver(_ video: RoomScanVideo) {
        let handler = videoReadyHandler
        videoReadyHandler = nil
        handler?(video)
    }
}
