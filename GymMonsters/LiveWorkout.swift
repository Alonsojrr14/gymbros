import ActivityKit
import Foundation

/// Liga o treino em andamento ao Live Activity. Atualizações são locais (sem push).
@MainActor
enum LiveWorkout {
    private static var current: ActivityKit.Activity<WorkoutAttributes>? {
        ActivityKit.Activity<WorkoutAttributes>.activities.first
    }

    static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Começa (ou atualiza, se já existe) o Live Activity do treino
    static func show(title: String, start: Date, state: WorkoutAttributes.ContentState) async {
        guard enabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = current, activity.attributes.start == start {
            await activity.update(content)
            return
        }
        // Outro treino ainda aparecendo: encerra antes de começar este
        await endAll()
        _ = try? ActivityKit.Activity.request(attributes: WorkoutAttributes(title: title, start: start), content: content, pushType: nil)
    }

    static func endAll() async {
        for a in ActivityKit.Activity<WorkoutAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }
}
