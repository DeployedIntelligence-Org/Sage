import Foundation

/// Static factory methods for the prompts sent to Claude.
///
/// Keeping prompts here (rather than inline in services) makes them easy to
/// iterate on, test, and version independently of the networking layer.
enum PromptTemplates {

    // MARK: - Metric Suggestions

    /// Builds the user-turn message that asks Claude to suggest progress metrics.
    ///
    /// - Parameters:
    ///   - skill: The skill name the user wants to learn.
    ///   - level: The user's current skill level.
    /// - Returns: A formatted prompt string.
    static func metricSuggestions(skill: String, level: String) -> String {
        """
        User wants to learn: \(skill)
        Current level: \(level)

        Suggest 3-5 measurable metrics they could track. Return JSON format:
        {
          "metrics": [
            {
              "name": "Metric name",
              "type": "count|duration|rating|custom",
              "unit": "pieces|minutes|rating"
            }
          ],
          "reasoning": "Brief explanation"
        }
        """
    }

    /// System prompt that constrains Claude to return only valid JSON.
    static let metricSuggestionsSystem = """
        You are a skill-learning coach. \
        Respond ONLY with valid JSON matching the requested schema. \
        Do not include any explanation, markdown, or code fences outside the JSON object.
        """
}

// MARK: - Parsed Response

/// The decoded shape of Claude's metric-suggestion response.
struct MetricSuggestionResponse: Decodable {
    let metrics: [SuggestedMetric]
    let reasoning: String
}

struct SuggestedMetric: Decodable, Identifiable {
    let name: String
    let type: MetricType
    let unit: String

    var id: String { name }

    enum MetricType: String, Decodable {
        case count, duration, rating, custom
    }

    /// Converts a `SuggestedMetric` into the app's `CustomMetric` model.
    func toCustomMetric() -> CustomMetric {
        CustomMetric(name: name, unit: unit)
    }
}
