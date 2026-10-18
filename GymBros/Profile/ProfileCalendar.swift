import SwiftUI

// Calendário do mês com a foto (ou o tipo) do que foi feito em cada dia. O mesmo calendário serve
// para o seu histórico privado, para os seus posts públicos e para os posts de um amigo.

struct CalendarMark: Identifiable {
    let id: String
    let date: Date
    let kind: ActivityKind
    var photo: Data?
}

struct ActivityCalendar: View {
    let marks: [CalendarMark]
    let onDay: (Date) -> Void
    @State private var month = Date.now

    var body: some View {
        let cal = GMMonth.calendar
        let start = GMMonth.start(of: month)
        let cells = GMMonth.cells(month)
        let byDay = Dictionary(grouping: marks) { cal.startOfDay(for: $0.date) }
        let isCurrent = cal.isDate(start, equalTo: .now, toGranularity: .month)

        VStack(spacing: 12) {
            HStack {
                GMIconButton(icon: "chevron.left", size: 34, label: "Mês anterior") { shift(-1) }
                Spacer()
                Text(GMMonth.title(start)).font(.title3.weight(.heavy))
                Spacer()
                GMIconButton(icon: "chevron.right", size: 34, tint: isCurrent ? Theme.dim : .white, label: "Próximo mês") { if !isCurrent { shift(1) } }
            }
            GMMonth.header
            GMCard(padding: 10) { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                    if let d {
                        dayCell(d, items: byDay[cal.startOfDay(for: d)] ?? [])
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            } }
        }
    }

    private func dayCell(_ d: Date, items: [CalendarMark]) -> some View {
        let today = Calendar.current.isDateInToday(d)
        let photos = items.compactMap(\.photo)
        return Button {
            if !items.isEmpty { onDay(d) }
        } label: {
            ZStack {
                if let first = photos.first, let img = UIImage(data: first) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: 42, height: 42).clipShape(.circle)
                    if photos.count > 1, let img2 = UIImage(data: photos[1]) {
                        Image(uiImage: img2).resizable().scaledToFill().frame(width: 26, height: 26).clipShape(.circle)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                            .offset(x: 14, y: 14)
                    }
                } else if let a = items.first {
                    Circle().fill(Theme.accent.opacity(0.9)).frame(width: 42, height: 42)
                    Image(systemName: a.kind.symbol).font(.subheadline.bold()).foregroundStyle(.black)
                    if items.count > 1 {
                        Text("\(items.count)").gmFont(10, weight: .heavy, relativeTo: .caption2).minimumScaleFactor(0.6).foregroundStyle(.black)
                            .frame(width: 18, height: 18).background(.white, in: .circle).offset(x: 15, y: -15)
                    }
                } else {
                    Text("\(Calendar.current.component(.day, from: d))")
                        .font(.body.weight(today ? .heavy : .regular).monospacedDigit())
                        .foregroundStyle(today ? Theme.accent : .white)
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GMPress())
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = GMMonth.calendar.date(byAdding: .month, value: n, to: month) ?? month }
    }
}

/// Posts do perfil em calendário; tocar num dia mostra os posts dele
struct PostsCalendar: View {
    let posts: [FeedItem]
    @State private var day: Date?

    var body: some View {
        ActivityCalendar(marks: posts.map { CalendarMark(id: $0.id, date: $0.date, kind: $0.kind, photo: $0.photo) }) { day = $0 }
            .gmSheet(isPresented: Binding(get: { day != nil }, set: { if !$0 { day = nil } })) { _ in
                DayPosts(day: day ?? .now, posts: posts.filter { p in day.map { Calendar.current.isDate(p.date, inSameDayAs: $0) } ?? false })
            }
    }
}

/// Lista dos posts de um dia, cada um abre o check-in completo
private struct DayPosts: View {
    let day: Date
    let posts: [FeedItem]
    @State private var opened: FeedItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GMDateText.day(day)).font(.headline)
            ForEach(posts.sorted { $0.date < $1.date }) { p in
                Button { opened = p } label: {
                    HStack(spacing: 12) {
                        thumb(p).frame(width: 58, height: 58).clipShape(.rect(cornerRadius: Theme.radiusM))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            Text("\(p.kind.name) · \(durationText(p.minutes)) · \(p.date.formatted(.dateTime.hour().minute()))")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                    .foregroundStyle(.white)
                }
                .buttonStyle(GMPress())
            }
        }
        .gmModal(item: $opened) { CheckInDetailView(item: $0) }
    }

    @ViewBuilder
    private func thumb(_ p: FeedItem) -> some View {
        if let d = p.photo, let img = UIImage(data: d) {
            Color.clear.overlay { Image(uiImage: img).resizable().scaledToFill() }
        } else {
            Image(systemName: p.kind.symbol)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(p.hasPhoto ? Theme.accent.opacity(0.3) : Theme.raised)
                .foregroundStyle(.white)
        }
    }
}
