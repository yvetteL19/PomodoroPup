import XCTest
@testable import PomodoroPupCore

@MainActor
final class NotificationFeedbackTests: XCTestCase {
    func testCompletedPhaseSendsOnlyAfterSnapshotIsSaved() async {
        let fixture = FeedbackFixture()
        fixture.model.startTimer()
        fixture.clock.advance(60)
        fixture.model.refresh()

        XCTAssertEqual(fixture.messages.count, 1)
        XCTAssertFalse(fixture.messages[0].soundEnabled)
        XCTAssertEqual(fixture.messages[0].savedCompletionCount, 1)
        XCTAssertEqual(fixture.model.completedPomodoros, 1)
    }

    func testFailedSaveSuppressesNotification() async {
        let fixture = FeedbackFixture()
        fixture.model.startTimer()
        let corrupt = Data("preserve me".utf8)
        fixture.defaults.set(corrupt, forKey: StateStore.snapshotKey)
        fixture.clock.advance(60)
        fixture.model.refresh()

        XCTAssertNotNil(fixture.model.storageError)
        XCTAssertTrue(fixture.messages.isEmpty)
        XCTAssertEqual(fixture.defaults.data(forKey: StateStore.snapshotKey), corrupt)
    }

    func testNotificationPreferenceAndEffectsFlagGateInjectedSender() async {
        let fixture = FeedbackFixture()
        fixture.model.notificationEnabled = false
        fixture.model.startTimer()
        fixture.clock.advance(60)
        fixture.model.refresh()
        XCTAssertTrue(fixture.messages.isEmpty)

        let silent = FeedbackFixture(effectsEnabled: false)
        silent.model.startTimer()
        silent.clock.advance(60)
        silent.model.refresh()
        XCTAssertTrue(silent.messages.isEmpty)
    }

    func testManualSkipsDoNotSendCompletionReminders() async {
        let fixture = FeedbackFixture()
        fixture.model.startTimer()
        fixture.model.skipPhase()
        fixture.model.skipPhase()
        XCTAssertTrue(fixture.model.isWaitingForNextSession)
        XCTAssertTrue(fixture.messages.isEmpty)
    }

    func testDailyGoalUsesOneNotificationInsteadOfDuplicateBreakReminder() async {
        let fixture = FeedbackFixture()
        fixture.model.dailyGoal = 1
        fixture.model.startTimer()
        fixture.clock.advance(60)
        fixture.model.refresh()
        XCTAssertEqual(fixture.messages.count, 1)
        XCTAssertEqual(fixture.messages[0].savedCompletionCount, 1)
        fixture.model.refresh()
        XCTAssertEqual(fixture.messages.count, 1)
    }
}

private final class FeedbackClock: TimerClock {
    var now = Date(timeIntervalSince1970: 1_792_670_400)
    var uptime: TimeInterval = 1000
    func advance(_ seconds: TimeInterval) {
        now.addTimeInterval(seconds)
        uptime += seconds
    }
}

private final class FeedbackFixture {
    struct Message {
        let soundEnabled: Bool
        let savedCompletionCount: Int?
    }
    let suite = "PomodoroPup.NotificationFeedbackTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let clock = FeedbackClock()
    var model: DogViewModel!
    var messages: [Message] = []

    init(effectsEnabled: Bool = true) {
        defaults = UserDefaults(suiteName: suite)!
        model = DogViewModel(
            store: StateStore(defaults: defaults), clock: clock,
            automaticTicks: false, effectsEnabled: effectsEnabled,
            notificationSender: { [weak self] _, _, sound in
                guard let self else { return }
                let state = self.defaults.data(forKey: StateStore.snapshotKey)
                    .flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
                self.messages.append(Message(soundEnabled: sound, savedCompletionCount: state?.completedPomodoros))
            }
        )
        // Effects are enabled only to exercise the injected notification callback.
        // Real sound and animation are disabled before any timer can advance.
        model.soundEnabled = false
        model.animationEnabled = false
        model.workDuration = 60
        model.breakDuration = 60
    }

    deinit { defaults.removePersistentDomain(forName: suite) }
}
