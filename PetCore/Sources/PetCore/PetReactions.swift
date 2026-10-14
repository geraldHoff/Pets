/// The notification the pet sends after a state change.
public struct PetNotification: Equatable, Sendable {
    public var title: String
    public var body: String
    /// Mood to render in the notification's attachment / content extension.
    public var mood: Mood

    public init(title: String, body: String, mood: Mood) {
        self.title = title
        self.body = body
        self.mood = mood
    }
}

public enum PetReactions {
    /// Decides whether a transition is worth a notification. Only mood changes
    /// notify, so repeated thresholds inside one mood band don't spam the user.
    public static func notification(from old: PetState, to new: PetState, petName: String = "Your pet") -> PetNotification? {
        guard old.mood != new.mood else { return nil }
        let body: String
        switch new.mood {
        case .happy:
            body = "\(petName) is bouncing around. Thanks for the attention!"
        case .content:
            body = "\(petName) is doing fine, but keep an eye on that screen time."
        case .sleepy:
            body = "\(petName) is getting drowsy from all this screen time."
        case .sad:
            body = "\(petName) is sad. Maybe put the phone down for a bit?"
        }
        return PetNotification(title: title(for: new.mood, petName: petName), body: body, mood: new.mood)
    }

    static func title(for mood: Mood, petName: String) -> String {
        switch mood {
        case .happy: "\(petName) is happy"
        case .content: "\(petName) is content"
        case .sleepy: "\(petName) is sleepy"
        case .sad: "\(petName) is sad"
        }
    }
}
