import XCTest
@testable import PaneKit

@MainActor
final class AppIconStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Records the apps asked for and answers `icon` (nil: the TV gave none).
    private actor Fetches {
        private(set) var asked: [String] = []
        var icon: Data?
        init(_ icon: Data?) { self.icon = icon }
        func fetch(_ id: String) -> Data? { asked.append(id); return icon }
        func answer(_ icon: Data?) { self.icon = icon }
    }

    private let png = Fixture.data("app-icon.png")

    func testFetchedIconIsShownAndKeptOnDisk() async {
        let fetches = Fetches(png)
        let store = AppIconStore(directory: directory)
        XCTAssertNil(store.icon(for: "com.example.app"))
        await store.refresh(["com.example.app"]) { await fetches.fetch($0) }
        XCTAssertEqual(store.icon(for: "com.example.app"), png)
        XCTAssertEqual(AppIconStore(directory: directory).icon(for: "com.example.app"), png)
    }

    func testEachAppIsAskedOncePerLaunch() async {
        let fetches = Fetches(png)
        let store = AppIconStore(directory: directory)
        await store.refresh(["a", "b", "a"]) { await fetches.fetch($0) }
        await store.refresh(["a", "b"]) { await fetches.fetch($0) }
        let asked = await fetches.asked
        XCTAssertEqual(asked, ["a", "b"])
    }

    func testCachedIconIsAskedAgainAtLaunch() async {
        let fetches = Fetches(png)
        await AppIconStore(directory: directory).refresh(["a"]) { await fetches.fetch($0) }
        let newer = Data("newer".utf8)
        await fetches.answer(newer)
        let store = AppIconStore(directory: directory)
        await store.refresh(["a"]) { await fetches.fetch($0) }
        XCTAssertEqual(store.icon(for: "a"), newer)
    }

    func testMissingIconIsAskedAgainAndKeepsTheCachedOne() async {
        let fetches = Fetches(png)
        await AppIconStore(directory: directory).refresh(["a"]) { await fetches.fetch($0) }
        await fetches.answer(nil)
        let store = AppIconStore(directory: directory)
        await store.refresh(["a"]) { await fetches.fetch($0) }
        await store.refresh(["a"]) { await fetches.fetch($0) }
        XCTAssertEqual(store.icon(for: "a"), png)
        let asked = await fetches.asked
        XCTAssertEqual(asked, ["a", "a", "a"])
    }

    func testEmptyAnswerIsNoIcon() async {
        let fetches = Fetches(Data())
        let store = AppIconStore(directory: directory)
        await store.refresh(["a"]) { await fetches.fetch($0) }
        XCTAssertNil(store.icon(for: "a"))
    }

    func testAnyAppIDMakesOneFileInTheDirectory() async throws {
        let fetches = Fetches(png)
        await AppIconStore(directory: directory).refresh(["../x/y", "."]) { await fetches.fetch($0) }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 2)
        let store = AppIconStore(directory: directory)
        XCTAssertEqual(store.icon(for: "../x/y"), png)
        XCTAssertEqual(store.icon(for: "."), png)
    }

    func testEdgeColourComesWithTheIcon() async {
        let fetches = Fetches(Fixture.data("app-icon-red.png"))
        let store = AppIconStore(directory: directory)
        XCTAssertNil(store.edge(for: "a"))
        await store.refresh(["a"]) { await fetches.fetch($0) }
        XCTAssertEqual(store.edge(for: "a"), IconColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(AppIconStore(directory: directory).edge(for: "a"), IconColor(red: 1, green: 0, blue: 0))
    }

    func testWithoutDirectoryIconsLiveInMemory() async {
        let fetches = Fetches(png)
        let store = AppIconStore(directory: nil)
        await store.refresh(["a"]) { await fetches.fetch($0) }
        XCTAssertEqual(store.icon(for: "a"), png)
    }
}
