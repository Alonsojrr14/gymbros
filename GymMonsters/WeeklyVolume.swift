import SwiftData
import SwiftUI

/// Séries por grupo muscular na semana, comparadas com a faixa de 10–20 séries recomendada para crescer
struct WeeklyVolumeView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.end != nil }) private var sessions: [WorkoutSession]
    @State private var offset = 0

    static let low = 10, high = 20

    private var week: DateInterval {
        let cal = Calendar.current
        let now = cal.date(byAdding: .weekOfYear, value: offset, to: .now)!
        return cal.dateInterval(of: .weekOfYear, for: now)!
    }

    /// Séries feitas (sem aquecimento) por grupo principal do exercício
    private var counts: [MuscleGroup: Int] {
        var out: [MuscleGroup: Int] = [:]
        for s in sessions where week.contains(s.start) {
            for set in s.sets where set.done && !set.warmup {
                if let g = Exercise.byID(set.exerciseID)?.group, g != .corpo { out[g, default: 0] += 1 }
            }
        }
        return out
    }

    var body: some View {
        let c = counts
        let groups = MuscleGroup.allCases.filter { $0 != .corpo }
        let inRange = groups.filter { (Self.low...Self.high).contains(c[$0] ?? 0) }.count
        GMScreen("Volume semanal", back: true) {
            HStack {
                GMIconButton(icon: "chevron.left", size: 34) { offset -= 1 }
                Spacer()
                VStack(spacing: 2) {
                    Text(offset == 0 ? "Esta semana" : offset == -1 ? "Semana passada" : weekTitle).font(.headline)
                    Text("\(c.values.reduce(0, +)) séries · \(inRange) de \(groups.count) grupos na faixa").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                GMIconButton(icon: "chevron.right", size: 34, tint: offset == 0 ? Theme.dim : .white) { if offset < 0 { offset += 1 } }
            }
            GMSection(footer: "Conta as séries feitas de cada exercício no músculo principal dele (aquecimento fica de fora). Entre \(Self.low) e \(Self.high) séries por semana é a faixa que a maioria dos estudos associa a ganho de massa; abaixo disso o músculo cresce menos, acima a recuperação pesa.") {
                ForEach(groups.sorted { (c[$0] ?? 0) > (c[$1] ?? 0) }) { g in
                    bar(g, c[g] ?? 0)
                    if g != groups.last { Color.clear.frame(height: 2) }
                }
            }
        }
    }

    private var weekTitle: String {
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(week.start.formatted(f)) – \(week.end.addingTimeInterval(-1).formatted(f))"
    }

    private func bar(_ g: MuscleGroup, _ n: Int) -> some View {
        let maxN = 26.0
        let color: Color = n < Self.low ? .orange : n <= Self.high ? Theme.accent : .cyan
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(g.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(n)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(color)
                Text(n < Self.low ? "faltam \(Self.low - n)" : n <= Self.high ? "na faixa" : "acima")
                    .font(.caption).foregroundStyle(Theme.dim).frame(width: 64, alignment: .trailing)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    // Faixa recomendada
                    Rectangle().fill(Theme.accent.opacity(0.15))
                        .frame(width: w * CGFloat(Self.high - Self.low) / maxN)
                        .offset(x: w * CGFloat(Self.low) / maxN)
                    Capsule().fill(color).frame(width: max(w * min(CGFloat(n), maxN) / maxN, n > 0 ? 6 : 0))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
        }
    }
}
