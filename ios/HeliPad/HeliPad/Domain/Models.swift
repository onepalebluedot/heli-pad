import Foundation

// MARK: - Task Kinds & Urgency

/// A record that takes part in two-phone merging.
public protocol StampedRecord: Codable {
    /// Stable identity within its own collection.
    var stampKey: String { get }
    var stamp: RecordStamp? { get set }
}

/// Orders two edits without trusting either phone's wall clock.
///
/// A Lamport counter: every local edit takes a number above anything the device
/// has seen, including stamps that arrived from the other phone. So a higher
/// counter means "this happened after, or at the same time as" — never "this
/// device's clock happens to be ahead". The device id only breaks exact ties, so
/// both phones resolve a simultaneous edit the same way.
public struct RecordStamp: Codable, Hashable, Comparable {
    public var counter: Int
    public var deviceID: String

    public init(counter: Int = 0, deviceID: String = "") {
        self.counter = counter
        self.deviceID = deviceID
    }

    public static func < (lhs: RecordStamp, rhs: RecordStamp) -> Bool {
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.deviceID < rhs.deviceID
    }
}

/// A record that was deleted, remembered on purpose.
///
/// Without this, deleting a stop on one phone is undone the moment the other
/// phone uploads a household that still contains it. The stamp says when the
/// delete happened relative to other edits; `deletedAt` exists only so old
/// tombstones can be swept up.
public struct Tombstone: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable, Hashable {
        case event, person, template, location
    }

    public var id: String
    public var kind: Kind
    public var stamp: RecordStamp
    public var deletedAt: Date

    public init(id: String, kind: Kind, stamp: RecordStamp, deletedAt: Date) {
        self.id = id
        self.kind = kind
        self.stamp = stamp
        self.deletedAt = deletedAt
    }

    /// Key that keeps ids from different collections apart.
    public var key: String { "\(kind.rawValue):\(id)" }
}

public enum TaskKind: String, Codable, CaseIterable, Hashable {
    case drive
    case cook
    case lead
    case placeholder
    case dropoff
    case pickup
    case practice
    case lesson
    case clinic
    case play
    case dinner
    case home
    case other
}

public extension TaskKind {
    /// The big-picture bucket a stop belongs to. Stats and templates group by
    /// this rather than by the raw kind, so "Drive" and "Pickup" both read as
    /// School rather than as two separate activities.
    var category: String {
        switch self {
        case .dropoff, .pickup: return "School"
        case .practice: return "Sports"
        case .lesson: return "Arts"
        case .play: return "Social"
        case .clinic: return "Health"
        case .dinner, .cook, .home: return "Family"
        case .drive, .lead, .placeholder, .other: return "Other"
        }
    }

    /// Display order for the category vocabulary, used by pickers and legends.
    static var categories: [String] {
        ["School", "Sports", "Arts", "Social", "Family", "Health", "Other"]
    }
}

public enum UrgencyTone: String, Codable, Hashable {
    case later
    case ontrack
    case soon
    case now
    case started
    case late
    case driverNeeded
    case clear
}

// MARK: - Finite recurrence

public enum RecurrenceMode: String, Codable, CaseIterable, Hashable {
    case none
    case weekly
}

public enum RecurrenceEditScope: String, CaseIterable, Identifiable, Hashable {
    case occurrence
    case series

    public var id: String { rawValue }
}

public enum RecurrenceEnd: Codable, Hashable {
    case weekCount(Int)
    case throughDate(String)
}

/// A value used by every recurrence entry point. Dates are calendar dates and
/// times remain wall-clock strings, so DST changes never shift a routine by an
/// hour or turn a selected weekday into another day.
public struct RecurrencePattern: Codable, Hashable {
    public var mode: RecurrenceMode
    public var startDate: String
    public var timeZone: String
    public var weekdays: [Int]
    public var end: RecurrenceEnd

    public init(
        mode: RecurrenceMode = .none,
        startDate: String,
        timeZone: String = "device",
        weekdays: [Int] = [],
        end: RecurrenceEnd = .weekCount(1)
    ) {
        self.mode = mode
        self.startDate = startDate
        self.timeZone = timeZone
        self.weekdays = weekdays
        self.end = end
    }
}

/// The independently mergeable definition of one finite materialized series.
/// `deleted` is intentionally durable; unlike ordinary row tombstones it is
/// never swept after 30 days and therefore cannot resurrect a long routine.
public struct SeriesDefinition: Identifiable, StampedRecord, Hashable {
    public var seriesId: String
    public var pattern: RecurrencePattern
    public var deleted: Bool
    public var stamp: RecordStamp? = nil

