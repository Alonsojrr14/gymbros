import SwiftData
import UIKit
import WidgetKit

/// Grava para o widget o check-in mais recente das suas ligas (de qualquer pessoa, você incluído)
@MainActor
enum BrosWidgetFeed {
    static let kind = "GymBrosBros"

    static func update(context: ModelContext, me: String = UserDefaults.standard.string(forKey: "trainerName") ?? "") {
        let leagues = ((try? context.fetch(FetchDescriptor<League>())) ?? []).filter { !$0.isPastSeason }
        let checkIns = (try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []
        let activities = Dictionary(((try? context.fetch(FetchDescriptor<Activity>())) ?? []).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        var latest: (FeedItem, League)?
        for l in leagues {
            let feed = ModerationStore.shared.visible(LeagueBoard.feed(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid },
                                                                        activities: activities, me: me, myAvatar: .egg))
            if let f = feed.first(where: { !$0.pending }), f.date > (latest?.0.date ?? .distantPast) { latest = (f, l) }
        }
        guard let (f, l) = latest else { BrosPost.clear(); return WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        // O seu aparece com o bro que te representa na liga
        let form = f.isMe ? MonsterForm.byID(((try? context.fetch(FetchDescriptor<Monster>())) ?? []).first { $0.uuid == l.monsterUUID }?.lastFormID ?? "") ?? f.avatar : f.avatar
        BrosPost(name: f.isMe ? "Você" : f.name, sprite: form.sprite, title: f.title, place: "\(l.emoji) \(l.name)", date: f.date,
                 photo: f.photo.flatMap(small)).save()
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    /// Foto reduzida para caber no widget
    private static func small(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let side: CGFloat = 600
        let s = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        return UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.7)
    }
}

/// Treinos importados do Apple Saúde viram check-in sozinhos (se você ligar): perfil e ligas que aceitam, um check-in por dia
@MainActor
enum HealthAutoPost {
    static let key = "health.autoPost"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    static func post(_ imported: [Activity], context: ModelContext, title: String? = nil) {
        guard isOn, Terms.canPublish, !imported.isEmpty else { return }
        let leagues = ((try? context.fetch(FetchDescriptor<League>())) ?? []).filter { $0.hasStarted && !$0.isOver && !$0.isPastSeason }
        let posted = Set(((try? context.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []).map(\.activityUUID))
        let cal = Calendar.current
        for (_, day) in Dictionary(grouping: imported.filter { !posted.contains($0.uuid) }, by: { cal.startOfDay(for: $0.date) }) {
            let sorted = day.sorted { $0.minutes > $1.minutes }
            guard let main = sorted.first else { continue }
            var subject = PostSubject(activity: main)
            subject.photo = nil
            let targets = Set(leagues.filter { $0.problems(subject).isEmpty }.map(\.uuid)).union([ProfileFeed.id])
            postCheckIns(activity: main, leagues: targets, title: sorted.count > 1 ? sorted.map(\.typeName).joined(separator: " + ") : title ?? main.typeName,
                         note: "", photo: nil, context: context, grouped: Array(sorted.dropFirst()))
        }
        try? context.save()
    }
}
