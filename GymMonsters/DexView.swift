import SwiftUI

struct DexView: View {
    let snapshot: Snapshot
    let discovered: Set<String>

    var body: some View {
        NavigationStack {
            ScrollView {
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
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Dex · \(discovered.count)/\(MonsterForm.all.count)")
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
