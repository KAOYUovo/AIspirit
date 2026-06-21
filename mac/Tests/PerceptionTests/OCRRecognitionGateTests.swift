import Foundation
import Testing
import Perception
import DebugTools

@Test func ocrGateDoesNotCallRecognizerWhenFlagIsDisabled() async {
    let recognizer = MockOCRTextRecognizer(text: ["score"])
    var flags = PerceptionFeatureFlags()
    flags.ocrRecognition = false

    let result = await OCRRecognitionGate(
        recognizer: recognizer,
        featureFlags: flags
    ).recognizeText(in: frame())

    #expect(result.didRun == false)
    #expect(result.text.isEmpty)
    #expect(result.errors.isEmpty)
    #expect(result.latency.ocrMs == 0)
}

@Test func ocrGateReturnsRecognizedTextWhenFlagIsEnabled() async {
    var flags = PerceptionFeatureFlags()
    flags.ocrRecognition = true

    let result = await OCRRecognitionGate(
        recognizer: MockOCRTextRecognizer(text: ["Lakers 101", "Warriors 99"]),
        featureFlags: flags
    ).recognizeText(in: frame())

    #expect(result.didRun)
    #expect(result.text == ["Lakers 101", "Warriors 99"])
    #expect(result.errors.isEmpty)
    #expect(result.latency.ocrMs != nil)
}

@Test func ocrGateIgnoresTextAndRecordsFallbackWhenRecognizerFails() async {
    var flags = PerceptionFeatureFlags()
    flags.ocrRecognition = true

    let result = await OCRRecognitionGate(
        recognizer: MockOCRTextRecognizer(error: .captureFailed("bad image")),
        featureFlags: flags
    ).recognizeText(in: frame())

    #expect(result.didRun)
    #expect(result.text.isEmpty)
    #expect(result.errors.count == 1)
    #expect(result.errors[0].code == "ocr_failed")
    #expect(result.errors[0].isFallbackApplied)
}

@Test func ocrTextRecognizerFailsWithoutImageData() async {
    var empty = frame()
    empty.imageData = nil

    await #expect(throws: CollectorFailure.captureFailed("OCR frame has no image data")) {
        _ = try await OCRTextRecognizer().recognizeText(in: empty)
    }
}

private func frame() -> CapturedFrame {
    CapturedFrame(
        id: "frame-ocr",
        timestamp: Date(timeIntervalSince1970: 1_780_040_000),
        width: 320,
        height: 180,
        displayID: 1,
        imageData: Data([0xFF, 0xD8, 0xFF])
    )
}
