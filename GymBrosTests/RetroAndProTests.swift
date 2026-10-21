import AVFoundation
import XCTest
@testable import GymBros

/// Retrospectiva em vídeo, exportar a liga, Pro e "Vem aí"
@MainActor
final class RetroAndProTests: GymTestCase {
    func testRetrospectiveVideoHasIntroPhotosAndEnd() async throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { _ in
            UIColor.green.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let url = try await RetroVideo.make(photos: [photo, photo], intro: ["3 treinos"], title: "2026 no GymBros", watermark: "@bro · GymBros",
                                            format: .square, speed: .superFast) { _ in }
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let seconds = try await asset.load(.duration).seconds
        // Abertura 2,4 s + 2 fotos de 0,35 s + fim 1,8 s
        XCTAssertEqual(seconds, 4.9, accuracy: 0.2)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await track?.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1080, height: 1080))
    }

    func testLeagueExportCSV() throws {
        let l = MockLeague.make()
        let feed = LeagueBoard.feed(league: l, mine: [], activities: [:], me: "Eu", myAvatar: .egg, remote: MockLeagueBackend.build(l.key), reviews: [])
        let url = try XCTUnwrap(LeagueExport.csv(league: l, feed: feed))
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.first, "data;pessoa;titulo;atividade;minutos;pontos;foto;situacao")
        XCTAssertEqual(lines.count, feed.count + 1)
    }

    func testProUnlocksEverythingUntilEnforced() {
        XCTAssertFalse(ProStore.enforced)
        XCTAssertTrue(ProFeature.allCases.allSatisfy { ProStore.shared.allows($0) })
    }

    func testComingSoonVotesToggle() {
        let d = scratchDefaults("vem")
        ComingFeedback.set("premios", interested: true, d)
        XCTAssertEqual(ComingFeedback.all(d)["premios"], true)
        ComingFeedback.set("premios", interested: nil, d)
        XCTAssertNil(ComingFeedback.all(d)["premios"])
        XCTAssertEqual(Set(ComingFeature.all.map(\.id)).count, ComingFeature.all.count)
    }
}
