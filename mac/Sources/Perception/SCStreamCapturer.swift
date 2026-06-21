import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

public actor SCStreamCapturer: ScreenStreaming {
    private let parameters: PerceptionParameters
    private let targetDisplayID: UInt32?
    private let sampleQueue: DispatchQueue
    private let ciContext = CIContext()
    private var isRunning = false
    private var stream: SCStream?
    private var output: StreamOutput?
    private var frames: [CapturedFrame] = []

    public init(parameters: PerceptionParameters = .defaults, targetDisplayID: UInt32? = nil) {
        self.parameters = parameters
        self.targetDisplayID = targetDisplayID
        self.sampleQueue = DispatchQueue(label: "ai.spirit.perception.scstream")
    }

    public func start() async throws {
        do {
            let content = try await SCShareableContent.current
            guard let display = selectedDisplay(from: content.displays) else {
                throw CollectorFailure.captureFailed("no shareable display is available")
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)

            let output = StreamOutput(owner: self)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()

            self.output = output
            self.stream = stream
            isRunning = true
        } catch let failure as CollectorFailure {
            throw failure
        } catch {
            throw Self.collectorFailure(from: error)
        }
    }

    public func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        isRunning = false
        stream = nil
        output = nil
        frames.removeAll()
    }

    public func nextFrame() async throws -> CapturedFrame? {
        guard isRunning else {
            return nil
        }
        guard frames.isEmpty == false else {
            return nil
        }
        return frames.removeFirst()
    }

    fileprivate func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return
        }

        let imageData = try? ImageEncoder(parameters: parameters).jpegData(from: cgImage)
        frames.append(
            CapturedFrame(
                id: UUID().uuidString,
                timestamp: Date(),
                width: width,
                height: height,
                displayID: targetDisplayID,
                imageData: imageData
            )
        )
    }

    private func selectedDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        guard displays.isEmpty == false else {
            return nil
        }

        if let targetDisplayID,
           let display = displays.first(where: { $0.displayID == targetDisplayID }) {
            return display
        }

        return displays.first
    }

    private static func collectorFailure(from error: Error) -> CollectorFailure {
        let message = String(describing: error)
        let lowercased = message.lowercased()
        if lowercased.contains("permission") || lowercased.contains("denied") {
            return .permissionDenied(message)
        }
        return .captureFailed(message)
    }
}

private final class StreamOutput: NSObject, SCStreamOutput {
    private let owner: SCStreamCapturer

    init(owner: SCStreamCapturer) {
        self.owner = owner
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else {
            return
        }
        Task {
            await owner.enqueue(sampleBuffer)
        }
    }
}
