import XCTest
@testable import PaneKit

/// Tokens in memory: no test touches the real keychain.
final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [UUID: String] = [:]

    func token(for id: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[id]
    }

    func setToken(_ token: String?, for id: UUID) {
        lock.lock(); defer { lock.unlock() }
        tokens[id] = token
    }
}

@MainActor
final class TVConfigStoreTests: XCTestCase {
    private func scratchDefaults() -> UserDefaults {
        let name = "PaneKitTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    func testUpsertPersistsAndActivatesFirst() {
        let defaults = scratchDefaults()
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(store.tvs, [])
        XCTAssertNil(store.active)

        let living = TVConfig(name: "Salon", host: "tv.local", port: 8080, mac: "00:11:22:33:44:55")
        let bedroom = TVConfig(name: "Chambre", host: "tv2.local", port: 8081, mac: nil)
        store.upsert(living, token: nil)
        store.upsert(bedroom, token: nil)
        XCTAssertEqual(store.activeID, living.id)
        XCTAssertEqual(store.active, living)

        var renamed = living
        renamed.name = "Grand salon"
        store.upsert(renamed, token: nil)
        XCTAssertEqual(store.tvs, [renamed, bedroom])

        store.activeID = bedroom.id
        let reloaded = TVConfigStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reloaded.tvs, [renamed, bedroom])
        XCTAssertEqual(reloaded.activeID, bedroom.id)
        XCTAssertEqual(reloaded.active, bedroom)
    }

    func testTokenGoesToSecretsNotDefaults() {
        let defaults = scratchDefaults()
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: defaults, secrets: secrets)
        let tv = TVConfig(name: "Salon", host: "tv.local", port: 8080, mac: nil)
        store.upsert(tv, token: "s3cret-t0ken")

        XCTAssertEqual(secrets.token(for: tv.id), "s3cret-t0ken")
        XCTAssertEqual(store.endpoint(for: tv), Endpoint(host: "tv.local", port: 8080, token: "s3cret-t0ken"))
        let dump = defaults.dictionaryRepresentation().values.map { value -> String in
            if let data = value as? Data { return String(decoding: data, as: UTF8.self) }
            return String(describing: value)
        }.joined(separator: "\n")
        XCTAssertTrue(dump.contains("tv.local"), "the TV itself is in the defaults")
        XCTAssertFalse(dump.contains("s3cret-t0ken"))

        store.upsert(tv, token: nil)
        XCTAssertNil(secrets.token(for: tv.id))
        XCTAssertNil(store.endpoint(for: tv).token)
    }

    func testUpdateKeepsTheTokenAndPersists() {
        let defaults = scratchDefaults()
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: defaults, secrets: secrets)
        var tv = TVConfig(name: "Salon", host: "tv.local", port: 8080, mac: nil)
        store.upsert(tv, token: "s3cret-t0ken")
        tv.mac = "00:11:22:33:44:55"
        store.update(tv)
        XCTAssertEqual(secrets.token(for: tv.id), "s3cret-t0ken")
        XCTAssertEqual(store.active, tv)
        XCTAssertEqual(TVConfigStore(defaults: defaults, secrets: secrets).active?.mac, "00:11:22:33:44:55")

        let stranger = TVConfig(name: "Ailleurs", host: "x.local")
        store.update(stranger)
        XCTAssertEqual(store.tvs, [tv], "update does not add a TV")
    }

    func testRemoveForgetsTheTVAndItsToken() {
        let defaults = scratchDefaults()
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: defaults, secrets: secrets)
        let living = TVConfig(name: "Salon", host: "tv.local")
        let bedroom = TVConfig(name: "Chambre", host: "tv2.local")
        store.upsert(living, token: "a")
        store.upsert(bedroom, token: "b")
        XCTAssertEqual(store.activeID, living.id)

        store.remove(living.id)
        XCTAssertEqual(store.tvs, [bedroom])
        XCTAssertNil(secrets.token(for: living.id))
        XCTAssertEqual(secrets.token(for: bedroom.id), "b")
        XCTAssertEqual(store.activeID, bedroom.id, "another TV takes over")

        store.remove(bedroom.id)
        XCTAssertEqual(store.tvs, [])
        XCTAssertNil(store.active)
        let reloaded = TVConfigStore(defaults: defaults, secrets: secrets)
        XCTAssertEqual(reloaded.tvs, [])
        XCTAssertNil(reloaded.activeID)
    }

    // MARK: Found TVs

    private func found(_ host: String, port: Int = 8080, token: String? = nil, mac: String? = nil) -> FoundTV {
        FoundTV(host: host, port: port, token: token, mac: mac, model: nil, version: "0.130.0")
    }

    func testAddingNewTVNamesItTVThenTV2() {
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: secrets)
        let a = store.add(found("192.0.2.10", token: "a", mac: "00:11:22:33:44:55"))
        let b = store.add(found("192.0.2.11", token: "b", mac: "00:11:22:33:44:66"))
        XCTAssertEqual(store.tvs.map(\.name), ["TV", "TV 2"])
        XCTAssertEqual(secrets.token(for: a.id), "a")
        XCTAssertEqual(secrets.token(for: b.id), "b")
        XCTAssertEqual(store.activeID, a.id)
        XCTAssertEqual(store.add(found("192.0.2.12"), name: "Salon").name, "Salon")
    }

    func testAddingKnownMACUpdatesInsteadOfDuplicating() {
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: secrets)
        let tv = TVConfig(name: "Salon", host: "192.0.2.10", mac: "00:11:22:33:44:55")
        store.upsert(tv, token: "old")
        let result = store.add(found("192.0.2.11", token: "n", mac: "00-11-22-33-44-55"))
        XCTAssertEqual(store.tvs.count, 1)
        XCTAssertEqual(result.id, tv.id)
        XCTAssertEqual(result.name, "Salon")
        XCTAssertEqual(store.tvs[0].host, "192.0.2.11")
        XCTAssertEqual(store.tvs[0].mac, "00:11:22:33:44:55")
        XCTAssertEqual(secrets.token(for: tv.id), "n")
    }

    func testAddingSameHostAndPortUpdates() {
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: MemorySecretStore())
        let tv = TVConfig(name: "Salon", host: "Tv.Local", port: 8080)
        store.upsert(tv, token: nil)
        store.add(found("tv.local", mac: "00-11-22-33-44-55"))
        XCTAssertEqual(store.tvs.count, 1)
        XCTAssertEqual(store.tvs[0].id, tv.id)
        XCTAssertEqual(store.tvs[0].mac, "00:11:22:33:44:55")
    }

    func testSameHostButDifferentKnownMACIsAnotherTV() {
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: MemorySecretStore())
        let tv = TVConfig(name: "Salon", host: "192.0.2.10", port: 8080, mac: "00:11:22:33:44:55")
        store.upsert(tv, token: nil)
        store.add(found("192.0.2.10", mac: "00:11:22:33:44:66"))
        XCTAssertEqual(store.tvs.count, 2)
        XCTAssertEqual(store.tvs[0].mac, "00:11:22:33:44:55")
    }

    func testAddingWithoutMACKeepsKnownMACAndNilTokenDeletes() {
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: secrets)
        let tv = TVConfig(name: "Salon", host: "192.0.2.10", mac: "00:11:22:33:44:55")
        store.upsert(tv, token: "old")
        store.add(found("192.0.2.10", token: nil))
        XCTAssertEqual(store.tvs[0].mac, "00:11:22:33:44:55")
        XCTAssertNil(secrets.token(for: tv.id))
    }

    func testSameHostOtherPortIsAnotherTV() {
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: MemorySecretStore())
        store.add(found("192.0.2.10"))
        store.add(found("192.0.2.10", port: 8081))
        XCTAssertEqual(store.tvs.count, 2)
    }

    func testTokensByHostSkipsEmptyLowercasesAndFirstWins() {
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: secrets)
        let a = TVConfig(name: "A", host: "Tv.Local")
        let b = TVConfig(name: "B", host: "192.0.2.11")
        let c = TVConfig(name: "C", host: "tv.local", port: 8081)
        let d = TVConfig(name: "D", host: "192.0.2.12")
        store.upsert(a, token: "first")
        store.upsert(b, token: nil)
        store.upsert(c, token: "second")
        store.upsert(d, token: "")
        XCTAssertEqual(store.tokensByHost, ["tv.local": "first"])
    }

    func testTokenForHostAndPort() {
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: MemorySecretStore())
        store.upsert(TVConfig(name: "A", host: "Tv.Local", port: 8080), token: "t")
        XCTAssertEqual(store.token(forHost: "tv.LOCAL", port: 8080), "t")
        XCTAssertNil(store.token(forHost: "tv.local", port: 8081))
        XCTAssertNil(store.token(forHost: "other", port: 8080))
    }

    func testOwnerOfAddressIsTheOtherTV() {
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: MemorySecretStore())
        let a = TVConfig(name: "A", host: "192.0.2.10")
        let b = TVConfig(name: "B", host: "192.0.2.11")
        store.upsert(a, token: nil)
        store.upsert(b, token: nil)
        XCTAssertEqual(store.owner(host: "192.0.2.10", port: 8080, excluding: b.id), a)
        XCTAssertNil(store.owner(host: "192.0.2.12", port: 8080, excluding: b.id))
    }

    func testOwnerIgnoresTheTVItselfAndCase() {
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: MemorySecretStore())
        let tv = TVConfig(name: "A", host: "TV.local")
        store.upsert(tv, token: nil)
        XCTAssertEqual(store.owner(host: "tv.local", port: 8080, excluding: UUID()), tv)
        XCTAssertNil(store.owner(host: "tv.local", port: 8080, excluding: tv.id))
    }

    func testOwnerNeedsTheSamePort() {
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: MemorySecretStore())
        store.upsert(TVConfig(name: "A", host: "192.0.2.10", port: 8080), token: nil)
        XCTAssertNil(store.owner(host: "192.0.2.10", port: 8081, excluding: UUID()))
    }

    func testSetTokenAndRename() {
        let secrets = MemorySecretStore()
        let store = TVConfigStore(defaults: scratchDefaults(), secrets: secrets)
        let tv = TVConfig(name: "Salon", host: "192.0.2.10")
        store.upsert(tv, token: nil)
        store.setToken("x", for: tv.id)
        XCTAssertEqual(store.token(for: tv.id), "x")
        store.setToken("", for: tv.id)
        XCTAssertNil(store.token(for: tv.id))
    }

    func testRenameTrimsAndIgnoresEmpty() {
        let defaults = scratchDefaults()
        let store = TVConfigStore(defaults: defaults, secrets: MemorySecretStore())
        let tv = TVConfig(name: "Salon", host: "192.0.2.10")
        store.upsert(tv, token: nil)
        store.rename(tv.id, to: "  Chambre \n")
        XCTAssertEqual(store.tvs[0].name, "Chambre")
        store.rename(tv.id, to: "   ")
        XCTAssertEqual(store.tvs[0].name, "Chambre")
        XCTAssertEqual(TVConfigStore(defaults: defaults, secrets: MemorySecretStore()).tvs[0].name, "Chambre")
    }

    func testReadsTVsWrittenByPlan2() {
        let defaults = scratchDefaults()
        let json = """
        [{"id":"1B4E28BA-2FA1-11D2-883F-B9A761BDE3FB","name":"Salon","host":"192.0.2.10","port":8080,"mac":"00:11:22:33:44:55"},\
        {"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","name":"Chambre","host":"192.0.2.11","port":8081}]
        """
        defaults.set(Data(json.utf8), forKey: "tvs")
        let store = TVConfigStore(defaults: defaults, secrets: MemorySecretStore())
        XCTAssertEqual(store.tvs, [
            TVConfig(id: UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-B9A761BDE3FB")!, name: "Salon", host: "192.0.2.10", port: 8080, mac: "00:11:22:33:44:55"),
            TVConfig(id: UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!, name: "Chambre", host: "192.0.2.11", port: 8081, mac: nil),
        ])
    }
}