    public var id: String { seriesId }
    public var stampKey: String { seriesId }

    public init(seriesId: String, pattern: RecurrencePattern, deleted: Bool = false, stamp: RecordStamp? = nil) {
        self.seriesId = seriesId
        self.pattern = pattern
        self.deleted = deleted
        self.stamp = stamp
    }
}

public enum SeriesExceptionKind: String, Codable, Hashable {
    case excluded
    case modified
}

/// A durable decision about one original series slot. Exclusions prevent a
/// deleted occurrence from being regenerated; modifications bind a moved or
/// edited row to the slot it came from.
public struct SeriesException: Identifiable, StampedRecord, Hashable {
    public var seriesId: String
    public var originalDate: String
    public var kind: SeriesExceptionKind
    public var occurrenceId: String?
    public var stamp: RecordStamp? = nil

    public var id: String { "\(seriesId)|\(originalDate)" }
    public var stampKey: String { id }

    public init(
        seriesId: String,
        originalDate: String,
        kind: SeriesExceptionKind,
        occurrenceId: String? = nil,
        stamp: RecordStamp? = nil
    ) {
        self.seriesId = seriesId
        self.originalDate = originalDate
        self.kind = kind
        self.occurrenceId = occurrenceId
        self.stamp = stamp
    }
}

public struct OccurrenceOverride: Codable, Hashable {
    public var modified: Bool
    public var moved: Bool

    public init(modified: Bool = true, moved: Bool = false) {
        self.modified = modified
        self.moved = moved
    }
}

// MARK: - Person

public struct Person: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var relationship: String // Mother, Father, Grandmother, Child, Other
    public var kind: String         // "caregiver" | "child"
    public var color: String
    public var baseLocation: String?
    public var stamp: RecordStamp? = nil

    public var role: String { relationship }

    public init(id: String, name: String, relationship: String, kind: String, color: String = "#397cad", baseLocation: String? = nil) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.kind = kind
        self.color = color
        self.baseLocation = baseLocation
    }

    public init(id: String, name: String, role: String, monogram: String = "") {
        self.id = id
        self.name = name
        self.relationship = role
        self.kind = (role.lowercased() == "caregiver") ? "caregiver" : "child"
        self.color = "#397cad"
        self.baseLocation = "Home"
    }
}



// MARK: - Person inks

/// The household's own names against the inks assigned to them. The theme reads
/// it so that the many places holding only a name — a rail row, a chip, an
/// avatar — still draw a real family as distinct people. Kept current by
/// `AppStore.reconcile()`.
public enum PersonInks {
    private static var byName: [String: String] = [:]

    public static func register(_ people: [Person]) {
        var map: [String: String] = [:]
        for person in people { map[person.name] = person.color }
        byName = map
    }

    public static func hex(for name: String) -> String? {
        return byName[name]
    }
}

// MARK: - Location / Place

public struct LocationItem: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var address: String
    public var icon: String?
    public var routeKey: String?
    public var source: String?
    public var latitude: Double?
    public var longitude: Double?
    public var placeId: String?
    public var stamp: RecordStamp? = nil

    public init(
        name: String,
        address: String,
        icon: String? = nil,
        routeKey: String? = nil,
        source: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeId: String? = nil
    ) {
        self.name = name
        self.address = address
        self.icon = icon
        self.routeKey = routeKey
        self.source = source
        self.latitude = latitude
        self.longitude = longitude
        self.placeId = placeId
    }
}

// MARK: - Place Autocomplete Models

public struct PlacePrediction: Identifiable, Hashable {
    public var id: String { placeId }
    public var placeId: String
    public var primaryText: String
    public var secondaryText: String
    public var fullText: String
    public var latitude: Double?
    public var longitude: Double?

