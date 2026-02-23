import Foundation

/// A practice session that has been booked on the user's calendar.
struct ScheduledSession: Identifiable {

    var id: Int64?
    var skillGoalId: Int64?
    var scheduledStart: Date
    var scheduledEnd: Date
    /// The `EKEvent.eventIdentifier` returned after saving to EventKit.
    var calendarEventId: String?
    var completed: Bool
    var completedAt: Date?
    var createdAt: Date

    // MARK: - Computed

    var duration: TimeInterval {
        scheduledEnd.timeIntervalSince(scheduledStart)
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }

    // MARK: - Init

    init(
        id: Int64? = nil,
        skillGoalId: Int64? = nil,
        scheduledStart: Date,
        scheduledEnd: Date,
        calendarEventId: String? = nil,
        completed: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.skillGoalId = skillGoalId
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.calendarEventId = calendarEventId
        self.completed = completed
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}
