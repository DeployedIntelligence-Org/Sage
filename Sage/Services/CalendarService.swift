import Foundation
import EventKit

/// Wraps EventKit to provide calendar authorization and free-slot calculation.
///
/// Must be called from the main actor so EventKit usage stays on a single thread.
@MainActor
final class CalendarService {

    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    /// Earliest scheduling hour (7 AM).
    private let scheduleStartHour = 7
    /// Latest scheduling hour (10 PM).
    private let scheduleEndHour = 22

    // MARK: - Authorization

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var isAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        }
        return authorizationStatus == .authorized
    }

    /// Requests full calendar read/write access. Returns `true` if the user grants it.
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await eventStore.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    // MARK: - Free-slot calculation

    /// Returns all contiguous free intervals on `date` that are at least `minDuration` seconds long.
    ///
    /// - The search window is `scheduleStartHour …  scheduleEndHour` in local time.
    /// - All-day events are ignored.
    /// - Overlapping events are merged before gap detection.
    func findFreeSlots(for date: Date, minDuration: TimeInterval) -> [DateInterval] {
        guard isAuthorized else { return [] }

        let cal = Calendar.current
        guard
            let windowStart = cal.date(bySettingHour: scheduleStartHour, minute: 0, second: 0, of: date),
            let windowEnd   = cal.date(bySettingHour: scheduleEndHour,   minute: 0, second: 0, of: date)
        else { return [] }

        // Fetch events overlapping the window.
        let predicate = eventStore.predicateForEvents(
            withStart: windowStart,
            end: windowEnd,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)

        // Build busy intervals clamped to the window, sorted by start time.
        let busy: [DateInterval] = events
            .compactMap { event -> DateInterval? in
                guard !event.isAllDay else { return nil }
                let start = max(event.startDate, windowStart)
                let end   = min(event.endDate,   windowEnd)
                guard start < end else { return nil }
                return DateInterval(start: start, end: end)
            }
            .sorted { $0.start < $1.start }

        let merged = merge(busy)

        // Walk the window and collect gaps between busy blocks.
        var freeSlots: [DateInterval] = []
        var cursor = windowStart

        for busyBlock in merged {
            if cursor < busyBlock.start {
                let gap = DateInterval(start: cursor, end: busyBlock.start)
                if gap.duration >= minDuration { freeSlots.append(gap) }
            }
            if busyBlock.end > cursor { cursor = busyBlock.end }
        }

        // Trailing gap after the last busy block (or the whole window if no events).
        if cursor < windowEnd {
            let gap = DateInterval(start: cursor, end: windowEnd)
            if gap.duration >= minDuration { freeSlots.append(gap) }
        }

        return freeSlots
    }

    // MARK: - Session scheduling

    /// Creates an EKEvent for a practice session and saves it to the user's default calendar.
    ///
    /// - Returns: The `eventIdentifier` of the saved event, or `nil` if the save failed.
    @discardableResult
    func scheduleSession(skillName: String, startTime: Date, duration: TimeInterval) -> String? {
        guard isAuthorized else { return nil }

        let event = EKEvent(eventStore: eventStore)
        event.title     = "Practice \(skillName)"
        event.startDate = startTime
        event.endDate   = startTime.addingTimeInterval(duration)
        event.calendar  = eventStore.defaultCalendarForNewEvents
        event.notes     = "Scheduled by Sage"

        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    /// Merges a sorted array of potentially-overlapping intervals into non-overlapping ones.
    private func merge(_ sorted: [DateInterval]) -> [DateInterval] {
        guard !sorted.isEmpty else { return [] }
        var result = [sorted[0]]
        for interval in sorted.dropFirst() {
            let last = result[result.count - 1]
            if interval.start <= last.end {
                if interval.end > last.end {
                    result[result.count - 1] = DateInterval(start: last.start, end: interval.end)
                }
            } else {
                result.append(interval)
            }
        }
        return result
    }
}
