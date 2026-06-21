import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct ScreenCaptureKitCapturer: ScreenCapturing {
    private let parameters: PerceptionParameters
    private let targetDisplayID: UInt32?

    public init(parameters: PerceptionParameters = .defaults, targetDisplayID: UInt32? = nil) {
        self.parameters = parameters
        self.targetDisplayID = targetDisplayID
    }

    public func capture() async throws -> CapturedFrame {
        do {
            let content = try await SCShareableContent.current
            guard let display = selectedDisplay(from: content.displays) else {
                throw CollectorFailure.captureFailed("no shareable display is available")
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let imageData = try ImageEncoder(parameters: parameters).jpegData(from: image)

            return CapturedFrame(
                id: UUID().uuidString,
                timestamp: Date(),
                width: image.width,
                height: image.height,
                displayID: display.displayID,
                imageData: imageData
            )
        } catch let failure as CollectorFailure {
            throw failure
        } catch {
            throw Self.collectorFailure(from: error)
        }
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
