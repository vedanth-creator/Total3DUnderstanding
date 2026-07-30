import AVFoundation
import Foundation

final class AVFoundationRoomVideoCaptureService: NSObject, RoomVideoCapturing, @unchecked Sendable {
    let captureSession = AVCaptureSession()

    var onRecordingFinished: ((Result<RoomScanVideo, Error>) -> Void)?
    var onInterruptionChanged: ((Bool, String?) -> Void)?

    var isSceneLikelyDark: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sceneLikelyDark
    }

    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.canvas.room-video-capture.session")
    private let sampleQueue = DispatchQueue(label: "com.canvas.room-video-capture.samples")
    private let stateLock = NSLock()

    private var isConfigured = false
    private var discardCurrentRecording = false
    private var currentRecordingURL: URL?
    private var sceneLikelyDark = false
    private var sampledFrameCount = 0
    private var notificationTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        registerForSessionNotifications()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func prepare() async throws {
        guard await requestCameraAccessIfNeeded() else {
            throw RoomVideoCaptureServiceError.cameraPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: RoomVideoCaptureServiceError.configurationFailed)
                    return
                }

                do {
                    if !self.isConfigured {
                        try self.configureSession()
                    }
                    if !self.captureSession.isRunning {
                        self.captureSession.startRunning()
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self, self.isConfigured, self.captureSession.isRunning else {
                    continuation.resume(throwing: RoomVideoCaptureServiceError.configurationFailed)
                    return
                }
                guard !self.movieOutput.isRecording else {
                    continuation.resume(returning: ())
                    return
                }

                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("room-scan-\(UUID().uuidString)")
                    .appendingPathExtension("mov")
                self.currentRecordingURL = url
                self.discardCurrentRecording = false
                self.movieOutput.maxRecordedDuration = CMTime(seconds: 90, preferredTimescale: 600)

                if let connection = self.movieOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }

                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                continuation.resume(returning: ())
            }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    func cancelRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.discardCurrentRecording = true
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else if let url = self.currentRecordingURL {
                try? FileManager.default.removeItem(at: url)
                self.currentRecordingURL = nil
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    private func requestCameraAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .high

        guard let rearCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw RoomVideoCaptureServiceError.cameraUnavailable
        }

        let cameraInput = try AVCaptureDeviceInput(device: rearCamera)
        guard captureSession.canAddInput(cameraInput) else {
            throw RoomVideoCaptureServiceError.configurationFailed
        }
        captureSession.addInput(cameraInput)

        guard captureSession.canAddOutput(movieOutput) else {
            throw RoomVideoCaptureServiceError.configurationFailed
        }
        captureSession.addOutput(movieOutput)

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }

        isConfigured = true
    }

    private func registerForSessionNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: captureSession,
                queue: .main
            ) { [weak self] notification in
                let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)
                    .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
                self?.onInterruptionChanged?(true, Self.message(for: reason))
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: captureSession,
                queue: .main
            ) { [weak self] _ in
                self?.onInterruptionChanged?(false, nil)
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: captureSession,
                queue: .main
            ) { [weak self] _ in
                self?.onInterruptionChanged?(true, "The camera session stopped unexpectedly.")
            }
        )
    }

    private static func message(for reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceInUseByAnotherClient:
            "The camera is being used by another app."
        case .videoDeviceNotAvailableInBackground:
            "Recording stopped because the app entered the background."
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            "The camera is unavailable while multiple apps are active."
        default:
            "The camera session was interrupted."
        }
    }
}

extension AVFoundationRoomVideoCaptureService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let shouldDiscard = discardCurrentRecording
        discardCurrentRecording = false
        currentRecordingURL = nil

        if shouldDiscard {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        let recordingFinishedSuccessfully = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        if !recordingFinishedSuccessfully, let error {
            try? FileManager.default.removeItem(at: outputFileURL)
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingFinished?(.failure(error))
            }
            return
        }

        Task {
            do {
                let video = try await RoomScanVideo.inspect(
                    localFileURL: outputFileURL,
                    source: .recorded
                )
                await MainActor.run { [weak self] in
                    self?.onRecordingFinished?(.success(video))
                }
            } catch {
                try? FileManager.default.removeItem(at: outputFileURL)
                await MainActor.run { [weak self] in
                    self?.onRecordingFinished?(.failure(error))
                }
            }
        }
    }
}

extension AVFoundationRoomVideoCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        sampledFrameCount += 1
        guard sampledFrameCount.isMultiple(of: 15),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let luma = baseAddress.assumingMemoryBound(to: UInt8.self)
        let samplingStride = 32
        var total = 0
        var count = 0

        for row in Swift.stride(from: 0, to: height, by: samplingStride) {
            for column in Swift.stride(from: 0, to: width, by: samplingStride) {
                total += Int(luma[row * bytesPerRow + column])
                count += 1
            }
        }

        guard count > 0 else { return }
        stateLock.lock()
        sceneLikelyDark = (total / count) < 48
        stateLock.unlock()
    }
}
