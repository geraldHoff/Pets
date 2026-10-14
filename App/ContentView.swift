import PetCore
import SwiftUI

struct ContentView: View {
    /// Launch argument used by CI: `-screenshotMood sleepy` shows that mood without touching saved state.
    private static let screenshotMood = UserDefaults.standard.string(forKey: "screenshotMood").flatMap(Mood.init(rawValue:))

    // TODO(milestone 3): switch to PetStore(appGroup:) once the App Group entitlement is set up.
    private let store = PetStore(defaults: .standard)

    @State private var state: PetState
    @State private var lastNotification: PetNotification?
    @State private var thresholdCount = 0

    init() {
        let initial = Self.screenshotMood.map(PetState.sample) ?? PetStore(defaults: .standard).load()
        _state = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Screen Pet")
                .font(.largeTitle.bold())

            PetSpriteView(animation: PetSprites.animation(for: state.mood))
                .frame(maxWidth: 260)
                .id(state.mood) // restart the animation when the mood changes

            VStack(spacing: 8) {
                Text(state.mood.rawValue.capitalized)
                    .font(.title2.weight(.semibold))
                ProgressView(value: Double(state.energy), total: 100) {
                    Text("Energy \(state.energy)")
                        .font(.caption)
                }
                .frame(maxWidth: 260)
            }

            HStack(spacing: 12) {
                Button("Feed") { send(.fed) }
                    .disabled(!state.canFeed(at: .now))
                Button("Play") { send(.played) }
                    .disabled(!state.canPlay(at: .now))
            }
            .buttonStyle(.borderedProminent)

            // Stand-ins for DeviceActivityMonitor callbacks until milestone 2.
            HStack(spacing: 12) {
                Button("Simulate threshold") {
                    thresholdCount += 1
                    send(.thresholdReached(eventName: "debug-\(thresholdCount)"))
                }
                Button("New day") { send(.newDay) }
            }
            .buttonStyle(.bordered)

            if let note = lastNotification {
                NotificationPreview(notification: note)
            }

            Spacer()
        }
        .padding()
    }

    private func send(_ event: PetEvent) {
        let old = state
        state = old.applying(event, at: .now)
        lastNotification = PetReactions.notification(from: old, to: state) ?? lastNotification
        if Self.screenshotMood == nil {
            store.save(state)
        }
    }
}

/// Mimics the notification the monitor extension will post, to iterate on copy and art.
private struct NotificationPreview: View {
    let notification: PetNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PetSpriteView(animation: PetSprites.animation(for: notification.mood))
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title).font(.subheadline.bold())
                Text(notification.body).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
