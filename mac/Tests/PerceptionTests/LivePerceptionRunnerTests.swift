import CoreGraphics
import Foundation
import Testing
import Perception
import DebugTools

@Test func liveRunnerCapturesFrameAndBuildsDiagnosticEvent() async throws {
    let frame = try capturedFrame(id: "live-frame-1")
    let runner = LivePerceptionRunner(
        idleDetector: MockIdleDetector(idleDuration: 1),
        frontAppDetector: MockFrontAppDetector(snapshot: FrontAppSnapshot(appName: "Safari", windowTitles: ["Article"])),
        screenStateMonitor: MockScreenStateMonitor(state: .active),
        powerMonitor: MockPowerMonitor(snapshot: .nominal),
        screenCapture: MockScreenCapture(frames: [frame]),
        parameters: .defaults
    )

    let result = await runner.runTick(timestamp: Date(timeIntervalSince1970: 1_790_010_000))

    #expect(result.frame == frame)
    #expect(result.captureSkipped == false)
    #expect(result.event.decision.kind == .analyze)
    #expect(result.event.snapshot?.appName == "Safari")
    #expect(result.event.snapshot?.idleDuration == 1)
    #expect(result.event.snapshot?.recentInputActive == true)
    #expect(result.event.snapshot?.regionHash != nil)
    #expect(result.event.snapshot?.screenshotRef == "live:live-frame-1")
    #expect(result.event.errors.isEmpty)
}

@Test func liveRunnerRecordsPermissionDeniedWhenCaptureFails() async {
    let runner = LivePerceptionRunner(
        idleDetector: MockIdleDetector(idleDuration: 10),
        frontAppDetector: MockFrontAppDetector(snapshot: FrontAppSnapshot(appName: "Safari")),
        screenStateMonitor: MockScreenStateMonitor(state: .active),
        powerMonitor: MockPowerMonitor(snapshot: .nominal),
        screenCapture: MockScreenCapture(error: .permissionDenied("screen recording denied")),
        parameters: .defaults
    )

    let result = await runner.runTick(timestamp: Date(timeIntervalSince1970: 1_790_010_100))

    #expect(result.frame == nil)
    #expect(result.captureSkipped)
    #expect(result.event.decision.kind == .skipNoScreen)
    #expect(result.event.decision.fallbacks == ["skip current frame"])
    #expect(result.event.errors.first?.code == "screen_capture_permission_denied")
    #expect(result.event.errors.first?.isFallbackApplied == true)
}

@Test func liveRunnerDoesNotCaptureWhenScreenIsLocked() async {
    let runner = LivePerceptionRunner(
        idleDetector: MockIdleDetector(idleDuration: 0),
        frontAppDetector: MockFrontAppDetector(snapshot: FrontAppSnapshot(appName: "Safari")),
        screenStateMonitor: MockScreenStateMonitor(state: .locked),
        powerMonitor: MockPowerMonitor(snapshot: .nominal),
        screenCapture: MockScreenCapture(),
        parameters: .defaults
    )

    let result = await runner.runTick(timestamp: Date(timeIntervalSince1970: 1_790_010_200))

    #expect(result.frame == nil)
    #expect(result.captureSkipped)
    #expect(result.event.decision.kind == .pausedScreenLocked)
    #expect(result.event.errors.isEmpty)
}

@Test func liveRunnerDoesNotCaptureWhenIdleExceedsThreshold() async {
    let runner = LivePerceptionRunner(
        idleDetector: MockIdleDetector(idleDuration: 90),
        frontAppDetector: MockFrontAppDetector(snapshot: FrontAppSnapshot(appName: "Safari")),
        screenStateMonitor: MockScreenStateMonitor(state: .active),
        powerMonitor: MockPowerMonitor(snapshot: .nominal),
        screenCapture: MockScreenCapture(),
        parameters: .defaults
    )

    let result = await runner.runTick(timestamp: Date(timeIntervalSince1970: 1_790_010_300))

    #expect(result.frame == nil)
    #expect(result.captureSkipped)
    #expect(result.event.decision.kind == .skipIdle)
    #expect(result.event.snapshot?.idleDuration == 90)
}

private func capturedFrame(id: String) throws -> CapturedFrame {
    let image = try stripedImage(width: 90, height: 90)
    return CapturedFrame(
        id: id,
        timestamp: Date(timeIntervalSince1970: 1_790_010_000),
        width: image.width,
        height: image.height,
        displayID: 1,
        imageData: try ImageEncoder().jpegData(from: image)
    )
}

private func stripedImage(width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CollectorFailure.captureFailed("failed to create test context")
    }

    for x in 0..<width {
        let value = ((x / 6) % 2 == 0) ? 0.1 : 0.9
        context.setFillColor(CGColor(gray: value, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }

    guard let image = context.makeImage() else {
        throw CollectorFailure.captureFailed("failed to create test image")
    }
    return image
}
