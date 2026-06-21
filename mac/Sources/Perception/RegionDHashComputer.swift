import CoreGraphics
import Foundation

public struct RegionDHashSnapshot: Codable, Equatable, Sendable {
    public var globalHash: UInt64
    public var regionHashes: [ScreenRegion: UInt64]

    public init(globalHash: UInt64, regionHashes: [ScreenRegion: UInt64]) {
        self.globalHash = globalHash
        self.regionHashes = regionHashes
    }
}

public struct RegionDHashComparison: Equatable, Sendable {
    public var current: RegionDHashSnapshot
    public var previous: RegionDHashSnapshot?
    public var regionHash: RegionHashDTO

    public init(current: RegionDHashSnapshot, previous: RegionDHashSnapshot?, regionHash: RegionHashDTO) {
        self.current = current
        self.previous = previous
        self.regionHash = regionHash
    }
}

public struct RegionDHashComputer: Sendable {
    private let parameters: PerceptionParameters

    public init(parameters: PerceptionParameters = .defaults) {
        self.parameters = parameters
    }

    public func snapshot(for image: CGImage) throws -> RegionDHashSnapshot {
        RegionDHashSnapshot(
            globalHash: try hash(image: image, rect: CGRect(x: 0, y: 0, width: image.width, height: image.height)),
            regionHashes: try regionRects(for: image).reduce(into: [ScreenRegion: UInt64]()) { result, entry in
                result[entry.region] = try hash(image: image, rect: entry.rect)
            }
        )
    }

    public func compare(current image: CGImage, previous: RegionDHashSnapshot?) throws -> RegionDHashComparison {
        let current = try snapshot(for: image)
        return compare(current: current, previous: previous)
    }

    public func compare(
        current: RegionDHashSnapshot,
        previous: RegionDHashSnapshot?
    ) -> RegionDHashComparison {
        guard let previous else {
            return RegionDHashComparison(
                current: current,
                previous: nil,
                regionHash: RegionHashDTO(
                    globalDistance: 0,
                    regionDistances: ScreenRegion.allCases.reduce(into: [:]) { $0[$1] = 0 },
                    changedRegions: []
                )
            )
        }

        let distances = ScreenRegion.allCases.reduce(into: [ScreenRegion: Int]()) { result, region in
            guard let currentHash = current.regionHashes[region],
                  let previousHash = previous.regionHashes[region] else {
                return
            }
            result[region] = hammingDistance(currentHash, previousHash)
        }
        let changedRegions = ScreenRegion.allCases.filter { region in
            (distances[region] ?? 0) >= parameters.dHashRegionThreshold
        }

        return RegionDHashComparison(
            current: current,
            previous: previous,
            regionHash: RegionHashDTO(
                globalDistance: hammingDistance(current.globalHash, previous.globalHash),
                regionDistances: distances,
                changedRegions: changedRegions
            )
        )
    }

    public func hash(image: CGImage, rect: CGRect) throws -> UInt64 {
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw CollectorFailure.captureFailed("failed to create dHash context")
        }

        context.interpolationQuality = .low
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(
            x: -rect.origin.x * CGFloat(width) / rect.width,
            y: -(CGFloat(image.height) - rect.maxY) * CGFloat(height) / rect.height,
            width: CGFloat(image.width) * CGFloat(width) / rect.width,
            height: CGFloat(image.height) * CGFloat(height) / rect.height
        ))

        var hash: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                hash <<= 1
                if pixels[row * width + column] > pixels[row * width + column + 1] {
                    hash |= 1
                }
            }
        }
        return hash
    }

    private func regionRects(for image: CGImage) -> [(region: ScreenRegion, rect: CGRect)] {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        return ScreenRegion.allCases.enumerated().map { index, region in
            let column = index % 3
            let row = index / 3
            let minX = floor(imageWidth * CGFloat(column) / 3)
            let maxX = floor(imageWidth * CGFloat(column + 1) / 3)
            let minY = floor(imageHeight * CGFloat(row) / 3)
            let maxY = floor(imageHeight * CGFloat(row + 1) / 3)
            return (
                region,
                CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
            )
        }
    }

    private func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}
