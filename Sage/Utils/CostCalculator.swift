import Foundation

/// Estimates the USD cost of a Claude API call based on token usage.
///
/// Pricing is approximated from Anthropic's published rates and should be
/// treated as informational only — check the Anthropic dashboard for exact billing.
enum CostCalculator {

    // Pricing per million tokens (USD) — claude-opus-4-6 list prices.
    private static let inputCostPerMillionTokens: Double  = 15.0
    private static let outputCostPerMillionTokens: Double = 75.0

    /// Calculates the estimated cost of a single API response.
    /// - Parameter usage: The token usage from `ClaudeResponse.usage`.
    /// - Returns: Estimated cost in USD.
    static func estimatedCost(for usage: Usage) -> Double {
        let inputCost  = Double(usage.inputTokens)  / 1_000_000 * inputCostPerMillionTokens
        let outputCost = Double(usage.outputTokens) / 1_000_000 * outputCostPerMillionTokens
        return inputCost + outputCost
    }

    /// Formats a cost value as a human-readable USD string (e.g. "$0.0023").
    static func formatted(_ cost: Double) -> String {
        String(format: "$%.4f", cost)
    }
}
