import SwiftUI

struct DexView: View {
    let snapshot: Snapshot
    let discovered: Set<String>
    let achievements: [Achievement]
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            GMScreen(tab == 0 ? "Dex" : "Conquistas",
                     subtitle: tab == 0 ? "\(discovered.count) de \(MonsterForm.all.count) formas descobertas"
                                        : "\(achievements.filter(\.unlocked).count) de \(achievements.count) desbloqueadas") {
                GMSegmented(options: [(0, "Monstros"), (1, "Conquistas")], selection: $tab)
                if tab == 0 { monsters } else { trophies }
            }
        }
    }

    private var trophies: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(achievements.sorted { ($0.unlocked ? 0 : 1, -$0.progress) < ($1.unlocked ? 0 : 1, -$1.progress) }) { a in
                VStack(spacing: 8) {
                    Image(systemName: a.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(a.unlocked ? Color.yellow : Theme.dim)
                        .frame(height: 38)
                    Text(a.title).font(.subheadline.bold()).multilineTextAlignment(.center)
                    Text(a.detail).font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    if !a.unlocked {
                        GMProgressBar(value: a.progress, height: 6)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .opacity(a.unlocked ? 1 : 0.7)
            }
        }

    }

    private var monsters: some View {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Stage.allCases, id: \.self) { stage in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(stage.name).font(.headline)
                                Spacer()
                                Text(stage == .egg ? "início" : "\(stage.threshold) XP")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.dim)
                            }
                            let forms = MonsterForm.all.filter { $0.stage == stage }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: forms.count > 1 ? 2 : 1), spacing: 10) {
                                ForEach(forms) { cell($0) }
                            }
                        }
                    }
                }

    }

    private func cell(_ f: MonsterForm) -> some View {
        let known = discovered.contains(f.id)
        let current = snapshot.form == f
        return VStack(spacing: 8) {
            MonsterSprite(form: f, hidden: !known)
                .frame(height: f.stage.branches ? 90 : 120)
            Text(known ? f.name : "???").font(.subheadline.bold())
            if let a = f.attribute {
                Label(a.name, systemImage: a.symbol)
                    .font(.caption)
                    .foregroundStyle(known ? a.color : Theme.dim)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(current ? Theme.accent : .clear, lineWidth: 2))
    }
}
