import SwiftUI

/// Step 3 — the user selects metrics to track progress on their skill.
/// AI-suggested metrics are shown as checkboxes (all pre-selected).
/// The user can also add custom metrics manually.
struct MetricSelectionView: View {

    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading
            suggestionsSection
            addMetricForm
            manualMetricList
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How will you measure progress?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select the metrics you want to track. You can add your own too.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        if vm.isFetchingSuggestions {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Getting suggestions from Sage…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else if let error = vm.suggestionError {
            VStack(alignment: .leading, spacing: 8) {
                Label("Suggested by Sage", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { vm.fetchSuggestions() }
                        .font(.caption)
                }
            }
        } else if !vm.suggestedMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Suggested by Sage", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(vm.suggestedMetrics) { suggestion in
                        suggestionRow(suggestion)

                        if suggestion.id != vm.suggestedMetrics.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func suggestionRow(_ suggestion: SuggestedMetric) -> some View {
        let selected = vm.isSelected(suggestion)
        return Button(action: { vm.toggleSuggestion(suggestion) }) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.accentColor : Color(.systemGray3))
                    .animation(.easeInOut(duration: 0.15), value: selected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(suggestion.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Custom Metric Form

    private var addMetricForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add your own metric", systemImage: "plus.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Name (e.g. Speed)", text: $vm.newMetricName)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .unit }

                TextField("Unit (e.g. wpm)", text: $vm.newMetricUnit)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: 120)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .focused($focusedField, equals: .unit)
                    .submitLabel(.done)
                    .onSubmit { attemptAdd() }
            }

            HStack(spacing: 0) {
                directionToggle

                Spacer()

                Button(action: attemptAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(vm.isNewMetricValid ? Color.accentColor : Color(.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!vm.isNewMetricValid)
                .animation(.easeInOut(duration: 0.2), value: vm.isNewMetricValid)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var directionToggle: some View {
        HStack(spacing: 6) {
            Text("Higher is better")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("", isOn: $vm.newMetricIsHigherBetter)
                .labelsHidden()
                .tint(.green)
        }
    }

    // MARK: - Manually-Added Metric List

    @ViewBuilder
    private var manualMetricList: some View {
        if !vm.metrics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Added by you", systemImage: "checklist")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(vm.metrics) { metric in
                        MetricRow(metric: metric)
                            .padding(.horizontal, 14)

                        if metric.id != vm.metrics.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                    .onDelete { vm.removeMetric(at: $0) }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Helpers

    private func attemptAdd() {
        vm.addMetric()
        focusedField = .name
    }
}

#Preview {
    let vm = OnboardingViewModel()
    return ScrollView {
        MetricSelectionView(vm: vm)
            .padding(24)
    }
}
