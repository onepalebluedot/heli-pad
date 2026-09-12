import Foundation

/// Everything the chat can display.
///
/// A03 requires that the assistant never renders model prose or raw streaming
/// tokens. This enum is the only thing the chat view knows how to draw, and
/// every case is built by app code from app data. The model's contribution is
/// limited to choosing which allowlisted operation ran and, at the end, which
/// app-owned template summarises it.
public enum AssistantCard: Hashable, Sendable, Identifiable, Codable {
    case summary(SummaryCard)
    case eventList(EventListCard)
    case people(PeopleCard)
    case places(PlacesCard)
    case proposal(ProposalCard)
    case trends(TrendCard)
    case help(HelpCard)
    case clarification(ClarificationCard)
    case refusal(RefusalCard)
    case receipt(ReceiptCard)
    case failure(FailureCard)

    public var id: String {
        switch self {
        case .summary(let c): return "summary:\(c.id)"
        case .eventList(let c): return "events:\(c.id)"
        case .people(let c): return "people:\(c.id)"
        case .places(let c): return "places:\(c.id)"
        case .proposal(let c): return "proposal:\(c.proposalID)"
        case .trends(let c): return "trends:\(c.id)"
        case .help(let c): return "help:\(c.topic.rawValue)"
        case .clarification(let c): return "clarify:\(c.id)"
        case .refusal(let c): return "refusal:\(c.id)"
        case .receipt(let c): return "receipt:\(c.id)"
        case .failure(let c): return "failure:\(c.id)"
        }
    }
}

/// One line of app-owned narration. `text` is assembled from a fixed template
/// and validated slots, never copied from the model.
public struct SummaryCard: Hashable, Sendable, Codable {
    public var id: String
    public var text: String

    public init(id: String = UUID().uuidString, text: String) {
        self.id = id
        self.text = text
    }
}

public struct EventListCard: Hashable, Sendable, Codable {
    public var id: String
    /// The period these rows came from, always shown.
    public var periodLabel: String
    public var rows: [EventRow]
    /// How many matches were left out by the display cap, so the count on
    /// screen never implies the query found only this many.
    public var omittedCount: Int

    public init(id: String = UUID().uuidString, periodLabel: String, rows: [EventRow], omittedCount: Int = 0) {
        self.id = id
        self.periodLabel = periodLabel
        self.rows = rows
        self.omittedCount = omittedCount
    }
}

/// A tappable row that opens the real event in the app. `eventID` and `date`
/// are what the host uses to route; the assistant does not navigate on its own.
public struct EventRow: Hashable, Sendable, Identifiable, Codable {
    public var id: String { eventID }
    public var eventID: String
    public var date: String
    public var time: String
    public var endTime: String
    /// Household-authored. The view renders it quoted and inert.
    public var title: String
    public var ownerLabel: String
    public var isUnassigned: Bool
    public var locationName: String
    public var category: String
    public var isPast: Bool

    public init(
        eventID: String, date: String, time: String, endTime: String, title: String,
        ownerLabel: String, isUnassigned: Bool, locationName: String, category: String, isPast: Bool
    ) {
        self.eventID = eventID
        self.date = date
        self.time = time
        self.endTime = endTime
        self.title = title
        self.ownerLabel = ownerLabel
        self.isUnassigned = isUnassigned
        self.locationName = locationName
        self.category = category
        self.isPast = isPast
    }
}

public struct PeopleCard: Hashable, Sendable, Codable {
    public var id: String
    public var caregivers: [AssistantPerson]
    public var children: [AssistantPerson]

    public init(id: String = UUID().uuidString, caregivers: [AssistantPerson], children: [AssistantPerson]) {
        self.id = id
        self.caregivers = caregivers
        self.children = children
    }
}

public struct PlacesCard: Hashable, Sendable, Codable {
    public var id: String
    public var places: [AssistantPlace]

    public init(id: String = UUID().uuidString, places: [AssistantPlace]) {
        self.id = id
        self.places = places
    }
}

public struct HelpCard: Hashable, Sendable, Codable {
    public var topic: HelpTopic
    public var title: String
    public var body: [String]

    public init(topic: HelpTopic, title: String, body: [String]) {
        self.topic = topic
        self.title = title
        self.body = body
    }
}

/// A question the app asks when a name, date or person was ambiguous. A03
/// forbids guessing an assignment, so the run stops here and waits.
public struct ClarificationCard: Hashable, Sendable, Codable {
    public var id: String
    public var question: String
    public var options: [Option]

    public struct Option: Hashable, Sendable, Identifiable, Codable {
        public var id: String
        public var label: String
        /// The message that is sent on the user's behalf when they tap it.
        public var reply: String

        public init(id: String, label: String, reply: String) {
            self.id = id
            self.label = label
            self.reply = reply
        }
    }

    public init(id: String = UUID().uuidString, question: String, options: [Option]) {
        self.id = id
        self.question = question
        self.options = options
    }
}

public struct RefusalCard: Hashable, Sendable, Codable {
    public var id: String
    public var text: String
    /// What the assistant *can* do, so a refusal is still useful.
    public var suggestions: [String]

    public init(id: String = UUID().uuidString, text: String, suggestions: [String]) {
        self.id = id
        self.text = text
        self.suggestions = suggestions
    }
}

/// Shown only after a mutation actually succeeded (A04).
public struct ReceiptCard: Hashable, Sendable, Codable {
    public var id: String
    public var headline: String
    public var detail: String
    /// "Saved on this device, sync pending" vs "Synced", stated exactly.
    public var syncLabel: String
    /// App-local creation is never described as calendar export.
    public var externalCalendarLabel: String?
    public var rows: [EventRow]

    public init(
        id: String = UUID().uuidString,
        headline: String,
        detail: String,
        syncLabel: String,
        externalCalendarLabel: String? = nil,
        rows: [EventRow]
    ) {
        self.id = id
        self.headline = headline
        self.detail = detail
        self.syncLabel = syncLabel
        self.externalCalendarLabel = externalCalendarLabel
        self.rows = rows
    }
}

/// Something did not work. Truthful recovery, no partial result dressed up as
/// an answer.
public struct FailureCard: Hashable, Sendable, Codable {
    public enum Reason: String, Hashable, Sendable, Codable {
        case offline
        case cancelled
        case timedOut
        case quota
        case serviceError
        case invalidModelResponse
        case toolRejected
        case roundLimit
        case proposalExpired
        case proposalStale
        case saveFailed
    }

    public var id: String
    public var reason: Reason
    public var text: String
    public var canRetry: Bool

    public init(id: String = UUID().uuidString, reason: Reason, text: String, canRetry: Bool) {
        self.id = id
        self.reason = reason
        self.text = text
        self.canRetry = canRetry
    }
}
