import ActivityKit
import SwiftUI
import WidgetKit

private let accent = Color(red: 0.64, green: 0.90, blue: 0.21)
private let dim = Color.white.opacity(0.6)

struct WodLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WodAttributes.self) { context in
            WodLockScreen(context: context)
                .activityBackgroundTint(Color(red: 0.05, green: 0.06, blue: 0.08))
                .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.name).font(.headline)
                        Text(context.attributes.format).font(.caption2).foregroundStyle(dim)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WodClock(state: s).font(.title2.monospacedDigit().bold()).foregroundStyle(accent).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WodBottom(state: s)
                }
            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            } compactTrailing: {
                WodClock(state: s).monospacedDigit().frame(width: 46).foregroundStyle(accent)
            } minimal: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            }
        }
    }
}

/// Cronômetro que o próprio iOS atualiza, para cima ou para baixo
private struct WodClock: View {
    let state: WodAttributes.ContentState

    var body: some View {
        if let paused = state.pausedText {
            Text(paused)
        } else if state.countsDown, let end = state.end {
            Text(timerInterval: Date.now...max(end, .now), countsDown: true).multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: state.start...Date.distantFuture, countsDown: false).multilineTextAlignment(.trailing)
        }
    }
}

private struct WodBottom: View {
    let state: WodAttributes.ContentState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.pausedText != nil ? "Pausado" : state.label).font(.subheadline.bold())
                if state.showRounds {
                    Text("\(state.rounds) rodada\(state.rounds == 1 ? "" : "s")").font(.caption).foregroundStyle(dim)
                }
            }
            Spacer()
            if state.showRounds {
                Button(intent: AddRoundIntent()) {
                    Label("+1 rodada", systemImage: "plus")
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

private struct WodLockScreen: View {
    let context: ActivityViewContext<WodAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text(context.attributes.name).font(.headline).foregroundStyle(.white)
                Text(context.attributes.format).font(.caption).foregroundStyle(dim)
                Spacer()
                WodClock(state: context.state)
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(accent)
                    .frame(width: 110, alignment: .trailing)
            }
            WodBottom(state: context.state).foregroundStyle(.white)
        }
        .padding(16)
    }
}
