import XCTest
@testable import AssistantKit

/// R-series semantics the assistant depends on. The 20- and 30-week rows are
/// the same fixture the prewalk verified against the app's own `PlanCore`, so
/// a divergence here is a divergence from the app.
final class RecurrenceTests: XCTestCase {
    private func rule(weeks: Int, weekdays: [Int] = [0, 2], start: String = "2026-09-14") -> RecurrenceRule {
        RecurrenceRule(mode: .weekly, weekdays: weekdays, bound: .weeks(weeks), startDate: start)
    }

    func testMatchesTheVerifiedOccurrenceTable() throws {
        let one = try RecurrenceCore.dates(for: rule(weeks: 1))
        XCTAssertEqual(one.count, 2)
        XCTAssertEqual(one.first, "2026-09-14")
        XCTAssertEqual(one.last, "2026-09-16")

        let twenty = try RecurrenceCore.dates(for: rule(weeks: 20))
        XCTAssertEqual(twenty.count, 40)
        XCTAssertEqual(twenty.first, "2026-09-14")
        XCTAssertEqual(twenty.last, "2027-01-27")

        let thirty = try RecurrenceCore.dates(for: rule(weeks: 30))
        XCTAssertEqual(thirty.count, 60)
        XCTAssertEqual(thirty.first, "2026-09-14")
        XCTAssertEqual(thirty.last, "2027-04-07")
    }

    func testFirstWeekDropsDaysBeforeTheStartDate() throws {
        // Start on Wednesday, repeat Monday and Wednesday: the first Monday is
        // before the start and must not appear.
        let dates = try RecurrenceCore.dates(for: rule(weeks: 2, weekdays: [0, 2], start: "2026-09-16"))
        XCTAssertEqual(dates, ["2026-09-16", "2026-09-21", "2026-09-23"])
    }

    func testEndDateBoundIsInclusiveAndStopsMidWeek() throws {
        let dates = try RecurrenceCore.dates(for: RecurrenceRule(
            mode: .weekly, weekdays: [0, 2], bound: .until("2026-09-28"), startDate: "2026-09-14"
        ))
        // 28 Sep is a Monday and is included; the Wednesday after it is not.
        XCTAssertEqual(dates, ["2026-09-14", "2026-09-16", "2026-09-21", "2026-09-23", "2026-09-28"])
    }

    func testEndDateOnTheStartDateProducesOneOccurrence() throws {
        let dates = try RecurrenceCore.dates(for: RecurrenceRule(
            mode: .weekly, weekdays: [0], bound: .until("2026-09-14"), startDate: "2026-09-14"
        ))
        XCTAssertEqual(dates, ["2026-09-14"])
    }

    func testRejectsOutOfRangeAndEmptyRules() {
        XCTAssertThrowsError(try RecurrenceCore.dates(for: rule(weeks: 0)))
        XCTAssertThrowsError(try RecurrenceCore.dates(for: rule(weeks: 53)))
        XCTAssertThrowsError(try RecurrenceCore.dates(for: RecurrenceRule(
            mode: .weekly, weekdays: [], bound: .weeks(4), startDate: "2026-09-14"
        )))
        XCTAssertThrowsError(try RecurrenceCore.dates(for: RecurrenceRule(
            mode: .weekly, weekdays: [7], bound: .weeks(4), startDate: "2026-09-14"
        )))
        XCTAssertThrowsError(try RecurrenceCore.dates(for: RecurrenceRule(
            mode: .weekly, weekdays: [0], bound: .until("2026-09-01"), startDate: "2026-09-14"
        )))
        XCTAssertThrowsError(try RecurrenceCore.dates(for: RecurrenceRule(
            mode: .weekly, weekdays: [0], bound: .weeks(4), startDate: "not-a-date"
        )))
    }

    func testSingleEventIgnoresWeekdays() throws {
        let dates = try RecurrenceCore.dates(for: RecurrenceRule(
            mode: .none, weekdays: [0, 1, 2], bound: .weeks(9), startDate: "2026-09-16"
        ))
        XCTAssertEqual(dates, ["2026-09-16"])
    }

    func testDescriptionIsAppAuthored() {
        XCTAssertEqual(RecurrenceCore.describe(rule(weeks: 30, weekdays: [1])), "Every Tuesday for 30 weeks")
        XCTAssertEqual(
            RecurrenceCore.describe(RecurrenceRule(mode: .weekly, weekdays: [0, 2], bound: .until("2026-12-18"), startDate: "2026-09-14")),
            "Every Monday and Wednesday through Dec 18"
        )
    }

    func testCalendarMathBasics() {
        XCTAssertEqual(CalendarMath.monday("2026-09-11"), "2026-09-07")
        XCTAssertEqual(CalendarMath.monday("2026-09-13"), "2026-09-07") // Sunday belongs to the week that started Monday
        XCTAssertEqual(CalendarMath.weekdayIndex("2026-09-14"), 0)
        XCTAssertEqual(CalendarMath.weekdayIndex("2026-09-13"), 6)
        XCTAssertEqual(CalendarMath.daysBetween("2026-09-07", "2026-09-14"), 7)
        XCTAssertNil(CalendarMath.minutes("7pm"))
        XCTAssertNil(CalendarMath.minutes("25:00"))
        XCTAssertEqual(CalendarMath.minutes("16:05"), 965)
    }

    func testPreviousPeriodIsEqualLengthAndAdjacent() throws {
        let range = try XCTUnwrap(DateRange(start: "2026-09-01", end: "2026-09-30"))
        let previous = range.previousEqualLength
        XCTAssertEqual(previous.start, "2026-08-02")
        XCTAssertEqual(previous.end, "2026-08-31")
        XCTAssertEqual(previous.dayCount, range.dayCount)
    }
}
