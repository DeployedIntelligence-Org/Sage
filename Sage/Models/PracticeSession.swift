import Foundation

/// A single practice session logged by the user.
///
/// Maps to the `practice_sessions` table (schema v3).
struct PracticeSession: Identifiable, Equatable {
    var id: Int64?
    var skillGoalId: Int64?
    var durationMinutes: Int
    var notes: String?
    /// Recorded values for each of the user's tracked metrics.
    var metricEntries: [MetricEntry]
    var createdAt: Date

    init(
        id: Int64? = nil,
        skillGoalId: Int64? = nil,
        durationMinutes: Int = 0,
        notes: String? = nil,
        metricEntries: [MetricEntry] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.skillGoalId = skillGoalId
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.metricEntries = metricEntries
        self.createdAt = createdAt
    }

    // MARK: - JSON helpers

    func metricEntriesJSON() throws -> String {
        let data = try JSONEncoder().encode(metricEntries)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DatabaseError.encodingFailed("metricEntries")
        }
        return json
    }

    static func decodeMetricEntries(from json: String) throws -> [MetricEntry] {
        guard let data = json.data(using: .utf8) else {
            throw DatabaseError.decodingFailed("metricEntries")
        }
        return try JSONDecoder().decode([MetricEntry].self, from: data)
    }
}

// MARK: - MetricEntry

/// A single recorded value for one `CustomMetric` within a `PracticeSession`.
struct MetricEntry: Codable, Equatable {
    var metricName: String
    var value: Double
    var unit: String
}
