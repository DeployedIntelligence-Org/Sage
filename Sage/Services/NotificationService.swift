import Foundation
import UserNotifications

/// Manages local notifications for post-session check-ins.
///
/// ## Notification flow
/// When a session's `scheduledEnd` arrives:
/// 1. A banner fires with five quick-rate action buttons (⭐ … ⭐⭐⭐⭐⭐).
/// 2. **Quick action tap**: silently creates a `PracticeSession` with the chosen
///    rating, marks the `ScheduledSession` complete, and publishes
///    `recentlyLoggedSessionId` so `HomeView` can deep-link to the Chat tab where
///    Claude already knows about the result.
/// 3. **Banner body tap** (or no notification): sets `pendingFeedbackSessionId`
///    so `CalendarView` presents `PostSessionFeedbackView`.
final class NotificationService: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = NotificationService()

    // MARK: - Category / action identifiers

    static let checkInCategoryId   = "SAGE_CHECK_IN"
    private static let rateActionPrefix = "SAGE_RATE_"
    private static let ratingRange = 1...5

    // MARK: - Published state

    /// Non-nil when the user tapped the notification body (→ present `PostSessionFeedbackView`).
    @Published var pendingFeedbackSessionId: Int64?

    /// Set after a quick-rating action is handled; clears itself after `HomeView` consumes it.
    @Published var recentlyLoggedSessionId: Int64?

    // MARK: - Init

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategory()
    }

    // MARK: - Permission

    /// Requests notification authorisation. Call when a session is first scheduled so the
    /// system prompt appears in a meaningful context.
    func requestPermission() async {
        do {
            try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[NotificationService] Permission request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Schedule / Cancel

    /// Schedules a local notification at `session.scheduledEnd`.
    ///
    /// The notification includes five star-rating action buttons so the user can log
    /// without opening the app. Silently skips if the end time is in the past.
    func scheduleCheckIn(for session: ScheduledSession, skillName: String) {
        guard let sessionId = session.id else { return }

        let fireDate = session.scheduledEnd
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session Ended 🎯"
        content.body = "How did your \(skillName) practice go?"
        content.sound = .default
        content.categoryIdentifier = Self.checkInCategoryId
        // Store session ID as a string — numeric types can lose type info round-tripping
        // through UNNotificationRequest's userInfo dictionary.
        content.userInfo = ["sessionId": "\(sessionId)"]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationId(for: sessionId),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Schedule failed: \(error.localizedDescription)")
            }
        }
    }

    /// Cancels the pending check-in notification for `sessionId`.
    func cancelCheckIn(for sessionId: Int64) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId(for: sessionId)])
    }

    // MARK: - Private helpers

    private func notificationId(for sessionId: Int64) -> String {
        "sage-check-in-\(sessionId)"
    }

    /// Registers the check-in category with ⭐–⭐⭐⭐⭐⭐ quick-rate actions.
    private func registerNotificationCategory() {
        let stars = ["⭐", "⭐⭐", "⭐⭐⭐", "⭐⭐⭐⭐", "⭐⭐⭐⭐⭐"]
        let actions = Self.ratingRange.map { rating in
            UNNotificationAction(
                identifier: Self.rateActionPrefix + "\(rating)",
                title: stars[rating - 1],
                options: []
            )
        }

        let category = UNNotificationCategory(
            identifier: Self.checkInCategoryId,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Parses a star rating (1-5) from a notification action identifier, or returns nil
    /// for the default tap-body action.
    private func rating(from actionIdentifier: String) -> Int? {
        guard actionIdentifier.hasPrefix(Self.rateActionPrefix) else { return nil }
        let suffix = actionIdentifier.dropFirst(Self.rateActionPrefix.count)
        return Int(suffix)
    }

    /// Silently creates a `PracticeSession` with the quick-action rating, marks the
    /// `ScheduledSession` complete, and publishes the logged session ID.
    ///
    /// Must run on the main actor because it mutates `@Published` properties.
    @MainActor
    private func logQuickRating(sessionId: Int64, rating: Int) async {
        let db = DatabaseService.shared
        guard
            let session = try? db.fetchScheduledSession(id: sessionId),
            !session.completed
        else { return }

        let practice = PracticeSession(
            skillGoalId: session.skillGoalId,
            durationMinutes: session.durationMinutes,
            rating: rating
        )
        _ = try? db.insert(practice)
        try? db.markScheduledSessionCompleted(id: sessionId)
        cancelCheckIn(for: sessionId)

        recentlyLoggedSessionId = sessionId
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Called when the user interacts with a notification (tap body or quick-action button).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard
            let idStr = userInfo["sessionId"] as? String,
            let sessionId = Int64(idStr)
        else {
            completionHandler()
            return
        }

        if let stars = rating(from: response.actionIdentifier) {
            // Quick-rate action: log silently, then let HomeView switch to chat.
            Task { @MainActor in
                await logQuickRating(sessionId: sessionId, rating: stars)
            }
        } else {
            // Body tap: open full feedback sheet.
            DispatchQueue.main.async {
                self.pendingFeedbackSessionId = sessionId
            }
        }
        completionHandler()
    }

    /// Called when a notification arrives while the app is in the foreground.
    /// Displays the banner (so the user can use the quick-rate buttons) and also
    /// sets `pendingFeedbackSessionId` so the check-in sheet can be shown.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let idStr = userInfo["sessionId"] as? String, let sessionId = Int64(idStr) {
            DispatchQueue.main.async {
                self.pendingFeedbackSessionId = sessionId
            }
        }
        completionHandler([.banner, .sound])
    }
}
