import Foundation

/// Finds clashes between proposed events and what the household already has.
///
/// Scope note for integration: this covers overlap with the travel buffer,
/// same-child double booking, and the protected dinner window — the rules that
/// need no travel estimate. The app's `PlanCore.candidate` additionally scores
/// route slack between two locations; when this work stream merges, that call
/// replaces the overlap test here rather than running alongside it. Nothing
/// below invents a travel time.
public enum ConflictFinder {
    public static func conflicts(
        proposed: [AssistantEvent],
        existing: [AssistantEvent],
        planning: PlanningContext
    ) -> [ScheduleConflict] {
        var found: [ScheduleConflict] = []
        let existingByDate = Dictionary(grouping: existing, by: \.date)

        for candidate in proposed {
            guard let start = CalendarMath.minutes(candidate.time),
                  let end = CalendarMath.minutes(candidate.endTime) else { continue }

            for other in existingByDate[candidate.date] ?? [] {
                guard other.id != candidate.id, !other.done else { continue }
                guard let otherStart = CalendarMath.minutes(other.time),
                      let otherEnd = CalendarMath.minutes(other.endTime) else { continue }

                let sharedChild = !Set(candidate.kids).intersection(other.kids).isEmpty
                let sameOwner = !candidate.isUnassigned && candidate.owner == other.owner

                // A caregiver has to travel between stops; a child does not need
                // the buffer to be in two places at once, so the two tests use
                // different windows on purpose.
                if sameOwner, overlaps(start - planning.bufferMinutes, end + planning.bufferMinutes, otherStart, otherEnd) {
                    found.append(ScheduleConflict(
                        cause: .caregiverDoubleBooked,
                        date: candidate.date,
                        existingEventID: other.id,
                        detail: "\(candidate.owner) is already on \u{201C}\(UntrustedText(other.title).forModel(limit: 60))\u{201D} at \(other.time), within the \(planning.bufferMinutes)-minute travel buffer."
                    ))
                }

                if sharedChild, overlaps(start, end, otherStart, otherEnd) {
                    let names = Set(candidate.kids).intersection(other.kids).sorted().joined(separator: ", ")
                    found.append(ScheduleConflict(
                        cause: .childDoubleBooked,
                        date: candidate.date,
                        existingEventID: other.id,
                        detail: "\(names) is already at \u{201C}\(UntrustedText(other.title).forModel(limit: 60))\u{201D} from \(other.time) to \(other.endTime)."
                    ))
                }
            }

            if planning.dinnerProtection, let dinner = CalendarMath.minutes(planning.dinnerTime),
               overlaps(start, end, dinner, dinner + 60) {
                found.append(ScheduleConflict(
                    cause: .dinnerWindow,
                    date: candidate.date,
                    existingEventID: nil,
                    detail: "Runs through the protected dinner hour starting \(planning.dinnerTime)."
                ))
            }
        }

        return found
    }

    /// Half-open comparison: an event ending exactly when another starts is not
    /// a clash.
    private static func overlaps(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
        a < d && c < b
    }
}
