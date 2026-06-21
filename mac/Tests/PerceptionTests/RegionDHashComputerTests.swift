import CoreGraphics
import Foundation
import Testing
import Perception

@Test func regionDHashSnapshotContainsGlobalAndNineRegions() throws {
    let computer = RegionDHashComputer()
    let image = try stripedImage(width: 90, height: 90, inverted: false)

    let snapshot = try computer.snapshot(for: image)

    #expect(snapshot.regionHashes.count == 9)
    #expect(Set(snapshot.regionHashes.keys) == Set(ScreenRegion.allCases))
}

@Test func regionDHashDistanceIsZeroForIdenticalImage() throws {
    let computer = RegionDHashComputer()
    let image = try stripedImage(width: 90, height: 90, inverted: false)
    let previous = try computer.snapshot(for: image)

    let comparison = try computer.compare(current: image, previous: previous)

    #expect(comparison.regionHash.globalDistance == 0)
    #expect(comparison.regionHash.regionDistances.values.allSatisfy { $0 == 0 })
    #expect(comparison.regionHash.changedRegions.isEmpty)
}

@Test func regionDHashDetectsGlobalChanges() throws {
    let computer = RegionDHashComputer()
    let previous = try computer.snapshot(for: stripedImage(width: 90, height: 90, inverted: false))

    let comparison = try computer.compare(
        current: stripedImage(width: 90, height: 90, inverted: true),
        previous: previous
    )

    #expect(comparison.regionHash.globalDistance >= PerceptionParameters.defaults.dHashGlobalThreshold)
    #expect(comparison.regionHash.hasSignificantChange())
}

@Test func regionDHashDetectsChangedRegionUsingInjectedThreshold() throws {
    let computer = RegionDHashComputer(parameters: PerceptionParameters(dHashRegionThreshold: 1))
    let previous = try computer.snapshot(for: quadrantImage(width: 90, height: 90, highlightedRegion: nil))

    let comparison = try computer.compare(
        current: quadrantImage(width: 90, height: 90, highlightedRegion: .bottomRight),
        previous: previous
    )

    #expect(comparison.regionHash.regionDistances[.bottomRight, default: 0] > 0)
    #expect(comparison.regionHash.changedRegions.contains(.bottomRight))
}

@Test func regionDHashFirstComparisonHasNoDistance() throws {
    let computer = RegionDHashComputer()
    let image = try stripedImage(width: 90, height: 90, inverted: false)

    let comparison = try computer.compare(current: image, previous: nil)

    #expect(comparison.previous == nil)
    #expect(comparison.regionHash.globalDistance == 0)
    #expect(comparison.regionHash.changedRegions.isEmpty)
}

private func stripedImage(width: Int, height: Int, inverted: Bool) throws -> CGImage {
    try drawImage(width: width, height: height) { context in
        for x in 0..<width {
            let value = ((x / 6) % 2 == 0) != inverted ? 0.1 : 0.9
            context.setFillColor(CGColor(gray: value, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
    }
}

private func quadrantImage(width: Int, height: Int, highlightedRegion: ScreenRegion?) throws -> CGImage {
    try drawImage(width: width, height: height) { context in
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let highlightedRegion else {
            return
        }

        let index = ScreenRegion.allCases.firstIndex(of: highlightedRegion) ?? 0
        let column = index % 3
        let row = index / 3
        let cellWidth = width / 3
        let cellHeight = height / 3
        let drawingY = (2 - row) * cellHeight
        for x in (column * cellWidth)..<((column + 1) * cellWidth) {
            let value = ((x / 3) % 2 == 0) ? 0.05 : 0.95
            context.setFillColor(CGColor(gray: value, alpha: 1))
            context.fill(CGRect(x: x, y: drawingY, width: 1, height: cellHeight))
        }
    }
}

private func drawImage(
    width: Int,
    height: Int,
    draw: (CGContext) -> Void
) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CollectorFailure.captureFailed("failed to create test context")
    }

    draw(context)
    guard let image = context.makeImage() else {
        throw CollectorFailure.captureFailed("failed to create test image")
    }
    return image
}
