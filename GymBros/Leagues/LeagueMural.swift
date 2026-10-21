import PhotosUI
import SwiftData
import SwiftUI

/// Mural da liga: recados dos participantes (com o bro de cada um) e os seus.
/// Os seus ficam no aparelho até o servidor aceitar (LeagueMessage.syncedAt).
struct LeagueMuralView: View {
    let league: League
    let avatar: MonsterForm
    @Environment(\.modelContext) private var context
    @Query(sort: \LeagueMessage.date, order: .reverse) private var allMessages: [LeagueMessage]
    @AppStorage("trainerName") private var trainerName = ""
    @State private var text = ""
    @State private var menu: LeagueMessage?
    @State private var moderation: ModerationRequest?
    @State private var blocked = false
    @State private var terms = TermsGate()
    @State private var mode = 0
    @State private var pick: PhotosPickerItem?
    @State private var photo: Data?
    @State private var viewing: Data?
    @Query private var checkIns: [LeagueCheckIn]

    private struct Line: Identifiable {
        let id: String
        var memberID = "me"
        let name: String
        let form: MonsterForm
        let isMe: Bool
        let date: Date
        let text: String
        var pending = false
        var mine: LeagueMessage?
        var photo: Data?
    }

    var body: some View {
        let lines = merged
        VStack(alignment: .leading, spacing: 16) {
            GMSegmented(options: [(0, "Conversa"), (1, "Mídia")], selection: $mode)
            if mode == 1 {
                mediaGrid(lines)
            } else {
            if !league.isOver { composer }
            if lines.isEmpty {
                GMEmptyState(icon: "bubble.left.and.bubble.right", title: "Mural vazio", message: "Mande o primeiro recado pra galera da liga.")
            }
            let cal = Calendar.current
            let days = Dictionary(grouping: lines.prefix(150)) { cal.startOfDay(for: $0.date) }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: 10) {
                    Text(dayTitle(day)).font(.headline)
                    ForEach(days[day]!.sorted { $0.date > $1.date }) { bubble($0) }
                }
            }
            }
        }
        .onChange(of: pick) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self) { photo = compressedPhoto(d) } }
        }
        .gmModal(item: Binding(get: { viewing.map(PhotoBox.init) }, set: { viewing = $0?.data })) { box in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()
                if let img = UIImage(data: box.data) { Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                GMIconButton(icon: "xmark", label: "Fechar") { viewing = nil }.padding(16)
            }
        }
        .gmActions(isPresented: Binding(get: { menu != nil }, set: { if !$0 { menu = nil } }), title: "Recado", actions: menu.map { m in [
            GMAction("Apagar recado", icon: "trash", destructive: true) {
                context.delete(m)
                try? context.save()
            }
        ] } ?? [])
        .moderation($moderation)
        .termsGate($terms)
        .onChange(of: text) { blocked = false }
    }

    private var merged: [Line] {
        let remote = LeagueRemoteStore.shared.remote(league)
        let others = ModerationStore.shared.visible(remote.messages).compactMap { m -> Line? in
            guard let who = remote.member(m.memberID) else { return nil }
            return Line(id: m.id, memberID: who.id, name: who.name, form: who.form, isMe: false, date: m.date, text: m.text)
        }
        let mine = allMessages.filter { $0.leagueUUID == league.uuid }.map {
            Line(id: $0.uuid.uuidString, name: trainerName.isEmpty ? "Você" : trainerName, form: avatar, isMe: true, date: $0.date,
                 text: $0.text, pending: $0.syncedAt == nil, mine: $0, photo: $0.photo)
        }
        return others + mine
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let photo, let img = UIImage(data: photo) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 90, height: 90).clipShape(.rect(cornerRadius: Theme.radiusM))
                    .overlay(alignment: .topTrailing) {
                        Button { self.photo = nil; pick = nil } label: {
                            Image(systemName: "xmark").font(.caption2.bold()).frame(width: 22, height: 22).background(.black.opacity(0.6), in: .circle).foregroundStyle(.white)
                        }
                        .buttonStyle(GMPress()).padding(3)
                    }
            }
            composerField
            if blocked { ContentBlockedNote() }
        }
    }

    /// Fotos do mural e dos check-ins da liga
    @ViewBuilder
    private func mediaGrid(_ lines: [Line]) -> some View {
        let fromMural = lines.compactMap(\.photo)
        let fromCheckIns = checkIns.filter { $0.leagueUUID == league.uuid }.sorted { $0.date > $1.date }.flatMap(\.photos)
        let all = Array((fromMural + fromCheckIns).prefix(120))
        if all.isEmpty {
            GMEmptyState(icon: "photo.on.rectangle", title: "Nenhuma foto ainda", message: "Fotos do mural e dos check-ins aparecem aqui.")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(Array(all.enumerated()), id: \.offset) { _, data in
                    Button { viewing = data } label: {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay { if let img = UIImage(data: data) { Image(uiImage: img).resizable().scaledToFill() } }
                            .clipShape(.rect(cornerRadius: Theme.radiusS))
                    }
                    .buttonStyle(GMPress())
                }
            }
        }
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $pick, matching: .images) {
                Image(systemName: "photo").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40)
                    .background(Theme.raised, in: .circle).foregroundStyle(.white)
            }
            .buttonStyle(GMPress())
            .accessibilityLabel("Mandar foto")
            GMTextField(placeholder: "Escrever no mural…", text: $text, axis: .vertical)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
                    .accessibilityLabel("Enviar")
                    .background(canSend ? Theme.accent : Theme.raised, in: .circle)
                    .foregroundStyle(canSend ? .black : Theme.dim)
            }
            .buttonStyle(GMPress())
            .disabled(!canSend)
        }
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || photo != nil else { return }
        guard AccessStore.shared.can(.messagesPublish) else { return }
        guard ContentFilter.allows(t) else { blocked = true; return }
        terms.run { publish(t) }
    }

    private func publish(_ t: String) {
        let m = LeagueMessage(leagueUUID: league.uuid, text: t)
        m.photo = photo
        context.insert(m)
        try? context.save()
        text = ""
        photo = nil
        pick = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await LeagueRemoteStore.shared.flush(context: context) }
    }

    private func bubble(_ l: Line) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if l.isMe { Spacer(minLength: 40) } else { MonsterSprite(form: l.form).frame(width: 32, height: 32) }
            VStack(alignment: l.isMe ? .trailing : .leading, spacing: 3) {
                if !l.isMe { Text(l.name).font(.caption.weight(.bold)).foregroundStyle(Theme.dim) }
                if let data = l.photo, let img = UIImage(data: data) {
                    Button { viewing = data } label: {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 180, height: 180).clipShape(.rect(cornerRadius: Theme.radiusL))
                    }
                    .buttonStyle(GMPress())
                }
                if !l.text.isEmpty {
                Text(mentionText(l.text))
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(l.isMe ? Theme.accent : Theme.card, in: .rect(cornerRadius: Theme.radiusL))
                    .foregroundStyle(l.isMe ? .black : .white)
                }
                HStack(spacing: 4) {
                    if l.pending { Image(systemName: "clock") }
                    Text(l.date.formatted(.dateTime.hour().minute()))
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
            }
            .onLongPressGesture {
                if let m = l.mine {
                    menu = m
                } else if !l.isMe {
                    moderation = ModerationRequest(target: ModerationTarget(userID: l.memberID, userName: l.name, content: .message, id: l.id))
                }
            }
            if l.isMe { MonsterSprite(form: l.form).frame(width: 32, height: 32) } else { Spacer(minLength: 40) }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Hoje" }
        if cal.isDateInYesterday(day) { return "Ontem" }
        let s = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

private struct PhotoBox: Identifiable {
    let data: Data
    var id: Int { data.hashValue }
}
