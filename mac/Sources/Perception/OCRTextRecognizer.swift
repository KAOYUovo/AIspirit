import AppKit
import Foundation
import Vision

public struct OCRTextRecognizer: OCRTextRecognizing {
    public init() {}

    public func recognizeText(in frame: CapturedFrame) async throws -> [String] {
        guard let imageData = frame.imageData else {
            throw CollectorFailure.captureFailed("OCR frame has no image data")
        }
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CollectorFailure.captureFailed("OCR frame image data is not decodable")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: CollectorFailure.captureFailed(String(describing: error)))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { $0.isEmpty == false }
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: CollectorFailure.captureFailed(String(describing: error)))
            }
        }
    }
}
