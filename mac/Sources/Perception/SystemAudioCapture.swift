import CoreMedia
import Foundation
import ScreenCaptureKit

public actor SystemAudioCapture: SystemAudioCapturing {
    private let targetDisplayID: UInt32?
    private let sampleQueue: DispatchQueue
    private var isRunning = false
    private var stream: SCStream?
    private var output: AudioStreamOutput?
    private var chunks: [AudioChunk] = []

    public init(targetDisplayID: UInt32? = nil) {
        self.targetDisplayID = targetDisplayID
        self.sampleQueue = DispatchQueue(label: "ai.spirit.perception.system-audio")
    }

    public func start() async throws {
        do {
            chunks.removeAll()
            let content = try await SCShareableContent.current
            guard let display = selectedDisplay(from: content.displays) else {
                throw CollectorFailure.captureFailed("no shareable display is available")
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true

            let output = AudioStreamOutput(owner: self)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sampleQueue)
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
    }

    public func nextAudioChunk() async throws -> AudioChunk? {
        guard isRunning else {
            return nil
        }
        guard chunks.isEmpty == false else {
            return nil
        }
        return chunks.removeFirst()
    }

    fileprivate func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        ) == kCMBlockBufferNoErr,
        let dataPointer else {
            return
        }

        let format = CMSampleBufferGetFormatDescription(sampleBuffer)
        let streamDescription = format.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let sampleRate = Int(streamDescription?.mSampleRate ?? 0)
        let channelCount = Int(streamDescription?.mChannelsPerFrame ?? 0)
        let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let duration = CMSampleBufferGetDuration(sampleBuffer).seconds
        let timestampStart = Date(timeIntervalSince1970: start.isFinite ? start : Date().timeIntervalSince1970)
        let timestampEnd = timestampStart.addingTimeInterval(duration.isFinite ? duration : 0)

        chunks.append(
            AudioChunk(
                id: UUID().uuidString,
                timestampStart: timestampStart,
                timestampEnd: timestampEnd,
                sampleRate: sampleRate,
                channelCount: channelCount,
                pcmData: Data(bytes: dataPointer, count: length)
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

private final class AudioStreamOutput: NSObject, SCStreamOutput {
    private let owner: SystemAudioCapture

    init(owner: SystemAudioCapture) {
        self.owner = owner
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else {
            return
        }
        Task {
            await owner.enqueue(sampleBuffer)
        }
    }
}
