import CoreGraphics
import Foundation

public struct CGEventSourceIdleDetector: IdleDetecting {
    public init() {}

    public func secondsSinceLastInput() async throws -> TimeInterval {
        let anyInputEventType = CGEventType(rawValue: UInt32.max)!
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEventType
        )
        guard seconds.isFinite, seconds >= 0 else {
            throw CollectorFailure.unavailable("Idle detection returned an invalid duration.")
        }
        return seconds
    }
}
