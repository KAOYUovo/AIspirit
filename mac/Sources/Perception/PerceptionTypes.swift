import Foundation

public enum ScreenRegion: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case center
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

public enum AttentionState: String, Codable, Sendable {
    case busy
    case observing
    case engaged
}

public enum ContentType: String, Codable, Sendable {
    case movie
    case tvShow
    case sports
    case liveStream
    case course
    case game
    case office
    case coding
    case chat
    case unknown
}

public enum PerceptionMode: String, Codable, Sendable {
    case normal
    case coWatching
    case lowPower
    case paused
}

public enum GateDecisionKind: String, Codable, Sendable {
    case analyze
    case skipIdle
    case skipStable
    case skipAIBusy
    case skipNoScreen
    case skipPrivacyBlocked
    case pausedScreenLocked
    case pausedScreenSleeping
    case pausedSystemSleeping
    case lowPowerThrottled
    case fallback
}

public enum TriggerSignal: String, Codable, Sendable {
    case regionHashChanged
    case appChanged
    case windowTitleChanged
    case recentInputActive
    case forceRefreshInterval
    case dynamicContent
    case userInvoked
    case coWatchingKeyframe
}

public enum PetActionType: String, Codable, Sendable {
    case setExpression
    case playAnimation
    case showBubble
    case suppressBubble
    case enterCoWatching
    case exitCoWatching
}

public enum AttentionEventKind: String, Codable, Equatable, Sendable {
    case passive
    case userInvokedPet
}

public enum PetActionIntent: String, Codable, Equatable, Sendable {
    case shortBubble
    case longBubble
}
