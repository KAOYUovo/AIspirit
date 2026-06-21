import Foundation
import Testing
import Perception
import DebugTools

@Test func streamCaptureGateDoesNotStartStreamWhenFlagIsDisabled() async {
    let frame = makeFrame("fallback-unused")
    let stream = MockScreenStream(frames: [frame])
    var flags = PerceptionFeatureFlags()
    flags.coWatchingStream = false

    let result = await ScreenStreamCaptureGate(
        stream: stream,
        singleFrameCapturer: MockScreenCapture(frames: [frame]),
        featureFlags: flags
    ).captureFrames()

    #expect(await stream.didStart == false)
    #expect(result.frames.isEmpty)
    #expect(result.didStartStream == false)
    #expect(result.didUseFallback == false)
    #expect(result.decision?.kind == .skipStable)
}

@Test func streamCaptureGateReturnsFramesWhenStreamStarts() async {
    let first = makeFrame("stream-1")
    let second = makeFrame("stream-2")
    let stream = MockScreenStream(frames: [first, second])
    var flags = PerceptionFeatureFlags()
    flags.coWatchingStream = true

    let result = await ScreenStreamCaptureGate(
        stream: stream,
        singleFrameCapturer: MockScreenCapture(frames: []),
        featureFlags: flags
    ).captureFrames()

    #expect(await stream.didStart)
    #expect(await stream.didStop)
    #expect(result.frames == [first, second])
    #expect(result.didStartStream)
    #expect(result.didUseFallback == false)
    #expect(result.errors.isEmpty)
}

@Test func streamCaptureGateFallsBackToMultiFrameScreenshotsWhenStartFails() async {
    let fallbackFrames = [makeFrame("fallback-1"), makeFrame("fallback-2"), makeFrame("fallback-3")]
    let stream = MockScreenStream(startError: .unavailable("stream denied"))
    var flags = PerceptionFeatureFlags()
    flags.coWatchingStream = true

    let result = await ScreenStreamCaptureGate(
        stream: stream,
        singleFrameCapturer: MockScreenCapture(frames: fallbackFrames),
        featureFlags: flags,
        fallbackFrameCount: 3
    ).captureFrames()

    #expect(await stream.didStop)
    #expect(result.frames == fallbackFrames)
    #expect(result.didUseFallback)
    #expect(result.decision?.kind == .fallback)
    #expect(result.decision?.fallbacks == ["multi-frame single screenshot capture"])
    #expect(result.errors.first?.code == "screen_stream_unavailable")
}

@Test func streamCaptureGateReportsFallbackCaptureFailure() async {
    let stream = MockScreenStream(startError: .unavailable("stream denied"))
    var flags = PerceptionFeatureFlags()
    flags.coWatchingStream = true

    let result = await ScreenStreamCaptureGate(
        stream: stream,
        singleFrameCapturer: MockScreenCapture(error: .captureFailed("no screen")),
        featureFlags: flags,
        fallbackFrameCount: 3
    ).captureFrames()

    #expect(result.frames.isEmpty)
    #expect(result.didUseFallback)
    #expect(result.errors.map(\.code) == [
        "screen_stream_unavailable",
        "screen_stream_fallback_capture_failed"
    ])
}

private func makeFrame(_ id: String) -> CapturedFrame {
    CapturedFrame(
        id: id,
        timestamp: Date(timeIntervalSince1970: 1_780_020_000),
        width: 1920,
        height: 1080,
        displayID: 1,
        imageData: Data([0xFF, 0xD8, 0xFF])
    )
}
