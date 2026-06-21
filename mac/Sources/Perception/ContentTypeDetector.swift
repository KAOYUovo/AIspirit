import Foundation

public struct ContentTypeDetectionInput: Equatable, Sendable {
    public var appName: String
    public var windowTitles: [String]
    public var keyframeRefs: [String]
    public var ocrText: [String]
    public var audioTranscript: String?

    public init(
        appName: String = "unknown",
        windowTitles: [String] = [],
        keyframeRefs: [String] = [],
        ocrText: [String] = [],
        audioTranscript: String? = nil
    ) {
        self.appName = appName
        self.windowTitles = windowTitles
        self.keyframeRefs = keyframeRefs
        self.ocrText = ocrText
        self.audioTranscript = audioTranscript
    }
}

public struct ContentTypeDetectionResult: Equatable, Sendable {
    public var contentType: ContentType
    public var reasons: [String]
    public var latency: PerceptionLatency

    public init(contentType: ContentType, reasons: [String], latency: PerceptionLatency) {
        self.contentType = contentType
        self.reasons = reasons
        self.latency = latency
    }
}

public struct ContentTypeDetector: Sendable {
    public init() {}

    public func detect(_ input: ContentTypeDetectionInput) -> ContentTypeDetectionResult {
        let start = Date()
        let corpus = normalizedCorpus(from: input)
        let matched = match(corpus: corpus)
        let latencyMs = max(0, Int(Date().timeIntervalSince(start) * 1000))
        return ContentTypeDetectionResult(
            contentType: matched.type,
            reasons: matched.reasons,
            latency: PerceptionLatency(contentTypeMs: latencyMs, totalMs: latencyMs)
        )
    }

    private func normalizedCorpus(from input: ContentTypeDetectionInput) -> String {
        ([input.appName] + input.windowTitles + input.ocrText + [input.audioTranscript ?? ""] + input.keyframeRefs)
            .joined(separator: " ")
            .lowercased()
    }

    private func match(corpus: String) -> (type: ContentType, reasons: [String]) {
        if containsAny(corpus, [
            "nba", "nfl", "mlb", "nhl", "fifa", "premier league", "world cup",
            "score", "scored", "final minute", "quarter", "period", "possession",
            "lakers", "warriors", "celtics", "bos", "lal"
        ]) {
            return (.sports, ["sports keyword in title/OCR/transcript"])
        }

        if containsAny(corpus, ["xcode", "visual studio code", "vscode", "github", "swift", "python", "typescript", "debug", "compiler"]) {
            return (.coding, ["coding app or developer keyword"])
        }

        if containsAny(corpus, ["wechat", "messages", "slack", "discord", "telegram", "whatsapp", "chat", "dm"]) {
            return (.chat, ["chat app or conversation keyword"])
        }

        if containsAny(corpus, ["keynote", "powerpoint", "excel", "numbers", "pages", "word", "spreadsheet", "slides", "document", "meeting"]) {
            return (.office, ["office app or document keyword"])
        }

        if containsAny(corpus, ["live", "stream", "直播"]) {
            return (.liveStream, ["live stream keyword"])
        }

        if containsAny(corpus, ["course", "lecture", "lesson", "tutorial", "class"]) {
            return (.course, ["course keyword"])
        }

        if containsAny(corpus, ["movie", "film", "cinema"]) {
            return (.movie, ["movie keyword"])
        }

        if containsAny(corpus, ["episode", "season", "tv show", "series"]) {
            return (.tvShow, ["tv show keyword"])
        }

        if containsAny(corpus, ["game", "steam", "battle", "level"]) {
            return (.game, ["game keyword"])
        }

        return (.unknown, ["no content type keyword matched"])
    }

    private func containsAny(_ corpus: String, _ keywords: [String]) -> Bool {
        keywords.contains { corpus.contains($0) }
    }
}
