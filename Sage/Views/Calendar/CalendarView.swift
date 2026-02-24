import SwiftUI
import EventKit

/// Root view for the Schedule tab.
///
/// Handles three states: permission not determined, permission denied, and authorized.
/// When authorized it shows a week-strip date picker above the free-slots list.
///
/// Also presents:
/// - A pending check-ins banner at the top when past sessions haven't been logged yet.
/// - A `PostSessionFeedbackView` sheet triggered by a notification tap or the banner.
struct CalendarView: View {

    @StateObject private var viewModel = CalendarViewModel()
    @ObservedObject private var notificationService = NotificationService.shared

    var body: some View {
        Group {
            if viewModel.isDenied {
                permissionDeniedView
            } else if !viewModel.isAuthorized {
                permissionRequestView
            } else {
                authorizedContent
            }
        }
        .navigationTitle("Schedule")
        .task {
            // Re-read status each time the view appears (user may have changed it in Settings).
            viewModel.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if viewModel.isAuthorized {
                viewModel.loadSkillGoal()
                viewModel.loadPendingCheckIns()
                await viewModel.loadFreeSlots()
            }
        }
        // Scheduling sheet
        .sheet(isPresented: Binding(
            get: { viewModel.slotToSchedule != nil },
            set: { if !$0 { viewModel.slotToSchedule = nil } }
        )) {
            if let slot = viewModel.slotToSchedule {
                ScheduleSessionView(slot: slot, viewModel: viewModel)
            }
        }
        // Post-session feedback sheet
        .sheet(isPresented: Binding(
            get: { viewModel.pendingFeedbackSession != nil },
            set: {
                if !$0 {
                    viewModel.pendingFeedbackSession = nil
                    NotificationService.shared.pendingFeedbackSessionId = nil
                }
            }
        )) {
            if let session = viewModel.pendingFeedbackSession {
                PostSessionFeedbackView(
                    session: session,
                    skillName: viewModel.skillGoal?.skillName ?? "Practice",
                    metrics: viewModel.skillGoal?.customMetrics ?? [],
                    viewModel: viewModel
                )
            }
        }
        // Respond to notification taps — resolve session ID → full ScheduledSession.
        .onChange(of: notificationService.pendingFeedbackSessionId) { _, sessionId in
            guard let sessionId else { return }
            viewModel.loadPendingFeedbackSession(id: sessionId)
        }
    }

    // MARK: - Permission: not determined

    private var permissionRequestView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("Calendar Access")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Sage reads your calendar to find free time for practice sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button("Allow Calendar Access") {
                Task { await viewModel.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
    }

    // MARK: - Permission: denied

    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Calendar Access Denied")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Enable calendar access in Settings to schedule practice sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
    }

    // MARK: - Authorized content

    private var authorizedContent: some View {
        VStack(spacing: 0) {
            // Pending check-ins banner — shown above the week strip when sessions need logging.
            if !viewModel.pendingCheckIns.isEmpty {
                pendingCheckInsBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            WeekStripView(
                dates: viewModel.weekDates,
                selectedDate: viewModel.selectedDate
            ) { date in
                Task { await viewModel.select(date: date) }
            }
            .padding(.vertical, 12)
            .background(Color(.systemBackground))

            Divider()

            FreeSlotsView(viewModel: viewModel)
        }
        .animation(.spring(response: 0.3), value: viewModel.pendingCheckIns.isEmpty)
    }

    // MARK: - Pending check-ins banner

    private var pendingCheckInsBanner: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.pendingCheckIns, id: \.id) { session in
                Button {
                    viewModel.loadPendingFeedbackSession(id: session.id ?? 0)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log your session")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(sessionSummary(for: session))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if session.id != viewModel.pendingCheckIns.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Helpers

    private func sessionSummary(for session: ScheduledSession) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: session.scheduledEnd, relativeTo: Date())
        return "\(session.durationMinutes) min · ended \(relative)"
    }
}

// MARK: - WeekStripView

private struct WeekStripView: View {
    let dates: [Date]
    let selectedDate: Date
    let onSelect: (Date) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    )
                    .onTapGesture { onSelect(date) }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - DayCell

private struct DayCell: View {
    let date: Date
    let isSelected: Bool

    private var weekdayLetter: String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private var dayNumber: String {
        date.formatted(.dateTime.day())
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(weekdayLetter)
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : .secondary)
            Text(dayNumber)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(isSelected ? .white : isToday ? .blue : .primary)
        }
        .frame(width: 40, height: 56)
        .background(isSelected ? Color.blue : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isToday && !isSelected ? Color.blue.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
}
