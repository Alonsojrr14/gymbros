import SwiftData
import SwiftUI

/// Comentário (ou reação) num check-in de liga. Por enquanto fica só neste aparelho.
@Model
final class CheckInComment {
    var uuid: UUID = UUID()
    /// `FeedItem.id` do check-in (o seu ou o de um participante simulado)
    var itemID: String = ""
    var text: String = ""
    var date: Date = Date.now
    /// Quem escreveu: "me" (você) ou o `memberID` de outra pessoa. Comentários antigos não tinham autor: são seus.
    var authorID: String = "me"
    /// Nome de quem escreveu quando não é você (o seu vem sempre do nome atual)
    var authorName: String = ""

    init(itemID: String, text: String, authorID: String = "me", authorName: String = "") {
        self.itemID = itemID
        self.text = text
        self.authorID = authorID
        self.authorName = authorName
    }

    var isMine: Bool { authorID == "me" }
}

/// Tela cheia de um check-in: foto em destaque, autor, título, detalhes e comentários
struct CheckInDetailView: View {
    let item: FeedItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var checkIns: [LeagueCheckIn]
    @Query(sort: \CheckInComment.date) private var allComments: [CheckInComment]
    @AppStorage("trainerName") private var trainerName = ""
    @State private var text = ""
    @State private var menu = false
    @State private var editing: Activity?
    @Query private var activities: [Activity]
    @State private var confirmDelete = false
    @State private var reacting = false
    @State private var commentMenu: CheckInComment?
    @FocusState private var typing: Bool

