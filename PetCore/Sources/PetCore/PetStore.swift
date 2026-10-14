import Foundation

/// Loads and saves `PetState` as JSON in a `UserDefaults` suite.
/// In the app and extensions, use `PetStore(appGroup:)` so every process sees the same state.
public struct PetStore {
    public static let stateKey = "petState"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Returns nil when the App Group isn't configured for this target (missing entitlement).
    public init?(appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return nil }
        self.init(defaults: defaults)
    }

    /// The saved state, or `.fresh` if nothing (or something unreadable) is saved.
    public func load() -> PetState {
        guard let data = defaults.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(PetState.self, from: data)
        else { return .fresh }
        return state
    }

    public func save(_ state: PetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }

    /// Load, apply `event`, save. Returns both states so the caller can decide on a notification.
    @discardableResult
    public func apply(_ event: PetEvent, at now: Date, rules: PetRules = .default) -> (old: PetState, new: PetState) {
        let old = load()
        let new = old.applying(event, at: now, rules: rules)
        if new != old { save(new) }
        return (old, new)
    }
}
