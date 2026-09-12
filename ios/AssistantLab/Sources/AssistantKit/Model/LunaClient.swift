import Foundation

/// One item of the conversation as the model sees it.
///
/// Note what is absent: there is no case for free assistant prose. The model's
/// only outputs are tool calls and a final structured decision, and those are
/// the only things replayed back to it on the next round.
public enum ConversationItem: Hashable, Sendable {
    case userMessage(String)
    case toolCall(RawToolCall)
    case toolResult(callID: String, payload: String)
    /// A previous turn's decision, as the JSON the model itself produced.
    case assistantDecision(String)
    /// A refused call, so the model can correct course instead of retrying the
    /// same thing. Carries app-authored text only.
    case toolRejected(callID: String, reason: String)
}

public struct LunaRequest: Sendable {
    public var instructions: String
    public var items: [ConversationItem]
    /// Explicit, non-negotiable ceiling on generated tokens.
    public var maxOutputTokens: Int

    public init(instructions: String, items: [ConversationItem], maxOutputTokens: Int) {
        self.instructions = instructions
        self.items = items
        self.maxOutputTokens = maxOutputTokens
    }
}

/// The model's closing decision.
///
/// `message` is the model's own words. It is shown to the user, which is a
/// deliberate relaxation of A03's "render only app-owned templates" rule - a
/// scheduling assistant that can only speak in canned sentences does not feel
/// like something you can talk to.
///
/// What replaces the templating guarantee is grounding: `ProseValidator`
/// checks every number in the message against the numbers the app's own
/// operations returned, and the message is rejected if it asserts a figure
/// that did not come from household data. The typed cards below it are still
/// built entirely by app code, so the authoritative version of any fact is
/// always on screen next to the prose.
public struct FinalDecision: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case result
        case clarify
        case refuse
        /// Greetings, thanks, "what can you do" - conversational turns that
        /// need no operation. Held to a stricter prose rule than the others:
        /// with no tool output to ground against, the message may not assert
        /// anything numeric.
        case converse
    }

    public var outcome: Outcome
    public var resultTemplate: AssistantCopy.ResultTemplate?
    public var clarificationKind: AssistantCopy.ClarificationKind?
    /// Household person ids to offer as clarification choices. Validated
    /// against the household before anything is rendered.
    public var candidatePersonIDs: [String]
    /// Candidate dates, YYYY-MM-DD, validated before rendering.
    public var candidateDates: [String]
    public var refusalReason: AssistantCopy.RefusalReason?
    /// The model's own wording. Validated before display; the template is the
    /// fallback when it fails.
    public var message: String?

    public init(
        outcome: Outcome,
        resultTemplate: AssistantCopy.ResultTemplate? = nil,
        clarificationKind: AssistantCopy.ClarificationKind? = nil,
        candidatePersonIDs: [String] = [],
        candidateDates: [String] = [],
        refusalReason: AssistantCopy.RefusalReason? = nil,
        message: String? = nil
    ) {
        self.outcome = outcome
        self.resultTemplate = resultTemplate
        self.clarificationKind = clarificationKind
        self.candidatePersonIDs = candidatePersonIDs
        self.candidateDates = candidateDates
        self.refusalReason = refusalReason
        self.message = message
    }

    /// Strict JSON schema for the structured output. Optionality is expressed
    /// as a nullable enum, because strict mode requires every key present.
    public static var responseSchema: [String: Any] {
        [
            "type": "json_schema",
            "name": "helipad_assistant_decision",
            "strict": true,
            "schema": [
                "type": "object",
                "additionalProperties": false,
                "required": ["outcome", "result_template", "clarification_kind", "candidate_person_ids", "candidate_dates", "refusal_reason", "message"],
                "properties": [
                    "outcome": ["type": "string", "enum": ["result", "clarify", "refuse", "converse"]],
                    "message": [
                        "type": ["string", "null"],
                        "description": "What to say to the person, in your own words. One or two sentences, warm and plain. Every number you write must have come from an operation result - if you are unsure, leave it out and let the card carry it."
                    ],
                    "result_template": ["type": ["string", "null"], "enum": AssistantCopy.ResultTemplate.allCases.map(\.rawValue) + [NSNull()]],
                    "clarification_kind": ["type": ["string", "null"], "enum": AssistantCopy.ClarificationKind.allCases.map(\.rawValue) + [NSNull()]],
                    "candidate_person_ids": ["type": "array", "maxItems": 6, "items": ["type": "string"]],
                    "candidate_dates": ["type": "array", "maxItems": 6, "items": ["type": "string"]],
                    "refusal_reason": ["type": ["string", "null"], "enum": AssistantCopy.RefusalReason.allCases.map(\.rawValue) + [NSNull()]]
                ]
            ]
        ]
    }

    public static func decode(_ json: String) throws -> FinalDecision {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LunaError.invalidResponse("decision was not a JSON object")
        }
        guard let outcomeRaw = object["outcome"] as? String,
              let outcome = Outcome(rawValue: outcomeRaw) else {
            throw LunaError.invalidResponse("missing or unknown outcome")
        }
        func enumValue<T: RawRepresentable>(_ key: String) -> T? where T.RawValue == String {
            guard let raw = object[key] as? String else { return nil }
            return T(rawValue: raw)
        }
        let ids = (object["candidate_person_ids"] as? [Any])?.compactMap { $0 as? String } ?? []
        let dates = (object["candidate_dates"] as? [Any])?.compactMap { $0 as? String } ?? []

        return FinalDecision(
            outcome: outcome,
            resultTemplate: enumValue("result_template"),
            clarificationKind: enumValue("clarification_kind"),
            candidatePersonIDs: Array(ids.prefix(6)),
            candidateDates: Array(dates.prefix(6)),
            refusalReason: enumValue("refusal_reason"),
            message: object["message"] as? String
        )
    }
}

public enum LunaReply: Sendable {
    case toolCalls([RawToolCall])
    case final(FinalDecision)
}

public enum LunaError: Error, Equatable, Sendable {
    case notConfigured(String)
    case offline
    case cancelled
    case timedOut
    case quotaExceeded
    /// Non-success from the relay. `detail` is for logs; the user sees
    /// app-owned copy.
    case service(status: Int, detail: String)
    case invalidResponse(String)

    public var failureReason: FailureCard.Reason {
        switch self {
        case .offline: return .offline
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .quotaExceeded: return .quota
        case .invalidResponse: return .invalidModelResponse
        case .notConfigured, .service: return .serviceError
        }
    }
}

/// One round-trip to the model. Implementations must not retry on their own:
/// the engine owns the round budget.
public protocol LunaClient: Sendable {
    func send(_ request: LunaRequest) async throws -> LunaReply
}
