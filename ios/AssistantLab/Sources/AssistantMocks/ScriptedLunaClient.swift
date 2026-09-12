import Foundation
import AssistantKit

/// A deterministic stand-in for the model.
///
/// It plans exactly the way the real model is asked to: read the user's
/// message, call allowlisted operations, use ids that came back from earlier
/// calls, and finish with a structured decision. It never produces prose,
/// because the real one cannot either.
///
/// What this does and does not prove: it exercises the whole pipeline \u{2014}
/// validation, household scoping, proposal building, conflict detection,
/// confirmation, rendering \u{2014} without a network call or a provider key. It
/// does not prove that `gpt-5.6-luna` chooses these calls. That is A02's staging
/// check against the deployment account, and it is still outstanding.
public struct ScriptedLunaClient: LunaClient {
    /// Injected so a test can pin the assistant's idea of "this week".
    private let today: String
    private let displayedWeekStart: String

    public init(today: String = Fixtures.today, displayedWeekStart: String = Fixtures.displayedWeekStart) {
        self.today = today
        self.displayedWeekStart = displayedWeekStart
    }

    public func send(_ request: LunaRequest) async throws -> LunaReply {
        let turn = Turn(items: request.items)
        guard let message = turn.userMessage?.lowercased() else {
            return .final(FinalDecision(outcome: .refuse, refusalReason: .outOfScope))
        }

        if let small = smallTalk(message) {
            return .final(FinalDecision(outcome: .converse, message: small))
        }

        // Anything that is not this household's schedule is refused before a
        // single operation runs.
        if let reason = offTopicReason(message) {
            return .final(FinalDecision(
                outcome: .refuse,
                refusalReason: reason,
                message: refusalLine(reason)
            ))
        }

        if message.contains("assign") {
            return assignPlan(message, turn)
        }
        if isCreateRequest(message) {
            return createPlan(message, turn)
        }
        if message.contains("compare") || message.contains("busier") || message.contains("trend") || message.contains("workload") {
            return trendPlan(message, turn)
        }
        if message.contains("who") || message.contains("family") || message.contains("household") {
            return turn.ran(.listHouseholdPeople)
                ? .final(FinalDecision(outcome: .result, resultTemplate: .peopleListed, message: "Here's everyone."))
                : call(.listHouseholdPeople, ["include_children": true])
        }
        if message.contains("place") || message.contains("saved location") {
            return turn.ran(.listSavedPlaces)
                ? .final(FinalDecision(outcome: .result, resultTemplate: .placesListed, message: "These are the places you've saved."))
                : call(.listSavedPlaces, ["verified_only": false])
        }
        if let topic = helpTopic(message) {
            return turn.ran(.getAppHelp)
                ? .final(FinalDecision(outcome: .result, resultTemplate: .helpShown, message: "Here's how that works."))
                : call(.getAppHelp, ["topic": topic.rawValue])
        }
        return findPlan(message, turn)
    }

    /// Conversational openers the app should answer without reaching for an
    /// operation. Numeric-free on purpose: `ProseValidator` rejects figures on
    /// a turn where nothing was looked up.
    private func smallTalk(_ message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        switch trimmed {
        case "hi", "hey", "hello", "yo", "good morning", "good evening":
            return "Hi. Ask me anything about the family's schedule \u{2014} what's coming up, who's driving, or a new activity you want to set up."
        case "thanks", "thank you", "ta", "cheers":
            return "Any time."
        case "ok", "okay", "got it", "cool":
            return "Anything else you want to look at?"
        default:
            break
        }
        if message.contains("what can you do") || message.contains("how do you work") {
            return "I can look through the family's schedule, set up a repeating activity, hand a run of events to one of you, and compare how busy one stretch was against another. Everything I'd change comes back as a review first."
        }
        return nil
    }

    private func refusalLine(_ reason: AssistantCopy.RefusalReason) -> String {
        switch reason {
        case .generalKnowledge:
            return "That one's outside what I can see \u{2014} I only have this household's schedule to work from."
        case .professionalAdvice:
            return "I'd leave that to someone qualified. I can help with the scheduling side of it though."
        case .unsupportedOperation:
            return "I can't do that one. Here's what I can help with."
        case .outOfScope:
            return "That's outside the app, so I'll leave it. Ask me about the family's schedule and I'm useful."
        }
    }

    // MARK: - Plans

