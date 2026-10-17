import ActivityKit
import SwiftUI
import WidgetKit

struct WodLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WodAttributes.self) { context in
            WodLockScreen(context: context)
                .activityBackgroundTint(Theme.bg)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.name).font(.headline)
                        Text(context.attributes.format).font(.caption2).foregroundStyle(Theme.dim)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WodClock(state: s).font(.title2.monospacedDigit().bold()).foregroundStyle(Theme.accent).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WodBottom(state: s)
                }
            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(Theme.streak)
            } compactTrailing: {
                WodClock(state: s).monospacedDigit().frame(width: 46).foregroundStyle(Theme.accent)
            } minimal: {
                Image(systemName: "flame.fill").foregroundStyle(Theme.streak)
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
                    Text("\(state.rounds) rodada\(state.rounds == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.dim)
                }
            }
            Spacer()
            if state.showRounds {
                Button(intent: AddRoundIntent()) {
                    Label("+1 rodada", systemImage: "plus")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.accent, in: .capsule)
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
                Image(systemName: "flame.fill").foregroundStyle(Theme.streak)
                Text(context.attributes.name).font(.headline).foregroundStyle(.white)
                Text(context.attributes.format).font(.caption).foregroundStyle(Theme.dim)
                Spacer()
                WodClock(state: context.state)
                    .font(.system(.title, design: .rounded, weight: .heavy).monospacedDigit()).minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 110, alignment: .trailing)
            }
            WodBottom(state: context.state).foregroundStyle(.white)
        }
        .padding(16)
    }
}
