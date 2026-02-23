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
            // Refresh free slots — the booked time is now busy.
            await loadFreeSlots()
            return true
        } catch {
            schedulingError = "Failed to save session: \(error.localizedDescription)"
            return false
        }
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
