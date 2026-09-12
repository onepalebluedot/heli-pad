import Foundation

/// Every user-visible sentence the assistant can produce.
///
/// The model selects an identifier from these enums; the wording and all the
/// numbers in it come from here and from tool results the app computed. That is
/// what makes "the assistant can only talk about the app" a property of the
/// code rather than a hope about the prompt.
public enum AssistantCopy {

    // MARK: - Result templates

    /// Which app-owned sentence introduces the cards. The model picks the id;
    /// it never supplies the text or the numbers.
    public enum ResultTemplate: String, CaseIterable, Codable, Sendable {
        case foundEvents = "found_events"
        case foundNoEvents = "found_no_events"
        case reviewReady = "review_ready"
        case reviewReadyWithConflicts = "review_ready_with_conflicts"
        case trendsReady = "trends_ready"
        case peopleListed = "people_listed"
        case placesListed = "places_listed"
        case helpShown = "help_shown"
    }

    /// Slots are filled from tool output, not from anything the model wrote.
    public struct ResultSlots: Sendable {
        public var count: Int
        public var periodLabel: String
        public var conflictCount: Int

        public init(count: Int = 0, periodLabel: String = "", conflictCount: Int = 0) {
            self.count = count
            self.periodLabel = periodLabel
            self.conflictCount = conflictCount
        }
    }

    public static func text(for template: ResultTemplate, slots: ResultSlots) -> String {
        switch template {
        case .foundEvents:
            let noun = slots.count == 1 ? "event" : "events"
            return "\(slots.count) \(noun) in \(slots.periodLabel)."
        case .foundNoEvents:
            return "Nothing scheduled in \(slots.periodLabel)."
        case .reviewReady:
            let noun = slots.count == 1 ? "change" : "changes"
            return "Here is the review: \(slots.count) \(noun). Nothing is saved until you confirm."
        case .reviewReadyWithConflicts:
            let noun = slots.count == 1 ? "change" : "changes"
            let clash = slots.conflictCount == 1 ? "conflict" : "conflicts"
            return "Here is the review: \(slots.count) \(noun), with \(slots.conflictCount) \(clash) to look at. Nothing is saved until you confirm."
        case .trendsReady:
            return "Here is what the app has recorded for \(slots.periodLabel)."
        case .peopleListed:
            return "Everyone in your household."
        case .placesListed:
            return "Your saved places."
        case .helpShown:
            return "Here is how that works in HeliPad."
        }
    }

    // MARK: - Clarification

    public enum ClarificationKind: String, CaseIterable, Codable, Sendable {
        case ambiguousPerson = "ambiguous_person"
        case ambiguousDate = "ambiguous_date"
        case missingTime = "missing_time"
        case missingSeriesBound = "missing_series_bound"
        case ambiguousPlace = "ambiguous_place"
        case ambiguousEvent = "ambiguous_event"
    }

    public static func clarificationQuestion(_ kind: ClarificationKind) -> String {
        switch kind {
        case .ambiguousPerson: return "Which person did you mean?"
        case .ambiguousDate: return "Which date did you mean?"
        case .missingTime: return "What time should it start and end?"
        case .missingSeriesBound: return "How long should this repeat?"
        case .ambiguousPlace: return "Which saved place did you mean?"
        case .ambiguousEvent: return "Which event did you mean?"
        }
    }

    /// Offered when a series has no end. The app supplies these, matching the
    /// presets the manual editor offers.
    public static let seriesBoundOptions: [ClarificationCard.Option] = [
        .init(id: "weeks_20", label: "20 weeks", reply: "Repeat it for 20 weeks."),
        .init(id: "weeks_30", label: "30 weeks", reply: "Repeat it for 30 weeks."),
        .init(id: "weeks_custom", label: "A different number of weeks", reply: "Let me pick the number of weeks.")
    ]

    // MARK: - Refusals

    public enum RefusalReason: String, CaseIterable, Codable, Sendable {
        case outOfScope = "out_of_scope"
        case generalKnowledge = "general_knowledge"
        case professionalAdvice = "professional_advice"
        case unsupportedOperation = "unsupported_operation"
    }

    public static func refusal(_ reason: RefusalReason) -> RefusalCard {
        let text: String
        switch reason {
        case .outOfScope:
            text = "I only work inside HeliPad \u{2014} your household's schedule, people, saved places and planning."
        case .generalKnowledge:
            text = "I can't look things up outside HeliPad. I only see this household's schedule."
        case .professionalAdvice:
            text = "That needs a professional, not a scheduling assistant. I can still help with the calendar side of it."
        case .unsupportedOperation:
            text = "HeliPad's assistant can't do that. Here is what it can do."
        }
        return RefusalCard(text: text, suggestions: capabilities)
    }

    public static let capabilities = [
        "Find events in a date range",
        "Create a recurring activity for review",
        "Assign a caregiver to events for review",
        "Compare how busy two periods were"
    ]

