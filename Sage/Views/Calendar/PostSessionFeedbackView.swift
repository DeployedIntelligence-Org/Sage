import SwiftUI

/// Sheet presented when a scheduled session has ended, prompting the user for a
/// star rating (1–5), optional metric values, and optional notes.
/// On save it creates a `PracticeSession` record and marks the scheduled session as completed.
struct PostSessionFeedbackView: View {

    let session: ScheduledSession
    let skillName: String
    /// The custom metrics the user tracks for this skill goal.
    /// Each non-empty entry becomes a `MetricEntry` on the saved `PracticeSession`.
    let metrics: [CustomMetric]
    @ObservedObject var viewModel: CalendarViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var selectedRating: Int = 0
    // Keyed by CustomMetric.id — stores the user's raw text input for each metric.
    @State private var metricInputs: [String: String] = [:]
    @State private var notes: String = ""
    @State private var isSaving = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    ratingSection
                    if !metrics.isEmpty {
                        metricsSection
                    }
                    notesSection
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        // Clear the pending notification state so the sheet doesn't re-appear.
                        NotificationService.shared.pendingFeedbackSessionId = nil
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            Text("Session Complete!")
                .font(.title2.weight(.semibold))

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.subheadline)
                Text("\(skillName) · \(session.durationMinutes) min")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Rating

    private var ratingSection: some View {
        VStack(spacing: 14) {
            Text("How did it go?")
                .font(.headline)

            StarRatingView(rating: $selectedRating)

            if selectedRating > 0 {
                Text(ratingLabel(for: selectedRating))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.25), value: selectedRating)
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Metrics (optional)", systemImage: "chart.bar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(metrics) { metric in
                    MetricInputRow(
                        metric: metric,
                        text: Binding(
                            get: { metricInputs[metric.id] ?? "" },
                            set: { metricInputs[metric.id] = $0 }
                        )
                    )

                    if metric.id != metrics.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes (optional)", systemImage: "pencil")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextEditor(text: $notes)
                .frame(minHeight: 80, maxHeight: 160)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Save Check-in")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(selectedRating == 0 || isSaving)
    }

    // MARK: - Actions

    private func save() {
        guard selectedRating > 0 else { return }
        isSaving = true

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build MetricEntry list from non-empty, parseable inputs.
        let entries: [MetricEntry] = metrics.compactMap { metric in
            guard
                let raw = metricInputs[metric.id],
                !raw.trimmingCharacters(in: .whitespaces).isEmpty,
                let value = Double(raw.trimmingCharacters(in: .whitespaces))
            else { return nil }
            return MetricEntry(metricName: metric.name, value: value, unit: metric.unit)
        }

        Task {
            await viewModel.submitFeedback(
                for: session,
                rating: selectedRating,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                metricEntries: entries
            )
            isSaving = false
            dismiss()
        }
    }

    // MARK: - Helpers

    private func ratingLabel(for rating: Int) -> String {
        switch rating {
        case 1: return "Rough session — keep going!"
        case 2: return "Below expectations"
        case 3: return "Solid practice"
        case 4: return "Great session!"
        case 5: return "Outstanding! 🎉"
        default: return ""
        }
    }
}

// MARK: - MetricInputRow

private struct MetricInputRow: View {
    let metric: CustomMetric
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name)
                    .font(.subheadline)
                if let target = metric.targetValue {
                    Text("Target: \(formatTarget(target)) \(metric.unit)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            TextField("—", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)

            Text(metric.unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func formatTarget(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - StarRatingView

private struct StarRatingView: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: 38))
                    .foregroundStyle(star <= rating ? .yellow : Color(.tertiaryLabel))
                    .onTapGesture { rating = star }
                    .scaleEffect(star == rating ? 1.15 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.5), value: rating)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PostSessionFeedbackView(
        session: ScheduledSession(
            id: 1,
            skillGoalId: 1,
            scheduledStart: Date().addingTimeInterval(-3600),
            scheduledEnd: Date()
        ),
        skillName: "Piano",
        metrics: [
            CustomMetric(name: "Pieces completed", unit: "pieces", isHigherBetter: true),
            CustomMetric(name: "Practice tempo", unit: "BPM", targetValue: 120, isHigherBetter: true),
        ],
        viewModel: CalendarViewModel()
    )
}
