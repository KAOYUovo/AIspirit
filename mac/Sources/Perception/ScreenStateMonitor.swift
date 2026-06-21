import AppKit
import Foundation

public final class ScreenStateMonitor: ScreenStateMonitoring, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "ai.spirit.perception.screen-state")
    private var state: ScreenState
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    public init(initialState: ScreenState = .active, observeNotifications: Bool = true) {
        self.state = initialState

        if observeNotifications {
            installObservers()
        }
    }

    deinit {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()

        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        distributedObservers.forEach { distributedCenter.removeObserver($0) }
    }

    public func currentState() async throws -> ScreenState {
        stateQueue.sync { state }
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributedCenter = DistributedNotificationCenter.default()

        distributedObservers.append(
            distributedCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setState(.locked)
            }
        )
        distributedObservers.append(
            distributedCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setState(.active)
            }
        )

        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setState(.screenSleeping)
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setState(.active)
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setState(.systemSleeping)
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setState(.active)
            }
        )
    }

    private func setState(_ state: ScreenState) {
        stateQueue.sync {
            self.state = state
        }
    }
}
