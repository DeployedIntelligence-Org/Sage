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

        Suggest 3-5 measurable metrics they could track to measure improvement.

        Return ONLY a JSON object in exactly this format with no extra text:
        {
          "metrics": [
            {
              "name": "Metric name",
              "unit": "unit of measurement",
              "isHigherBetter": true
            }
          ]
        }

        Rules:
        - "name" is a short, human-readable metric name (e.g. "Words per minute")
        - "unit" is the measurement unit (e.g. "wpm", "minutes", "pages", "%")
        - "isHigherBetter" is true if a higher value means better performance, false otherwise
        - Return 3-5 metrics relevant to the skill and level
        """
    }

    /// System prompt that constrains Claude to return only valid JSON.
    static let metricSuggestionsSystem = """
        You are a skill-learning coach. \
        Respond ONLY with a valid JSON object. \
        Do not include any explanation, markdown, code fences, or text outside the JSON object.
        """

    // MARK: - AI Coach Chat

    /// Dynamic system prompt for the conversational AI coach.
    ///
    /// - Parameters:
    ///   - skillName: The skill the user is learning.
    ///   - currentLevel: The user's self-reported current level.
    ///   - targetLevel: The user's goal level.
    ///   - metrics: The custom metrics the user tracks.
    ///   - recentSessions: Up to the most recent practice sessions to give the coach context.
    ///                     Pass an empty array (default) when no session history is available.
    /// - Returns: A system prompt string personalised to the user's profile.
    static func coachSystem(
        skillName: String,
        currentLevel: String?,
        targetLevel: String?,
        metrics: [CustomMetric],
        recentSessions: [PracticeSession] = []
    ) -> String {
        let levelContext: String
        if let current = currentLevel, let target = targetLevel {
            levelContext = "The user is currently at \(current) level and wants to reach \(target) level."
        } else if let current = currentLevel {
            levelContext = "The user is currently at \(current) level."
        } else {
            levelContext = ""
        }

        let metricsContext: String
        if metrics.isEmpty {
            metricsContext = ""
        } else {
            let list = metrics.map { "• \($0.name) (\($0.unit))" }.joined(separator: "\n")
            metricsContext = "They track the following metrics:\n\(list)"
        }

        let sessionsContext: String
        if recentSessions.isEmpty {
            sessionsContext = ""
        } else {
            let lines = recentSessions.prefix(5).map { session -> String in
                let dateStr = Self.shortDate(session.createdAt)
                let duration = session.durationMinutes > 0 ? "\(session.durationMinutes) min" : nil
                let metricLine = session.metricEntries.isEmpty ? nil :
                    session.metricEntries.map { "\($0.metricName): \(formatNumber($0.value)) \($0.unit)" }.joined(separator: ", ")
                let notesLine = session.notes.map { "Notes: \($0)" }

                let parts = [duration, metricLine, notesLine].compactMap { $0 }
                let detail = parts.isEmpty ? "" : " — \(parts.joined(separator: "; "))"
                return "- \(dateStr)\(detail)"
            }
            sessionsContext = "Recent practice sessions (newest first):\n" + lines.joined(separator: "\n")
        }

        let sections = [levelContext, metricsContext, sessionsContext]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return """
        You are Sage, an expert AI coach helping the user improve at \(skillName).
        \(sections)

        Your role:
        • Provide specific, actionable coaching tailored to the user's level.
        • Reference their tracked metrics when relevant to make feedback concrete.
        • If recent practice sessions are shown, use them to give context-aware feedback.
        • Celebrate progress and keep the tone encouraging but honest.
        • Ask clarifying questions when you need more context.
        • Keep responses concise and conversational — this is a chat, not a lecture.
        • If the user shares a practice result, acknowledge it and suggest a next step.
        """
    }

    // MARK: - Conversation Title

    /// System prompt that instructs Claude to return only a short plain-text title.
    static let conversationTitleSystem = """
        You are a concise assistant. \
        Respond with ONLY a short title (3-6 words) that captures the topic of the message. \
        No punctuation at the end, no quotes, no extra text.
        """

    /// User-turn prompt asking Claude to generate a conversation title.
    static func conversationTitleUser(firstMessage: String) -> String {
        "Generate a short title for a conversation that starts with: \(firstMessage)"
    }

    // MARK: - Private helpers

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        } else {
            var s = String(format: "%.2f", value)
            while s.last == "0" { s.removeLast() }
            if s.last == "." { s.removeLast() }
            return s
        }
    }
}

// MARK: - Parsed Response

/// The decoded shape of Claude's metric-suggestion response.
struct MetricSuggestionResponse: Decodable {
    let metrics: [SuggestedMetric]
}

struct SuggestedMetric: Decodable, Identifiable {
    let name: String
    let unit: String
    let isHigherBetter: Bool

    var id: String { name }

    /// Converts a `SuggestedMetric` into the app's `CustomMetric` model.
    func toCustomMetric() -> CustomMetric {
        CustomMetric(name: name, unit: unit, isHigherBetter: isHigherBetter)
    }
}

