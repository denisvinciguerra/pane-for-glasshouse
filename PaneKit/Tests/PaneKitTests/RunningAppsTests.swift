import XCTest
@testable import PaneKit

@MainActor final class RunningAppsTests: XCTestCase {
    private let overview = Data(#"{"writable":true,"running":[{"id":"app.example","title":"Example","mb":42,"foreground":true},{"id":"app.other","title":"Other","mb":null}]}"#.utf8)

    private func ready(_ api: FakeAPI) async -> TVSession {
        await api.serve("/api/apps", overview)
        let session = makeSession(api)
        await session.loadCapsAndTabs()
        await session.refreshStats()
        await session.refreshApps()
        return session
    }

    func testDecodesUnknownMemoryAndOldServer() throws {
        let payload = try JSONDecoder().decode(AppsOverview.self, from: overview)
        XCTAssertEqual(payload.running?.count, 2)
        XCTAssertNil(payload.running?.last?.mb)
        let old = try JSONDecoder().decode(AppsOverview.self, from: Data(#"{"writable":true}"#.utf8))
        XCTAssertNil(old.running)
    }

    func testCloseRefreshesListAndFocus() async {
        let api = FakeAPI()
        let session = await ready(api)
        let epoch = session.focusEpoch
        let closed = await session.closeApp("app.example")
        XCTAssertTrue(closed)
        XCTAssertEqual(session.appsOverview?.running?.map(\.id), ["app.other"])
        XCTAssertEqual(session.focusEpoch, epoch + 1)
        XCTAssertNil(session.closingApp)
        let calls = await api.closedApps
        XCTAssertEqual(calls, ["app.example"])
    }

    func testReadOnlyAndStaleSessionsDoNotCloseApps() async {
        let api = FakeAPI()
        let session = await ready(api)
        session.markStale()
        let stale = await session.closeApp("app.example")
        XCTAssertFalse(stale)
        await session.refreshStats()
        await api.serve("/api/apps", Data(#"{"writable":false,"running":[{"id":"app.example","title":"Example"}]}"#.utf8))
        await session.refreshApps()
        let readOnly = await session.closeApp("app.example")
        XCTAssertFalse(readOnly)
        let calls = await api.closedApps
        XCTAssertTrue(calls.isEmpty)
    }

    func testFailureKeepsAppAndReportsError() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.failSend(.rejected("Protected app"))
        let closed = await session.closeApp("app.example")
        XCTAssertFalse(closed)
        XCTAssertEqual(session.transientMessage, "Protected app")
        XCTAssertEqual(session.appsOverview?.running?.count, 2)
        XCTAssertNil(session.closingApp)
    }

    func testUnsupportedServerDoesNotRemoveAppsTab() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.fail("/api/apps", .http(404))
        await session.refreshApps()
        XCTAssertEqual(session.appsError, .http(404))
        XCTAssertTrue(session.availableTabs.contains(.apps))
        let closed = await session.closeApp("app.example")
        XCTAssertFalse(closed)
    }

    func testReadStartedBeforeCloseCannotRestoreClosedApp() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.hold("/api/apps")
        let oldRead = Task { await session.refreshApps() }
        while await api.heldCount("/api/apps") == 0 { await Task.yield() }
        let closed = await session.closeApp("app.example")
        XCTAssertTrue(closed)
        await api.release("/api/apps")
        await oldRead.value
        XCTAssertEqual(session.appsOverview?.running?.map(\.id), ["app.other"])
    }

    func testRecentOrderAndBackgroundArePreservedWithoutDuplicates() throws {
        let recent = try JSONDecoder().decode(RecentAppsPayload.self, from: Data(#"{"ok":true,"apps":[{"id":"stopped","title":"Stopped"},{"id":"app.example","title":"Recent title"},{"id":"app.example","title":"Duplicate"}]}"#.utf8))
        let running = try JSONDecoder().decode(AppsOverview.self, from: overview)
        let list = AppActivityList(recents: recent.apps ?? [], running: running.running ?? [])
        XCTAssertEqual(list.recents.map(\.id), ["stopped", "app.example"])
        XCTAssertNil(list.recents.first?.running)
        XCTAssertEqual(list.recents.last?.title, "Recent title")
        XCTAssertEqual(list.recents.last?.running?.mb, 42)
        XCTAssertEqual(list.recents.last?.running?.foreground, true)
        XCTAssertEqual(list.background.map(\.id), ["app.other"])
    }

    func testEmptyRecentsStillShowsAllRunningAppsInBackground() throws {
        let running = try JSONDecoder().decode(AppsOverview.self, from: overview)
        let list = AppActivityList(recents: [], running: running.running ?? [])
        XCTAssertTrue(list.recents.isEmpty)
        XCTAssertEqual(list.background.map(\.id), ["app.example", "app.other"])
    }

    func testClosingStoppedRecentRemovesCardThroughRecentsRoute() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.serve("/api/home/recents", Data(#"{"ok":true,"apps":[{"id":"stopped","title":"Stopped"}]}"#.utf8))
        await session.refreshApps()
        let closed = await session.closeApp("stopped")
        XCTAssertTrue(closed)
        XCTAssertEqual(session.recentApps?.apps?.count, 0)
        let calls = await api.closedRecentApps
        XCTAssertEqual(calls, ["stopped"])
    }

    func testClosingRunningRecentRemovesCardAndProcess() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.serve("/api/home/recents", Data(#"{"ok":true,"apps":[{"id":"app.example","title":"Example"}]}"#.utf8))
        await session.refreshApps()
        let closed = await session.closeApp("app.example")
        XCTAssertTrue(closed)
        XCTAssertTrue(session.recentApps?.apps?.isEmpty == true)
        XCTAssertEqual(session.appsOverview?.running?.map(\.id), ["app.other"])
        let calls = await api.closedRecentApps
        XCTAssertEqual(calls, ["app.example"])
    }

    func testRefusedRecentReadDisablesCardRemoval() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.serve("/api/home/recents", Data(#"{"ok":true,"apps":[{"id":"app.example","title":"Example"}]}"#.utf8))
        await session.refreshApps()
        await api.serve("/api/home/recents", Data(#"{"ok":false,"error":"Unavailable"}"#.utf8))
        await session.refreshApps()
        let closed = await session.closeApp("app.example")
        XCTAssertFalse(closed)
        let calls = await api.closedRecentApps
        XCTAssertTrue(calls.isEmpty)
    }

    func testForegroundMissingFromRecentsDoesNotMoveToBackground() throws {
        let running = try JSONDecoder().decode(AppsOverview.self, from: overview)
        let list = AppActivityList(recents: [], running: running.running ?? [], foregroundID: "app.example")
        XCTAssertEqual(list.recents.map(\.id), ["app.example"])
        XCTAssertTrue(list.recents[0].onScreen)
        XCTAssertEqual(list.background.map(\.id), ["app.other"])
        XCTAssertFalse(list.background[0].onScreen)
    }

    func testStaleForegroundFlagsDoNotMarkMultipleAppsOnScreen() throws {
        let running = try JSONDecoder().decode(AppsOverview.self, from: Data(#"{"running":[{"id":"a","title":"A","foreground":true},{"id":"b","title":"B","foreground":true}]}"#.utf8))
        let home = AppActivityList(recents: [], running: running.running ?? [])
        XCTAssertFalse(home.background.contains(where: \.onScreen))
        let active = AppActivityList(recents: [], running: running.running ?? [], foregroundID: "b")
        XCTAssertEqual(active.recents.filter(\.onScreen).map(\.id), ["b"])
        XCTAssertFalse(active.background.contains(where: \.onScreen))
    }

    func testCloseRemovesCardCreatedWhenForegroundAppLeaves() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.createRecentOnClose()
        let closed = await session.closeApp("app.example")
        XCTAssertTrue(closed)
        XCTAssertTrue(session.recentApps?.apps?.isEmpty == true)
        XCTAssertEqual(session.appsOverview?.running?.map(\.id), ["app.other"])
        let calls = await api.closedRecentApps
        XCTAssertEqual(calls, ["app.example"])
    }

    func testLeavingForegroundKeepsAppAboveBackgroundUntilFreshListArrives() throws {
        let running = try JSONDecoder().decode(AppsOverview.self, from: overview)
        let transition = RecentApp(id: "app.example", title: "Example")
        let list = AppActivityList(recents: [], running: running.running ?? [], transition: transition)
        XCTAssertEqual(list.recents.map(\.id), ["app.example"])
        XCTAssertFalse(list.recents[0].onScreen)
        XCTAssertEqual(list.background.map(\.id), ["app.other"])
        let settled = AppActivityList(recents: [transition], running: running.running ?? [], transition: transition)
        XCTAssertEqual(settled.recents.map(\.id), ["app.example"])
    }

    func testCloseAllIncludesStoppedRecentsAndBackgroundWithoutDuplicates() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.serve("/api/home/recents", Data(#"{"ok":true,"apps":[{"id":"stopped","title":"Stopped"},{"id":"app.example","title":"Example"}]}"#.utf8))
        await session.refreshApps()
        XCTAssertTrue(session.canCloseAllApps)
        let closed = await session.closeAllApps()
        XCTAssertTrue(closed)
        let calls = await api.closedApps
        XCTAssertEqual(calls, ["stopped", "app.example", "app.other"])
        XCTAssertTrue(session.recentApps?.apps?.isEmpty == true)
        XCTAssertTrue(session.appsOverview?.running?.isEmpty == true)
        XCTAssertFalse(session.isClosingAllApps)
        XCTAssertFalse(session.canCloseAllApps)
    }

    func testCloseAllContinuesAfterOneFailureAndKeepsFailedApp() async {
        let api = FakeAPI()
        let session = await ready(api)
        await api.serve("/api/home/recents", Data(#"{"ok":true,"apps":[]}"#.utf8))
        await session.refreshApps()
        await api.failClosing("app.example", .rejected("Refused"))
        let closed = await session.closeAllApps()
        XCTAssertFalse(closed)
        XCTAssertEqual(session.appsOverview?.running?.map(\.id), ["app.example"])
        let calls = await api.closedApps
        XCTAssertEqual(calls, ["app.example", "app.other"])
        XCTAssertNotNil(session.transientMessage)
        XCTAssertFalse(session.isClosingAllApps)
    }

    func testCloseAllRefusesStaleOrIncompleteLists() async {
        let api = FakeAPI()
        let session = await ready(api)
        XCTAssertFalse(session.canCloseAllApps)
        let incomplete = await session.closeAllApps()
        XCTAssertFalse(incomplete)
        await api.serve("/api/home/recents", Data(#"{"ok":true,"apps":[]}"#.utf8))
        await session.refreshApps()
        session.markStale()
        let stale = await session.closeAllApps()
        XCTAssertFalse(stale)
        let calls = await api.closedApps
        XCTAssertTrue(calls.isEmpty)
    }

    func testDemoLaunchAndCloseUpdateRecentAndMemoryLists() async throws {
        let demo = DemoTV()
        try await demo.send(.launchApp("netflix"))
        let running = try await demo.get("/api/apps", as: AppsOverview.self)
        XCTAssertTrue(running.running?.contains(where: { $0.id == "netflix" }) == true)
        let recents = try await demo.get("/api/home/recents", as: RecentAppsPayload.self)
        XCTAssertEqual(recents.apps?.first?.id, "netflix")
        try await demo.closeRecentApp(id: "netflix")
        let updated = try await demo.get("/api/apps", as: AppsOverview.self)
        XCTAssertFalse(updated.running?.contains(where: { $0.id == "netflix" }) == true)
        let stats = try await demo.get("/api/stats", as: Stats.self)
        XCTAssertFalse(stats.isForeground(appID: "netflix"))
    }

}
