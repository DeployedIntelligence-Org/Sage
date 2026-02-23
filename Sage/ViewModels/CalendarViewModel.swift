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

    // MARK: - Constants

    let durationOptions: [(label: String, value: TimeInterval)] = [
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("45 min", 45 * 60),
        ("60 min", 60 * 60),
    ]

    // MARK: - Private

    private let calendarService = CalendarService.shared

    // MARK: - Authorization helpers

    var isAuthorized: Bool { calendarService.isAuthorized }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - Actions

    func requestAccess() async {
        _ = await calendarService.requestAccess()
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if calendarService.isAuthorized {
            await loadFreeSlots()
        }
    }

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

    // MARK: - Week strip

    /// Seven dates centred on today (today ± 3 days).
    var weekDates: [Date] {
        let today = Date()
        return (-3...3).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: today)
        }
    }
}
