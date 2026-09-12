import Foundation

/// One comparable number. The app computes both sides; the model never does
/// arithmetic on household data (A05).
public struct TrendMetric: Hashable, Sendable, Identifiable, Codable {
    public enum Change: Hashable, Sendable, Codable {
        /// Both periods have data and the baseline is non-zero.
        case percent(Int, absolute: Int)
        /// Baseline was zero, so a percentage would be meaningless.
        case fromZero(absolute: Int)
        /// No usable comparison period.
        case noBaseline
        /// Deliberately not computed, with the reason shown.
        case insufficientData(String)
    }

    public var id: String
    public var title: String
    public var currentValue: Int
    public var previousValue: Int
    /// "events", "unassigned", etc. Rendered next to the number.
    public var unit: String
    public var change: Change

    public init(id: String, title: String, currentValue: Int, previousValue: Int, unit: String, change: Change) {
        self.id = id
        self.title = title
        self.currentValue = currentValue
        self.previousValue = previousValue
        self.unit = unit
        self.change = change
    }
}

public struct TrendCard: Hashable, Sendable, Codable {
    public var id: String
    public var periodLabel: String
    public var comparisonLabel: String
    /// Set when the requested period runs past today. Historical metrics then
    /// cover only the elapsed part, and that is stated.
    public var partialPeriodNote: String?
    public var metrics: [TrendMetric]
    /// Per-caregiver workload for the current period, highest first.
    public var workload: [WorkloadRow]
    /// Activity mix for the current period, highest first.
    public var categoryMix: [CategoryRow]
    /// Events behind these numbers, so every result links to its evidence.
    public var supportingEventIDs: [String]
    public var notes: [String]

    public struct WorkloadRow: Hashable, Sendable, Identifiable, Codable {
        public var id: String { name }
        public var name: String
        public var count: Int
        public init(name: String, count: Int) { self.name = name; self.count = count }
    }

    public struct CategoryRow: Hashable, Sendable, Identifiable, Codable {
        public var id: String { category }
        public var category: String
        public var count: Int
        public init(category: String, count: Int) { self.category = category; self.count = count }
    }

    public init(
        id: String = UUID().uuidString,
        periodLabel: String,
        comparisonLabel: String,
        partialPeriodNote: String?,
        metrics: [TrendMetric],
        workload: [WorkloadRow],
        categoryMix: [CategoryRow],
        supportingEventIDs: [String],
        notes: [String]
    ) {
        self.id = id
        self.periodLabel = periodLabel
        self.comparisonLabel = comparisonLabel
        self.partialPeriodNote = partialPeriodNote
        self.metrics = metrics
        self.workload = workload
        self.categoryMix = categoryMix
        self.supportingEventIDs = supportingEventIDs
        self.notes = notes
    }
}
