import AppKit
import Combine
import UserNotifications

enum NotificationPermissionStatus: Equatable {
    case notDetermined, allowed, denied, alertsDisabled, requesting, error
}

enum NotificationTestResult: Equatable {
    case sent, permissionRequired, failed
}

struct NotificationSettingsSnapshot: Equatable {
    enum Authorization: Equatable {
        case notDetermined, authorized, denied, provisional, unknown
    }

    let authorization: Authorization
    let alertsEnabled: Bool
}

/// The boundary is injectable so tests never query or mutate macOS notification settings.
@MainActor
protocol NotificationCenterClient {
    func settings() async throws -> NotificationSettingsSnapshot
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
final class SystemNotificationCenterClient: NotificationCenterClient {
    func settings() async throws -> NotificationSettingsSnapshot {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let authorization: NotificationSettingsSnapshot.Authorization
                switch settings.authorizationStatus {
                case .notDetermined: authorization = .notDetermined
                case .authorized: authorization = .authorized
                case .denied: authorization = .denied
                case .provisional: authorization = .provisional
                @unknown default: authorization = .unknown
                }
                continuation.resume(returning: NotificationSettingsSnapshot(
                    authorization: authorization,
                    alertsEnabled: settings.alertSetting == .enabled
                ))
            }
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var status: NotificationPermissionStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var testResult: NotificationTestResult?

    private let center: NotificationCenterClient
    private struct SettingsQuery {
        let revision: Int
        let task: Task<NotificationSettingsSnapshot, Error>
    }
    private var queryRevision = 0
    private var appliedQueryRevision = 0
    private var latestQuery: SettingsQuery?
    private var testRevision = 0
    private var permissionRequestInFlight = false

    init(center: NotificationCenterClient? = nil) {
        self.center = center ?? SystemNotificationCenterClient()
    }

    func refresh() async {
        guard !permissionRequestInFlight else { return }
        _ = await querySettings()
    }

    func requestPermission() async {
        guard !permissionRequestInFlight else { return }
        permissionRequestInFlight = true
        queryRevision += 1 // Invalidate any refresh that began before this explicit request.
        latestQuery = nil
        testRevision += 1
        status = .requesting
        errorMessage = nil
        testResult = nil
        defer { permissionRequestInFlight = false }

        do {
            let existing = try await center.settings()
            if existing.authorization == .notDetermined {
                _ = try await center.requestAuthorization()
            }
            // A request result alone does not describe disabled banners or a later
            // system-settings change. Always read the actual current configuration.
            apply(try await center.settings())
        } catch {
            report(error)
        }
    }

    func sendTest(soundEnabled: Bool) async {
        testRevision += 1
        let revision = testRevision
        testResult = nil
        let result = await deliver(
            title: NSLocalizedString("notification.test_title", comment: ""),
            body: NSLocalizedString("notification.test_body", comment: ""),
            soundEnabled: soundEnabled
        )
        if revision == testRevision { testResult = result }
    }

    /// Sending never requests permission. The user controls that action in the UI.
    func send(title: String, body: String, soundEnabled: Bool) async {
        _ = await deliver(title: title, body: body, soundEnabled: soundEnabled)
    }

    func openSystemSettings() {
        // Open the application by its real bundle identity. Private deep links into
        // notification panes are not a reliable navigation contract.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"),
              NSWorkspace.shared.open(url) else {
            status = .error
            errorMessage = NSLocalizedString("notification.settings_open_error", comment: "")
            return
        }
    }

    private func deliver(title: String, body: String, soundEnabled: Bool) async -> NotificationTestResult {
        guard !permissionRequestInFlight else { return .permissionRequired }
        var query = beginSettingsQuery()
        var resolvedSettings: NotificationSettingsSnapshot?
        while true {
            resolvedSettings = await resolve(query)
            guard !permissionRequestInFlight else { return .permissionRequired }
            if query.revision == queryRevision { break }
            // Activation and a visible settings window can both refresh permissions
            // while a send is awaiting its query. Reuse and await the newest query;
            // a newer request is not itself evidence that permission was revoked.
            query = latestQuery ?? beginSettingsQuery()
        }
        guard let settings = resolvedSettings else { return .failed }
        guard Self.permissionStatus(for: settings) == .allowed else { return .permissionRequired }
        let revision = query.revision
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = soundEnabled ? .default : nil
        do {
            try await center.add(UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            ))
            // Accepted by macOS; Focus and system presentation preferences may still
            // suppress the banner. UI copy should say sent, not promise delivery.
            return .sent
        } catch {
            if revision == queryRevision { report(error) }
            return .failed
        }
    }

    private func querySettings() async -> NotificationSettingsSnapshot? {
        await resolve(beginSettingsQuery())
    }

    private func beginSettingsQuery() -> SettingsQuery {
        queryRevision += 1
        let center = center
        let query = SettingsQuery(
            revision: queryRevision,
            task: Task { try await center.settings() }
        )
        latestQuery = query
        return query
    }

    private func resolve(_ query: SettingsQuery) async -> NotificationSettingsSnapshot? {
        do {
            let settings = try await query.task.value
            if query.revision == queryRevision && !permissionRequestInFlight && appliedQueryRevision != query.revision {
                appliedQueryRevision = query.revision
                apply(settings)
            }
            return settings
        } catch {
            if query.revision == queryRevision && !permissionRequestInFlight && appliedQueryRevision != query.revision {
                appliedQueryRevision = query.revision
                report(error)
            }
            return nil
        }
    }

    private func apply(_ settings: NotificationSettingsSnapshot) {
        status = Self.permissionStatus(for: settings)
        errorMessage = status == .error ? NSLocalizedString("notification.error_generic", comment: "") : nil
    }

    private static func permissionStatus(for settings: NotificationSettingsSnapshot) -> NotificationPermissionStatus {
        switch settings.authorization {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional:
            return settings.alertsEnabled ? .allowed : .alertsDisabled
        case .unknown: return .error
        }
    }

    private func report(_ error: Error) {
        status = .error
        errorMessage = error.localizedDescription
    }
}
