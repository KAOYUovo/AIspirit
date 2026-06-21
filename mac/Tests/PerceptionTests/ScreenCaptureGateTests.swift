import Foundation
import Testing
import Perception
import DebugTools

@Test func screenCaptureGateReturnsCapturedFrame() async {
    let frame = CapturedFrame(
        id: "frame-1",
        timestamp: Date(timeIntervalSince1970: 1_780_000_200),
        width: 100,
        height: 80,
        displayID: 1,
        imageData: Data([0xFF, 0xD8, 0xFF])
    )

    let result = await ScreenCaptureGate(capturer: MockScreenCapture(frames: [frame])).captureFrame()

    #expect(result.frame == frame)
    #expect(result.shouldSkipFrame == false)
    #expect(result.decision == nil)
    #expect(result.errors.isEmpty)
}

@Test func screenCaptureGateSkipsCurrentFrameOnPermissionDenied() async {
    let result = await ScreenCaptureGate(
        capturer: MockScreenCapture(error: .permissionDenied("screen recording denied"))
    ).captureFrame()

    #expect(result.frame == nil)
    #expect(result.shouldSkipFrame)
    #expect(result.decision?.kind == .skipNoScreen)
    #expect(result.errors.first?.code == "screen_capture_permission_denied")
    #expect(result.errors.first?.isFallbackApplied == true)
}

@Test func screenCaptureGateSkipsCurrentFrameOnCaptureFailure() async {
    let result = await ScreenCaptureGate(capturer: MockScreenCapture(error: .captureFailed("no display"))).captureFrame()

    #expect(result.frame == nil)
    #expect(result.shouldSkipFrame)
    #expect(result.decision?.kind == .skipNoScreen)
    #expect(result.decision?.fallbacks == ["skip current frame"])
}
