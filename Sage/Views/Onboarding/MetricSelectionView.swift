import SwiftUI

/// Step 3 — the user defines custom metrics to track progress on their skill.
/// This step is optional; the user can proceed without adding any metrics.
struct MetricSelectionView: View {

    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading
            addMetricForm
            suggestionsSection
            metricList
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How will you measure progress?")
                .font(.title2)
                .fontWeight(.bold)

            Text("Add metrics that help you track improvement. You can always add more later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Add Metric Form

    private var addMetricForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New metric", systemImage: "plus.circle.fill")
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
        } else if let error = vm.suggestionError {
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
        } else if !vm.suggestedMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Suggested by Sage", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ForEach(vm.suggestedMetrics) { suggestion in
                        let alreadyAdded = vm.metrics.contains(where: { $0.name == suggestion.name })
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(suggestion.unit)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: { vm.acceptSuggestion(suggestion) }) {
                                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(alreadyAdded ? .green : .accentColor)
                                    .font(.title3)
                            }
                            .disabled(alreadyAdded)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: - Metric List

    @ViewBuilder
    private var metricList: some View {
        if vm.metrics.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Added metrics", systemImage: "checklist")
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

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(.systemGray3))

                Text("No metrics yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Add at least one to track your progress,\nor skip and add later.")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.vertical, 24)
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
