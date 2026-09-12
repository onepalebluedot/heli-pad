import Foundation

/// The complete set of operations the model may name (A03). Anything outside
/// this enum fails to decode, which is the rejection: there is no default case
/// that guesses, and no dynamic registration.
public enum ToolName: String, CaseIterable, Codable, Sendable {
    case findEvents = "find_events"
    case getEvent = "get_event"
    case listHouseholdPeople = "list_household_people"
    case listSavedPlaces = "list_saved_places"
    case previewCreateEvents = "preview_create_events"
    case previewAssignTasks = "preview_assign_tasks"
    case getScheduleTrends = "get_schedule_trends"
    case getAppHelp = "get_app_help"

    /// Operations that only read. Nothing in this catalog writes: the two
    /// `preview_*` operations build a proposal the user must confirm, and
    /// confirmation is a UI action with no tool behind it (A04).
    public var isReadOnly: Bool {
        switch self {
        case .previewCreateEvents, .previewAssignTasks: return false
        default: return true
        }
    }
}

public struct ToolDefinition: Sendable {
    public let name: ToolName
    public let description: String
    public let parameters: JSONSchema

    /// Shape the Responses API expects for a strict function tool.
    public var wireFormat: [String: Any] {
        [
            "type": "function",
            "name": name.rawValue,
            "description": description,
            "strict": true,
            "parameters": parameters.json
        ]
    }
}

public enum ToolCatalog {
    public static let all: [ToolDefinition] = [
        findEvents, getEvent, listHouseholdPeople, listSavedPlaces,
        previewCreateEvents, previewAssignTasks, getScheduleTrends, getAppHelp
    ]

    public static func definition(for name: ToolName) -> ToolDefinition {
        all.first { $0.name == name }!
    }

    /// Serialised tool array for the request body. Built once per request; the
    /// relay is free to re-validate it server-side.
    public static func wireFormatJSON() throws -> Data {
        try JSONSerialization.data(withJSONObject: all.map(\.wireFormat), options: [.sortedKeys])
    }

    // MARK: - Definitions

    static let findEvents = ToolDefinition(
        name: .findEvents,
        description: "Find scheduled events in this household inside an explicit date range. Returns app data; it does not create or change anything.",
        parameters: .object(description: "Event search", properties: [
            ("start_date", .string(description: "First day to include, YYYY-MM-DD, in the household timezone.")),
            ("end_date", .string(description: "Last day to include, inclusive, YYYY-MM-DD.")),
            ("person_ids", .array(description: "Restrict to events involving these household person ids. Empty array means no person filter. Ids must come from list_household_people.", items: .string(description: "Household person id"), maxItems: 20)),
            ("categories", .array(description: "Restrict to these activity categories. Empty array means all.", items: .stringEnum(description: "Activity category", values: EventKind.categories), maxItems: 7)),
            ("only_unassigned", .boolean(description: "True to return only events with no caregiver assigned.")),
            ("text_contains", .nullable(.string(description: "Optional case-insensitive substring of the event title. Null for no title filter.")))
        ])
    )

    static let getEvent = ToolDefinition(
        name: .getEvent,
        description: "Read one event by its app id. The id must have come from find_events in this conversation.",
        parameters: .object(description: "Single event lookup", properties: [
            ("event_id", .string(description: "App event id previously returned by find_events."))
        ])
    )

    static let listHouseholdPeople = ToolDefinition(
        name: .listHouseholdPeople,
        description: "List the caregivers and children in this household, with their app ids.",
        parameters: .object(description: "No inputs", properties: [
            ("include_children", .boolean(description: "True to include children as well as caregivers."))
        ])
    )

    static let listSavedPlaces = ToolDefinition(
        name: .listSavedPlaces,
        description: "List the household's saved place names. Street addresses and coordinates are not available to this operation.",
        parameters: .object(description: "No inputs", properties: [
            ("verified_only", .boolean(description: "True to list only places the app can actually locate."))
        ])
    )