    public init(
        placeId: String,
        primaryText: String,
        secondaryText: String,
        fullText: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.placeId = placeId
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.fullText = fullText
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct PlaceDetail: Hashable {
    public var name: String
    public var formattedAddress: String
    public var latitude: Double
    public var longitude: Double
    public var placeId: String

    public init(name: String, formattedAddress: String, latitude: Double, longitude: Double, placeId: String) {
        self.name = name
        self.formattedAddress = formattedAddress
        self.latitude = latitude
        self.longitude = longitude
        self.placeId = placeId
    }
}

// MARK: - Task Record (The universal event / handoff representation)

public struct TaskRecord: Identifiable, Codable, Hashable {
    public var id: String
    public var date: String           // "YYYY-MM-DD"
    public var time: String           // "HH:mm"
    public var endTime: String        // "HH:mm"
    public var title: String
    public var owner: String          // "Mom", "Dad", "Nani", "Grandma", "Family", "TBD"
    public var lead: String?
    public var kids: [String]
    public var kid: String?
    public var location: String
    public var mode: String           // "Drive", "Walk", "Carpool", "School Bus", "Home"
    public var kind: TaskKind
    public var done: Bool
    public var tentative: Bool
    public var locked: Bool
    public var gcal: Bool
    public var notes: String
    public var allDay: Bool
    public var bufferMinutes: Int?
    public var color: String?
    public var seriesId: String?
    /// The calendar slot this row represents, even if the occurrence is moved.
    public var originalOccurrenceDate: String?
    public var recurrenceOverride: OccurrenceOverride?
    public var calendarId: String?
    public var locationMissing: Bool?
    public var latitude: Double?
    public var longitude: Double?
    public var formattedAddress: String?
    /// Set on save when this record's content actually changed.
    public var stamp: RecordStamp? = nil

    public init(
        id: String,
        date: String = PlanCore.BASE_WEEK,
        time: String = "16:00",
        endTime: String = "17:00",
        title: String = "Event",
        owner: String = "TBD",
        lead: String? = nil,
        kids: [String] = [],
        kid: String? = nil,
        location: String = "Home",
        mode: String = "Drive",
        kind: TaskKind = .drive,
        done: Bool = false,
        tentative: Bool = false,
        locked: Bool = false,
        gcal: Bool = false,
        notes: String = "",
        allDay: Bool = false,
        bufferMinutes: Int? = nil,
        color: String? = nil,
        seriesId: String? = nil,
        originalOccurrenceDate: String? = nil,
        recurrenceOverride: OccurrenceOverride? = nil,
        calendarId: String? = nil,
        locationMissing: Bool? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        formattedAddress: String? = nil
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.endTime = endTime
        self.title = title
        self.owner = owner
        self.lead = lead ?? owner
        self.kids = kids
        self.kid = kid ?? kids.joined(separator: ", ")
        self.location = location
        self.mode = mode
        self.kind = kind
        self.done = done
        self.tentative = tentative
        self.locked = locked
        self.gcal = gcal
        self.notes = notes
        self.allDay = allDay
        self.bufferMinutes = bufferMinutes
        self.color = color
        self.seriesId = seriesId
        self.originalOccurrenceDate = originalOccurrenceDate
        self.recurrenceOverride = recurrenceOverride
        self.calendarId = calendarId
        self.locationMissing = locationMissing
        self.latitude = latitude
        self.longitude = longitude
        self.formattedAddress = formattedAddress
    }
}

// MARK: - Template Item

public struct TemplateItem: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var time: String
    public var endTime: String
    public var kids: [String]
    public var kid: String
    public var owner: String
    public var location: String
    public var mode: String
    public var duration: Int
    public var notes: String?
    public var category: String?
    /// Weekdays this shortcut normally lands on, 0 = Monday. Optional so a
    /// household saved before shortcuts had days still decodes.
    public var weekdays: [Int]?
    /// Relative finite duration for newly scheduled copies. Nil keeps legacy
    /// shortcuts bounded to the single displayed week until someone changes it.
    public var recurrenceWeekCount: Int?
    public var stamp: RecordStamp? = nil

    public init(
        id: String,
        title: String,
        time: String,
        endTime: String,
        kids: [String] = [],
        kid: String = "",
        owner: String = "TBD",
        location: String = "Home",
        mode: String = "Drive",
        duration: Int = 60,
        notes: String? = nil,
        category: String? = nil,
        weekdays: [Int]? = nil,
        recurrenceWeekCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.time = time
        self.endTime = endTime
        self.kids = kids
        self.kid = kid.isEmpty ? kids.joined(separator: ", ") : kid
        self.owner = owner
        self.location = location
        self.mode = mode
        self.duration = duration
        self.notes = notes
        self.category = category
        self.weekdays = weekdays
        self.recurrenceWeekCount = recurrenceWeekCount
    }

    /// Days this shortcut repeats on, cleaned and ordered Monday-first.
    public var repeatDays: Set<Int> {
        Set((weekdays ?? []).filter { (0...6).contains($0) })
    }
}

// MARK: - Planning & Risk Types

public struct CandidateDetail: Hashable, Codable {
    public var name: String
    public var origin: String
    public var eta: Int?
    public var leave: Int
    public var slack: Int?
    public var onwardSlack: Int?
    public var unknown: Bool
    public var conflict: Bool
    public var reason: String

