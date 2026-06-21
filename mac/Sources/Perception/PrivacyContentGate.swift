import Foundation

public struct PrivacyContentInput: Equatable, Sendable {
    public var ocrText: [String]
    public var audioTranscript: String?

    public init(ocrText: [String] = [], audioTranscript: String? = nil) {
        self.ocrText = ocrText
        self.audioTranscript = audioTranscript
    }
}

public struct PrivacyContentResult: Equatable, Sendable {
    public var filteredOCRText: [String]
    public var filteredAudioTranscript: String?
    public var isBlocked: Bool
    public var decision: GateDecision
    public var errors: [DiagnosticErrorDTO]

    public init(
        filteredOCRText: [String],
        filteredAudioTranscript: String?,
        isBlocked: Bool,
        decision: GateDecision,
        errors: [DiagnosticErrorDTO]
    ) {
        self.filteredOCRText = filteredOCRText
        self.filteredAudioTranscript = filteredAudioTranscript
        self.isBlocked = isBlocked
        self.decision = decision
        self.errors = errors
    }
}

public struct PrivacyContentGate: Sendable {
    private let sensitivePatterns: [String]

    public init(sensitivePatterns: [String] = Self.defaultSensitivePatterns) {
        self.sensitivePatterns = sensitivePatterns.map { $0.lowercased() }
    }

    public func evaluate(_ input: PrivacyContentInput) -> PrivacyContentResult {
        let allText = (input.ocrText + [input.audioTranscript ?? ""]).joined(separator: " ").lowercased()
        let matched = sensitivePatterns.filter { allText.contains($0) }

        guard matched.isEmpty else {
            return PrivacyContentResult(
                filteredOCRText: [],
                filteredAudioTranscript: nil,
                isBlocked: true,
                decision: GateDecision(
                    kind: .skipPrivacyBlocked,
                    reasons: ["sensitive OCR/transcript content matched"],
                    triggeredSignals: [],
                    fallbacks: ["drop OCR text and audio transcript"]
                ),
                errors: [
                    DiagnosticErrorDTO(
                        module: "perception",
                        code: "privacy_content_blocked",
                        message: "Sensitive content matched Gate 6 filter",
                        isFallbackApplied: true
                    )
                ]
            )
        }

        return PrivacyContentResult(
            filteredOCRText: input.ocrText,
            filteredAudioTranscript: input.audioTranscript,
            isBlocked: false,
            decision: GateDecision(
                kind: .analyze,
                reasons: ["content privacy filter passed"],
                triggeredSignals: [],
                fallbacks: []
            ),
            errors: []
        )
    }

    public static let defaultSensitivePatterns = [
        "password",
        "passcode",
        "one-time code",
        "verification code",
        "验证码",
        "密码",
        "secret key",
        "recovery key",
        "private key",
        "api key",
        "token:",
        "2fa"
    ]
}
