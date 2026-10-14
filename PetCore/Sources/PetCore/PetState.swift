import Foundation

/// How the pet feels. Derived from `PetState.energy`, never stored.
public enum Mood: String, Codable, CaseIterable, Sendable {
    case happy, content, sleepy, sad

    /// Energy bands: 75...100 happy, 50..<75 content, 25..<50 sleepy, 0..<25 sad.
    public init(energy: Int) {
        switch energy {
        case 75...: self = .happy
        case 50..<75: self = .content
        case 25..<50: self = .sleepy
        default: self = .sad
        }
    }
}

/// Something that happened to the pet. Produced by the monitor extension
/// (threshold / interval callbacks) or by the user in the app or a notification.
public enum PetEvent: Equatable, Sendable {
    /// A `DeviceActivityEvent` reached its threshold. `eventName` is the event's
    /// raw name, used to ignore duplicate callbacks for the same threshold.
    case thresholdReached(eventName: String)
    /// The daily `DeviceActivitySchedule` interval started: reset for a new day.
    case newDay
    case fed
    case played
}

/// Tunable numbers for the reducer.
public struct PetRules: Equatable, Sendable {
    public var maxEnergy: Int
    public var thresholdPenalty: Int
    public var feedBoost: Int
    public var playBoost: Int
    /// Minimum time between feeds, so care can't instantly cancel out screen time.
    public var feedCooldown: TimeInterval
    public var playCooldown: TimeInterval

    public init(
        maxEnergy: Int = 100,
        thresholdPenalty: Int = 25,
        feedBoost: Int = 15,
        playBoost: Int = 10,
        feedCooldown: TimeInterval = 2 * 60 * 60,
        playCooldown: TimeInterval = 30 * 60
    ) {
        self.maxEnergy = maxEnergy
        self.thresholdPenalty = thresholdPenalty
        self.feedBoost = feedBoost
        self.playBoost = playBoost
        self.feedCooldown = feedCooldown
        self.playCooldown = playCooldown
    }

    public static let `default` = PetRules()
}

/// The whole persisted pet. Small and `Codable` so it fits in the App Group,
/// a notification's `userInfo`, or a Live Activity `ContentState` (4 KB limit).
public struct PetState: Codable, Equatable, Sendable {
    public var energy: Int
    public var lastFed: Date?
    public var lastPlayed: Date?
    /// Names of the thresholds already hit today (a set, so duplicate callbacks are no-ops).
    public var thresholdsHitToday: Set<String>

    public var mood: Mood { Mood(energy: energy) }

    public init(
        energy: Int = PetRules.default.maxEnergy,
        lastFed: Date? = nil,
        lastPlayed: Date? = nil,
        thresholdsHitToday: Set<String> = []
    ) {
        self.energy = energy
        self.lastFed = lastFed
        self.lastPlayed = lastPlayed
        self.thresholdsHitToday = thresholdsHitToday
    }

    public static let fresh = PetState()

    /// A state showing `mood`, for previews and CI screenshots.
    public static func sample(_ mood: Mood) -> PetState {
        switch mood {
        case .happy: PetState(energy: 90)
        case .content: PetState(energy: 60)
        case .sleepy: PetState(energy: 35)
        case .sad: PetState(energy: 10)
        }
    }

    public func canFeed(at now: Date, rules: PetRules = .default) -> Bool {
        lastFed.map { now.timeIntervalSince($0) >= rules.feedCooldown } ?? true
    }

    public func canPlay(at now: Date, rules: PetRules = .default) -> Bool {
        lastPlayed.map { now.timeIntervalSince($0) >= rules.playCooldown } ?? true
    }

    /// Pure reducer: returns the state after `event`. Events that aren't allowed
    /// (duplicate threshold, feeding during cooldown) return the state unchanged.
    public func applying(_ event: PetEvent, at now: Date, rules: PetRules = .default) -> PetState {
        var next = self
        switch event {
        case .thresholdReached(let name):
            guard !thresholdsHitToday.contains(name) else { return self }
            next.thresholdsHitToday.insert(name)
            next.energy -= rules.thresholdPenalty
        case .newDay:
            next.energy = rules.maxEnergy
            next.thresholdsHitToday = []
        case .fed:
            guard canFeed(at: now, rules: rules) else { return self }
            next.lastFed = now
            next.energy += rules.feedBoost
        case .played:
            guard canPlay(at: now, rules: rules) else { return self }
            next.lastPlayed = now
            next.energy += rules.playBoost
        }
        next.energy = min(max(next.energy, 0), rules.maxEnergy)
        return next
    }
}
