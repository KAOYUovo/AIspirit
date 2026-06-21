import Foundation

public struct WebMetadataSearch: WebMetadataSearching {
    public init() {}

    public func searchMetadata(query: String) async throws -> WebMetadataResult? {
        throw CollectorFailure.networkDisabled
    }
}