    private func findPlan(_ message: String, _ turn: Turn) -> LunaReply {
        if turn.ran(.findEvents) {
            let count = turn.lastFindCount ?? 0
            let line = count == 0
                ? "Nothing on the calendar for that stretch."
                : "Here's what's on \u{2014} \(count) in all."
            return .final(FinalDecision(
                outcome: .result,
                resultTemplate: count == 0 ? .foundNoEvents : .foundEvents,
                message: line
            ))
        }
        let range = self.range(in: message) ?? currentWeek
        var args: [String: Any] = [
            "start_date": range.start,
            "end_date": range.end,
            "person_ids": [],
            "categories": [],
            "only_unassigned": message.contains("unassigned") || message.contains("needs a driver"),
            "text_contains": NSNull()
        ]
        if message.contains("pickup") { args["text_contains"] = "pickup" }
        return call(.findEvents, args)
    }

    private func trendPlan(_ message: String, _ turn: Turn) -> LunaReply {
        if turn.ran(.getScheduleTrends) {
            return .final(FinalDecision(
                outcome: .result,
                resultTemplate: .trendsReady,
                message: "Here's how the two stretches compare. The card breaks down who's been driving and what kind of thing it was."
            ))
        }
        let range = self.range(in: message) ?? currentMonth
        return call(.getScheduleTrends, [
            "start_date": range.start,
            "end_date": range.end,
            "person_ids": []
        ])
    }

    private func createPlan(_ message: String, _ turn: Turn) -> LunaReply {
        if turn.ran(.previewCreateEvents) {
            let conflicts = turn.lastProposalConflicts ?? 0
            let line = conflicts > 0
                ? "I've laid it out below. A few of them clash with something already booked \u{2014} have a look before you confirm."
                : "Here it is. Nothing's saved until you hit confirm."
            return .final(FinalDecision(
                outcome: .result,
                resultTemplate: conflicts > 0 ? .reviewReadyWithConflicts : .reviewReady,
                message: line
            ))
        }

        let weekdays = self.weekdays(in: message)
        let repeats = message.contains("every") || message.contains("weekly") || !weekdays.isEmpty
        let weekCount = self.weekCount(in: message)

        // A series with no stated length is a clarification, not a guess.
        if repeats && weekCount == nil && endDate(in: message) == nil {
            return .final(FinalDecision(
                outcome: .clarify,
                clarificationKind: .missingSeriesBound,
                message: "How long should this run for?"
            ))
        }

        guard let start = startTime(in: message) else {
            return .final(FinalDecision(outcome: .clarify, clarificationKind: .missingTime))
        }

        let startDate = repeats
            ? firstDate(onOrAfter: today, weekdays: weekdays.isEmpty ? [CalendarMath.weekdayIndex(today) ?? 0] : weekdays)
            : (self.range(in: message)?.start ?? today)

        var args: [String: Any] = [
            "title": title(in: message),
            "start_date": startDate,
            "start_time": start,
            // Null on purpose: the app owns the default duration, and the
            // scripted planner should exercise that path rather than inventing
            // an hour the way it used to.
            "end_time": NSNull(),
            "location_name": place(in: message) as Any? ?? NSNull(),
            "kind": kind(in: message).rawValue,
            "child_ids": childIDs(in: message),
            "owner_id": NSNull(),
            "repeat_mode": repeats ? "weekly" : "none",
            "weekdays": repeats ? (weekdays.isEmpty ? [CalendarMath.weekdayIndex(startDate) ?? 0] : weekdays) : [],
            "week_count": NSNull(),
            "end_date": NSNull()
        ]
        if repeats {
            if let weekCount {
                args["week_count"] = weekCount
            } else if let end = endDate(in: message) {
                args["end_date"] = end
            }
        }
        return call(.previewCreateEvents, args)
    }

    private func assignPlan(_ message: String, _ turn: Turn) -> LunaReply {
        if turn.ran(.previewAssignTasks) {
            let conflicts = turn.lastProposalConflicts ?? 0
            let line = conflicts > 0
                ? "Ready to hand over, though some of these overlap with what they've already got on."
                : "Ready to hand over \u{2014} check the list and confirm."
            return .final(FinalDecision(
                outcome: .result,
                resultTemplate: conflicts > 0 ? .reviewReadyWithConflicts : .reviewReady,
                message: line
            ))
        }
        if !turn.ran(.listHouseholdPeople) {
            return call(.listHouseholdPeople, ["include_children": false])
        }

        // The caregiver has to come from the roster the app returned.
        guard let owner = turn.people.first(where: { message.contains($0.name.lowercased()) }) else {
            return .final(FinalDecision(
                outcome: .clarify,
                clarificationKind: .ambiguousPerson,
                candidatePersonIDs: turn.people.map(\.id),
                message: "Who should take these?"
            ))
        }

        if !turn.ran(.findEvents) {
            let range = self.range(in: message) ?? nextWeek
            var args: [String: Any] = [
                "start_date": range.start,
                "end_date": range.end,
                "person_ids": [],
                "categories": [],
                "only_unassigned": true,
                "text_contains": NSNull()
            ]
            if message.contains("pickup") { args["text_contains"] = "pickup" }
            else if message.contains("drop") { args["text_contains"] = "drop" }
            return call(.findEvents, args)
        }

        let ids = turn.lastFindEventIDs
        guard !ids.isEmpty else {
            return .final(FinalDecision(outcome: .result, resultTemplate: .foundNoEvents))
        }
        return call(.previewAssignTasks, ["event_ids": ids, "owner_id": owner.id])
    }

