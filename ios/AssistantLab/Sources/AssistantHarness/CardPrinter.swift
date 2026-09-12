import Foundation
import AssistantKit

/// Text rendering of the same typed cards the SwiftUI sheet draws, so the
/// harness shows exactly what the app would show.
enum CardPrinter {
    static func lines(_ card: AssistantCard) -> [String] {
        switch card {
        case .summary(let c):
            return [c.text]

        case .eventList(let c):
            var out = ["\u{250C} \(c.periodLabel)"]
            if c.rows.isEmpty { out.append("\u{2502} (nothing scheduled)") }
            out += c.rows.prefix(12).map { "\u{2502} " + row($0) }
            if c.rows.count > 12 { out.append("\u{2502} \u{2026} \(c.rows.count - 12) more shown in app") }
            if c.omittedCount > 0 { out.append("\u{2502} + \(c.omittedCount) beyond the display cap") }
            return out + ["\u{2514}"]

        case .people(let c):
            var out = ["\u{250C} Household"]
            out += c.caregivers.map { "\u{2502} \($0.name) \u{00B7} \($0.relationship)" }
            out += c.children.map { "\u{2502} \($0.name) \u{00B7} child" }
            return out + ["\u{2514}"]

        case .places(let c):
            return ["\u{250C} Saved places"]
                + c.places.map { "\u{2502} \($0.name)\($0.isVerified ? "" : "  (no location saved)")" }
                + ["\u{2514}"]

        case .proposal(let c):
            var out = ["\u{250C} REVIEW \u{00B7} \(c.headline)"]
            if let rule = c.ruleDescription { out.append("\u{2502} \(rule)") }
            out.append("\u{2502} \(c.affectedCount) event(s) \u{00B7} \(c.periodLabel)")
            out.append("\u{2502} \(c.destinationNote)")
            out += c.assumptions.map { "\u{2502} i \($0)" }
            if !c.conflicts.isEmpty {
                out.append("\u{2502} \(c.conflicts.count) conflict(s):")
                out += c.conflicts.prefix(4).map { "\u{2502}   ! \(CalendarMath.shortLabel($0.date)) \u{00B7} \($0.detail)" }
                if c.conflicts.count > 4 { out.append("\u{2502}   \u{2026} \(c.conflicts.count - 4) more") }
            }
            out += c.rows.prefix(4).map { "\u{2502} " + row($0) }
            if c.rows.count > 4 { out.append("\u{2502} \u{2026} \(c.rows.count - 4) more occurrences") }
            out.append("\u{2502} [ Confirm ]  [ Cancel ]   nothing saved yet")
            return out + ["\u{2514}"]

        case .trends(let c):
            var out = ["\u{250C} \(c.periodLabel) \u{00B7} \(c.comparisonLabel)"]
            if let note = c.partialPeriodNote { out.append("\u{2502} ! \(note)") }
            out += c.metrics.map { "\u{2502} \($0.title): \($0.currentValue) (was \($0.previousValue)) \(change($0.change))" }
            if !c.workload.isEmpty {
                out.append("\u{2502} Driving: " + c.workload.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
            }
            if !c.categoryMix.isEmpty {
                out.append("\u{2502} Mix: " + c.categoryMix.map { "\($0.category) \($0.count)" }.joined(separator: ", "))
            }
            out += c.notes.map { "\u{2502} \u{00B7} \($0)" }
            return out + ["\u{2514}"]

        case .help(let c):
            return ["\u{250C} \(c.title)"] + c.body.map { "\u{2502} \($0)" } + ["\u{2514}"]

        case .clarification(let c):
            return ["\u{250C} \(c.question)"]
                + c.options.map { "\u{2502} [ \($0.label) ]" }
                + ["\u{2514}"]

        case .refusal(let c):
            return ["\u{250C} \(c.text)"] + c.suggestions.map { "\u{2502} \u{00B7} \($0)" } + ["\u{2514}"]

        case .receipt(let c):
            var out = ["\u{250C} \u{2713} \(c.headline)"]
            if !c.detail.isEmpty { out.append("\u{2502} \(c.detail)") }
            out.append("\u{2502} \(c.syncLabel)")
            if let external = c.externalCalendarLabel { out.append("\u{2502} \(external)") }
            out += c.rows.prefix(3).map { "\u{2502} " + row($0) }
            if c.rows.count > 3 { out.append("\u{2502} \u{2026} \(c.rows.count - 3) more") }
            return out + ["\u{2514}"]

        case .failure(let c):
            return ["\u{250C} \u{26A0} \(c.text)", "\u{2514}"]
        }
    }

    private static func row(_ r: EventRow) -> String {
        "\(CalendarMath.shortLabel(r.date)) \(r.time)\u{2013}\(r.endTime)  \u{201C}\(r.title)\u{201D}  \u{00B7} \(r.locationName) \u{00B7} \(r.ownerLabel)"
    }

    private static func change(_ c: TrendMetric.Change) -> String {
        switch c {
        case .percent(let pct, let abs): return "[\(pct >= 0 ? "+" : "")\(pct)%, \(abs >= 0 ? "+" : "")\(abs)]"
        case .fromZero(let abs): return "[+\(abs), no baseline to divide by]"
        case .noBaseline: return "[no baseline]"
        case .insufficientData(let why): return "[insufficient data: \(why)]"
        }
    }
}
