import HealthKit
import SwiftUI
import WatchKit

/// Treino guiado começou no iPhone: o iOS abre este app e entrega a configuração do treino
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await WorkoutRecorder.shared.startGuided() }
    }
}

@main
struct GymBrosWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var link = PhoneLink.shared
    @State private var recorder = WorkoutRecorder.shared

    init() {
        PhoneLink.shared.activate()
        #if DEBUG
        PhoneLink.shared.applyLaunchArguments()
        WorkoutRecorder.shared.applyLaunchArguments()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environment(link)
                .environment(recorder)
                .tint(Theme.accent)
        }
    }
}

/// Páginas lado a lado, cada uma ocupando a tela inteira (nada rola)
struct WatchRoot: View {
    enum Page { case bro, attributes, training, record }

    @Environment(PhoneLink.self) private var link
    @Environment(WorkoutRecorder.self) private var recorder
    @State private var page = Page.bro

    var body: some View {
        if recorder.isFree {
            RecordingView()
        } else {
            NavigationStack {
                TabView(selection: $page) {
                    if link.workout != nil {
                        TrainingPage().tag(Page.training)
                    }
                    BroPage().tag(Page.bro)
                    if link.bro.map({ !$0.isEgg }) == true {
                        AttributesPage().tag(Page.attributes)
                    }
                    KindPicker().tag(Page.record)
                }
                .tabViewStyle(.page)
            }
            .containerBackground(Theme.bg.gradient, for: .navigation)
            // Começou um treino no iPhone: o relógio já vai para ele
            .onChange(of: link.workout?.start) { _, start in
                if start != nil { page = .training } else if page == .training { page = .bro }
            }
            .onAppear {
                if link.workout != nil { page = .training }
                #if DEBUG
                if let p = UserDefaults.standard.string(forKey: "page") {
                    page = ["attributes": .attributes, "training": .training, "record": .record][p] ?? .bro
                }
                #endif
            }
        }
    }
}
