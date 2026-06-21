import Foundation
import Perception

public struct GateChainFixtureCase: Codable, Equatable, Sendable {
    public var id: String
    public var description: String
    public var screenState: ScreenState
    public var powerSnapshot: PowerSnapshot
    public var idleDuration: TimeInterval
    public var frontAppSnapshot: FrontAppSnapshot
    public var previousFrontAppSnapshot: FrontAppSnapshot?
    public var regionHash: RegionHashDTO?
    public var recentInputActive: Bool
    public var aiBusy: Bool
    public var secondsSinceLastAnalysis: TimeInterval
    public var secondsSinceLastAI: TimeInterval
    public var expectedDecisionKind: GateDecisionKind
    public var expectedSignals: [TriggerSignal]

    public init(
        id: String,
        description: String,
        screenState: ScreenState = .active,
        powerSnapshot: PowerSnapshot = .nominal,
        idleDuration: TimeInterval = 2,
        frontAppSnapshot: FrontAppSnapshot = FrontAppSnapshot(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitles: ["Article"]),
        previousFrontAppSnapshot: FrontAppSnapshot? = nil,
        regionHash: RegionHashDTO? = nil,
        recentInputActive: Bool = false,
        aiBusy: Bool = false,
        secondsSinceLastAnalysis: TimeInterval = 30,
        secondsSinceLastAI: TimeInterval = 30,
        expectedDecisionKind: GateDecisionKind,
        expectedSignals: [TriggerSignal] = []
    ) {
        self.id = id
        self.description = description
        self.screenState = screenState
        self.powerSnapshot = powerSnapshot
        self.idleDuration = idleDuration
        self.frontAppSnapshot = frontAppSnapshot
        self.previousFrontAppSnapshot = previousFrontAppSnapshot
        self.regionHash = regionHash
        self.recentInputActive = recentInputActive
        self.aiBusy = aiBusy
        self.secondsSinceLastAnalysis = secondsSinceLastAnalysis
        self.secondsSinceLastAI = secondsSinceLastAI
        self.expectedDecisionKind = expectedDecisionKind
        self.expectedSignals = expectedSignals
    }
}

public enum GateChainFixtureFactory {
    public static func requiredCases() -> [GateChainFixtureCase] {
        [
            GateChainFixtureCase(
                id: "locked-screen",
                description: "locked screen -> pausedScreenLocked",
                screenState: .locked,
                expectedDecisionKind: .pausedScreenLocked
            ),
            GateChainFixtureCase(
                id: "idle-over-threshold",
                description: "idle > 60s -> skipIdle",
                idleDuration: 60.1,
                expectedDecisionKind: .skipIdle
            ),
            GateChainFixtureCase(
                id: "ai-busy",
                description: "AI busy -> skipAIBusy",
                aiBusy: true,
                expectedDecisionKind: .skipAIBusy
            ),
            GateChainFixtureCase(
                id: "app-changed",
                description: "app changed -> analyze",
                frontAppSnapshot: FrontAppSnapshot(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", windowTitles: ["Article"]),
                previousFrontAppSnapshot: FrontAppSnapshot(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitles: ["Article"]),
                expectedDecisionKind: .analyze,
                expectedSignals: [.appChanged]
            ),
            GateChainFixtureCase(
                id: "window-title-changed",
                description: "window title changed -> analyze",
                frontAppSnapshot: FrontAppSnapshot(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitles: ["Dashboard"]),
                previousFrontAppSnapshot: FrontAppSnapshot(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitles: ["Article"]),
                expectedDecisionKind: .analyze,
                expectedSignals: [.windowTitleChanged]
            ),
            GateChainFixtureCase(
                id: "region-hash-changed",
                description: "region hash changed -> analyze",
                regionHash: RegionHashDTO(
                    globalDistance: 2,
                    regionDistances: [.bottomRight: 8],
                    changedRegions: [.bottomRight]
                ),
                expectedDecisionKind: .analyze,
                expectedSignals: [.regionHashChanged]
            ),
            GateChainFixtureCase(
                id: "recent-input-min-interval",
                description: "recent input active + min interval reached -> analyze",
                recentInputActive: true,
                secondsSinceLastAI: 15,
                expectedDecisionKind: .analyze,
                expectedSignals: [.recentInputActive]
            ),
            GateChainFixtureCase(
                id: "stable-under-force-refresh",
                description: "no signal + under force refresh -> skipStable",
                secondsSinceLastAnalysis: 119,
                secondsSinceLastAI: 14,
                expectedDecisionKind: .skipStable
            ),
            GateChainFixtureCase(
                id: "force-refresh",
                description: "force refresh interval reached -> analyze",
                secondsSinceLastAnalysis: 120,
                expectedDecisionKind: .analyze,
                expectedSignals: [.forceRefreshInterval]
            ),
            GateChainFixtureCase(
                id: "privacy-blocked",
                description: "privacy blocked -> skipPrivacyBlocked",
                frontAppSnapshot: FrontAppSnapshot(appName: "1Password", bundleIdentifier: "com.1password.1password", windowTitles: ["Vault"]),
                expectedDecisionKind: .skipPrivacyBlocked
            )
        ]
    }
}
