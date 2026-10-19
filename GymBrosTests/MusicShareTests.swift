import XCTest
@testable import GymBros

private struct FakeProvider: NowPlayingProvider {
    let source: MusicSource
    var isAvailable = true
    var granted = true
    var track: NowPlayingTrack?

    func isAuthorized() async -> Bool { granted }
    func requestAccess() async -> Bool { granted }
    func current() async -> NowPlayingTrack? { granted ? track : nil }
}

@MainActor
final class MusicShareTests: XCTestCase {
    private let suite = "MusicShareTests"
    private var defaults: UserDefaults!
    private let song = NowPlayingTrack(title: "Till I Collapse", artist: "Eminem", source: .appleMusic)

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func store(granted: Bool = true, spotify: Bool = false) -> MusicShareStore {
        MusicShareStore(defaults: defaults, providers: [
            .appleMusic: FakeProvider(source: .appleMusic, granted: granted, track: song),
            .spotify: FakeProvider(source: .spotify, isAvailable: spotify),
        ])
    }

    func testOffByDefaultReadsNothing() async {
        let s = store()
        XCTAssertFalse(s.sharing)
        await s.refresh()
        XCTAssertNil(s.current)
    }

    func testTurningOnReadsTheCurrentSong() async {
        let s = store()
        await s.setSharing(true)
        XCTAssertTrue(s.sharing)
        XCTAssertEqual(s.current, song)
        await s.setSharing(false)
        XCTAssertFalse(s.sharing)
        XCTAssertNil(s.current)
    }

    func testDeniedAccessStaysOffWithMessage() async {
        let s = store(granted: false)
        await s.setSharing(true)
        XCTAssertFalse(s.sharing)
        XCTAssertNotNil(s.message)
    }

    func testSpotifyHiddenUntilRegistered() {
        XCTAssertEqual(store().availableSources, [.appleMusic])
        XCTAssertEqual(store(spotify: true).availableSources, [.appleMusic, .spotify])
        XCTAssertFalse(SpotifyNowPlaying().isAvailable)
    }

    func testMusicGoesWithTheAccount() {
        XCTAssertTrue(Set(MusicShareStore.defaultsKeys).isSubset(of: Set(AccountData.userKeys)))
    }
}
