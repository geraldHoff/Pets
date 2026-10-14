import Foundation
import Testing
@testable import PetCore

private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Suite struct MoodTests {
    @Test(arguments: [
        (100, Mood.happy), (75, .happy),
        (74, .content), (50, .content),
        (49, .sleepy), (25, .sleepy),
        (24, .sad), (0, .sad),
    ])
    func energyBands(energy: Int, expected: Mood) {
        #expect(Mood(energy: energy) == expected)
    }

    @Test func samplesShowTheirMood() {
        for mood in Mood.allCases {
            #expect(PetState.sample(mood).mood == mood)
        }
    }
}

@Suite struct ReducerTests {
    @Test func thresholdLowersEnergy() {
        let state = PetState.fresh.applying(.thresholdReached(eventName: "30min"), at: noon)
        #expect(state.energy == 75)
        #expect(state.thresholdsHitToday == ["30min"])
    }

    @Test func duplicateThresholdCallbackIsIgnored() {
        let once = PetState.fresh.applying(.thresholdReached(eventName: "30min"), at: noon)
        let twice = once.applying(.thresholdReached(eventName: "30min"), at: noon)
        #expect(twice == once)
    }

    @Test func fourThresholdsMakeThePetSad() {
        var state = PetState.fresh
        for name in ["30min", "1h", "2h", "3h"] {
            state = state.applying(.thresholdReached(eventName: name), at: noon)
        }
        #expect(state.energy == 0)
        #expect(state.mood == .sad)
    }

    @Test func energyNeverGoesBelowZeroOrAboveMax() {
        var state = PetState(energy: 10)
        state = state.applying(.thresholdReached(eventName: "a"), at: noon)
        #expect(state.energy == 0)

        state = PetState(energy: 95).applying(.fed, at: noon)
        #expect(state.energy == 100)
    }

    @Test func newDayResets() {
        let tired = PetState(energy: 20, lastFed: noon, thresholdsHitToday: ["30min", "1h"])
        let state = tired.applying(.newDay, at: noon)
        #expect(state.energy == 100)
        #expect(state.thresholdsHitToday.isEmpty)
        #expect(state.lastFed == noon, "care history survives the reset")
    }

    @Test func feedingHasACooldown() {
        let fed = PetState(energy: 50).applying(.fed, at: noon)
        #expect(fed.energy == 65)
        #expect(fed.lastFed == noon)

        let tooSoon = fed.applying(.fed, at: noon.addingTimeInterval(60 * 60))
        #expect(tooSoon == fed)

        let later = fed.applying(.fed, at: noon.addingTimeInterval(2 * 60 * 60))
        #expect(later.energy == 80)
    }

    @Test func playingHasItsOwnCooldown() {
        let played = PetState(energy: 50).applying(.played, at: noon)
        #expect(played.energy == 60)
        #expect(played.canPlay(at: noon.addingTimeInterval(29 * 60)) == false)
        #expect(played.canPlay(at: noon.addingTimeInterval(30 * 60)))
        #expect(played.canFeed(at: noon), "playing doesn't block feeding")
    }

    @Test func customRules() {
        let rules = PetRules(thresholdPenalty: 50)
        let state = PetState.fresh.applying(.thresholdReached(eventName: "x"), at: noon, rules: rules)
        #expect(state.energy == 50)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let state = PetState(energy: 42, lastFed: noon, lastPlayed: nil, thresholdsHitToday: ["1h"])
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(PetState.self, from: data) == state)
        #expect(data.count < 4096, "must fit a Live Activity ContentState / push payload")
    }
}

@Suite struct ReactionTests {
    @Test func moodChangeNotifies() throws {
        let old = PetState(energy: 80)
        let new = old.applying(.thresholdReached(eventName: "1h"), at: noon)
        let note = try #require(PetReactions.notification(from: old, to: new, petName: "Mochi"))
        #expect(note.mood == .content)
        #expect(note.title == "Mochi is content")
        #expect(note.body.contains("Mochi"))
    }

    @Test func sameMoodStaysQuiet() {
        let old = PetState(energy: 100)
        let new = PetState(energy: 90)
        #expect(PetReactions.notification(from: old, to: new) == nil)
    }

    @Test func everyMoodHasCopy() {
        for mood in Mood.allCases {
            let from = PetState.sample(mood == .happy ? .sad : .happy)
            let note = PetReactions.notification(from: from, to: .sample(mood))
            #expect(note?.mood == mood)
            #expect(note?.body.isEmpty == false)
        }
    }
}

@Suite struct StoreTests {
    private func makeStore() -> PetStore {
        let suite = "PetCoreTests-\(UUID().uuidString)"
        return PetStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func loadsFreshWhenEmpty() {
        #expect(makeStore().load() == .fresh)
    }

    @Test func saveThenLoad() {
        let store = makeStore()
        let state = PetState(energy: 33, thresholdsHitToday: ["2h"])
        store.save(state)
        #expect(store.load() == state)
    }

    @Test func applyPersistsAndReturnsBothStates() {
        let store = makeStore()
        let (old, new) = store.apply(.thresholdReached(eventName: "30min"), at: noon)
        #expect(old == .fresh)
        #expect(new.energy == 75)
        #expect(store.load() == new)
    }
}
