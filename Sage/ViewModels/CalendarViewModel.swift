import Foundation
import EventKit

@MainActor
final class CalendarViewModel: ObservableObject {

    // MARK: - Published state

    @Published var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var selectedDuration: TimeInterval = 30 * 60
    @Published var freeSlots: [DateInterval] = []
    @Published var isLoading = false

    /// Set to a slot to present the scheduling sheet.
    @Published var slotToSchedule: DateInterval? = nil

    /// The most recently saved ScheduledSession (used to confirm success).
    @Published var lastScheduled: ScheduledSession? = nil

    /// Non-nil when scheduling fails.
    @Published var schedulingError: String? = nil

    /// The user's active skill goal (loaded once on first authorized appear).
    @Published var skillGoal: SkillGoal? = nil

    /// Sessions that have ended but haven't been logged yet.
    /// Shown as a pending check-ins banner in `CalendarView`.
    @Published var pendingCheckIns: [ScheduledSession] = []

    /// Non-nil when a post-session check-in sheet should be presented.
    @Published var pendingFeedbackSession: ScheduledSession? = nil

    // MARK: - Constants

    let durationOptions: [(label: String, value: TimeInterval)] = [
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("45 min", 45 * 60),
        ("60 min", 60 * 60),
    ]

    // MARK: - Private

    private let calendarService = CalendarService.shared
    private let db = DatabaseService.shared

    // MARK: - Authorization helpers

    var isAuthorized: Bool { calendarService.isAuthorized }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - Skill goal

    func loadSkillGoal() {
        skillGoal = try? db.fetchAll().first
    }

    // MARK: - Authorization

    func requestAccess() async {
        _ = await calendarService.requestAccess()
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if calendarService.isAuthorized {
            loadSkillGoal()
            await loadFreeSlots()
        }
    }

    // MARK: - Free slots

    func loadFreeSlots() async {
        guard isAuthorized else { return }
        isLoading = true
        freeSlots = calendarService.findFreeSlots(for: selectedDate, minDuration: selectedDuration)
        isLoading = false
    }

    func select(date: Date) async {
        selectedDate = date
        await loadFreeSlots()
    }

    func select(duration: TimeInterval) async {
        selectedDuration = duration
        await loadFreeSlots()
    }

    // MARK: - Session scheduling

    /// Creates a calendar event and persists a `ScheduledSession` to the database.
    ///
    /// Also requests notification permission (if not already granted) and schedules
    /// a check-in notification at the session's end time.
    ///
    /// On success, sets `lastScheduled`, refreshes free slots, and returns `true`.
    /// On failure, sets `schedulingError` and returns `false`.
    func scheduleSession(startTime: Date) async -> Bool {
        guard let goal = skillGoal else {
            schedulingError = "No active skill goal found."
            return false
        }

        let sessionEnd = startTime.addingTimeInterval(selectedDuration)
        let eventId = calendarService.scheduleSession(
            skillName: goal.skillName,
            startTime: startTime,
            duration: selectedDuration
        )

        let session = ScheduledSession(
            skillGoalId: goal.id,
            scheduledStart: startTime,
            scheduledEnd: sessionEnd,
            calendarEventId: eventId
        )

        do {
            let saved = try db.insert(session)
            lastScheduled = saved
            schedulingError = nil

            // Request notification permission and schedule the post-session check-in.
            await NotificationService.shared.requestPermission()
            NotificationService.shared.scheduleCheckIn(for: saved, skillName: goal.skillName)

            // Refresh free slots — the booked time is now busy.
            await loadFreeSlots()
            return true
        } catch {
            schedulingError = "Failed to save session: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Pending check-ins

    /// Loads all sessions whose end time has passed and haven't been logged yet.
    func loadPendingCheckIns() {
        pendingCheckIns = (try? db.fetchPendingScheduledSessions()) ?? []
    }

    /// Resolves a session ID (from a notification tap) to a full `ScheduledSession`
    /// and sets `pendingFeedbackSession` to present the check-in sheet.
    func loadPendingFeedbackSession(id: Int64) {
        guard let session = try? db.fetchScheduledSession(id: id) else { return }
        // Don't re-present if the session was already completed.
        guard !session.completed else {
            NotificationService.shared.pendingFeedbackSessionId = nil
            return
        }
        pendingFeedbackSession = session
    }

    // MARK: - Submit feedback

    /// Creates a `PracticeSession` from the scheduled session, marks it as completed,
    /// cancels the pending notification, and clears all check-in state.
    ///
    /// - Parameters:
    ///   - session: The scheduled session that just ended.
    ///   - rating: Star rating 1–5 supplied by the user.
    ///   - notes: Optional free-text notes.
    ///   - metricEntries: Recorded values for the user's tracked metrics (may be empty).
    func submitFeedback(
        for session: ScheduledSession,
        rating: Int,
        notes: String?,
        metricEntries: [MetricEntry] = []
    ) async {
        guard let sessionId = session.id else { return }

        do {
            let practice = PracticeSession(
                skillGoalId: session.skillGoalId,
                durationMinutes: session.durationMinutes,
                notes: notes,
                metricEntries: metricEntries,
                rating: rating
            )
            _ = try db.insert(practice)
            try db.markScheduledSessionCompleted(id: sessionId)
            NotificationService.shared.cancelCheckIn(for: sessionId)
        } catch {
            schedulingError = "Failed to save check-in: \(error.localizedDescription)"
        }

        // Always clear the pending state so the sheet goes away.
        NotificationService.shared.pendingFeedbackSessionId = nil
        pendingFeedbackSession = nil
        loadPendingCheckIns()
        await loadFreeSlots()
    }

    // MARK: - Week strip

    /// Seven dates centred on today (today ± 3 days).
    var weekDates: [Date] {
        let today = Date()
        return (-3...3).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: today)
        }
    }
}
