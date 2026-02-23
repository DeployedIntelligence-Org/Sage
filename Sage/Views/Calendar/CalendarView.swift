import SwiftUI
import EventKit

/// Root view for the Schedule tab.
///
/// Handles three states: permission not determined, permission denied, and authorized.
/// When authorized it shows a week-strip date picker above the free-slots list.
struct CalendarView: View {

    @StateObject private var viewModel = CalendarViewModel()

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
                await viewModel.loadFreeSlots()
            }
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
