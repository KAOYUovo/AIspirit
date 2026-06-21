import Foundation

public struct WebMetadataSearchInput: Equatable, Sendable {
    public var contentType: ContentType
    public var windowTitles: [String]
    public var ocrText: [String]
    public var audioTranscript: String?
    public var privacyPassed: Bool

    public init(
        contentType: ContentType,
        windowTitles: [String] = [],
        ocrText: [String] = [],
        audioTranscript: String? = nil,
        privacyPassed: Bool = true
    ) {
        self.contentType = contentType
        self.windowTitles = windowTitles
        self.ocrText = ocrText
        self.audioTranscript = audioTranscript
        self.privacyPassed = privacyPassed
    }
}

public struct WebMetadataSearchGateResult: Equatable, Sendable {
    public var result: WebMetadataResult?
    public var query: String?
    public var didRun: Bool
    public var errors: [DiagnosticErrorDTO]

    public init(result: WebMetadataResult?, query: String?, didRun: Bool, errors: [DiagnosticErrorDTO]) {
        self.result = result
        self.query = query
        self.didRun = didRun
        self.errors = errors
    }
}

public struct WebMetadataSearchGate: Sendable {
    private let searcher: any WebMetadataSearching
    private let featureFlags: PerceptionFeatureFlags
    private let maxQueryLength: Int

    public init(
        searcher: any WebMetadataSearching,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        maxQueryLength: Int = 160
    ) {
        self.searcher = searcher
        self.featureFlags = featureFlags
        self.maxQueryLength = maxQueryLength
    }

    public func search(_ input: WebMetadataSearchInput) async -> WebMetadataSearchGateResult {
        guard featureFlags.webMetadataSearch else {
            return WebMetadataSearchGateResult(result: nil, query: nil, didRun: false, errors: [])
        }

        guard input.privacyPassed else {
            return WebMetadataSearchGateResult(
                result: nil,
                query: nil,
                didRun: false,
                errors: [
                    DiagnosticErrorDTO(
                        module: "perception",
                        code: "web_metadata_blocked_by_privacy",
                        message: "Gate 6 privacy filter blocked web metadata search",
                        isFallbackApplied: true
                    )
                ]
            )
        }

        let query = makeQuery(input)
        guard query.isEmpty == false else {
            return WebMetadataSearchGateResult(result: nil, query: nil, didRun: false, errors: [])
        }

        do {
            return WebMetadataSearchGateResult(
                result: try await searcher.searchMetadata(query: query),
                query: query,
                didRun: true,
                errors: []
            )
        } catch {
            return WebMetadataSearchGateResult(
                result: nil,
                query: query,
                didRun: true,
                errors: [
                    DiagnosticErrorDTO(
                        module: "perception",
                        code: "web_metadata_search_failed",
                        message: String(describing: error),
                        isFallbackApplied: true
                    )
                ]
            )
        }
    }

    private func makeQuery(_ input: WebMetadataSearchInput) -> String {
        let textMetadata = (input.windowTitles.prefix(2) + input.ocrText.prefix(2) + [input.audioTranscript ?? ""])
        let parts = ([input.contentType.rawValue] + textMetadata)
            .flatMap { $0.split(whereSeparator: \.isWhitespace) }
            .map(sanitizedToken)
            .filter { $0.isEmpty == false }
            .filter { token in
                token.rangeOfCharacter(from: .letters) != nil
            }
        let query = unique(parts)
            .prefix(12)
            .joined(separator: " ")
        return String(query.prefix(max(0, maxQueryLength)))
    }

    private func sanitizedToken(_ token: Substring) -> String {
        String(token.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        })
    }

    private func unique(_ parts: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for part in parts {
            let normalized = part.lowercased()
            guard seen.insert(normalized).inserted else {
                continue
            }
            output.append(part)
        }
        return output
    }
}
