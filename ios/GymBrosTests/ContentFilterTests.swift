import SwiftData
import XCTest
@testable import GymBros

/// Filtro de palavras: pega variações comuns e deixa passar palavras inocentes
final class ContentFilterTests: GymTestCase {
    func testBlocksOffensiveTermsInPortugueseAndEnglish() {
        for text in ["Que treino de merda", "vai se matar", "you piece of shit", "kill yourself", "FDP", "seu otário"] {
            XCTAssertFalse(ContentFilter.allows(text), text)
        }
    }

    func testNormalizesAccentsCaseAndCommonSwaps() {
        for text in ["CUZÃO", "P0RR4", "c@ralho", "$h1t", "merda!", "Merdaaa", "porrraaa", "p u t a", "putaria123", "Fucking hell"] {
            XCTAssertFalse(ContentFilter.allows(text), text)
        }
    }

    func testRespectsWordBoundaries() {
        let innocent = ["computador", "Scunthorpe", "class", "assessoria", "cuidado", "escuta", "putativo", "Fagundes",
                        "as pernas", "Bora treinar!", "3x10 supino", "Dia de perna 🦵", "e o a", "Cucumber", "Shiitake", ""]
        for text in innocent {
            XCTAssertTrue(ContentFilter.allows(text), text)
        }
    }

    func testPrefixTermsAndCustomList() {
        XCTAssertEqual(ContentFilter.match(in: "caralhooo", terms: ["caralho*"]), "caralho*")
        XCTAssertNil(ContentFilter.match(in: "caralh", terms: ["caralho*"]))
        XCTAssertEqual(ContentFilter.match(in: "abc frango xyz", terms: ["frango"]), "frango")
        XCTAssertNil(ContentFilter.match(in: "frangos", terms: ["frango"]))
        XCTAssertEqual(ContentFilter.match(in: "nossa, dia de perna", terms: ["dia de perna"]), "dia de perna")
    }

    func testEveryListedTermIsCaughtByItself() {
        for term in BlockedTerms.all {
            let plain = term.hasSuffix("*") ? String(term.dropLast()) : term
            XCTAssertFalse(ContentFilter.allows(plain), term)
        }
    }

    func testPublishableBlanksBlockedText() {
        XCTAssertEqual(ContentFilter.publishable("Zero"), "Zero")
        XCTAssertEqual(ContentFilter.publishable("Rei da porra"), "")
    }

    func testBlockedCheckInIsNotPosted() throws {
        let ctx = try memoryContext()
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        ctx.insert(activity)
        postCheckIns(activity: activity, leagues: [ProfileFeed.id], title: "Corrida de merda", note: "", photo: nil, context: ctx, signedIn: true)
        postCheckIns(activity: activity, leagues: [ProfileFeed.id], title: "Corrida", note: "vai se matar", photo: nil, context: ctx, signedIn: true)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<LeagueCheckIn>()), 0)

        postCheckIns(activity: activity, leagues: [ProfileFeed.id], title: "Corrida", note: "Bora", photo: nil, context: ctx, signedIn: true)
        let post = try XCTUnwrap(ctx.fetch(FetchDescriptor<LeagueCheckIn>()).first)

        syncCheckIns(activity: activity, destinations: [ProfileFeed.id], title: "Merda", note: "", photo: nil, place: nil, context: ctx, signedIn: true)
        XCTAssertEqual(post.title, "Corrida")
        XCTAssertEqual(post.note, "Bora")
    }

    func testRemovingDestinationsIgnoresFilter() throws {
        let ctx = try memoryContext()
        let activity = Activity(kind: .corrida, date: .now, minutes: 30, effort: 5)
        ctx.insert(activity)
        let league = UUID()
        ctx.insert(LeagueCheckIn(leagueUUID: ProfileFeed.id, activityUUID: activity.uuid, title: "Treino de merda", note: "", date: .now, photo: nil))
        ctx.insert(LeagueCheckIn(leagueUUID: league, activityUUID: activity.uuid, title: "Treino de merda", note: "", date: .now, photo: nil))

        syncCheckIns(activity: activity, destinations: [league], title: "Treino de merda", note: "", photo: nil, place: nil, context: ctx, signedIn: true)
        let kept = try ctx.fetch(FetchDescriptor<LeagueCheckIn>())
        XCTAssertEqual(kept.map(\.leagueUUID), [league])
        XCTAssertEqual(kept.first?.title, "Treino de merda")

        syncCheckIns(activity: activity, destinations: [], title: "Treino de merda", note: "", photo: nil, place: nil, context: ctx, signedIn: true)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<LeagueCheckIn>()), 0)
    }
}
