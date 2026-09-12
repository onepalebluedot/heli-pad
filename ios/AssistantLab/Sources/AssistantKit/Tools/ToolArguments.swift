import Foundation

/// A tool call as it arrived from the model: a name and an argument blob,
/// neither of them trusted yet.
public struct RawToolCall: Hashable, Sendable {
    public let callID: String
    public let name: String
    public let argumentsJSON: String

    public init(callID: String, name: String, argumentsJSON: String) {
        self.callID = callID
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Why a call was refused. Every case maps to app-owned copy; none of these
/// strings come from the model.
public enum ToolRejection: Error, Equatable, Sendable {
    case unknownTool(String)
    case malformedArguments(tool: String, detail: String)
    case unknownField(tool: String, field: String)
    case missingField(tool: String, field: String)
    case invalidValue(tool: String, field: String, detail: String)
    case rangeTooLong(days: Int, limit: Int)
    case unknownPersonID(String)
    case unknownEventID(String)
    case unknownPlace(String)
    case personIsNotCaregiver(String)
    case recurrence(RecurrenceError)

    public var developerDescription: String {
        switch self {
        case .unknownTool(let n): return "unknown tool '\(n)'"
        case .malformedArguments(let t, let d): return "\(t): malformed arguments (\(d))"
        case .unknownField(let t, let f): return "\(t): unknown field '\(f)'"
        case .missingField(let t, let f): return "\(t): missing field '\(f)'"
        case .invalidValue(let t, let f, let d): return "\(t): invalid \(f) (\(d))"
        case .rangeTooLong(let days, let limit): return "date range of \(days) days exceeds \(limit)"
        case .unknownPersonID(let id): return "no such person '\(id)' in this household"
        case .unknownEventID(let id): return "no such event '\(id)' in this household"
        case .unknownPlace(let name): return "no saved place '\(name)'"
        case .personIsNotCaregiver(let id): return "person '\(id)' is not a caregiver"
        case .recurrence(let e): return "recurrence: \(e)"
        }
    }
}

/// The validated, typed form of an allowlisted call. Only these values reach
/// the query and command layers.
public enum ValidatedToolCall: Sendable {
    case findEvents(FindEventsArgs)
    case getEvent(eventID: String)
    case listHouseholdPeople(includeChildren: Bool)
    case listSavedPlaces(verifiedOnly: Bool)
    case previewCreateEvents(CreateEventsArgs)
    case previewAssignTasks(eventIDs: [String], ownerID: String)
    case getScheduleTrends(range: DateRange, personIDs: [String])
    case getAppHelp(HelpTopic)

    public var name: ToolName {
        switch self {
        case .findEvents: return .findEvents
        case .getEvent: return .getEvent
        case .listHouseholdPeople: return .listHouseholdPeople
        case .listSavedPlaces: return .listSavedPlaces
        case .previewCreateEvents: return .previewCreateEvents
        case .previewAssignTasks: return .previewAssignTasks
        case .getScheduleTrends: return .getScheduleTrends
        case .getAppHelp: return .getAppHelp
        }
    }
}

public struct FindEventsArgs: Hashable, Sendable {
    public var range: DateRange
    public var personIDs: [String]
    public var categories: [String]
    public var onlyUnassigned: Bool
    public var textContains: String?
}

public struct CreateEventsArgs: Hashable, Sendable {
    public var title: String
    public var startTime: String
    public var endTime: String
    public var locationName: String?
    public var kind: EventKind
    public var childIDs: [String]
    public var ownerID: String?
    public var rule: RecurrenceRule
    /// True when the request carried no end time and the app supplied its
    /// default for this kind. Surfaced on the review so the assumption is
    /// visible rather than silent.
    public var durationWasAssumed: Bool = false
    /// True when no saved place was named and the event fell back to home.
    public var locationWasAssumed: Bool = false
}

/// Shape-level validation: names, fields, formats, enums and bounds.
///
/// Identifier existence is *not* checked here — that needs household data and
/// happens in `ToolRouter`, so that an id which merely looks plausible still
/// cannot reach a query.
public enum ToolArgumentParser {
    /// Widest window any single query may cover. Two years is past anything the
    /// planner materialises and keeps one call from sweeping all history.
    public static let maxRangeDays = 731

    public static func validate(_ call: RawToolCall) throws -> ValidatedToolCall {
        guard let tool = ToolName(rawValue: call.name) else {
            throw ToolRejection.unknownTool(call.name)
        }

        let object = try decodeObject(tool: call.name, json: call.argumentsJSON)
        try rejectUnknownFields(tool: tool, object: object)

        switch tool {
        case .findEvents:
            let range = try range(tool: tool, object: object, startKey: "start_date", endKey: "end_date")
            return .findEvents(FindEventsArgs(
                range: range,
                personIDs: try stringArray(tool: tool, object: object, key: "person_ids", max: 20),
                categories: try categories(tool: tool, object: object),
                onlyUnassigned: try bool(tool: tool, object: object, key: "only_unassigned"),
                textContains: try optionalString(tool: tool, object: object, key: "text_contains")
            ))

        case .getEvent:
            return .getEvent(eventID: try nonEmptyString(tool: tool, object: object, key: "event_id"))

        case .listHouseholdPeople:
            return .listHouseholdPeople(includeChildren: try bool(tool: tool, object: object, key: "include_children"))

        case .listSavedPlaces:
            return .listSavedPlaces(verifiedOnly: try bool(tool: tool, object: object, key: "verified_only"))

        case .previewCreateEvents:
            return .previewCreateEvents(try createArgs(tool: tool, object: object))

        case .previewAssignTasks:
            let ids = try stringArray(tool: tool, object: object, key: "event_ids", max: 60)
            guard !ids.isEmpty else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "event_ids", detail: "at least one event is required")
            }
            return .previewAssignTasks(
                eventIDs: ids,
                ownerID: try nonEmptyString(tool: tool, object: object, key: "owner_id")
            )

        case .getScheduleTrends:
            return .getScheduleTrends(
                range: try range(tool: tool, object: object, startKey: "start_date", endKey: "end_date"),
                personIDs: try stringArray(tool: tool, object: object, key: "person_ids", max: 20)
            )

        case .getAppHelp:
            let raw = try nonEmptyString(tool: tool, object: object, key: "topic")
            guard let topic = HelpTopic(rawValue: raw) else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "topic", detail: "unsupported topic")
            }
            return .getAppHelp(topic)
        }
    }

    // MARK: - Field helpers

    private static func decodeObject(tool: String, json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8) else {
            throw ToolRejection.malformedArguments(tool: tool, detail: "arguments were not UTF-8")
        }
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let object = any as? [String: Any] else {
            throw ToolRejection.malformedArguments(tool: tool, detail: "arguments were not a JSON object")
        }
        return object
    }

    /// Strict-mode schemas name every field, so anything else in the payload is
    /// either a model error or an attempt to reach a parameter that does not
    /// exist. Both are refused rather than ignored.
    private static func rejectUnknownFields(tool: ToolName, object: [String: Any]) throws {
        guard case .object(_, let properties) = ToolCatalog.definition(for: tool).parameters else { return }
        let allowed = Set(properties.map(\.0))
        for key in object.keys where !allowed.contains(key) {
            throw ToolRejection.unknownField(tool: tool.rawValue, field: key)
        }
    }

    private static func value(tool: ToolName, object: [String: Any], key: String) throws -> Any {
        guard let v = object[key] else { throw ToolRejection.missingField(tool: tool.rawValue, field: key) }
        return v
    }

    private static func bool(tool: ToolName, object: [String: Any], key: String) throws -> Bool {
        guard let b = try value(tool: tool, object: object, key: key) as? Bool else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "expected true or false")
        }
        return b
    }

    private static func nonEmptyString(tool: ToolName, object: [String: Any], key: String) throws -> String {
        guard let s = try value(tool: tool, object: object, key: key) as? String else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "expected a string")
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "must not be empty")
        }
        return trimmed
    }

    private static func optionalString(tool: ToolName, object: [String: Any], key: String) throws -> String? {
        let v = try value(tool: tool, object: object, key: key)
        if v is NSNull { return nil }
        guard let s = v as? String else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "expected a string or null")
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalInt(tool: ToolName, object: [String: Any], key: String) throws -> Int? {
        let v = try value(tool: tool, object: object, key: key)
        if v is NSNull { return nil }
        guard let n = v as? NSNumber, CFNumberIsFloatType(n) == false else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "expected a whole number or null")
        }
        return n.intValue
    }

    private static func stringArray(tool: ToolName, object: [String: Any], key: String, max: Int) throws -> [String] {
        guard let raw = try value(tool: tool, object: object, key: key) as? [Any] else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "expected an array")
        }
        guard raw.count <= max else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "at most \(max) entries")
        }
        var out: [String] = []
        for element in raw {
            guard let s = element as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "entries must be non-empty strings")
            }
            out.append(s.trimmingCharacters(in: .whitespaces))
        }
        // Duplicates are collapsed rather than refused: the same id twice is a
        // harmless model slip, and de-duplicating here keeps "affected count"
        // honest downstream.
        return Array(NSOrderedSet(array: out).array as! [String])
    }

    private static func categories(tool: ToolName, object: [String: Any]) throws -> [String] {
        let raw = try stringArray(tool: tool, object: object, key: "categories", max: 7)
        let allowed = Set(EventKind.categories)
        for c in raw where !allowed.contains(c) {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: "categories", detail: "unknown category '\(c)'")
        }
        return raw
    }

    private static func date(tool: ToolName, object: [String: Any], key: String) throws -> String {
        let s = try nonEmptyString(tool: tool, object: object, key: key)
        guard CalendarMath.isValidDate(s) else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "expected YYYY-MM-DD")
        }
        return s
    }

    private static func time(tool: ToolName, object: [String: Any], key: String) throws -> String {
        let s = try nonEmptyString(tool: tool, object: object, key: key)
        guard CalendarMath.minutes(s) != nil else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: key, detail: "expected 24-hour HH:mm")
        }
        return s
    }

    private static func range(tool: ToolName, object: [String: Any], startKey: String, endKey: String) throws -> DateRange {
        let start = try date(tool: tool, object: object, key: startKey)
        let end = try date(tool: tool, object: object, key: endKey)
        guard let range = DateRange(start: start, end: end) else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: endKey, detail: "end date is before start date")
        }
        guard range.dayCount <= maxRangeDays else {
            throw ToolRejection.rangeTooLong(days: range.dayCount, limit: maxRangeDays)
        }
        return range
    }

    private static func createArgs(tool: ToolName, object: [String: Any]) throws -> CreateEventsArgs {
        let title = try nonEmptyString(tool: tool, object: object, key: "title")
        guard title.count <= 80 else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: "title", detail: "at most 80 characters")
        }
        let startDate = try date(tool: tool, object: object, key: "start_date")
        let startTime = try time(tool: tool, object: object, key: "start_time")
        guard let startMinutes = CalendarMath.minutes(startTime) else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: "start_time", detail: "expected 24-hour HH:mm")
        }

        let kindRaw = try nonEmptyString(tool: tool, object: object, key: "kind")
        guard let kind = EventKind(rawValue: kindRaw) else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: "kind", detail: "unknown activity kind")
        }

        // A missing end time is filled from the app's own table rather than by
        // the model. An end that runs past midnight is clamped to the end of
        // the day, because the record format cannot express a stop that lands
        // on the following date.
        let endTime: String
        let durationWasAssumed: Bool
        if let stated = try optionalString(tool: tool, object: object, key: "end_time") {
            guard let endMinutes = CalendarMath.minutes(stated) else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "end_time", detail: "expected 24-hour HH:mm")
            }
            guard endMinutes > startMinutes else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "end_time", detail: "must be after start_time on the same day")
            }
            endTime = stated
            durationWasAssumed = false
        } else {
            let proposed = startMinutes + kind.defaultDurationMinutes
            guard proposed < 24 * 60 else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "start_time", detail: "a \(kind.defaultDurationMinutes)-minute \(kind.rawValue) starting at \(startTime) would run past midnight; give an explicit end_time")
            }
            endTime = CalendarMath.time(fromMinutes: proposed)
            durationWasAssumed = true
        }

        let repeatModeRaw = try nonEmptyString(tool: tool, object: object, key: "repeat_mode")
        guard let mode = RecurrenceRule.Mode(rawValue: repeatModeRaw) else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: "repeat_mode", detail: "expected 'none' or 'weekly'")
        }

        let weekdaysRaw = try value(tool: tool, object: object, key: "weekdays")
        guard let weekdayAny = weekdaysRaw as? [Any] else {
            throw ToolRejection.invalidValue(tool: tool.rawValue, field: "weekdays", detail: "expected an array")
        }
        var weekdays: [Int] = []
        for element in weekdayAny {
            guard let n = element as? NSNumber, CFNumberIsFloatType(n) == false, (0...6).contains(n.intValue) else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "weekdays", detail: "entries must be 0 (Monday) through 6 (Sunday)")
            }
            weekdays.append(n.intValue)
        }

        let weekCount = try optionalInt(tool: tool, object: object, key: "week_count")
        let endDate = try optionalString(tool: tool, object: object, key: "end_date")

        let bound: RecurrenceRule.Bound
        switch mode {
        case .none:
            guard weekCount == nil, endDate == nil else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "repeat_mode", detail: "a single event cannot carry week_count or end_date")
            }
            weekdays = [CalendarMath.weekdayIndex(startDate) ?? 0]
            bound = .weeks(1)
        case .weekly:
            guard !weekdays.isEmpty else {
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "weekdays", detail: "a weekly series needs at least one weekday")
            }
            switch (weekCount, endDate) {
            case (let n?, nil):
                // The schema declares the range, but schema enforcement happens
                // on the provider's side. Re-checking here means a model that
                // ignores it is refused at the boundary rather than deeper in.
                guard (1...RecurrenceCore.maxWeeks).contains(n) else {
                    throw ToolRejection.invalidValue(tool: tool.rawValue, field: "week_count", detail: "must be 1 to \(RecurrenceCore.maxWeeks)")
                }
                bound = .weeks(n)
            case (nil, let d?):
                guard CalendarMath.isValidDate(d) else {
                    throw ToolRejection.invalidValue(tool: tool.rawValue, field: "end_date", detail: "expected YYYY-MM-DD")
                }
                bound = .until(d)
            case (nil, nil):
                throw ToolRejection.missingField(tool: tool.rawValue, field: "week_count or end_date")
            case (_?, _?):
                throw ToolRejection.invalidValue(tool: tool.rawValue, field: "week_count", detail: "set either week_count or end_date, not both")
            }
        }

        let locationName = try optionalString(tool: tool, object: object, key: "location_name")

        return CreateEventsArgs(
            title: TitleNormalizer.normalize(title),
            startTime: startTime,
            endTime: endTime,
            locationName: locationName,
            kind: kind,
            childIDs: try stringArray(tool: tool, object: object, key: "child_ids", max: 10),
            ownerID: try optionalString(tool: tool, object: object, key: "owner_id"),
            rule: RecurrenceRule(mode: mode, weekdays: weekdays, bound: bound, startDate: startDate),
            durationWasAssumed: durationWasAssumed,
            locationWasAssumed: locationName == nil
        )
    }
}
