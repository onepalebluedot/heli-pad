import XCTest
@testable import AssistantKit
import AssistantMocks

final class LocationLookupTests: XCTestCase {
    private final class Places: HouseholdQueryPort, @unchecked Sendable {
        let matches: [AssistantLocation]
        let fails: Bool
        init(_ matches: [AssistantLocation], fails: Bool = false) {
            self.matches = matches
            self.fails = fails
        }
        func events(in session: AssistantSession) async throws -> [AssistantEvent] { [] }
        func people(in session: AssistantSession) async throws -> [AssistantPerson] { [] }
        func places(in session: AssistantSession) async throws -> [AssistantPlace] { [] }
        func planningContext(in session: AssistantSession) async throws -> PlanningContext { Fixtures.planning }
        func searchLocations(query: String, in session: AssistantSession) async throws -> [AssistantLocation] {
            if fails { throw URLError(.notConnectedToInternet) }
            return matches
        }
    }

    private let destination = AssistantLocation(name: "The Archive", address: "123 Main Street", latitude: 42.2, longitude: -83.7)

    private func preview(_ port: Places, lookup: Bool = true) async throws -> ToolOutcome {
        try await ToolRouter(query: port).run(.previewCreateEvents(CreateEventsArgs(
            title: "Baby shower", startTime: "16:00", endTime: "17:00",
            locationName: "The Archive", kind: .play, childIDs: [], ownerID: nil,
            rule: .single(on: "2026-09-15"), lookupLocation: lookup
        )), in: Fixtures.session)
    }

    func testUniqueMatchCarriesCoordinatesThroughProposalSerialization() async throws {
        let outcome = try await preview(Places([destination]))
        let proposal = try XCTUnwrap(outcome.proposal)
        let decoded = try JSONDecoder().decode(MutationBatch.self, from: JSONEncoder().encode(proposal.batch))
        XCTAssertEqual(decoded.creates.first?.resolvedLocation, destination)
        XCTAssertTrue(outcome.modelPayload.contains("123 Main Street"))
        XCTAssertFalse(outcome.modelPayload.contains("latitude"))
    }

    func testAmbiguousMatchDoesNotPickADestination() async throws {
        let outcome = try await preview(Places([destination, destination]))
        XCTAssertNil(outcome.proposal?.batch.creates.first?.resolvedLocation)
        XCTAssertEqual(outcome.proposal?.batch.creates.first?.location, "The Archive")
        XCTAssertTrue(outcome.modelPayload.contains("multiple destinations"))
    }

    func testOfflineLookupStillBuildsTextOnlyReview() async throws {
        let outcome = try await preview(Places([], fails: true))
        XCTAssertEqual(outcome.proposal?.batch.creates.first?.location, "The Archive")
        XCTAssertTrue(outcome.modelPayload.contains("unavailable"))
    }

    func testTextOnlyDoesNotUseAvailableMatch() async throws {
        let outcome = try await preview(Places([destination]), lookup: false)
        XCTAssertNil(outcome.proposal?.batch.creates.first?.resolvedLocation)
    }
}
