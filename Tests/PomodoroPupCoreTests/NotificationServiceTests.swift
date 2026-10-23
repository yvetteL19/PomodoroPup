import XCTest
import UserNotifications
@testable import PomodoroPupCore

@MainActor
final class NotificationServiceTests: XCTestCase {
    func testRefreshMapsActualSystemSettingsWithoutRequestingPermission() async {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center)
        let examples: [(NotificationSettingsSnapshot.Authorization, Bool, NotificationPermissionStatus)] = [
            (.notDetermined, false, .notDetermined),
            (.authorized, true, .allowed),
            (.authorized, false, .alertsDisabled),
            (.denied, false, .denied),
            (.provisional, true, .allowed),
            (.provisional, false, .alertsDisabled),
            (.unknown, false, .error)
        ]
        for (authorization, alertsEnabled, expected) in examples {
            center.snapshot = NotificationSettingsSnapshot(authorization: authorization, alertsEnabled: alertsEnabled)
            await service.refresh()
            XCTAssertEqual(service.status, expected)
        }
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testExplicitRequestReadsSettingsAgainInsteadOfTrustingBooleanResult() async {
        let center = MockNotificationCenter()
        center.snapshotAfterAuthorization = NotificationSettingsSnapshot(authorization: .authorized, alertsEnabled: false)
        let service = NotificationService(center: center)
        await service.requestPermission()

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(center.settingsRequests, 2)
        XCTAssertEqual(service.status, .alertsDisabled)
        XCTAssertNil(service.errorMessage)
    }

