import Foundation
import Combine

final class MemorySecrets: IntegrationSecretStore {
    var values: [String: String] = [:]
    func get(_ key: String) throws -> String? { values[key] }
    func set(_ value: String, for key: String) throws { values[key] = value.isEmpty ? nil : value }
}

actor TestCloud: HouseholdCloudService {
    var remote: RemoteHousehold?
    var uploads: [PersistedState] = []
    var blockNext = false
    var failureNext = false
    var gate: CheckedContinuation<Void, Never>?
    var arrival: CheckedContinuation<Void, Never>?
    var revision = 0

    func blockUpload() { blockNext = true }
    func failUpload() { failureNext = true }
    func waitForUpload() async {
        if gate != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func release() { gate?.resume(); gate = nil }
    func uploadCount() -> Int { uploads.count }
    func lastUpload() -> PersistedState? { uploads.last }
    func setRemote(_ state: PersistedState) {
        revision += 1
        remote = RemoteHousehold(state: state, revision: String(revision))
    }
    func pushHousehold(state: PersistedState, householdId: String, expectedRevision: String?, rawConnectionString: String) async throws -> String {
        uploads.append(state)
        if blockNext {
            blockNext = false
            await withCheckedContinuation { continuation in
                gate = continuation
                arrival?.resume()
                arrival = nil
            }
        }
        if failureNext { failureNext = false; throw NeonError.networkError("Offline") }
        guard expectedRevision == remote?.revision else { throw NeonError.conflict }
        revision += 1
        remote = RemoteHousehold(state: state, revision: String(revision))
        return String(revision)
    }
    func pullHousehold(householdId: String, rawConnectionString: String) async throws -> RemoteHousehold? { remote }
    func fetchRevision(householdId: String, rawConnectionString: String) async throws -> String? { remote?.revision }
}

// Intercepts Neon SQL at the URLSession boundary. Never sends credentials or
// household fixtures to a network service.
final class SQLProtocol: URLProtocol {
    static var requests: [[String: Any]] = []
    static var returnConflict = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            data = bytes
        }
        let body = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
        Self.requests.append(body)
        let query = body["query"] as? String ?? ""
        let rows: [[String: Any]] = query.contains("RETURNING") && !Self.returnConflict ? [["revision": "2026-09-08 12:00:00+00"]] : []
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["rows": rows]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ProductionRegressionTests {
    static func check(_ condition: Bool, _ message: String, line: Int = #line) {
        precondition(condition, "Line \(line): \(message)")
    }

    @MainActor static func main() async throws {
        let iso = ISO8601DateFormatter()
        var now = iso.date(from: "2026-09-13T23:59:00Z")!
        let secrets = MemorySecrets()
        let cloud = TestCloud()
        let suite = "helipad.regression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func store(_ service: HouseholdCloudService = TestCloud()) -> AppStore {
            AppStore(timeZone: "UTC", cloudService: service, secretStore: secrets, schedulesNotifications: false, now: { now })
        }

        let fresh = store(cloud)
        fresh.restore(from: defaults)
        await fresh.resumePendingSync()
        check(await cloud.uploadCount() == 0, "first restore must not upload sample data")
        check(fresh.neonConnectionString.isEmpty && !fresh.neonSyncEnabled, "no bundled connection")
        check(AppConfig.defaultNeonConnectionString.isEmpty, "no shipped database secret")

        let old = TaskRecord(id: "old", date: "2026-09-13", title: "One-off", owner: "Mom", done: true)
        let future = TaskRecord(id: "future", date: "2026-09-14", title: "Next week", owner: "Mom")
        fresh.replaceRecords([old, future])
        fresh.hasCompletedOnboarding = true
        fresh.save(syncToCloud: false)
        now = iso.date(from: "2026-09-14T00:00:00Z")!
        fresh.syncWithDeviceDate()
        check(fresh.weekStart == "2026-09-14", "week rolls over")
        check(fresh.eventsByDay[0]?.first?.id == "future", "future event promoted into Go")
        check(fresh.records().first(where: { $0.id == "old" })?.date == "2026-09-13", "past date retained")
        check(fresh.records().first(where: { $0.id == "old" })?.done == true, "history retains completion")
        fresh.syncWithDeviceDate()
        check(fresh.records().count == 2, "rollover is idempotent")
        let restored = store()
        restored.restore(from: defaults)
        check(restored.records() == fresh.records(), "absolute dates survive relaunch")
        now = iso.date(from: "2026-10-05T12:00:00Z")!
        restored.syncWithDeviceDate()
        check(restored.records().count == 2 && restored.eventsByDay.isEmpty, "multiple skipped weeks preserve history")

        // Legacy v1 bucket dates are already absolute; do not relabel them on load.
        var legacy = try JSONSerialization.jsonObject(with: defaults.data(forKey: HeliPersistence.storageKey)!) as! [String: Any]
        legacy.removeValue(forKey: "syncMetadata")
        legacy.removeValue(forKey: "weekStart")
        legacy["neonConnectionString"] = "postgresql://old:exposed@example.neon.tech/db"
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: HeliPersistence.storageKey)
        let migrated = store()
        migrated.restore(from: defaults)
        check(migrated.records().contains(where: { $0.id == "old" && $0.date == "2026-09-13" }), "v1 event dates retained")
        let cleaned = String(data: defaults.data(forKey: HeliPersistence.storageKey)!, encoding: .utf8)!
        check(!cleaned.contains("exposed") && migrated.neonConnectionString.isEmpty, "legacy database secret scrubbed")

        now = iso.date(from: "2026-09-14T14:37:00Z")!
        let live = store()
        let vm = GoViewModel(store: live)
        check(live.mockTime.isEmpty && vm.nowMinutes == 14 * 60 + 37, "production clock uses real injected time")
        var publications = 0
        let observation = vm.$nowMinutes.dropFirst().sink { _ in publications += 1 }
        vm.updateClock()
        vm.updateClock()
        check(publications == 0, "same minute does not publish")
        now = now.addingTimeInterval(60)
        vm.updateClock()
        check(publications == 1, "next minute publishes once")
        live.mockTime = "08:05"
        vm.updateClock()
        check(vm.nowMinutes == 485, "explicit test clock supported")
        live.mockTime = ""
        live.timeZone = "America/Los_Angeles"
        vm.updateClock()
        check(vm.nowMinutes == 7 * 60 + 38, "household timezone used")
        _ = observation

        live.timeZone = "UTC"
        live.replaceRecords([TaskRecord(id: "cache", date: "2026-09-14", owner: "Mom", location: "Oak Ridge Elementary")])
        _ = vm.computeView(store: live)
        let passes = vm.analysisPassCount
        for _ in 0..<12 { _ = vm.computeView(store: live) }
        check(vm.analysisPassCount == passes, "clock-only renders reuse analysis")
        live.currentUser = "Dad"
        live.liveWeather.temperature = 90
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes, "profile and weather do not invalidate schedule analysis")
        live.buffer += 1
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes + 1, "buffer invalidates cached planning")
        live.eventsByDay[0]![0].time = "17:15"
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes + 2, "direct event edit invalidates cache")
        live.routes["Home"]?["Oak Ridge Elementary"] = 99
        _ = vm.computeView(store: live)
        check(vm.analysisPassCount == passes + 3, "route update invalidates cache")
        let data = vm.computeView(store: live)
        check(data.drivers == PlanCore.loads(live.eventsByDay[0] ?? [], live.planningOptions()), "cached workloads match planning core")

        // Restore to a clean isolated suite and configure a user-owned connection.
        defaults.removePersistentDomain(forName: suite)
        let syncing = store(cloud)
        syncing.restore(from: defaults)
        syncing.hasCompletedOnboarding = true
        syncing.neonConnectionString = "postgresql://personal:private@example.neon.tech/db"
        syncing.googleMapsApiKey = "private-google-key"
        syncing.neonSyncEnabled = true
        syncing.save(syncToCloud: false)
        await cloud.blockUpload()
        let first = Task { @MainActor in try await syncing.syncWithNeon() }
        await cloud.waitForUpload()
        syncing.homeAddress = "Edited while uploading"
        syncing.buffer = 19
        syncing.save(syncToCloud: false)
        let joined = Task { @MainActor in try await syncing.syncWithNeon() }
        await cloud.release()
        try await first.value
        try await joined.value
        check(await cloud.uploadCount() == 2, "in-flight edits cause another upload")
        check(await cloud.lastUpload()?.buffer == 19, "latest edit reaches cloud")
        check(!syncing.syncPending, "all revisions acknowledged")
        let localData = defaults.data(forKey: HeliPersistence.storageKey)!
        let localText = String(data: localData, encoding: .utf8)!
        check(!localText.contains("private") && !localText.contains("postgresql"), "UserDefaults excludes credentials")
        check(secrets.values["neonConnectionString"] == syncing.neonConnectionString, "credentials use secret store")
        let payload = await cloud.lastUpload()!
        let cloudText = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        check(!cloudText.contains("private") && !cloudText.contains("syncMetadata"), "cloud excludes secrets and local sync metadata")

        await cloud.failUpload()
        syncing.buffer = 20
        syncing.save(syncToCloud: false)
        do { try await syncing.syncWithNeon(); preconditionFailure("Expected failure") } catch {}
        check(syncing.syncPending && syncing.syncError != nil, "failed work remains pending")
        let retry = store(cloud)
        retry.restore(from: defaults)
        check(retry.syncPending && retry.neonConnectionString == syncing.neonConnectionString, "pending work and secure connection survive restart")
        await retry.resumePendingSync()
        check(!retry.syncPending && retry.syncError == nil, "foreground retries pending revision")
        check(await cloud.lastUpload()?.buffer == 20, "retry sends latest state")

        var remoteEdit = await cloud.lastUpload()!
        remoteEdit.buffer = 33
        await cloud.setRemote(remoteEdit)
        retry.buffer = 21
        retry.save(syncToCloud: false)
        // A stale revision no longer strands the device: sync folds the cloud
        // household in and republishes, and the newer stamp decides the value.
        try await retry.syncWithNeon()
        check(retry.buffer == 21 && !retry.syncPending, "newer local settings survive a remote write and still upload")
        check(await cloud.lastUpload()?.buffer == 21, "merged settings reach the cloud")

        var newerRemote = await cloud.lastUpload()!
        newerRemote.buffer = 44
        newerRemote.settingsStamp = RecordStamp(counter: 9_000, deviceID: "other-phone")
        await cloud.setRemote(newerRemote)
        try await retry.syncWithNeon()
        check(retry.buffer == 44, "a newer remote settings stamp wins")

        let downloaded = try await retry.pullFromNeon()
        check(downloaded && !retry.syncPending, "explicit download establishes baseline")
        check(retry.hasCompletedOnboarding, "cloud restore retains onboarding completion")

        // Switching connection during a write must not acknowledge the old write for the new identity.
        await cloud.blockUpload()
        retry.buffer = 34
        retry.save(syncToCloud: false)
        let changing = Task { @MainActor in try await retry.syncWithNeon() }
        await cloud.waitForUpload()
        retry.cloudHouseholdID = "different-household"
        retry.save(syncToCloud: false)
        await cloud.release()
        do { try await changing.value; preconditionFailure("Expected identity error") } catch {}
        check(retry.syncPending, "identity change stays pending")
        check(HeliPersistence.load(from: defaults)?.syncMetadata?.remoteRevision == nil, "old revision not attached to new household")

        let manualCloud = TestCloud()
        let manual = store(manualCloud)
        manual.hasCompletedOnboarding = true
        manual.neonConnectionString = "postgresql://manual:private@example.neon.tech/db"
        manual.neonSyncEnabled = false
        await manualCloud.blockUpload()
        let manualUpload = Task { @MainActor in try await manual.syncWithNeon() }
        await manualCloud.waitForUpload()
        manual.buffer = 22
        manual.save(syncToCloud: false)
        await manualCloud.release()
        try await manualUpload.value
        check(await manualCloud.uploadCount() == 2, "manual sync also drains in-flight edits with auto-sync off")
        check(!manual.syncPending, "manual sync acknowledges the newest revision")

        // Two phones, one household: the case this whole mechanism exists for.
        let shared = TestCloud()
        let suiteA = "helipad.deviceA.\(UUID().uuidString)"
        let suiteB = "helipad.deviceB.\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteA)!
        let defaultsB = UserDefaults(suiteName: suiteB)!
        defer { defaults.removePersistentDomain(forName: suiteA) }
        defer { defaults.removePersistentDomain(forName: suiteB) }

        func phone(_ store: AppStore, _ defaults: UserDefaults) -> AppStore {
            store.restore(from: defaults)
            store.hasCompletedOnboarding = true
            store.neonConnectionString = "postgresql://pair:private@example.neon.tech/db"
            store.cloudHouseholdID = "shared-household"
            store.neonSyncEnabled = true
            store.save(syncToCloud: false)
            return store
        }
        let phoneA = phone(store(shared), defaultsA)
        let phoneB = phone(store(shared), defaultsB)

        // A publishes a stop; B has never seen this household.
        let soccer = TaskRecord(id: "ev-soccer", date: "2026-10-05", title: "Soccer", owner: "Mom")
        phoneA.replaceRecords([soccer])
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        check(phoneB.records().contains { $0.id == "ev-soccer" }, "second phone receives the first phone's stop")

        // Each phone adds a different stop without seeing the other's first.
        var aRecords = phoneA.records()
        aRecords.append(TaskRecord(id: "ev-piano", date: "2026-10-06", title: "Piano", owner: "Mom"))
        phoneA.replaceRecords(aRecords)
        var bRecords = phoneB.records()
        bRecords.append(TaskRecord(id: "ev-swim", date: "2026-10-07", title: "Swim", owner: "Dad"))
        phoneB.replaceRecords(bRecords)
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        try await phoneA.syncWithNeon()
        let aIds = Set(phoneA.records().map(\.id))
        let bIds = Set(phoneB.records().map(\.id))
        check(aIds == ["ev-soccer", "ev-piano", "ev-swim"], "concurrent adds all survive on the first phone")
        check(aIds == bIds, "both phones converge on the same schedule")

        // A delete must not be resurrected by the other phone's copy.
        phoneA.replaceRecords(phoneA.records().filter { $0.id != "ev-soccer" })
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        check(!phoneB.records().contains { $0.id == "ev-soccer" }, "a delete propagates instead of being undone")
        check(phoneB.records().count == 2, "the other two stops are untouched")

        // Editing the same stop on both phones: the later stamp wins, and both agree.
        func retitle(_ store: AppStore, _ title: String) {
            var list = store.records()
            guard let index = list.firstIndex(where: { $0.id == "ev-piano" }) else { return }
            list[index].title = title
            store.replaceRecords(list)
        }
        // Concurrent edits — neither phone saw the other's — have no "later".
        // The guarantee is that both land on the *same* one, not on a
        // particular one, so that is what gets asserted.
        retitle(phoneA, "Piano lesson")
        retitle(phoneB, "Piano recital")
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        try await phoneA.syncWithNeon()
        let aTitle = phoneA.records().first { $0.id == "ev-piano" }?.title
        let bTitle = phoneB.records().first { $0.id == "ev-piano" }?.title
        check(aTitle == bTitle, "both phones agree after a concurrent edit to one stop")
        check(aTitle == "Piano lesson" || aTitle == "Piano recital", "the surviving edit is one of the two")

        // A causal edit is different: B has seen A's title before changing it,
        // so B's must win on both phones.
        retitle(phoneA, "Piano practice")
        try await phoneA.syncWithNeon()
        try await phoneB.syncWithNeon()
        check(phoneB.records().first { $0.id == "ev-piano" }?.title == "Piano practice", "B sees A's edit first")
        retitle(phoneB, "Piano exam")
        try await phoneB.syncWithNeon()
        try await phoneA.syncWithNeon()
        check(phoneA.records().first { $0.id == "ev-piano" }?.title == "Piano exam", "an edit made after seeing the other phone's wins")

        // A phone that is behind picks the change up from a revision probe.
        var laterRecords = phoneA.records()
        laterRecords.append(TaskRecord(id: "ev-dentist", date: "2026-10-08", title: "Dentist", owner: "Mom"))
        phoneA.replaceRecords(laterRecords)
        try await phoneA.syncWithNeon()
        await phoneB.liveSyncTick()
        check(phoneB.records().contains { $0.id == "ev-dentist" }, "live tick pulls the other phone's new stop")
        let quiet = await shared.uploadCount()
        await phoneB.liveSyncTick()
        check(await shared.uploadCount() == quiet, "an idle tick with no change uploads nothing")

        // Two settled phones must go quiet. If each answered the other's write
        // with a write of its own they would trade revisions forever.
        let settled = await shared.uploadCount()
        for _ in 0..<6 {
            await phoneA.liveSyncTick()
            await phoneB.liveSyncTick()
        }
        check(await shared.uploadCount() == settled, "settled phones stop writing to each other")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SQLProtocol.self]
        let transport = NeonDatabaseService(session: URLSession(configuration: config))
        _ = try await transport.pushHousehold(state: payload, householdId: "kid's-home", expectedRevision: nil, rawConnectionString: syncing.neonConnectionString)
        let insert = SQLProtocol.requests.last!
        check((insert["query"] as! String).contains("DO NOTHING"), "first upload never overwrites existing row")
        check(!(insert["query"] as! String).contains("kid's-home"), "household identity parameterized")
        _ = try await transport.pushHousehold(state: payload, householdId: "kid's-home", expectedRevision: "2026-09-08 12:00:00+00", rawConnectionString: syncing.neonConnectionString)
        let update = SQLProtocol.requests.last!
        check((update["query"] as! String).contains("updated_at = $3::timestamptz"), "update compares revision atomically")
        SQLProtocol.returnConflict = true
        do {
            _ = try await transport.pushHousehold(state: payload, householdId: "kid's-home", expectedRevision: "stale", rawConnectionString: syncing.neonConnectionString)
            preconditionFailure("Expected zero-row conflict")
        } catch NeonError.conflict {}

        // Solo events without children & stats accuracy verification
        check(FamilyCore.resolveChildren(kids: [], kid: "").isEmpty, "empty kids resolves to empty list, not all kids")
        check(FamilyCore.resolveChildren(kids: ["Maya"], kid: "") == ["Maya"], "single kid preserved")
        check(FamilyCore.resolveChildren(kids: nil, kid: nil) == FamilyCore.KIDS, "nil fallback returns all kids")

        let statsStore = store()
        let soloDoctor = TaskRecord(id: "solo-doc", date: "2026-09-14", time: "10:00", endTime: "11:00", title: "Doctor", owner: "Dad", kids: [], location: "Medical Center", mode: "Drive", kind: .clinic)
        let soniSoccer = TaskRecord(id: "soni-soccer", date: "2026-09-14", time: "15:00", endTime: "16:00", title: "Soccer", owner: "Mom", kids: ["Soni"], location: "Field", mode: "Drive", kind: .practice)
        let soniOrphan = TaskRecord(id: "soni-orphan", date: "2026-09-15", time: "15:00", endTime: "16:00", title: "Swim", owner: "TBD", kids: ["Soni"], location: "Pool", mode: "Drive", kind: .practice)
        statsStore.replaceRecords([soloDoctor, soniSoccer, soniOrphan])

        let familyVM = FamilyViewModel()
        let counts = familyVM.driveCounts(store: statsStore)
        check(counts["Dad"] == 1, "caregiver drive count reflects solo adult drive")
        check(counts["Mom"] == 1, "caregiver drive count reflects kid drive")

        let soniStats = familyVM.statsForKid(kid: "Soni", store: statsStore)
        check(soniStats.eventCount == 2, "Soni stats include only Soni's own events")
        check(soniStats.needsDriverCount == 1, "Soni needs-a-driver count sees the unassigned swim only")

        let mayaStats = familyVM.statsForKid(kid: "Maya", store: statsStore)
        check(mayaStats.eventCount == 0, "Maya stats strictly exclude solo adult doctor event")
        check(mayaStats.needsDriverCount == 0, "Maya needs-a-driver count strictly excludes other kids' events")

        let noahStats = familyVM.statsForKid(kid: "Noah", store: statsStore)
        check(noahStats.eventCount == 0, "Noah stats strictly exclude solo adult doctor event")

        print("Production regression checks passed: credentials, sync races/conflicts/retry, two-phone merge and convergence, live sync quiescence, rollover, clock, analysis caching, solo events, and stats tracking.")
    }
}
