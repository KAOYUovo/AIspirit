import AppKit
import CoreGraphics
import Foundation

public struct ImageEncoder: Sendable {
    private let parameters: PerceptionParameters

    public init(parameters: PerceptionParameters = .defaults) {
        self.parameters = parameters
    }

    public func jpegData(from image: CGImage) throws -> Data {
        let resized = try resizedImageIfNeeded(image)
        let bitmap = NSBitmapImageRep(cgImage: resized)
        let quality = min(1, max(0, parameters.imageJPEGQuality))
        guard let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            throw CollectorFailure.captureFailed("failed to encode JPEG")
        }
        return data
    }

    public func outputSize(for width: Int, height: Int) -> (width: Int, height: Int) {
        let maxEdge = max(1, parameters.imageMaxEdge)
        let currentMaxEdge = max(width, height)
        guard currentMaxEdge > maxEdge else {
            return (width, height)
        }

        let scale = Double(maxEdge) / Double(currentMaxEdge)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }

    private func resizedImageIfNeeded(_ image: CGImage) throws -> CGImage {
        let size = outputSize(for: image.width, height: image.height)
        guard size.width != image.width || size.height != image.height else {
            return image
        }

        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CollectorFailure.captureFailed("failed to create resize context")
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))

        guard let resized = context.makeImage() else {
            throw CollectorFailure.captureFailed("failed to resize image")
        }
        return resized
    }
}