    public init(
        name: String,
        origin: String,
        eta: Int?,
        leave: Int,
        slack: Int?,
        onwardSlack: Int?,
        unknown: Bool,
        conflict: Bool,
        reason: String
    ) {
        self.name = name
        self.origin = origin
        self.eta = eta
        self.leave = leave
        self.slack = slack
        self.onwardSlack = onwardSlack
        self.unknown = unknown
        self.conflict = conflict
        self.reason = reason
    }
}

public struct Risk: Hashable, Codable {
    public var type: String // "driver", "overlap", "tight", "place", "route", "long", "dinner", "tentative"
    public var label: String

    public init(type: String, label: String) {
        self.type = type
        self.label = label
    }
}

public struct AnalyzedEvent: Identifiable, Hashable {
    public var event: TaskRecord
    public var detail: CandidateDetail
    public var risks: [Risk]
    public var status: String // "ready", "missing", "review"

    public var id: String { event.id }

    public init(event: TaskRecord, detail: CandidateDetail, risks: [Risk], status: String) {
        self.event = event
        self.detail = detail
        self.risks = risks
        self.status = status
    }
}

public struct SummaryResult {
    public var list: [AnalyzedEvent]
    public var total: Int
    public var ready: Int
    public var missing: Int
    public var review: Int

    public init(list: [AnalyzedEvent] = [], total: Int = 0, ready: Int = 0, missing: Int = 0, review: Int = 0) {
        self.list = list
        self.total = total
        self.ready = ready
        self.missing = missing
        self.review = review
    }
}

public struct RebalanceProposal: Identifiable, Hashable, Codable {
    public var id: String
    public var date: String
    public var title: String
    public var time: String
    public var from: String
    public var to: String
    public var eta: Int?
    public var saving: Int
    public var reason: String

    public init(id: String, date: String, title: String, time: String, from: String, to: String, eta: Int?, saving: Int, reason: String) {
        self.id = id
        self.date = date
        self.title = title
        self.time = time
        self.from = from
        self.to = to
        self.eta = eta
        self.saving = saving
        self.reason = reason
    }
}

public struct ProposalsResult {
    public var changes: [RebalanceProposal]
    public var before: [String: Int]
    public var after: [String: Int]
    public var events: [TaskRecord]

    public init(changes: [RebalanceProposal], before: [String: Int], after: [String: Int], events: [TaskRecord]) {
        self.changes = changes
        self.before = before
        self.after = after
        self.events = events
    }
}

// MARK: - Week Priorities & Calendar Meta

public struct WeekPriority: Codable, Hashable {
    public var enabled: Bool
    public var days: [Int] // 0..6 (Mon..Sun)
    public var time: String // e.g. "18:30"
    public var goal: String?
    public var meals: [String]?

    public init(enabled: Bool = true, days: [Int] = [0, 1, 2, 3, 4, 5, 6], time: String = "18:30", goal: String? = nil, meals: [String]? = nil) {
        self.enabled = enabled
        self.days = days
        self.time = time
        self.goal = goal
        self.meals = meals
    }
}

public struct CalendarMetadata: Codable, Hashable {
    public var exports: [String: String] // id -> signature
    public var pulled: [String]
    public var lastReview: String?
    public var appleCalendarIDs: [String]? = nil
    public var lastAppleImport: Date? = nil
    public var googleCalendarIDs: [String]? = nil
    public var lastGoogleImport: Date? = nil
    public var googleExportCalendarID: String? = nil

    public init(
        exports: [String: String] = [:],
        pulled: [String] = [],
        lastReview: String? = nil,
        appleCalendarIDs: [String]? = nil,
        lastAppleImport: Date? = nil,
        googleCalendarIDs: [String]? = nil,
        lastGoogleImport: Date? = nil,
        googleExportCalendarID: String? = nil
    ) {
        self.exports = exports
        self.pulled = pulled
        self.lastReview = lastReview
        self.appleCalendarIDs = appleCalendarIDs
        self.lastAppleImport = lastAppleImport
        self.googleCalendarIDs = googleCalendarIDs
        self.lastGoogleImport = lastGoogleImport
        self.googleExportCalendarID = googleExportCalendarID
    }
}

public struct PlanMetadata: Codable, Hashable {
    public var future: [TaskRecord]
    public var priorities: [String: WeekPriority]
    public var reviewed: [String: String] // week -> fingerprint
    public var calendar: CalendarMetadata
    /// Notes belong to the week being planned, rather than to every future week.
    /// Optional keeps snapshots written before weekly notes were introduced
    /// backward compatible with synthesized Codable decoding.
    public var weeklyNotes: [String: String]? = nil
    /// Deletes that must outlive the record, so the other phone cannot
    /// resurrect them. Swept once they are older than the retention horizon.
    public var tombstones: [Tombstone]? = nil
    public var seriesDefinitions: [SeriesDefinition]? = nil
    public var seriesExceptions: [SeriesException]? = nil

