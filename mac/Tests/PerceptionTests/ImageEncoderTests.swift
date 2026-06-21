import CoreGraphics
import Foundation
import Testing
import Perception

@Test func imageEncoderKeepsSmallImagesWithinBounds() throws {
    let encoder = ImageEncoder(parameters: PerceptionParameters(imageMaxEdge: 100))

    let size = encoder.outputSize(for: 80, height: 40)

    #expect(size.width == 80)
    #expect(size.height == 40)
}

@Test func imageEncoderScalesLongEdgeToConfiguredMaximum() throws {
    let encoder = ImageEncoder(parameters: PerceptionParameters(imageMaxEdge: 100))

    let landscape = encoder.outputSize(for: 400, height: 200)
    let portrait = encoder.outputSize(for: 200, height: 400)

    #expect(landscape.width == 100)
    #expect(landscape.height == 50)
    #expect(portrait.width == 50)
    #expect(portrait.height == 100)
}

@Test func imageEncoderProducesJPEGData() throws {
    let encoder = ImageEncoder(parameters: PerceptionParameters(imageMaxEdge: 16, imageJPEGQuality: 0.6))
    let image = try solidImage(width: 32, height: 24)

    let data = try encoder.jpegData(from: image)

    #expect(data.starts(with: [0xFF, 0xD8]))
    #expect(data.count > 10)
}

private func solidImage(width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CollectorFailure.captureFailed("failed to create test image")
    }

    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else {
        throw CollectorFailure.captureFailed("failed to create test CGImage")
    }
    return image
}