    static let previewCreateEvents = ToolDefinition(
        name: .previewCreateEvents,
        description: "Build a review of events that would be created, including every occurrence of a finite weekly series and any conflicts. This saves nothing. The person using the app confirms or cancels the review.",
        parameters: .object(description: "Proposed events", properties: [
            ("title", .string(description: "Event title exactly as the user said it.")),
            ("start_date", .string(description: "First occurrence date, YYYY-MM-DD.")),
            ("start_time", .string(description: "Start time, 24-hour HH:mm.")),
            ("end_time", .nullable(.string(description: "End time, 24-hour HH:mm, later than start_time on the same day. Pass null when the request did not say how long it lasts - the app fills in its own default for this kind of activity and shows the user what it assumed. Do not invent a duration."))),
            ("location_name", .nullable(.string(description: "A saved place name, spelled exactly as list_saved_places returned it. Call list_saved_places first: the household's places are not guessable from the title. Null only when no saved place fits, which puts the event at home."))),
            ("kind", .stringEnum(description: "Activity kind. This sets both the category the event is filed under and its default duration, so pick the closest fit rather than defaulting to 'other'. dropoff and pickup are school runs; practice is any sport or physical activity, including swimming; lesson is music, dance, art or tutoring; clinic is medical or dental; play is playdates and parties; dinner, cook and home are time at home; drive is a plain journey; other only when none of these fit.", values: EventKind.allCases.map(\.rawValue))),
            ("child_ids", .array(description: "Household person ids of the children involved. Empty if none were named.", items: .string(description: "Child person id"), maxItems: 10)),
            ("owner_id", .nullable(.string(description: "Caregiver person id to assign, or null to leave unassigned for later."))),
            ("repeat_mode", .stringEnum(description: "'none' for a single event, 'weekly' for a finite weekly series.", values: ["none", "weekly"])),
            ("weekdays", .array(description: "Weekly series only: days of the week, 0 = Monday through 6 = Sunday. Empty for repeat_mode 'none'.", items: .integer(description: "Weekday index", minimum: 0, maximum: 6), maxItems: 7)),
            ("week_count", .nullable(.integer(description: "Weekly series bounded by a number of calendar weeks, 1 to 52. Null when using end_date.", minimum: 1, maximum: 52))),
            ("end_date", .nullable(.string(description: "Weekly series bounded by an inclusive last date, YYYY-MM-DD. Null when using week_count.")))
        ])
    )

    static let previewAssignTasks = ToolDefinition(
        name: .previewAssignTasks,
        description: "Build a review of caregiver assignments for events that already exist. This saves nothing. The person using the app confirms or cancels the review.",
        parameters: .object(description: "Proposed assignments", properties: [
            ("event_ids", .array(description: "App event ids to assign, previously returned by find_events.", items: .string(description: "Event id"), maxItems: 60)),
            ("owner_id", .string(description: "Caregiver person id to assign them to, from list_household_people."))
        ])
    )

    static let getScheduleTrends = ToolDefinition(
        name: .getScheduleTrends,
        description: "Compare recorded schedule activity across a period and the equal-length period before it. Numbers are computed by the app, not by you.",
        parameters: .object(description: "Trend request", properties: [
            ("start_date", .string(description: "First day of the current period, YYYY-MM-DD.")),
            ("end_date", .string(description: "Last day of the current period, inclusive, YYYY-MM-DD.")),
            ("person_ids", .array(description: "Restrict to these household person ids. Empty array for the whole household.", items: .string(description: "Household person id"), maxItems: 20))
        ])
    )

    static let getAppHelp = ToolDefinition(
        name: .getAppHelp,
        description: "Look up how a HeliPad feature works. Only these topics exist; there is no general knowledge here.",
        parameters: .object(description: "Help lookup", properties: [
            ("topic", .stringEnum(description: "Help topic.", values: HelpTopic.allCases.map(\.rawValue)))
        ])
    )
}

/// Bounded help vocabulary (A03: "bounded get_app_help"). Adding a topic is a
/// code change with copy the app owns, not a model decision.
public enum HelpTopic: String, CaseIterable, Codable, Sendable {
    case recurringEvents = "recurring_events"
    case assigningCaregivers = "assigning_caregivers"
    case conflictsAndBuffer = "conflicts_and_buffer"
    case calendarConnections = "calendar_connections"
    case whatTheAssistantCanDo = "what_the_assistant_can_do"
    case privacyAndData = "privacy_and_data"
}
