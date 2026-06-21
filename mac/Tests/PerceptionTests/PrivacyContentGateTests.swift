import Testing
import Perception

@Test func privacyGatePassesNonSensitiveOCRAndTranscript() {
    let result = PrivacyContentGate().evaluate(
        PrivacyContentInput(
            ocrText: ["LAL 98 BOS 96"],
            audioTranscript: "final minute two point game"
        )
    )

    #expect(result.isBlocked == false)
    #expect(result.filteredOCRText == ["LAL 98 BOS 96"])
    #expect(result.filteredAudioTranscript == "final minute two point game")
    #expect(result.decision.kind == .analyze)
    #expect(result.errors.isEmpty)
}

@Test func privacyGateDropsSensitiveOCRText() {
    let result = PrivacyContentGate().evaluate(
        PrivacyContentInput(
            ocrText: ["verification code 123456"],
            audioTranscript: "commentary"
        )
    )

    #expect(result.isBlocked)
    #expect(result.filteredOCRText.isEmpty)
    #expect(result.filteredAudioTranscript == nil)
    #expect(result.decision.kind == .skipPrivacyBlocked)
    #expect(result.errors.first?.code == "privacy_content_blocked")
}

@Test func privacyGateDropsSensitiveTranscript() {
    let result = PrivacyContentGate().evaluate(
        PrivacyContentInput(
            ocrText: ["public title"],
            audioTranscript: "your password is on screen"
        )
    )

    #expect(result.isBlocked)
    #expect(result.filteredOCRText.isEmpty)
    #expect(result.filteredAudioTranscript == nil)
}