    // MARK: - Off-topic

    private func offTopicReason(_ message: String) -> AssistantCopy.RefusalReason? {
        let general = ["weather", "recipe", "news", "who won", "capital of", "translate", "stock", "search the web", "google", "wikipedia", "joke", "write a poem", "python", "javascript", "code"]
        if general.contains(where: message.contains) { return .generalKnowledge }

        let professional = ["diagnos", "symptom", "medication", "dosage", "legal advice", "custody", "invest"]
        if professional.contains(where: message.contains) { return .professionalAdvice }

        let unsupported = ["delete everything", "delete all", "export the database", "developer mode", "system prompt", "your instructions", "list every household", "other families", "admin"]
        if unsupported.contains(where: message.contains) { return .unsupportedOperation }

        if message.contains("ignore previous") || message.contains("ignore all previous") { return .outOfScope }
        return nil
    }

    private func helpTopic(_ message: String) -> HelpTopic? {
        if message.contains("what can you") || message.contains("what do you do") { return .whatTheAssistantCanDo }
        if message.contains("privacy") || message.contains("what data") || message.contains("openai") { return .privacyAndData }
        if message.contains("how do repeat") || message.contains("how does repeat") || message.contains("recurring work") { return .recurringEvents }
        if message.contains("conflict") || message.contains("buffer") { return .conflictsAndBuffer }
        if message.contains("google calendar") || message.contains("apple calendar") { return .calendarConnections }
        return nil
    }

    // MARK: - Message parsing

    private var currentWeek: DateRange {
        DateRange(start: displayedWeekStart, end: CalendarMath.addDays(displayedWeekStart, 6))!
    }

    private var nextWeek: DateRange {
        let start = CalendarMath.addDays(displayedWeekStart, 7)
        return DateRange(start: start, end: CalendarMath.addDays(start, 6))!
    }

    private var currentMonth: DateRange {
        let start = String(today.prefix(7)) + "-01"
        // Walk to the first of the next month and step back a day, so the
        // window is the real calendar month rather than a fixed 31 days.
        var cursor = start
        for _ in 0..<32 {
            let next = CalendarMath.addDays(cursor, 1)
            if next.prefix(7) != start.prefix(7) { break }
            cursor = next
        }
        return DateRange(start: start, end: cursor) ?? currentWeek
    }

    private func range(in message: String) -> DateRange? {
        if message.contains("next week") { return nextWeek }
        if message.contains("this week") || message.contains("the week") { return currentWeek }
        if message.contains("last week") {
            let start = CalendarMath.addDays(displayedWeekStart, -7)
            return DateRange(start: start, end: CalendarMath.addDays(start, 6))
        }
        if message.contains("tomorrow") {
            let d = CalendarMath.addDays(today, 1)
            return DateRange(start: d, end: d)
        }
        if message.contains("today") { return DateRange(start: today, end: today) }
        if message.contains("this month") || message.contains("last month") || message.contains("month") {
            return currentMonth
        }
        return nil
    }

    private static let weekdayWords: [(String, Int)] = [
        ("monday", 0), ("tuesday", 1), ("wednesday", 2), ("thursday", 3),
        ("friday", 4), ("saturday", 5), ("sunday", 6)
    ]

    private func weekdays(in message: String) -> [Int] {
        Self.weekdayWords.filter { message.contains($0.0) }.map(\.1).sorted()
    }

