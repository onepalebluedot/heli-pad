import XCTest
@testable import AssistantKit
import AssistantMocks

/// A06: chat history is device-local, partitioned per user and household, and
/// clearable. It now also survives quitting the app, which is what these cover.
final class TranscriptTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func message(_ text: String) -> ChatMessage {
        ChatMessage(author: .user, date: Date(timeIntervalSince1970: 1), text: text)
    }

    func testAConversationSurvivesANewInstance() {
        let first = ChatTranscript(storageDirectory: directory)
        first.append(message("what's on this week?"), for: Fixtures.session)

        // A fresh instance stands in for the next app launch.
        let second = ChatTranscript(storageDirectory: directory)
        XCTAssertEqual(second.messages(for: Fixtures.session).map(\.text), ["what's on this week?"])
    }

    func testCardsSurviveTheRoundTrip() throws {
        let rows = [EventRow(
            eventID: "evt-1", date: "2026-09-15", time: "16:00", endTime: "17:30",
            title: "Swimming", ownerLabel: "Needs a driver", isUnassigned: true,
            locationName: "Eastside Pool", category: "Sports", isPast: false
        )]
        let card = AssistantCard.proposal(ProposalCard(
            proposalID: "p1", headline: "Create \u{201C}Swimming\u{201D}",
            ruleDescription: "Every Tuesday for 30 weeks", affectedCount: 30,
            periodLabel: "Sep 15\u{2013}Apr 6", rows: rows,
            conflicts: [ScheduleConflict(cause: .dinnerWindow, date: "2026-09-15", existingEventID: nil, detail: "clash")],
            destinationNote: "HeliPad only", assumptions: ["90 minutes assumed"],
            expiresAt: Date(timeIntervalSince1970: 100)
        ))
        let trends = AssistantCard.trends(TrendCard(
            periodLabel: "Sep", comparisonLabel: "vs Aug", partialPeriodNote: nil,
            metrics: [TrendMetric(id: "m", title: "Events", currentValue: 3, previousValue: 1,
                                  unit: "events", change: .percent(200, absolute: 2))],
            workload: [.init(name: "Alex", count: 3)], categoryMix: [.init(category: "Sports", count: 3)],
            supportingEventIDs: ["evt-1"], notes: ["note"]
        ))

        let first = ChatTranscript(storageDirectory: directory)
        first.append(ChatMessage(author: .assistant, date: Date(timeIntervalSince1970: 2), cards: [card, trends]), for: Fixtures.session)

        let restored = try XCTUnwrap(ChatTranscript(storageDirectory: directory).messages(for: Fixtures.session).first)
        XCTAssertEqual(restored.cards.count, 2)
        guard case .proposal(let p) = restored.cards[0] else { return XCTFail("lost the proposal") }
        XCTAssertEqual(p.affectedCount, 30)
        XCTAssertEqual(p.assumptions, ["90 minutes assumed"])
        XCTAssertEqual(p.conflicts.first?.cause, .dinnerWindow)
        guard case .trends(let t) = restored.cards[1] else { return XCTFail("lost the trends") }
        XCTAssertEqual(t.metrics.first?.change, .percent(200, absolute: 2))
    }

    func testHouseholdsStayApartOnDiskToo() {
        let first = ChatTranscript(storageDirectory: directory)
        first.append(message("ours"), for: Fixtures.session)
        first.append(message("theirs"), for: Fixtures.otherSession)

        let second = ChatTranscript(storageDirectory: directory)
        XCTAssertEqual(second.messages(for: Fixtures.session).map(\.text), ["ours"])
        XCTAssertEqual(second.messages(for: Fixtures.otherSession).map(\.text), ["theirs"])
    }

    func testClearingRemovesItFromDiskNotJustMemory() {
        let first = ChatTranscript(storageDirectory: directory)
        first.append(message("private"), for: Fixtures.session)
        first.clear(for: Fixtures.session)

        XCTAssertTrue(ChatTranscript(storageDirectory: directory).messages(for: Fixtures.session).isEmpty)
    }

    func testSignOutRemovesEveryHouseholdsFile() {
        let first = ChatTranscript(storageDirectory: directory)
        first.append(message("ours"), for: Fixtures.session)
        first.append(message("theirs"), for: Fixtures.otherSession)
        first.clearAll()

        let second = ChatTranscript(storageDirectory: directory)
        XCTAssertTrue(second.messages(for: Fixtures.session).isEmpty)
        XCTAssertTrue(second.messages(for: Fixtures.otherSession).isEmpty)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(files.filter { $0.pathExtension == "json" }.isEmpty)
    }

    func testHistoryIsCappedSoTheFileCannotGrowForever() {
        let transcript = ChatTranscript(storageDirectory: directory)
        for index in 0..<(ChatTranscript.maxStoredMessages + 25) {
            transcript.append(message("m\(index)"), for: Fixtures.session)
        }
        let stored = ChatTranscript(storageDirectory: directory).messages(for: Fixtures.session)
        XCTAssertEqual(stored.count, ChatTranscript.maxStoredMessages)
        // The oldest fall off, the newest are kept.
        XCTAssertEqual(stored.last?.text, "m\(ChatTranscript.maxStoredMessages + 24)")
        XCTAssertEqual(stored.first?.text, "m25")
    }

    func testAnUnreadableTranscriptIsDiscardedNotFatal() throws {
        let transcript = ChatTranscript(storageDirectory: directory)
        transcript.append(message("good"), for: Fixtures.session)

        // Stands in for a card shape that changed between app versions.
        let file = try XCTUnwrap(
            (try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
                .first { $0.pathExtension == "json" }
        )
        try Data("{not json".utf8).write(to: file)

        XCTAssertTrue(ChatTranscript(storageDirectory: directory).messages(for: Fixtures.session).isEmpty)
    }

    func testNoDirectoryMeansMemoryOnly() {
        let transcript = ChatTranscript()
        transcript.append(message("ephemeral"), for: Fixtures.session)
        XCTAssertEqual(transcript.messages(for: Fixtures.session).count, 1)
        XCTAssertTrue(ChatTranscript(storageDirectory: directory).messages(for: Fixtures.session).isEmpty)
    }
}