    private var mine: LeagueCheckIn? { item.isMe ? checkIns.first { $0.uuid.uuidString == item.id } : nil }
    private var comments: [CheckInComment] { allComments.filter { $0.itemID == item.id } }
    /// Dados atuais (o check-in pode ter sido editado depois de aberto)
    private var title: String { mine?.title ?? item.title }
    private var note: String { mine?.note ?? item.note }
    private var photo: Data? { item.isMe ? mine?.photo : item.photo }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    VStack(alignment: .leading, spacing: 14) {
                        author
                        Text(title).gmFont(26, weight: .heavy, design: .rounded, relativeTo: .title)
                        if !note.isEmpty { Text(note).font(.body).foregroundStyle(.white.opacity(0.85)) }
                        chips
                        if !comments.isEmpty { commentList }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            composer
        }
        .background(Theme.bg.ignoresSafeArea())
        .gmActions(isPresented: $menu, title: title, actions: menuActions)
        .gmActions(isPresented: $confirmDelete, title: "Apagar check-in?",
                   message: "Sai desta liga. A atividade continua no seu histórico.", actions: [
            GMAction("Apagar check-in", icon: "trash", destructive: true) {
                if let c = mine {
                    LeagueOutbox.retract(c)
                    context.delete(c)
                }
                comments.forEach(context.delete)
                try? context.save()
                dismiss()
            }
        ])
        // Edita a atividade e o post juntos: destinos (perfil e ligas), título, foto e local
        .gmModal(item: $editing) { LogActivityView(snapshot: Snapshot(), editing: $0) }
        .gmActions(isPresented: Binding(get: { commentMenu != nil }, set: { if !$0 { commentMenu = nil } }), title: "Comentário",
                   actions: commentMenu.map { c in [
                       GMAction("Apagar comentário", icon: "trash", destructive: true) {
                           context.delete(c)
                           try? context.save()
                       }
                   ] } ?? [])
    }

    private var menuActions: [GMAction] {
        var list = [GMAction("Compartilhar", icon: "square.and.arrow.up") { share() }]
        if let c = mine {
            if let a = activities.first(where: { $0.uuid == c.activityUUID }) {
                list.append(GMAction("Editar", icon: "pencil") { editing = a })
            }
            list.append(GMAction("Apagar check-in", icon: "trash", destructive: true) { confirmDelete = true })
        }
        return list
    }

    // MARK: Foto

    private var hero: some View {
        ZStack {
            if let data = photo, let img = UIImage(data: data) {
                // Fundo borrado da própria foto, como nos apps de feed
                Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill().blur(radius: 40).opacity(0.7) }
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                LinearGradient(colors: [(item.isMe ? Theme.accent : Color.white).opacity(0.25), Theme.card], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 10) {
                    MonsterSprite(form: item.avatar).frame(width: 150, height: 150)
                    Label(item.kind.name, systemImage: item.kind.symbol).font(.headline).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: photo == nil ? 300 : 460)
        .clipped()
        .overlay(alignment: .top) {
            HStack {
                GMIconButton(icon: "chevron.left") { dismiss() }
                Spacer()
                GMIconButton(icon: "ellipsis") { menu = true }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .clipShape(.rect(bottomLeadingRadius: Theme.radius, bottomTrailingRadius: Theme.radius))
    }

    // MARK: Autor e detalhes

    private var author: some View {
        HStack(spacing: 12) {
            avatar(me: item.isMe, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isMe ? (trainerName.isEmpty ? "Você" : trainerName) : item.name).font(.headline)
                Text(when(item.date) + (item.place.map { " · \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(Theme.dim).lineLimit(2)
            }
            Spacer()
            Image(systemName: photo == nil ? item.kind.symbol : "photo.fill").font(.title3)
        }
    }

    private var chips: some View {
        GMFlow {
            chip(icon: "stopwatch", text: durationText(item.minutes))
            chip(icon: item.kind.symbol, text: item.kind.name)
            chip(icon: "bolt.fill", text: "+" + (item.scoring.map { $0.format(item.score) } ?? "\(item.score) XP"), tint: Theme.accent)
            if let place = item.place { chip(icon: "mappin.and.ellipse", text: place) }
        }
    }

    private func chip(icon: String, text: String, tint: Color = .white) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.raised, in: .capsule)
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func avatar(me: Bool, size: CGFloat) -> some View {
        if me {
            Avatar(size: size)
        } else {
            MonsterSprite(form: item.avatar).frame(width: size * 0.8, height: size * 0.8)
                .frame(width: size, height: size).background(Theme.raised, in: .circle)
        }
    }

    // MARK: Comentários

    private var commentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            GMDivider()
            ForEach(comments) { c in
                HStack(alignment: .top, spacing: 10) {
                    if c.isMine { Avatar(size: 32) } else { PersonAvatar(name: c.authorName, size: 32) }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(c.isMine ? (trainerName.isEmpty ? "Você" : trainerName) : c.authorName).font(.caption.bold())
                            Text(c.date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Theme.dim)
                        }
                        Text(c.text).font(isEmojiOnly(c.text) ? .title : .subheadline)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                // Só dá para apagar o que é seu
                .onLongPressGesture { if c.isMine { commentMenu = c } }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if reacting {
                HStack {
                    ForEach(["💪", "🔥", "👏", "😮‍💨", "🏆", "❤️"], id: \.self) { e in
                        Button { send(e); reacting = false } label: { Text(e).font(.system(size: 30)) }
                            .buttonStyle(GMPress())
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)
                .background(Theme.card, in: .capsule)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                HStack {
                    TextField("", text: $text, prompt: Text("Comentar…").foregroundStyle(Theme.dim), axis: .vertical)
                        .lineLimit(1...4)
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit { send(text) }
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { send(text) } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.card, in: .capsule)
                Button { withAnimation(.snappy) { reacting.toggle() } } label: {
                    Image(systemName: reacting ? "xmark" : "face.smiling")
                        .font(.title2)
                        .frame(width: 50, height: 50)
                        .background(Theme.card, in: .circle)
                        .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func send(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        context.insert(CheckInComment(itemID: item.id, text: t))
        try? context.save()
        if raw == text { text = "" }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func isEmojiOnly(_ s: String) -> Bool {
        s.count <= 3 && s.unicodeScalars.allSatisfy { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C || $0.value == 0x200D || $0.value == 0xFE0F }
    }

    private func when(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(d) { return "Hoje, \(time)" }
        if cal.isDateInYesterday(d) { return "Ontem, \(time)" }
        return "\(d.formatted(.dateTime.weekday().day().month(.abbreviated))), \(time)"
    }

    private func share() {
        var items: [Any] = ["\(title) · \(item.kind.name), \(durationText(item.minutes)) no GymBros 💪"]
        if let data = photo, let img = UIImage(data: data) { items.insert(img, at: 0) }
        presentShare(items)
    }
}