    private func weekCount(in message: String) -> Int? {
        guard let match = firstMatch(#"(\d{1,2})\s*weeks?"#, in: message), let n = Int(match) else { return nil }
        return (1...RecurrenceCore.maxWeeks).contains(n) ? n : nil
    }

    private func endDate(in message: String) -> String? {
        guard let match = firstMatch(#"(\d{4}-\d{2}-\d{2})"#, in: message) else { return nil }
        return CalendarMath.isValidDate(match) ? match : nil
    }

    private func startTime(in message: String) -> String? {
        if let iso = firstMatch(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: message, group: 0),
           let minutes = CalendarMath.minutes(iso.count == 4 ? "0" + iso : iso) {
            return CalendarMath.time(fromMinutes: minutes)
        }
        guard let clock = firstMatch(#"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, in: message, group: 0) else { return nil }
        let lower = clock.lowercased()
        let isPM = lower.contains("pm")
        let digits = lower.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").trimmingCharacters(in: .whitespaces)
        let parts = digits.split(separator: ":")
        guard var hour = Int(parts.first ?? "") else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        if isPM && hour < 12 { hour += 12 }
        if !isPM && hour == 12 { hour = 0 }
        return CalendarMath.time(fromMinutes: hour * 60 + minute)
    }

    private func title(in message: String) -> String {
        let activities = ["swimming", "swim", "soccer", "piano", "ballet", "tutoring", "karate", "basketball", "chess club", "gymnastics"]
        if let found = activities.first(where: message.contains) {
            return found.prefix(1).uppercased() + found.dropFirst()
        }
        return "New activity"
    }

    private func kind(in message: String) -> EventKind {
        if message.contains("swim") || message.contains("soccer") || message.contains("karate") || message.contains("basketball") || message.contains("gymnastics") { return .practice }
        if message.contains("piano") || message.contains("ballet") || message.contains("art") { return .lesson }
        if message.contains("dentist") || message.contains("doctor") || message.contains("checkup") { return .clinic }
        if message.contains("pickup") { return .pickup }
        if message.contains("drop") { return .dropoff }
        return .other
    }

    private func place(in message: String) -> String? {
        for place in Fixtures.places where message.contains(place.name.lowercased()) { return place.name }
        if message.contains("swim") { return "Eastside Pool" }
        if message.contains("soccer") { return "Riverside Fields" }
        return nil
    }

    private func childIDs(in message: String) -> [String] {
        Fixtures.people
            .filter { $0.role == .child && message.contains($0.name.lowercased()) }
            .map(\.id)
    }

    private func firstDate(onOrAfter start: String, weekdays: [Int]) -> String {
        for offset in 0...13 {
            let candidate = CalendarMath.addDays(start, offset)
            if let index = CalendarMath.weekdayIndex(candidate), weekdays.contains(index) { return candidate }
        }
        return start
    }

    private func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private func isCreateRequest(_ message: String) -> Bool {
        let verbs = ["schedule", "add", "create", "book", "set up", "put "]
        return verbs.contains { message.contains($0) }
    }

    private func call(_ tool: ToolName, _ arguments: [String: Any]) -> LunaReply {
        let data = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])) ?? Data("{}".utf8)
        return .toolCalls([RawToolCall(
            callID: "call-\(tool.rawValue)-\(UUID().uuidString.prefix(8))",
            name: tool.rawValue,
            argumentsJSON: String(data: data, encoding: .utf8) ?? "{}"
        )])
    }
}

// MARK: - Reading the turn so far

/// Reconstructs what has already happened in this turn from the items the
/// engine replays, the same way a real model would read its own context.
private struct Turn {
    let items: [ConversationItem]

    var sinceLastUserMessage: [ConversationItem] {
        guard let index = items.lastIndex(where: { if case .userMessage = $0 { return true }; return false }) else {
            return items
        }
        return Array(items[(index + 1)...])
    }

    var userMessage: String? {
        for item in items.reversed() {
            if case .userMessage(let text) = item { return text }
        }
        return nil
    }

    func ran(_ tool: ToolName) -> Bool {
        sinceLastUserMessage.contains { item in
            if case .toolCall(let call) = item { return call.name == tool.rawValue }
            return false
        }
    }

    private var results: [[String: Any]] {
        sinceLastUserMessage.compactMap { item in
            guard case .toolResult(_, let payload) = item,
                  let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return object
        }
    }

    var people: [AssistantPerson] {
        for result in results.reversed() {
            guard let rows = result["people"] as? [[String: Any]] else { continue }
            return rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let name = row["name"] as? String,
                      let roleRaw = row["role"] as? String,
                      let role = AssistantPerson.Role(rawValue: roleRaw) else { return nil }
                return AssistantPerson(id: id, name: name, role: role, relationship: row["relationship"] as? String ?? "")
            }
        }
        return []
    }

    var lastFindCount: Int? {
        for result in results.reversed() {
            if let total = result["total_matches"] as? Int { return total }
        }
        return nil
    }

    var lastFindEventIDs: [String] {
        for result in results.reversed() {
            if let events = result["events"] as? [[String: Any]] {
                return events.compactMap { $0["id"] as? String }
            }
        }
        return []
    }

    var lastProposalConflicts: Int? {
        for result in results.reversed() {
            if let count = result["conflict_count"] as? Int { return count }
        }
        return nil
    }
}