    public init(
        future: [TaskRecord] = [],
        priorities: [String: WeekPriority] = [:],
        reviewed: [String: String] = [:],
        calendar: CalendarMetadata = CalendarMetadata(),
        weeklyNotes: [String: String]? = nil,
        tombstones: [Tombstone]? = nil,
        seriesDefinitions: [SeriesDefinition]? = nil,
        seriesExceptions: [SeriesException]? = nil
    ) {
        self.future = future
        self.priorities = priorities
        self.reviewed = reviewed
        self.calendar = calendar
        self.weeklyNotes = weeklyNotes
        self.tombstones = tombstones
        self.seriesDefinitions = seriesDefinitions
        self.seriesExceptions = seriesExceptions
    }
}

// MARK: - Active Viewer & Legacy Bridges

public struct Place: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var kind: String

    public init(id: String, name: String, kind: String) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct TravelFacet: Hashable {
    public var originId: String
    public var destinationId: String
    public var mode: String

    public init(originId: String, destinationId: String, mode: String) {
        self.originId = originId
        self.destinationId = destinationId
        self.mode = mode
    }
}

public struct TripPlan: Hashable {
    public var departBy: Date
    public var travelMinutes: Int
    public var arriveBy: Date
    public var tone: UrgencyTone
    public var leaveInMinutes: Int

    public init(departBy: Date, travelMinutes: Int, arriveBy: Date, tone: UrgencyTone, leaveInMinutes: Int) {
        self.departBy = departBy
        self.travelMinutes = travelMinutes
        self.arriveBy = arriveBy
        self.tone = tone
        self.leaveInMinutes = leaveInMinutes
    }
}

public struct TaskItem: Identifiable, Hashable {
    public let id: String
    public var kind: TaskKind
    public var title: String
    public var start: Date
    public var end: Date?
    public var children: [String]
    public var assigneeId: String?
    public var backupId: String?
    public var isDone: Bool
    public var bufferMinutes: Int
    public var group: String // go | dinner | home
    public var stamp: String?
    public var travel: TravelFacet?

    public init(
        id: String,
        kind: TaskKind,
        title: String,
        start: Date,
        end: Date? = nil,
        children: [String] = [],
        assigneeId: String? = nil,
        backupId: String? = nil,
        isDone: Bool = false,
        bufferMinutes: Int = 10,
        group: String = "go",
        stamp: String? = nil,
        travel: TravelFacet? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.children = children
        self.assigneeId = assigneeId
        self.backupId = backupId
        self.isDone = isDone
        self.bufferMinutes = bufferMinutes
        self.group = group
        self.stamp = stamp
        self.travel = travel
    }
}

public struct ActiveViewer: Hashable {
    public var caregiverId: String
    public var isLabSwitchable: Bool

    public init(caregiverId: String = "Mom", isLabSwitchable: Bool = true) {
        self.caregiverId = caregiverId
        self.isLabSwitchable = isLabSwitchable
    }
}

public struct DayAgenda {
    public var viewer: ActiveViewer
    public var tasks: [TaskItem]
    public var people: [Person]
    public var places: [Place]

    public init(viewer: ActiveViewer, tasks: [TaskItem], people: [Person], places: [Place]) {
        self.viewer = viewer
        self.tasks = tasks
        self.people = people
        self.places = places
    }
}



// MARK: - Merge participation

extension TaskRecord: StampedRecord {
    public var stampKey: String { id }
}

extension Person: StampedRecord {
    public var stampKey: String { id }
}

extension TemplateItem: StampedRecord {
    public var stampKey: String { id }
}

extension LocationItem: StampedRecord {
    /// A place is identified by its name, so renaming one reads as a delete plus
    /// an add rather than an edit.
    public var stampKey: String { name }
}
