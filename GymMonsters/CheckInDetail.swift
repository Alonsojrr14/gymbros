import PhotosUI
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

    init(itemID: String, text: String) {
        self.itemID = itemID
        self.text = text
    }
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
    @State private var editing: LeagueCheckIn?
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
                        Text(title).font(.system(size: 26, weight: .heavy, design: .rounded))
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
                if let c = mine { context.delete(c) }
                comments.forEach(context.delete)
                try? context.save()
                dismiss()
            }
        ])
        .gmModal(item: $editing) { CheckInEditView(checkIn: $0) }
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
            list.append(GMAction("Editar", icon: "pencil") { editing = c })
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
            chip(icon: "bolt.fill", text: "+\(item.score)", tint: Theme.accent)
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
                    Avatar(size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(trainerName.isEmpty ? "Você" : trainerName).font(.caption.bold())
                            Text(c.date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Theme.dim)
                        }
                        Text(c.text).font(isEmojiOnly(c.text) ? .title : .subheadline)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onLongPressGesture { commentMenu = c }
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

/// Editar título, descrição e foto de um check-in seu
struct CheckInEditView: View {
    let checkIn: LeagueCheckIn
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var photo: Data?
    @State private var pick: PhotosPickerItem?
    @State private var loaded = false

    var body: some View {
        GMModal("Editar check-in", confirm: "Salvar", confirmEnabled: true, onConfirm: save) {
            GMSection("Post") {
                GMTextField(placeholder: "Título", text: $title)
                GMTextField(placeholder: "Descrição (opcional)", text: $note, axis: .vertical)
            }
            GMSection("Foto") {
                PhotosPicker(selection: $pick, matching: .images) {
                    ZStack {
                        if let photo, let img = UIImage(data: photo) {
                            Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
                        } else {
                            Theme.raised
                            Label("Escolher foto", systemImage: "photo").font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
                .onChange(of: pick) { _, item in
                    Task { if let data = try? await item?.loadTransferable(type: Data.self) { photo = compressedPhoto(data) } }
                }
                if photo != nil {
                    GMButton("Tirar foto", kind: .secondary, small: true) { photo = nil; pick = nil }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            title = checkIn.title
            note = checkIn.note
            photo = checkIn.photo
        }
    }

    private func save() {
        checkIn.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? checkIn.title : title.trimmingCharacters(in: .whitespaces)
        checkIn.note = note
        checkIn.photo = photo
        try? context.save()
        dismiss()
    }
}