    /// Shown in the empty composer. A06 asks these to cover finding, creating,
    /// assigning and comparing.
    public static let suggestedPrompts = [
        "What's on this week?",
        "Schedule swimming every Tuesday at 4pm for 30 weeks",
        "Assign next week's pickups to Alex",
        "How does this month compare with last month?"
    ]

    // MARK: - Failures

    public static func failure(_ reason: FailureCard.Reason) -> FailureCard {
        switch reason {
        case .offline:
            return FailureCard(reason: reason, text: "No connection, so I couldn't ask. Your schedule is unchanged and still works offline.", canRetry: true)
        case .cancelled:
            return FailureCard(reason: reason, text: "Stopped. Nothing was sent or changed.", canRetry: true)
        case .timedOut:
            return FailureCard(reason: reason, text: "That took too long and I stopped waiting. Nothing was changed.", canRetry: true)
        case .quota:
            return FailureCard(reason: reason, text: "This household has reached its assistant limit for now. Everything else in HeliPad still works.", canRetry: false)
        case .serviceError:
            return FailureCard(reason: reason, text: "The assistant service returned an error. Nothing was changed.", canRetry: true)
        case .invalidModelResponse:
            return FailureCard(reason: reason, text: "I couldn't make sense of that response, so I stopped rather than guess. Nothing was changed.", canRetry: true)
        case .toolRejected:
            return FailureCard(reason: reason, text: "That asked for something outside what I'm allowed to touch, so I stopped. Nothing was changed.", canRetry: false)
        case .roundLimit:
            return FailureCard(reason: reason, text: "I went back and forth too many times without landing on an answer, so I stopped. Try asking for one thing at a time.", canRetry: true)
        case .proposalExpired:
            return FailureCard(reason: reason, text: "This review is too old to apply. Ask again and I'll rebuild it against the current schedule.", canRetry: false)
        case .proposalStale:
            return FailureCard(reason: reason, text: "These events changed since the review was built, so I didn't overwrite the newer version. Ask again for a fresh review.", canRetry: false)
        case .saveFailed:
            return FailureCard(reason: reason, text: "The save didn't complete. Nothing was applied \u{2014} you can try again.", canRetry: true)
        }
    }

    // MARK: - Sync wording

    public static func syncLabel(_ state: MutationReceipt.SyncState) -> String {
        switch state {
        case .syncedToHousehold: return "Synced to your household"
        case .savedLocallySyncPending: return "Saved on this device \u{2014} sync pending"
        }
    }

    public static func externalCalendarLabel(exported: Bool) -> String {
        exported
            ? "Exported to your connected calendar"
            : "Saved in HeliPad only \u{2014} not sent to an external calendar"
    }

    // MARK: - Help

    public static func help(_ topic: HelpTopic) -> HelpCard {
        switch topic {
        case .recurringEvents:
            return HelpCard(topic: topic, title: "Repeating events", body: [
                "An event either does not repeat, or repeats weekly on the weekdays you choose.",
                "A weekly series is finite: it ends after a number of calendar weeks, or on a date you pick. 20 and 30 weeks are one tap.",
                "The series is stored as a rule, so deleting the last occurrence does not change when the series was meant to end."
            ])
        case .assigningCaregivers:
            return HelpCard(topic: topic, title: "Assigning a caregiver", body: [
                "Events with no caregiver show as needing a driver.",
                "You can assign one person to a whole set of events at once. I'll show you exactly which events before anything is saved."
            ])
        case .conflictsAndBuffer:
            return HelpCard(topic: topic, title: "Conflicts and the travel buffer", body: [
                "Two stops for the same caregiver clash when they overlap once the travel buffer is applied.",
                "The same child booked in two places at the same time is always a conflict.",
                "If dinner protection is on, events crossing the dinner hour are flagged.",
                "Conflicts are shown, never silently resolved."
            ])
        case .calendarConnections:
            return HelpCard(topic: topic, title: "Calendar connections", body: [
                "Anything I create is saved in HeliPad only.",
                "Sending an event to an external calendar is a separate, explicit step that you authorise."
            ])
        case .whatTheAssistantCanDo:
            return HelpCard(topic: topic, title: "What I can do", body: capabilities + [
                "I can't browse the web, run code, or answer questions outside this app."
            ])
        case .privacyAndData:
            return HelpCard(topic: topic, title: "What gets sent", body: [
                "To answer a question I send the parts of your household's schedule that the question needs: event titles, dates, times, saved place names, and household first names.",
                "Street addresses, coordinates and event notes are not sent.",
                "Requests are marked not to be stored by the provider for training or history. That is not the same as a guarantee of zero retention \u{2014} providers keep limited operational copies for abuse monitoring.",
                "Your chat history stays on this device and is cleared when you sign out or switch household."
            ])
        }
    }
}
