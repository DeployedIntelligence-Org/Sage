import SwiftUI

/// Displays available time slots for the date selected in CalendarView.
///
/// Contains a duration picker at the top and a scrollable list of free slots below.
struct FreeSlotsView: View {

    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        VStack(spacing: 0) {
            durationPicker
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            content
        }
    }

    // MARK: - Duration picker

    private var durationPicker: some View {
        HStack {
            Text("Duration")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(viewModel.durationOptions, id: \.value) { option in
                    Button(option.label) {
                        Task { await viewModel.select(duration: option.value) }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.selectedDuration == option.value
                            ? Color.blue
                            : Color(.systemGray5)
                    )
                    .foregroundStyle(
                        viewModel.selectedDuration == option.value
                            ? Color.white
                            : Color.primary
                    )
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VStack {
                Spacer()
                ProgressView("Finding free slots…")
                Spacer()
            }
        } else if viewModel.freeSlots.isEmpty {
            emptyView
        } else {
            slotsList
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 44))
                .foregroundStyle(Color(.systemGray3))
            Text("No Free Slots")
                .font(.headline)
            Text("Your calendar is fully booked for this duration. Try a shorter session or a different day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var slotsList: some View {
        List {
            Section {
                ForEach(viewModel.freeSlots, id: \.start) { slot in
                    FreeSlotRow(slot: slot, sessionDuration: viewModel.selectedDuration)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.slotToSchedule = slot }
                }
            } header: {
                Text(viewModel.selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - FreeSlotRow

private struct FreeSlotRow: View {
    let slot: DateInterval
    let sessionDuration: TimeInterval

    private var timeRangeText: String {
        let start = slot.start.formatted(date: .omitted, time: .shortened)
        let end   = slot.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var availableText: String {
        let totalMinutes = Int(slot.duration / 60)
        let hours   = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m available" }
        if hours > 0                { return "\(hours)h available" }
        return "\(minutes)m available"
    }

    private var fitsCount: Int {
        max(1, Int(slot.duration / sessionDuration))
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(timeRangeText)
                    .font(.body.weight(.medium))
                Text(availableText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(fitsCount)×")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.blue)
                Text("sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.systemGray3))
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    FreeSlotsView(viewModel: CalendarViewModel())
}
