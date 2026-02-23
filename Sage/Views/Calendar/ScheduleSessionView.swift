import SwiftUI

/// Sheet that lets the user confirm and book a free time slot as a practice session.
///
/// The start time is editable via a DatePicker clamped to the available free window,
/// so the user can pick any valid start within the slot (not just the earliest time).
struct ScheduleSessionView: View {

    let slot: DateInterval
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sessionStart: Date
    @State private var isScheduling = false
    @State private var didSchedule  = false

    // MARK: - Init

    init(slot: DateInterval, viewModel: CalendarViewModel) {
        self.slot = slot
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _sessionStart = State(initialValue: slot.start)
    }

    // MARK: - Derived

    private var sessionEnd: Date {
        sessionStart.addingTimeInterval(viewModel.selectedDuration)
    }

    /// Latest valid start so the session still fits entirely within the free window.
    private var latestStart: Date {
        slot.end.addingTimeInterval(-viewModel.selectedDuration)
    }

    private var startIsAdjustable: Bool {
        latestStart > slot.start
    }

    private var skillName: String {
        viewModel.skillGoal?.skillName ?? "your skill"
    }

    private var durationLabel: String {
        let mins = Int(viewModel.selectedDuration / 60)
        return mins >= 60
            ? "\(mins / 60)h\(mins % 60 > 0 ? " \(mins % 60)m" : "")"
            : "\(mins) min"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if didSchedule {
                    successView
                } else {
                    confirmationForm
                }
            }
            .navigationTitle("Schedule Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isScheduling)
                }
            }
        }
    }

    // MARK: - Confirmation form

    private var confirmationForm: some View {
        List {
            // Skill
            Section {
                HStack {
                    Label("Skill", systemImage: "brain.head.profile")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(skillName)
                        .fontWeight(.medium)
                }
            }

            // Time details
            Section("Session details") {
                HStack {
                    Label("Date", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(sessionStart.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .fontWeight(.medium)
                }

                // Editable start time — picker when adjustable, static label otherwise
                if startIsAdjustable {
                    DatePicker(
                        selection: $sessionStart,
                        in: slot.start...latestStart,
                        displayedComponents: .hourAndMinute
                    ) {
                        Label("Start", systemImage: "clock")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Label("Start", systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(sessionStart.formatted(date: .omitted, time: .shortened))
                            .fontWeight(.medium)
                    }
                }

                // End is always derived — read-only
                HStack {
                    Label("End", systemImage: "clock.badge.checkmark")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(sessionEnd.formatted(date: .omitted, time: .shortened))
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Duration", systemImage: "timer")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(durationLabel)
                        .fontWeight(.medium)
                }
            }

            // Free window context
            Section {
                HStack {
                    Label("Free window", systemImage: "calendar.badge.checkmark")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(slot.start.formatted(date: .omitted, time: .shortened)) – \(slot.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(startIsAdjustable
                     ? "Tap the start time above to choose when within this window your session begins."
                     : "This window fits exactly one session of this duration.")
                    .font(.caption)
            }

            // Action
            Section {
                Button {
                    Task { await confirmSchedule() }
                } label: {
                    HStack {
                        Spacer()
                        if isScheduling {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Schedule Session")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .listRowBackground(Color.blue)
                .foregroundStyle(.white)
                .disabled(isScheduling)
            }
        }
        .alert("Scheduling Failed", isPresented: Binding(
            get: { viewModel.schedulingError != nil },
            set: { if !$0 { viewModel.schedulingError = nil } }
        )) {
            Button("OK") { viewModel.schedulingError = nil }
        } message: {
            Text(viewModel.schedulingError ?? "")
        }
    }

    // MARK: - Success view

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("Session Scheduled!")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("\"\(skillName)\" added to your calendar on \(sessionStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) at \(sessionStart.formatted(date: .omitted, time: .shortened)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
    }

    // MARK: - Actions

    private func confirmSchedule() async {
        isScheduling = true
        let success = await viewModel.scheduleSession(startTime: sessionStart)
        isScheduling = false
        if success { didSchedule = true }
    }
}

#Preview {
    let vm = CalendarViewModel()
    let slot = DateInterval(
        start: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!,
        end:   Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    )
    return ScheduleSessionView(slot: slot, viewModel: vm)
}