    func testDeniedPermissionIsNotRequestedAgain() async {
        let center = MockNotificationCenter(snapshot: .denied)
        let service = NotificationService(center: center)
        await service.requestPermission()
        XCTAssertEqual(service.status, .denied)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    func testRequestingStateSurvivesActivationRefreshAndDuplicateRequest() async {
        let center = MockNotificationCenter()
        center.holdAuthorization = true
        let service = NotificationService(center: center)
        let request = Task { await service.requestPermission() }
        await center.waitForAuthorizationRequest()

        XCTAssertEqual(service.status, .requesting)
        await service.refresh()
        await service.requestPermission()
        XCTAssertEqual(service.status, .requesting)
        XCTAssertEqual(center.authorizationRequests, 1)
        center.completeAuthorization(with: .allowed)
        await request.value
        XCTAssertEqual(service.status, .allowed)
    }

    func testAuthorizationFailureIsVisibleAndRefreshCanRecover() async {
        let center = MockNotificationCenter()
        center.authorizationError = NotificationMockError.failed
        let service = NotificationService(center: center)
        await service.requestPermission()
        XCTAssertEqual(service.status, .error)
        XCTAssertNotNil(service.errorMessage)

        center.snapshot = .allowed
        await service.refresh()
        XCTAssertEqual(service.status, .allowed)
        XCTAssertNil(service.errorMessage)
    }

    func testTestNotificationHonorsSoundToggleAndUsesUniqueIdentifiers() async {
        let center = MockNotificationCenter(snapshot: .allowed)
        let service = NotificationService(center: center)
        await service.sendTest(soundEnabled: false)
        XCTAssertEqual(service.testResult, .sent)
        XCTAssertNil(center.requests.first?.content.sound)
        XCTAssertNil(center.requests.first?.trigger)

        await service.sendTest(soundEnabled: true)
        XCTAssertEqual(service.testResult, .sent)
        XCTAssertEqual(center.requests.count, 2)
        XCTAssertNotNil(center.requests.last?.content.sound)
        XCTAssertNotEqual(center.requests.first?.identifier, center.requests.last?.identifier)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    func testNaturalNotificationHonorsSoundAndDoesNotChangeTestResult() async {
        let center = MockNotificationCenter(snapshot: .allowed)
        let service = NotificationService(center: center)
        await service.send(title: "Focus finished", body: "Time for a break", soundEnabled: false)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.requests.first?.content.title, "Focus finished")
        XCTAssertEqual(center.requests.first?.content.body, "Time for a break")
        XCTAssertNil(center.requests.first?.content.sound)
        XCTAssertNil(service.testResult)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    func testSendingWithoutEnabledAlertsNeverPromptsOrEnqueuesNotification() async {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center)
        for snapshot in [NotificationSettingsSnapshot.notDetermined, .denied, .alertsDisabled] {
            center.snapshot = snapshot
            await service.sendTest(soundEnabled: true)
            XCTAssertEqual(service.testResult, .permissionRequired)
        }
        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    func testDeliveryErrorIsVisibleAndNeverReportedAsSent() async {
        let center = MockNotificationCenter(snapshot: .allowed)
        center.addError = NotificationMockError.failed
        let service = NotificationService(center: center)
        await service.sendTest(soundEnabled: false)
        XCTAssertEqual(service.testResult, .failed)
        XCTAssertEqual(service.status, .error)
        XCTAssertNotNil(service.errorMessage)
    }

    func testSettingsQueryErrorIsVisibleAndPreventsDelivery() async {
        let center = MockNotificationCenter(snapshot: .allowed)
        center.settingsError = NotificationMockError.failed
        let service = NotificationService(center: center)
        await service.sendTest(soundEnabled: false)
        XCTAssertEqual(service.status, .error)
        XCTAssertEqual(service.testResult, .failed)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testOlderSettingsResponseCannotOverwriteNewerState() async {
        let center = MockNotificationCenter()
        center.holdSettings = true
        let service = NotificationService(center: center)
        let older = Task { await service.refresh() }
        await center.waitForSettingsRequests(1)
        let newer = Task { await service.refresh() }
        await center.waitForSettingsRequests(2)

        center.completeSettings(at: 1, with: .denied)
        await newer.value
        XCTAssertEqual(service.status, .denied)
        center.completeSettings(at: 0, with: .allowed)
        await older.value
        XCTAssertEqual(service.status, .denied)
    }

    func testStaleAllowedResponseCannotSendAfterNewerDeniedSettings() async {
        let center = MockNotificationCenter()
        center.holdSettings = true
        let service = NotificationService(center: center)
        let test = Task { await service.sendTest(soundEnabled: true) }
        await center.waitForSettingsRequests(1)
        let refresh = Task { await service.refresh() }
        await center.waitForSettingsRequests(2)

        center.completeSettings(at: 1, with: .denied)
        await refresh.value
        center.completeSettings(at: 0, with: .allowed)
        await test.value
        XCTAssertEqual(service.status, .denied)
        XCTAssertEqual(service.testResult, .permissionRequired)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testConcurrentAllowedRefreshDoesNotDiscardNotification() async {
        let center = MockNotificationCenter()
        center.holdSettings = true
        let service = NotificationService(center: center)
        let test = Task { await service.sendTest(soundEnabled: false) }
        await center.waitForSettingsRequests(1)
        let refresh = Task { await service.refresh() }
        await center.waitForSettingsRequests(2)

        center.completeSettings(at: 1, with: .allowed)
        await refresh.value
        center.completeSettings(at: 0, with: .allowed)
        await test.value

        XCTAssertEqual(service.status, .allowed)
        XCTAssertEqual(service.testResult, .sent)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.settingsRequests, 2, "Delivery should reuse the latest result, not add another query.")
    }

    func testDeliveryUsesNewerOutstandingPermissionQuery() async {
        let center = MockNotificationCenter()
        center.holdSettings = true
        let service = NotificationService(center: center)
        let test = Task { await service.sendTest(soundEnabled: false) }
        await center.waitForSettingsRequests(1)
        let refresh = Task { await service.refresh() }
        await center.waitForSettingsRequests(2)

        // The send's older answer is denied, but a newer permission check is still
        // outstanding. Only that newest result should decide whether to send.
        center.completeSettings(at: 0, with: .denied)
        await Task.yield()
        XCTAssertNil(service.testResult)
        XCTAssertTrue(center.requests.isEmpty)
        center.completeSettings(at: 0, with: .allowed)
        await refresh.value
        await test.value

        XCTAssertEqual(service.status, .allowed)
        XCTAssertEqual(service.testResult, .sent)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.settingsRequests, 2)
    }
}

private enum NotificationMockError: Error { case failed }

private extension NotificationSettingsSnapshot {
    static let notDetermined = Self(authorization: .notDetermined, alertsEnabled: false)
    static let allowed = Self(authorization: .authorized, alertsEnabled: true)
    static let denied = Self(authorization: .denied, alertsEnabled: false)
    static let alertsDisabled = Self(authorization: .authorized, alertsEnabled: false)
}

@MainActor
private final class MockNotificationCenter: NotificationCenterClient {
    var snapshot: NotificationSettingsSnapshot
    var snapshotAfterAuthorization: NotificationSettingsSnapshot = .allowed
    var settingsError: Error?
    var authorizationError: Error?
    var addError: Error?
    var holdAuthorization = false
    var holdSettings = false
    private(set) var settingsRequests = 0
    private(set) var authorizationRequests = 0
    private(set) var requests: [UNNotificationRequest] = []
    private var authorizationContinuation: CheckedContinuation<Bool, Error>?
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var settingsContinuations: [CheckedContinuation<NotificationSettingsSnapshot, Error>] = []
    private var settingsWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(snapshot: NotificationSettingsSnapshot = .notDetermined) {
        self.snapshot = snapshot
    }

    func settings() async throws -> NotificationSettingsSnapshot {
        settingsRequests += 1
        if let settingsError { throw settingsError }
        if holdSettings {
            return try await withCheckedThrowingContinuation { continuation in
                settingsContinuations.append(continuation)
                let ready = settingsWaiters.filter { $0.0 <= settingsRequests }
                settingsWaiters.removeAll { $0.0 <= settingsRequests }
                ready.forEach { $0.1.resume() }
            }
        }
        return snapshot
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        if let authorizationError { throw authorizationError }
        if holdAuthorization {
            return try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                authorizationWaiters.forEach { $0.resume() }
                authorizationWaiters.removeAll()
            }
        }
        snapshot = snapshotAfterAuthorization
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let addError { throw addError }
        requests.append(request)
    }

    func waitForAuthorizationRequest() async {
        if authorizationContinuation != nil { return }
        await withCheckedContinuation { authorizationWaiters.append($0) }
    }

    func completeAuthorization(with snapshot: NotificationSettingsSnapshot) {
        self.snapshot = snapshot
        authorizationContinuation?.resume(returning: snapshot.authorization == .authorized)
        authorizationContinuation = nil
    }

    func waitForSettingsRequests(_ count: Int) async {
        if settingsRequests >= count { return }
        await withCheckedContinuation { settingsWaiters.append((count, $0)) }
    }

    func completeSettings(at index: Int, with snapshot: NotificationSettingsSnapshot) {
        settingsContinuations.remove(at: index).resume(returning: snapshot)
    }
}
