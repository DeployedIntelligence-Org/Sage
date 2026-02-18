import Foundation
import Combine

/// Manages state and validation for the multi-step onboarding flow.
@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Step

    enum Step: Int, CaseIterable {
        case skillInput = 0
        case levelSelection = 1
        case metricSelection = 2

        var title: String {
            switch self {
            case .skillInput:      return "Your Skill"
            case .levelSelection:  return "Your Level"
            case .metricSelection: return "Track Progress"
            }
        }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    // MARK: - Published State

    @Published var currentStep: Step = .skillInput
    @Published var isComplete: Bool = false

    // Step 1 — Skill Input
    @Published var skillName: String = ""
    @Published var skillDescription: String = ""
    @Published var skillCategory: String = ""

    // Step 2 — Level Selection
    @Published var currentLevel: String = ""
    @Published var targetLevel: String = ""

    // Step 3 — Metric Selection
    /// Metrics the user added manually.
    @Published var metrics: [CustomMetric] = []
    /// IDs (`name`) of AI-suggested metrics the user has checked.
    @Published var selectedMetrics: Set<String> = []

    // Transient metric builder
    @Published var newMetricName: String = ""
    @Published var newMetricUnit: String = ""
    @Published var newMetricIsHigherBetter: Bool = true

    // AI metric suggestions
    @Published var isFetchingSuggestions: Bool = false
    @Published var suggestionError: String? = nil
    @Published var suggestedMetrics: [SuggestedMetric] = []

    // MARK: - Computed

    var progress: Double {
        Double(currentStep.rawValue + 1) / Double(Step.allCases.count)
    }

    var isCurrentStepValid: Bool {
        switch currentStep {
        case .skillInput:
            return !skillName.trimmingCharacters(in: .whitespaces).isEmpty
        case .levelSelection:
            return !currentLevel.isEmpty && !targetLevel.isEmpty
        case .metricSelection:
            return true  // Optional — user may skip adding metrics
        }
    }

    var isNewMetricValid: Bool {
        !newMetricName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newMetricUnit.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Dependencies

    private let claudeService: ClaudeService
    private let databaseService: DatabaseService

    // MARK: - Init

    init(claudeService: ClaudeService = .shared, databaseService: DatabaseService = .shared) {
        self.claudeService = claudeService
        self.databaseService = databaseService
    }

    // MARK: - Navigation

    func advance() {
        guard isCurrentStepValid else { return }
        if let next = currentStep.next {
            currentStep = next
            if next == .metricSelection {
                fetchSuggestions()
            }
        } else {
            finish()
        }
    }

    func goBack() {
        if let previous = currentStep.previous {
            currentStep = previous
        }
    }

    // MARK: - AI Metric Suggestions

    func fetchSuggestions() {
        guard !skillName.isEmpty else { return }
        let level = currentLevel.isEmpty ? "Beginner" : currentLevel

        isFetchingSuggestions = true
        suggestionError = nil
        suggestedMetrics = []
        selectedMetrics = []

        Task {
            do {
                let prompt = PromptTemplates.metricSuggestions(skill: skillName, level: level)
                let response = try await claudeService.send(
                    userMessage: prompt,
                    systemPrompt: PromptTemplates.metricSuggestionsSystem,
                    maxTokens: Config.Claude.metricSuggestionMaxTokens
                )
                let parsed = try parseSuggestions(from: response.text)
                suggestedMetrics = parsed.metrics
                // Pre-select all suggestions so the user can deselect what they don't want.
                selectedMetrics = Set(parsed.metrics.map { $0.id })
            } catch let error as NetworkError {
                suggestionError = error.localizedDescription
            } catch {
                suggestionError = error.localizedDescription
            }
            isFetchingSuggestions = false
        }
    }

    /// Toggles the checked state for a suggested metric.
    func toggleSuggestion(_ suggestion: SuggestedMetric) {
        if selectedMetrics.contains(suggestion.id) {
            selectedMetrics.remove(suggestion.id)
        } else {
            selectedMetrics.insert(suggestion.id)
        }
    }

    func isSelected(_ suggestion: SuggestedMetric) -> Bool {
        selectedMetrics.contains(suggestion.id)
    }

    private func parseSuggestions(from text: String) throws -> MetricSuggestionResponse {
        guard let data = text.data(using: .utf8) else {
            throw NetworkError.decodingFailed("Response text is not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(MetricSuggestionResponse.self, from: data)
        } catch {
            throw NetworkError.decodingFailed("Could not parse metric suggestions: \(error.localizedDescription)")
        }
    }

    // MARK: - Metric Management

    func addMetric() {
        guard isNewMetricValid else { return }
        let metric = CustomMetric(
            name: newMetricName.trimmingCharacters(in: .whitespaces),
            unit: newMetricUnit.trimmingCharacters(in: .whitespaces),
            isHigherBetter: newMetricIsHigherBetter
        )
        metrics.append(metric)
        clearMetricDraft()
    }

    func removeMetric(at offsets: IndexSet) {
        metrics.remove(atOffsets: offsets)
    }

    func clearMetricDraft() {
        newMetricName = ""
        newMetricUnit = ""
        newMetricIsHigherBetter = true
    }

    // MARK: - Save & Finish

    /// Builds the SkillGoal combining checked suggestions and manually-added metrics,
    /// persists it to SQLite, and sets `isComplete`.
    /// - Returns: `true` if the save succeeded.
    @discardableResult
    func saveSkillGoal() -> Bool {
        let selectedFromSuggestions = suggestedMetrics
            .filter { selectedMetrics.contains($0.id) }
            .map { $0.toCustomMetric() }

        let allMetrics = selectedFromSuggestions + metrics

        var goal = buildSkillGoal(with: allMetrics)
        do {
            goal = try databaseService.insert(goal)
            isComplete = true
            return true
        } catch {
            print("[OnboardingViewModel] Failed to save goal: \(error.localizedDescription)")
            return false
        }
    }

    func buildSkillGoal(with customMetrics: [CustomMetric] = []) -> SkillGoal {
        SkillGoal(
            skillName: skillName.trimmingCharacters(in: .whitespaces),
            skillDescription: skillDescription.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : skillDescription.trimmingCharacters(in: .whitespaces),
            skillCategory: skillCategory.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : skillCategory.trimmingCharacters(in: .whitespaces),
            currentLevel: currentLevel.isEmpty ? nil : currentLevel,
            targetLevel: targetLevel.isEmpty ? nil : targetLevel,
            customMetrics: customMetrics
        )
    }

    private func finish() {
        saveSkillGoal()
    }
}
