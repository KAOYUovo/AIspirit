import AppKit
import CoreGraphics
import Foundation

public struct NSWorkspaceFrontAppDetector: FrontAppDetecting {
    public init() {}

    public func detect() async throws -> FrontAppSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .unknown
        }

        let processIdentifier = Int(app.processIdentifier)
        let titles = Self.windowTitles(processIdentifier: app.processIdentifier)

        return FrontAppSnapshot(
            appName: app.localizedName ?? "unknown",
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: processIdentifier,
            windowTitles: titles
        )
    }

    private static func windowTitles(processIdentifier: pid_t) -> [String] {
        guard
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return windowList.compactMap { window in
            guard
                let ownerPID = numericValue(window[kCGWindowOwnerPID as String]),
                pid_t(ownerPID) == processIdentifier,
                let title = window[kCGWindowName as String] as? String,
                title.isEmpty == false
            else {
                return nil
            }
            return title
        }
    }

    private static func numericValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        default:
            return nil
        }
    }
}
