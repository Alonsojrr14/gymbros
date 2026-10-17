import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.64, green: 0.90, blue: 0.21)
private let dim = Color.white.opacity(0.6)

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            LockScreenWorkout(context: context)
                .activityBackgroundTint(Color(red: 0.05, green: 0.06, blue: 0.08))
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(s.sprite + "_live").resizable().interpolation(.none).scaledToFit().frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: context.attributes.start...Date.distantFuture, countsDown: false)
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle(accent)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("\(s.doneSets)/\(s.totalSets) séries").font(.caption2).foregroundStyle(dim)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.exercise).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        SetLine(state: s, stale: context.isStale)
                        ProgressView(value: s.progress).tint(accent)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(accent)
            } compactTrailing: {
                if let end = s.restEnd, end > .now, !context.isStale {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 42)
                        .foregroundStyle(accent)
                } else {
                    Text("\(min(s.setNumber, s.setCount))/\(s.setCount)").monospacedDigit().foregroundStyle(accent)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(accent)
            }
        }
    }
}

/// Série atual ou descanso, com o botão da vez
private struct SetLine: View {
    let state: WorkoutAttributes.ContentState
    /// O descanso já acabou (conteúdo ficou velho), mesmo sem o app ter atualizado
    var stale = false

    var body: some View {
        HStack(spacing: 10) {
            if let end = state.restEnd, stale || end <= .now {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Descanso acabou").font(.caption).foregroundStyle(dim)
                    Text(state.exerciseDone ? "Exercício concluído" : "Série \(state.setNumber) de \(state.setCount) · \(state.setText)")
                        .font(.subheadline.bold()).foregroundStyle(accent)
                }
                Spacer()
                Button(intent: SkipRestIntent()) {
                    Label("Próxima série", systemImage: "arrow.right")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(accent, in: .capsule)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            } else if let end = state.restEnd, end > .now {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Descanso").font(.caption).foregroundStyle(dim)
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(accent)
                }
                Spacer()
                Button(intent: SkipRestIntent()) {
                    Label("Pular", systemImage: "forward.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.15), in: .capsule)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else if state.exerciseDone {
                Label("Exercício concluído", systemImage: "checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(accent)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Série \(state.setNumber) de \(state.setCount)").font(.caption).foregroundStyle(dim)
                    Text(state.setText).font(.headline.monospacedDigit()).foregroundStyle(accent)
                }
                Spacer()
                Button(intent: CompleteSetIntent()) {
                    Label("Série feita", systemImage: "checkmark")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(accent, in: .capsule)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LockScreenWorkout: View {
    let context: ActivityViewContext<WorkoutAttributes>

    var body: some View {
        let s = context.state
        HStack(alignment: .center, spacing: 14) {
            Image(s.sprite + "_live").resizable().interpolation(.none).scaledToFit().frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(context.attributes.title).font(.caption.bold()).foregroundStyle(dim).lineLimit(1)
                    Spacer()
                    Text(timerInterval: context.attributes.start...Date.distantFuture, countsDown: false)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                }
                Text(s.exercise).font(.headline).foregroundStyle(.white).lineLimit(1)
                SetLine(state: s, stale: context.isStale).foregroundStyle(.white)
                ProgressView(value: s.progress).tint(accent)
            }
        }
        .padding(16)
    }
}
