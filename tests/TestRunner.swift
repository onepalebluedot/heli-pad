import Foundation
import CoreLocation

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    if a != b {
        print("❌ Assertion Failed: [\(a)] != [\(b)]. \(msg) (\(file):\(line))")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        print("❌ Assertion Failed: Expected true, got false. \(msg) (\(file):\(line))")
        exit(1)
    }
}

func assertThrows(_ block: () throws -> Void, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    do {
        try block()
        print("❌ Assertion Failed: Expected throw, but succeeded. \(msg) (\(file):\(line))")
        exit(1)
    } catch {
        // success
    }
}

@main
struct TestRunner {
    static func main() async throws {
        print("🧪 Running HeliPad Domain Test Suite...")

        // =========================================================================
        // 1. PlanCore Tests (matching tests/plan-core.test.cjs)
        // =========================================================================
        print("  ▶ Running PlanCore tests...")

        let options = PlanningOptions(
            crew: ["Mom", "Dad", "Nani", "Grandma"],
            home: "Home",
            origins: ["Mom": "Home", "Dad": "Home", "Nani": "Home", "Grandma": "Home"],
            buffer: 12,
            routes: [
                "Home": ["School": 15, "Field": 20],
                "School": ["Home": 15, "Field": 10],
                "Field": ["Home": 20, "School": 10]
            ]
        )

        func makeTestEvent(
            id: String = "1",
            date: String = PlanCore.BASE_WEEK,
            title: String = "Pickup",
            time: String = "15:00",
            endTime: String = "15:30",
            location: String = "School",
            owner: String = "Mom",
            mode: String = "Drive",
            kids: [String] = ["Soni"],
            kind: TaskKind = .drive,
            done: Bool = false,
            tentative: Bool = false,
            locked: Bool = false
        ) -> TaskRecord {
            return TaskRecord(
                id: id,
                date: date,
                time: time,
                endTime: endTime,
                title: title,
                owner: owner,
                kids: kids,
                location: location,
                mode: mode,
                kind: kind,
                done: done,
                tentative: tentative,
                locked: locked
            )
        }

        // Test 1: Readiness summary
        do {
            let e1 = makeTestEvent()
            let e2 = makeTestEvent(id: "2", date: "2026-08-04", owner: "TBD")
            let e3 = makeTestEvent(id: "3", date: "2026-08-05", tentative: true)
            let summary = PlanCore.summary([e1, e2, e3], options)
            assertEqual(summary.ready, 1, "Ready count")
            assertEqual(summary.missing, 1, "Missing count")
            assertEqual(summary.review, 1, "Review count")
            assertEqual(summary.total, 3, "Total count")
        }

        // Test 2: Next journey candidate rejection
        do {
            let a = makeTestEvent()
            let b = makeTestEvent(id: "2", title: "Practice", time: "15:35", endTime: "16:30", location: "Field")
            let c = PlanCore.candidate(a, "Mom", [a, b], options)
            assertEqual(c.conflict, true, "Candidate should conflict due to onward journey")
            assertEqual(c.onwardSlack, -17, "Onward slack should be -17")
            assertEqual(PlanCore.candidate(a, "Dad", [a, b], options).conflict, false, "Dad should not conflict")
        }

        // Test 3: Zero buffer and tight window
        do {
            let a = makeTestEvent(time: "14:00", endTime: "14:30")
            let b = makeTestEvent(id: "2", time: "14:45", endTime: "15:30", location: "Field")
            var opt0 = options
            opt0.buffer = 0
            let c = PlanCore.candidate(b, "Mom", [a, b], opt0)
            assertEqual(c.slack, 5, "Slack should be 5")
            assertEqual(c.conflict, false, "Conflict should be false")
            let analysis = PlanCore.analyze([a, b], opt0)
            assertEqual(analysis[1].risks.first?.type, "tight", "Risk type should be tight")
        }

        // Test 4: Unknown routes
        do {
            let e = makeTestEvent(location: "Unknown place")
            let r = PlanCore.analyze([e], options)[0]
            assertEqual(r.detail.eta, nil, "ETA should be nil")
            assertEqual(r.status, "review", "Status should be review")
            assertEqual(PlanCore.proposals([e], options).changes.count, 0, "No changes proposed for unknown route")
        }

        // Test 5: Non-travel tasks
        do {
            let e = makeTestEvent(location: "Home", mode: "Home", kind: .cook)
            assertEqual(PlanCore.analyze([e], options)[0].event.owner, "Mom", "Owner retained")
            assertEqual(PlanCore.loads([e], options)["Mom"], 0, "No driving minutes for non-travel")
        }

        // Test 6: Rebalance proposals
        do {
            let all = [
                makeTestEvent(owner: "TBD"),
                makeTestEvent(id: "2", date: "2026-08-04", locked: true),
                makeTestEvent(id: "3", date: "2026-08-05", tentative: true),
                makeTestEvent(id: "4", date: "2026-08-06", done: true)
            ]
            let p = PlanCore.proposals(all, options)
            assertEqual(p.changes.count, 1, "Only 1 change")
            assertEqual(p.changes[0].id, "1", "Change target is event 1")
            let overlapCount = PlanCore.analyze(p.events, options).filter { $0.risks.contains { $0.type == "overlap" } }.count
            assertEqual(overlapCount, 0, "No overlaps introduced")
            assertEqual(all[0].owner, "TBD", "Original untouched")
        }

        // Test 7: Recurrence
        do {
            let r = try PlanCore.occurrences(makeTestEvent(date: "2026-12-28"), repeatMode: "weekly", count: 3)
            assertEqual(r.map { $0.date }, ["2026-12-28", "2027-01-04", "2027-01-11"], "Recurrence dates across new year")
            assertEqual(PlanCore.monday("2027-01-03"), "2026-12-28", "Monday calculation")
            assertEqual(PlanCore.daysBetween(PlanCore.BASE_WEEK, "2026-08-10"), 7, "Days between")
            assertThrows { _ = try PlanCore.occurrences(makeTestEvent(), repeatMode: "weekly", count: 53) }
            assertThrows { _ = try PlanCore.occurrences(makeTestEvent(time: "15:00", endTime: "14:00")) }
        }

        // Test 8: Calendar pull
        do {
            var existing = makeTestEvent(title: "Pickup", owner: "Dad", done: true)
            existing.calendarId = "g:1"
            existing.notes = "Private note"
            existing.bufferMinutes = 9

            var update = existing
            update.title = "Changed pickup"
            update.owner = "TBD"
            update.done = false
            update.notes = ""

            let pulled = PlanCore.pull([existing], [update])
            assertEqual(pulled[0].title, "Changed pickup", "Updated schedule title")
            assertEqual(pulled[0].owner, "Dad", "Preserved overlay owner")
            assertEqual(pulled[0].done, true, "Preserved overlay done")
            assertEqual(pulled[0].notes, "Private note", "Preserved overlay notes")
            assertEqual(PlanCore.pull(pulled, [update]).count, 1, "Idempotent pull")
        }

        // Test 9: Dinner goals
        do {
            let e = makeTestEvent(time: "18:40", endTime: "19:30")
            var pOpt = options
            pOpt.priorities = [PlanCore.BASE_WEEK: WeekPriority(enabled: true, days: [0], time: "18:30")]
            let r1 = PlanCore.analyze([e], pOpt)
            assertTrue(r1[0].risks.contains { $0.type == "dinner" }, "Crosses dinner")
            let e2 = makeTestEvent(date: "2026-08-04", time: "18:40", endTime: "19:30")
            let r2 = PlanCore.analyze([e2], pOpt)
            assertTrue(!r2[0].risks.contains { $0.type == "dinner" }, "Not on dinner day")
        }

        // Test 10: Multi-day recurrence
        do {
            let batch = try PlanCore.occurrences(
                makeTestEvent(date: "2026-12-30"),
                repeatMode: "weekly",
                count: 2,
                weekdays: [4, 0, 2, 2]
            )
            assertEqual(batch.map { $0.date }, ["2026-12-30", "2027-01-01", "2027-01-04", "2027-01-06", "2027-01-08"], "Multi-day recurrence")
            assertTrue(batch.allSatisfy { $0.title == "Pickup" && $0.owner == "Mom" })
        }

        print("  ✅ PlanCore tests passed.")

        // =========================================================================
        // 2. FamilyCore Tests (matching tests/family-core.test.cjs)
        // =========================================================================
        print("  ▶ Running FamilyCore tests...")

        do {
            let tpl = TemplateItem(id: "tpl_1", title: "School Drop-off", time: "07:35", endTime: "08:05", kids: ["Soni"], kid: "Soni", owner: "Dad", location: "School", mode: "Drive", duration: 30)
            let norm = FamilyCore.normalize(tpl)
            assertEqual(norm.time, "07:35")
            assertEqual(norm.endTime, "08:05")
            assertEqual(norm.kids, ["Soni"])

            let validated = try FamilyCore.validate(tpl)
            assertEqual(validated.title, "School Drop-off")

            let sig = FamilyCore.signature(tpl)
            assertTrue(!sig.isEmpty, "Signature generated")

            // Suggestions from repeated events
            let ev1 = makeTestEvent(id: "1", date: "2026-08-03", title: "Practice", time: "16:00", endTime: "17:00", location: "Field", owner: "Dad", kids: ["Noah"])
            let ev2 = makeTestEvent(id: "2", date: "2026-08-05", title: "Practice", time: "16:00", endTime: "17:00", location: "Field", owner: "Dad", kids: ["Noah"])
            let suggestions = FamilyCore.suggestions(events: [ev1, ev2], templates: [])
            assertEqual(suggestions.count, 1, "1 suggestion found")
            assertEqual(suggestions[0].draft.title, "Practice")
            assertEqual(suggestions[0].count, 2)
        }

        print("  ✅ FamilyCore tests passed.")

        // =========================================================================
        // 3. AppStore Tests (matching tests/app-store.test.cjs)
        // =========================================================================
        print("  ▶ Running AppStore tests...")

        func makeAppFixture() -> AppStore {
            let people = [
                Person(id: "a", name: "Alex", relationship: "Father", kind: "caregiver", color: "#123456"),
                Person(id: "b", name: "Jo", relationship: "Other", kind: "caregiver"),
                Person(id: "c", name: "Sam", relationship: "Child", kind: "child")
            ]
            let locs = [
                LocationItem(name: "Home", address: "1 Main"),
                LocationItem(name: "Work", address: "2 Main"),
                LocationItem(name: "School", address: "3 Main")
            ]
            let e1 = TaskRecord(id: "1", date: "2026-08-03", time: "16:00", endTime: "17:00", title: "Practice", owner: "Alex", lead: "Alex", kids: ["Sam"], kid: "Sam", location: "School", mode: "Drive", tentative: true, locked: true)
            let e2 = TaskRecord(id: "2", date: "2026-08-10", time: "16:00", endTime: "17:00", title: "Practice", owner: "Alex", lead: "Alex", kids: ["Sam"], kid: "Sam", location: "School", mode: "Drive", tentative: true, locked: true)
            let tpl = TemplateItem(id: "tpl", title: "Practice", time: "16:00", endTime: "17:00", kids: ["Sam"], kid: "Sam", owner: "Alex", location: "School", mode: "Drive", duration: 60)
            let draft = TaskRecord(id: "draft", date: "2026-08-03", time: "16:00", endTime: "17:00", title: "Practice", owner: "Alex", lead: "Alex", kids: ["Sam"], kid: "Sam", location: "School", mode: "Drive", tentative: true, locked: true)

            var plan = PlanMetadata()
            plan.future = [e2]
            plan.calendar.exports = ["1": "sig", "2": "sig", "ghost": "sig"]

            let store = AppStore(
                people: people,
                locations: locs,
                eventsByDay: [0: [e1]],
                plan: plan,
                templates: [tpl],
                parentLocations: ["Alex": "Work", "Jo": "Home"],
                homeAddress: "1 Main",
                homePlaceName: "Home",
                buffer: 12,
                trafficMode: false,
                dinnerProtection: false,
                currentUser: "Alex",
                routes: [
                    "Home": ["School": 20, "Work": 10],
                    "Work": ["School": 10, "Home": 10],
                    "School": ["Home": 20, "Work": 10]
                ],
                defaultLocations: locs
            )
            store.goCrewFilter = "Alex"
            store.goKidFilter = "Sam"
            store.goDraft = draft
            return store
        }

        // Test AppStore: Removing caregiver
        do {
            let app = makeAppFixture()
            var registeredDraft = app.templates[0]
            app.registerDraft {
                TaskRecord(id: "dyn", title: "Draft", owner: registeredDraft.owner, kids: registeredDraft.kids)
            }
            app.removePerson(id: "a")

            assertEqual(app.caregivers(), ["Jo"], "Only Jo left")
            for e in app.records() {
                assertEqual(e.owner, "TBD")
                assertEqual(e.lead, "TBD")
                assertEqual(e.locked, false)
                assertEqual(e.tentative, false)
            }
            assertEqual(app.templates[0].owner, "TBD")
            assertEqual(app.goDraft?.owner, "TBD")
            assertEqual(app.currentUser, "All")
            assertEqual(app.goCrewFilter, nil)
            assertEqual(app.parentLocations["Alex"], nil)
            assertEqual(app.plan.future[0].owner, "TBD")
        }

        // Test AppStore: Rename person cascades
        do {
            let app = makeAppFixture()
            try app.renamePerson(id: "a", value: "Alex O'Neill")
            assertEqual(app.people[0].id, "a")
            assertEqual(app.currentUser, "Alex O'Neill")
            assertEqual(app.parentLocations["Alex O'Neill"], "Work")
            for e in app.records() {
                assertEqual(e.owner, "Alex O'Neill")
            }
            assertEqual(app.templates[0].owner, "Alex O'Neill")
            assertEqual(app.goDraft?.owner, "Alex O'Neill")

            try app.renamePerson(id: "c", value: "Casey")
            for e in app.records() {
                assertEqual(e.kids, ["Casey"])
            }
            assertEqual(app.templates[0].kids, ["Casey"])
            assertEqual(app.goDraft?.kids, ["Casey"])

            assertThrows { try app.renamePerson(id: "a", value: "jo") }
            assertThrows { try app.renamePerson(id: "a", value: "All") }
        }

        // Test AppStore: Removing only child
        do {
            let app = makeAppFixture()
            app.removePerson(id: "c")
            for e in app.records() {
                assertEqual(e.kids, [])
                assertEqual(e.kid, "")
            }
            assertEqual(app.templates[0].kids, [])
            assertEqual(app.goDraft?.kids, [])
            assertEqual(app.goKidFilter, "all")
        }

        // Test AppStore: Role change
        do {
            let app = makeAppFixture()
            app.setPersonRole(id: "a", relationship: "Child")
            assertEqual(app.records()[0].owner, "TBD")
            assertTrue(!app.caregivers().contains("Alex"))
            assertTrue(app.children().contains("Alex"))

            app.setPersonRole(id: "c", relationship: "Other")
            assertEqual(app.records()[0].kids, [])
            assertEqual(app.parentLocations["Sam"], "Home")

            let p = app.addPerson(kind: "caregiver")
            assertTrue(app.caregivers().contains(p.name))
            assertEqual(app.parentLocations[p.name], "Home")
        }

        // Test AppStore: Place rename & move
        do {
            let app = makeAppFixture()
            try app.updateLocation(index: 2, data: LocationItem(name: "New School", address: "3 Main"))
            for e in app.records() {
                assertEqual(e.location, "New School")
            }
            assertEqual(app.travel(origin: "Work", destination: "New School", at: 960), 10)

            try app.updateLocation(index: 2, data: LocationItem(name: "New School", address: "99 Elsewhere"))
            assertEqual(app.travel(origin: "Work", destination: "New School", at: 960), nil)

            assertThrows { try app.removeLocation(index: 2) } // used by event
            assertThrows { try app.removeLocation(index: 0) } // home
        }

        // Test AppStore: Home address & bases
        do {
            let app = makeAppFixture()
            try app.setHomeAddress("9 New Street")
            assertEqual(app.homeAddress, "9 New Street")
            assertEqual(app.locations[0].address, "9 New Street")
            assertEqual(app.travel(origin: "Home", destination: "School", at: 480), nil)

            try app.setBases(["Alex": "School", "Jo": "Work"])
            let cand = PlanCore.candidate(app.records()[0], "Alex", app.records(), app.planningOptions())
            assertEqual(cand.eta, 0)
            assertThrows { try app.setBases(["Deleted": "Work"]) }
        }

        // Test AppStore: Settings (buffer, traffic, dinner)
        do {
            let app = makeAppFixture()
            try app.setSetting(key: "buffer", value: 0)
            var calc = PlanCore.analyze(app.records(), app.planningOptions())[0]
            assertEqual(calc.detail.leave, 950)

            try app.setSetting(key: "trafficMode", value: true)
            calc = PlanCore.analyze(app.records(), app.planningOptions())[0]
            assertEqual(calc.detail.eta, 12)
            assertEqual(calc.detail.leave, 948)

            try app.setSetting(key: "buffer", value: 45)
            calc = PlanCore.analyze(app.records(), app.planningOptions())[0]
            assertEqual(calc.detail.leave, 903)
            assertThrows { try app.setSetting(key: "buffer", value: 46) }

            app.plan.future = [TaskRecord(id: "8", date: "2026-08-10", time: "18:00", endTime: "19:00", title: "Practice", location: "Home", mode: "Home")]
            try app.setSetting(key: "dinnerProtection", value: true)
            assertTrue(PlanCore.analyze(app.plan.future, app.planningOptions())[0].risks.contains { $0.type == "dinner" })
            try app.setSetting(key: "dinnerProtection", value: false)
            assertTrue(!PlanCore.analyze(app.plan.future, app.planningOptions())[0].risks.contains { $0.type == "dinner" })
        }

        // Test AppStore: Reset schedule & time zone
        do {
            let app = makeAppFixture()
            assertEqual(app.plan.calendar.exports["ghost"], nil, "Orphan export cleaned up")
            app.resetSchedule(seed: [0: []])
            assertEqual(app.records().count, 0)
            assertEqual(app.plan.reviewed.count, 0)
            assertEqual(app.plan.calendar.exports.count, 0)

            try app.setSetting(key: "timeZone", value: "America/Detroit")
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let testDate = cal.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12, minute: 0, second: 0))!
            assertEqual(app.clock(now: testDate).minutes, 480) // 8:00 AM EDT (UTC-4) -> 8*60 = 480

