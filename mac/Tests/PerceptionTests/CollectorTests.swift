import Foundation
import Testing
import Perception
import DebugTools

@Test func mockCollectorsReturnConfiguredValues() async throws {
    let frame = CapturedFrame(
        id: "frame-1",
        timestamp: Date(timeIntervalSince1970: 1_780_000_000),
        width: 100,
        height: 80,
        displayID: 1,
        imageData: Data([1, 2, 3])
    )
    let audio = AudioChunk(
        id: "audio-1",
        timestampStart: frame.timestamp,
        timestampEnd: frame.timestamp.addingTimeInterval(5),
        sampleRate: 16_000,
        channelCount: 1,
        pcmData: Data([4, 5, 6])
    )

    #expect(try await MockIdleDetector(idleDuration: 3).secondsSinceLastInput() == 3)
    #expect(try await MockFrontAppDetector(snapshot: FrontAppSnapshot(appName: "Safari")).detect().appName == "Safari")
    #expect(try await MockScreenCapture(frames: [frame]).capture() == frame)

    let stream = MockScreenStream(frames: [frame])
    try await stream.start()
    #expect(await stream.didStart)
    #expect(try await stream.nextFrame() == frame)
    await stream.stop()
    #expect(await stream.didStop)

    #expect(try await MockScreenStateMonitor(state: .locked).currentState() == .locked)
    #expect(try await MockPowerMonitor(snapshot: .nominal).currentPowerSnapshot() == .nominal)
    #expect(try await MockOCRTextRecognizer(text: ["score"]).recognizeText(in: frame) == ["score"])

    let audioCapture = MockSystemAudioCapture(chunks: [audio])
    try await audioCapture.start()
    #expect(await audioCapture.didStart)
    #expect(try await audioCapture.nextAudioChunk() == audio)
    await audioCapture.stop()
    #expect(await audioCapture.didStop)

    #expect(try await MockWhisperTranscriber(transcript: TranscriptSegment(text: "hello")).transcribe(audio).text == "hello")

    let metadata = WebMetadataResult(query: "NBA", title: "NBA", summary: "basketball")
    #expect(try await MockWebMetadataSearch(result: metadata).searchMetadata(query: "NBA") == metadata)
}

@Test func mockCollectorsCanThrowConfiguredErrors() async {
    await #expect(throws: CollectorFailure.unavailable("idle")) {
        _ = try await MockIdleDetector(error: .unavailable("idle")).secondsSinceLastInput()
    }
    await #expect(throws: CollectorFailure.captureFailed("mock frame queue is empty")) {
        _ = try await MockScreenCapture().capture()
    }
}

@Test func realCollectorStubsExposeSafeFallbackDefaults() async throws {
    #expect(try await NSWorkspaceFrontAppDetector().detect().appName.isEmpty == false)
    #expect(try await ScreenStateMonitor(observeNotifications: false).currentState() == .active)
    let powerSnapshot = try await PowerMonitor().currentPowerSnapshot()
    if let batteryLevel = powerSnapshot.powerState.batteryLevel {
        #expect((0...1).contains(batteryLevel))
    }

    await #expect(throws: CollectorFailure.networkDisabled) {
        _ = try await WebMetadataSearch().searchMetadata(query: "NBA")
    }
}
