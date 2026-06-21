import Testing
import Perception

@Test func contentTypeDetectorRecognizesSportsFromOCRAndTranscript() {
    let result = ContentTypeDetector().detect(
        ContentTypeDetectionInput(
            appName: "Safari",
            windowTitles: ["NBA Finals Live"],
            ocrText: ["LAL 98 BOS 96"],
            audioTranscript: "final minute, two point game"
        )
    )

    #expect(result.contentType == .sports)
    #expect(result.reasons == ["sports keyword in title/OCR/transcript"])
    #expect(result.latency.contentTypeMs != nil)
}

@Test func contentTypeDetectorRecognizesOfficeFromDocumentContext() {
    let result = ContentTypeDetector().detect(
        ContentTypeDetectionInput(
            appName: "Microsoft Excel",
            windowTitles: ["Q2 revenue spreadsheet"]
        )
    )

    #expect(result.contentType == .office)
}

@Test func contentTypeDetectorRecognizesCodingFromDeveloperContext() {
    let result = ContentTypeDetector().detect(
        ContentTypeDetectionInput(
            appName: "Visual Studio Code",
            windowTitles: ["ContentTypeDetector.swift"],
            ocrText: ["func detect(_ input: ContentTypeDetectionInput)"]
        )
    )

    #expect(result.contentType == .coding)
}

@Test func contentTypeDetectorRecognizesChatFromMessagingContext() {
    let result = ContentTypeDetector().detect(
        ContentTypeDetectionInput(
            appName: "WeChat",
            windowTitles: ["Chat with Alex"]
        )
    )

    #expect(result.contentType == .chat)
}

@Test func contentTypeDetectorFallsBackToUnknown() {
    let result = ContentTypeDetector().detect(
        ContentTypeDetectionInput(
            appName: "Preview",
            windowTitles: ["untitled"]
        )
    )

    #expect(result.contentType == .unknown)
    #expect(result.reasons == ["no content type keyword matched"])
}