            try app.setSetting(key: "timeZone", value: "America/Los_Angeles")
            assertEqual(app.clock(now: testDate).minutes, 300) // 5:00 AM PDT (UTC-7) -> 5*60 = 300
            assertThrows { try app.setSetting(key: "timeZone", value: "Invalid/Zone") }
        }

        print("  ✅ AppStore tests passed.")

        // =========================================================================
        // 3.5. Review Dismissal & Family Driver Tests
        // =========================================================================
        print("  ▶ Running Review Dismissal & Family Driver tests...")
        do {
            let app = makeAppFixture()
            let vm = PlanViewModel()

            // Setup events: e1 ready (Alex), e2 tentative review (Jo), e3 missing (TBD)
            let e1 = TaskRecord(id: "ev-1", date: PlanCore.BASE_WEEK, time: "09:00", endTime: "10:00", title: "School", owner: "Alex", kids: ["Sam"], location: "School", mode: "Drive")
            let e2 = TaskRecord(id: "ev-2", date: PlanCore.BASE_WEEK, time: "11:00", endTime: "12:00", title: "Dentist", owner: "Jo", kids: ["Sam"], location: "Work", mode: "Drive", tentative: true)
            let e3 = TaskRecord(id: "ev-3", date: PlanCore.BASE_WEEK, time: "14:00", endTime: "15:00", title: "Soccer", owner: "TBD", kids: ["Sam"], location: "Home", mode: "Drive")

            app.replaceRecords([e1, e2, e3])

            // Initial state: missing=1, review=1, ready=1
            var summ = vm.summary(store: app)
            assertEqual(summ.missing, 1, "Initial missing count")
            assertEqual(summ.review, 1, "Initial review count")
            assertEqual(summ.ready, 1, "Initial ready count")

            var queue = vm.decisionQueue(store: app)
            assertEqual(queue.count, 2, "Decision queue has missing and review")
            assertTrue(queue.contains(where: { $0.id == "ev-2" }), "Queue contains review item")

            // Dismiss the review on ev-2
            app.dismissReview(for: "ev-2")
            assertTrue(app.isReviewDismissed(eventId: "ev-2"), "ev-2 is marked dismissed")

            summ = vm.summary(store: app)
            assertEqual(summ.missing, 1, "Missing count remains 1")
            assertEqual(summ.review, 0, "Review count drops to 0 after dismissal")
            assertEqual(summ.ready, 2, "Ready count increments to 2")

            queue = vm.decisionQueue(store: app)
            assertEqual(queue.count, 1, "Decision queue now only has missing item")
            assertTrue(!queue.contains(where: { $0.id == "ev-2" }), "ev-2 is excluded from queue")

            // Restore the review on ev-2
            app.restoreReview(for: "ev-2")
            assertTrue(!app.isReviewDismissed(eventId: "ev-2"), "ev-2 is no longer dismissed")
            summ = vm.summary(store: app)
            assertEqual(summ.review, 1, "Review count restored to 1")

            // Dismiss all reviews
            app.dismissAllReviews(for: ["ev-2"])
            assertTrue(app.isReviewDismissed(eventId: "ev-2"), "ev-2 is dismissed via dismissAllReviews")

            // Test Family driver assignment
            let eFamily = TaskRecord(id: "ev-fam", date: PlanCore.BASE_WEEK, time: "16:00", endTime: "17:00", title: "Dinner Out", owner: "Family", kids: ["Sam"], location: "Home", mode: "Drive")
            app.replaceRecords([eFamily])
            let famSummary = PlanCore.summary([eFamily], app.planningOptions())
            assertEqual(famSummary.missing, 0, "Family owner is NOT considered missing")
            assertEqual(famSummary.ready, 1, "Family owner is considered ready")

            // Test dayStatus with dismissed review
            let eReviewDay = TaskRecord(id: "ev-rev", date: "2026-08-04", time: "10:00", endTime: "11:00", title: "Doctor", owner: "Alex", kids: ["Sam"], location: "Work", mode: "Drive", tentative: true)
            app.replaceRecords([eReviewDay])
            assertEqual(vm.dayStatus(date: "2026-08-04", store: app), "review", "Day status is review prior to dismissal")
            app.dismissReview(for: "ev-rev")
            assertEqual(vm.dayStatus(date: "2026-08-04", store: app), "ready", "Day status flips to ready once review is dismissed")
        }
        print("  ✅ Review Dismissal & Family Driver tests passed.")

        // =========================================================================
        // 4. TimeFormat Tests
        // =========================================================================
        print("  ▶ Running TimeFormat tests...")
        assertEqual(TimeFormat.formatDuration(0), "0 min")
        assertEqual(TimeFormat.formatDuration(45), "45 min")
        assertEqual(TimeFormat.formatDuration(60), "1 hr")
        assertEqual(TimeFormat.formatDuration(75), "1 hr 15 min")
        assertEqual(TimeFormat.formatDuration(120), "2 hrs")
        assertEqual(TimeFormat.formatDuration(135), "2 hr 15 min")

        assertEqual(TimeFormat.formatDurationShort(45), "45m")
        assertEqual(TimeFormat.formatDurationShort(60), "1h")
        assertEqual(TimeFormat.formatDurationShort(75), "1h 15m")
        assertEqual(TimeFormat.formatDurationShort(120), "2h")
        assertEqual(TimeFormat.formatDurationShort(135), "2h 15m")

        // Check formatTime with valid and invalid strings
        let timeStr = TimeFormat.formatTime(14 * 60 + 30) // 14:30
        assertTrue(!timeStr.isEmpty)
        let timeStr2 = TimeFormat.formatTime("14:30")
        assertEqual(timeStr, timeStr2)
        assertEqual(TimeFormat.formatTime("invalid"), "invalid")
        print("  ✅ TimeFormat tests passed.")

        // =========================================================================
        // 5. Onboarding Tests
        // =========================================================================
        print("  ▶ Running Onboarding tests...")
        do {
            var draft = OnboardingDraft(
                yourName: "Sarah",
                yourRelationship: "Mother",
                homePlaceName: "Home",
                homeAddress: "18 Redwood Lane"
            )
            draft.crew = [OnboardingDraft.DraftPerson(name: "Mark", relationship: "Father")]
            draft.kids = [
                OnboardingDraft.DraftPerson(name: "Maya", relationship: "Child"),
                OnboardingDraft.DraftPerson(name: "Noah", relationship: "Child")
            ]
            draft.places = [
                OnboardingDraft.DraftPlace(name: "School", address: "2140 Schoolhouse Rd", minutesFromHome: 12),
                OnboardingDraft.DraftPlace(name: "Field", address: "880 Northfield Rd", minutesFromHome: 20)
            ]
            draft.activities = [
                OnboardingDraft.DraftActivity(
                    id: "a1",
                    title: "Soccer practice",
                    kidNames: ["Noah"],
                    placeName: "Field",
                    weekdays: [1, 3],
                    time: "17:15",
                    durationMinutes: 75,
                    ownerName: "Mark",
                    category: "Sports"
                )
            ]

            let result = draft.build()

            // Roster: you first, then crew, then kids.
            assertEqual(result.people.map { $0.name }, ["Sarah", "Mark", "Maya", "Noah"], "roster order")
            assertEqual(result.currentUser, "Sarah", "active user is you")
            assertEqual(result.people.filter { $0.kind == "caregiver" }.count, 2)
            assertEqual(result.people.filter { $0.kind == "child" }.count, 2)

            // Places: home leads, and every place is routable.
            assertEqual(result.locations.map { $0.name }, ["Home", "School", "Field"], "home leads places")
            assertEqual(result.routes["Home"]?["School"], 12, "drive time from home")
            assertEqual(result.routes["School"]?["Home"], 12, "matrix is symmetric")
            assertEqual(result.routes["Home"]?["Home"], 0)
            assertTrue((result.routes["School"]?["Field"] ?? 0) > 0, "place-to-place is estimated")

            // Routines land on the days that were picked, and nowhere else.
            assertEqual(result.eventsByDay[1]?.count, 1, "Tuesday has the practice")
            assertEqual(result.eventsByDay[3]?.count, 1, "Thursday has the practice")
            assertEqual(result.eventsByDay[0]?.count, 0, "Monday is untouched")
            assertEqual(result.eventsByDay[1]?.first?.title, "Soccer practice")
            assertEqual(result.eventsByDay[1]?.first?.endTime, "18:30", "duration sets the end")
            assertEqual(result.eventsByDay[1]?.first?.owner, "Mark")
            assertEqual(result.eventsByDay[1]?.first?.location, "Field")
            assertEqual(result.templates.count, 1, "each routine becomes a template")

            // Reserved and duplicate names never reach the roster.
            var messy = draft
            messy.crew.append(OnboardingDraft.DraftPerson(name: "Family", relationship: "Other"))
            messy.crew.append(OnboardingDraft.DraftPerson(name: "sarah", relationship: "Other"))
            messy.crew.append(OnboardingDraft.DraftPerson(name: "   ", relationship: "Other"))
            assertEqual(messy.caregiverNames, ["Sarah", "Mark"], "reserved and duplicate names dropped")

            // A routine pointing at a place that was deleted falls back home.
            var orphaned = draft
            orphaned.places = []
            let orphanResult = orphaned.build()
            assertEqual(orphanResult.eventsByDay[1]?.first?.location, "Home", "unknown place falls back home")
            assertEqual(orphanResult.eventsByDay[1]?.first?.mode, "Home")

            // Applying replaces the sample household outright.
            let store = AppStore()
            store.applyOnboarding(draft)
            assertEqual(store.caregivers(), ["Sarah", "Mark"], "store roster replaced")
            assertEqual(store.children(), ["Maya", "Noah"])
            assertEqual(store.currentUser, "Sarah")
            assertEqual(store.homeAddress, "18 Redwood Lane")
            assertEqual(store.travel(origin: "Home", destination: "School", at: nil), 12, "travel uses the given time")
            assertTrue(store.hasCompletedOnboarding, "setup is marked done")
            assertTrue(!store.showOnboarding, "setup closes on finish")
            assertEqual(store.records().count, 2, "the week holds both practices")
            assertEqual(store.parentLocations["Sarah"], "Home", "everyone starts at home")

            // A re-run starts from the answers, not from a blank form.
            let rerun = store.onboardingStartingPoint()
            assertEqual(rerun.yourName, "Sarah")
            assertEqual(rerun.kids.count, 2)
        }
        print("  ✅ Onboarding tests passed.")

        // =========================================================================
        // 6. Persistence Tests
        // =========================================================================
        print("  ▶ Running Persistence tests...")
        do {
            let defaults = UserDefaults(suiteName: "helipad.tests")!
            HeliPersistence.clear(from: defaults)
            assertTrue(HeliPersistence.load(from: defaults) == nil, "nothing stored yet")

            var draft = OnboardingDraft(yourName: "Sarah", homeAddress: "18 Redwood Lane")
            draft.kids = [OnboardingDraft.DraftPerson(name: "Maya", relationship: "Child")]

            let state = PersistedState(
                version: HeliPersistence.version(),
                people: draft.build().people,
                locations: draft.build().locations,
                eventsByDay: [:],
                plan: PlanMetadata(),
                templates: [],
                parentLocations: ["Sarah": "Home"],
                routes: [:],
                homeAddress: "18 Redwood Lane",
                homePlaceName: "Home",
                buffer: 9,
                trafficMode: false,
                dinnerProtection: true,
                currentUser: "Sarah",
                timeZone: "device",
                notifyLeaveBy: true,
                notifyDriverNeeded: false,
                notifyCrew: true,
                connections: ["google": true],
                hasCompletedOnboarding: true,
                onboardingDraft: draft
            )
            HeliPersistence.save(state, to: defaults)

            let loaded = HeliPersistence.load(from: defaults)
            assertTrue(loaded != nil, "state round-trips")
            assertEqual(loaded?.currentUser, "Sarah")
            assertEqual(loaded?.buffer, 9)
            assertEqual(loaded?.people.count, 2)
            assertEqual(loaded?.onboardingDraft?.yourName, "Sarah", "the answers come back too")

            // A restored store opens on the family, not on setup.
            let restored = AppStore()
            restored.restore(from: defaults)
            assertEqual(restored.currentUser, "Sarah")
            assertEqual(restored.buffer, 9)
            assertTrue(!restored.showOnboarding, "a set-up phone skips setup")

            // A phone with nothing stored opens setup.
            HeliPersistence.clear(from: defaults)
            let fresh = AppStore()
            fresh.restore(from: defaults)
            assertTrue(fresh.showOnboarding, "a new phone opens setup")

            HeliPersistence.clear(from: defaults)
        }
        print("  ✅ Persistence tests passed.")

        // =========================================================================
        // 6. Integration Services Tests (Weather, Google Maps, Neon, Location)
        // =========================================================================
        print("  ▶ Running Integration Services tests...")

        // WeatherService WMO mapping
        do {
            let clearMapped = WeatherService.mapWMOCode(0)
            assertEqual(clearMapped.icon, "sun")
            assertEqual(clearMapped.condition, "Sunny")

            let rainMapped = WeatherService.mapWMOCode(61)
            assertEqual(rainMapped.icon, "rain")
            assertEqual(rainMapped.condition, "Rain")

            let stormMapped = WeatherService.mapWMOCode(95)
            assertEqual(stormMapped.icon, "storm")
            assertEqual(stormMapped.condition, "Thunderstorms")

            let cloudMapped = WeatherService.mapWMOCode(45)
            assertEqual(cloudMapped.icon, "cloud")
            assertEqual(cloudMapped.condition, "Foggy")
        }

        // LocationService distance math
        do {
            let coordAnnArbor = CLLocationCoordinate2D(latitude: 42.2808, longitude: -83.7430)
            let coordDetroit = CLLocationCoordinate2D(latitude: 42.3314, longitude: -83.0458)
            let miles = LocationService.distanceInMiles(from: coordAnnArbor, to: coordDetroit)
            assertTrue(miles > 30 && miles < 45, "Ann Arbor to Detroit is approx 36-38 miles (got \(miles))")
        }

        // NeonDatabaseService connection string parsing
        do {
            let validUrl = "postgresql://alex_user:super_secret_pw@ep-quiet-star-123.us-east-2.aws.neon.tech/neondb?sslmode=require"
            let config = NeonConfig.parse(from: validUrl)
            assertTrue(config != nil, "Parsed valid Neon URL")
            assertEqual(config?.host, "ep-quiet-star-123.us-east-2.aws.neon.tech")
            assertEqual(config?.passwordOrToken, "super_secret_pw")
            assertEqual(config?.database, "neondb")

            let invalidUrl = "not-a-valid-url"
            let invalidConfig = NeonConfig.parse(from: invalidUrl)
            assertTrue(invalidConfig == nil, "Invalid URL returns nil")
        }

        // Persistence with Integration Settings
        do {
            let defaults = UserDefaults(suiteName: "TestRunner.Integrations")!
            HeliPersistence.clear(from: defaults)

            var state = PersistedState(
                version: HeliPersistence.version(),
                people: [],
                locations: [],
                eventsByDay: [:],
                plan: PlanMetadata(),
                templates: [],
                parentLocations: [:],
                routes: [:],
                homeAddress: "123 Main St",
                homePlaceName: "Home",
                buffer: 15,
                trafficMode: true,
                dinnerProtection: true,
                currentUser: "Mom",
                timeZone: "America/Detroit",
                notifyLeaveBy: true,
                notifyDriverNeeded: true,
                notifyCrew: true,
                connections: [:],
                hasCompletedOnboarding: true,
                googleMapsApiKey: "AIzaSyTestKey123",
                neonConnectionString: "postgresql://user:pass@host/db",
                neonSyncEnabled: true,
                lastNeonSyncDate: Date(timeIntervalSince1970: 1700000000),
                dismissedEventIds: ["event-1", "event-2"]
            )

            HeliPersistence.save(state, to: defaults)
            let loaded = HeliPersistence.load(from: defaults)
            assertTrue(loaded != nil, "Loaded persisted integrations state")
            assertEqual(loaded?.googleMapsApiKey, "AIzaSyTestKey123")
            assertEqual(loaded?.neonConnectionString, "postgresql://user:pass@host/db")
            assertEqual(loaded?.neonSyncEnabled, true)
            assertEqual(loaded?.dismissedEventIds, ["event-1", "event-2"])

            HeliPersistence.clear(from: defaults)
        }

        // Live Neon connection check with AppConfig
        if AppConfig.isCloudConfigured {
            do {
                let connected = try await NeonDatabaseService.shared.testConnection(rawConnectionString: AppConfig.defaultNeonConnectionString)
                assertTrue(connected, "Neon database connected successfully via HTTP API")
                print("      ☁️ Neon live connection verified: Connected & healthy")
            } catch {
                print("      ⚠️ Neon live connection check: \(error)")
            }
        }
        print("  ✅ Integration Services tests passed.")

        // =========================================================================
        // 9. Location Autocomplete & Places Tests
        // =========================================================================
        print("  ▶ Running Places Autocomplete tests...")
        do {
            let saved = [
                LocationItem(name: "Pioneer High School", address: "601 W Stadium Blvd, Ann Arbor, MI", latitude: 42.2610, longitude: -83.7530),
                LocationItem(name: "Target", address: "3749 Carpenter Rd, Ypsilanti, MI", latitude: 42.2150, longitude: -83.6820)
            ]

            // 1. Test empty query returns empty
            let emptyRes = await GoogleMapsService.shared.autocompletePlaces(query: "", savedLocations: saved)
            assertEqual(emptyRes.count, 0, "Empty query returns 0 results")

            // 2. Test saved location match (zero network latency)
            let pioneerRes = await GoogleMapsService.shared.autocompletePlaces(query: "Pioneer", savedLocations: saved)
            assertTrue(!pioneerRes.isEmpty, "Pioneer should return results")
            assertEqual(pioneerRes.first?.primaryText, "Pioneer High School")
            assertTrue(pioneerRes.first?.secondaryText.contains("Stadium") == true, "Address contains Stadium")

            // 3. Test seed place fallback / business match with street addresses
            let starbucksRes = await GoogleMapsService.shared.autocompletePlaces(query: "Starbucks", savedLocations: saved)
            print("      🔍 Starbucks predictions count: \(starbucksRes.count)")
            for p in starbucksRes.prefix(3) {
                print("         -> primary: '\(p.primaryText)', secondary: '\(p.secondaryText)'")
            }
            assertTrue(!starbucksRes.isEmpty, "Starbucks search should return seed/map results")
            assertTrue(starbucksRes.first?.primaryText.contains("Starbucks") == true, "Primary text contains Starbucks")
            assertTrue(!starbucksRes.first!.secondaryText.isEmpty, "Secondary text is not empty")

            // Test specific user address query
            let coachRes = await GoogleMapsService.shared.autocompletePlaces(query: "25622 Coach L")
            print("      🔍 '25622 Coach L' predictions count: \(coachRes.count)")
            for p in coachRes.prefix(3) {
                print("         -> primary: '\(p.primaryText)', secondary: '\(p.secondaryText)'")
            }
            assertTrue(!coachRes.isEmpty, "User address query '25622 Coach L' resolves")
            assertEqual(coachRes.first?.primaryText, "25622 Coach Ln")

            // 4. Test Home Address with GPS coordinates
            let store = AppStore()
            try store.setHomeAddress("25622 Coach Ln, South Lyon, MI", latitude: 42.4497, longitude: -83.6534)
            assertEqual(store.homeAddress, "25622 Coach Ln, South Lyon, MI")
            assertEqual(store.homeCoordinate?.latitude, 42.4497)
            assertEqual(store.homeCoordinate?.longitude, -83.6534)
            assertEqual(LocationService.shared.homeCoordinateFallback?.latitude, 42.4497)

            // 5. Test Simulator SF Location Fallback to Home
            // When simulator GPS reports Apple's default SF coordinates (37.7858, -122.4064):
            #if targetEnvironment(simulator)
            LocationService.shared.currentLocation = CLLocation(latitude: 37.785834, longitude: -122.406417)
            assertTrue(LocationService.shared.isSimulatorDefaultSF, "Detects Apple default SF simulator GPS")
            assertEqual(LocationService.shared.effectiveCoordinate.latitude, 42.4497, "Prefers Home coordinate over SF simulator default")
            assertEqual(LocationService.shared.effectiveCoordinate.longitude, -83.6534)
            #endif

            // 6. Test fetchPlaceDetails with fallback name and address
            let details = try await GoogleMapsService.shared.fetchPlaceDetails(
                placeId: "custom-test-id",
                fallbackName: "Ann Arbor YMCA",
                fallbackAddress: "400 W Washington St, Ann Arbor, MI"
            )
            assertEqual(details.name, "Ann Arbor YMCA")
            assertEqual(details.formattedAddress, "400 W Washington St, Ann Arbor, MI")
            assertTrue(details.latitude != 0.0 && details.longitude != 0.0, "Details returns valid coordinate")
        }
        print("  ✅ Places Autocomplete tests passed.")

        print("🎉 ALL DOMAIN TESTS PASSED PERFECTLY!\n")
    }
}
