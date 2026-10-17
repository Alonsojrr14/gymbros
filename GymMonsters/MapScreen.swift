import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Aba Mapa: academia, frequência, atividades ao ar livre e percursos
struct MapScreen: View {
    @Query(sort: \RouteRecord.start, order: .reverse) private var routes: [RouteRecord]
    @Query(sort: \GymVisit.start, order: .reverse) private var visits: [GymVisit]
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var editingGym = false
    @State private var outdoor: ActivityKind?
    @State private var route: RouteRecord?
    @State private var here: CLLocation?
    @State private var arrival = GymLocation.shared.notifyArrival
    @State private var autoFinish = GymLocation.shared.autoFinish
    @State private var gym = GymLocation.shared.gym

    var body: some View {
        NavigationStack {
            GMScreen("Mapa", avatar: true) {
                bigMap
                statusCard
                gymSection
                outdoorSection
                if !routes.isEmpty { routesSection }
            }
            .gmModal(isPresented: $editingGym) { GymPickerView() }
            .gmModal(item: $outdoor) { RouteRunView(kind: $0) }
            .gmSheet(isPresented: Binding(get: { route != nil }, set: { if !$0 { route = nil } })) { _ in
                if let r = route { routeDetail(r) }
            }
            .onChange(of: editingGym) { _, open in if !open { gym = GymLocation.shared.gym; focusGym() } }
            .task {
                here = await GymLocation.shared.currentLocation()
                focusGym()
            }
        }
    }

    // MARK: Mapa

    private var bigMap: some View {
        Map(position: $camera) {
            UserAnnotation()
            if let g = gym {
                MapCircle(center: g.coordinate, radius: g.radius).foregroundStyle(Theme.accent.opacity(0.18)).stroke(Theme.accent, lineWidth: 2)
                Annotation(g.name, coordinate: g.coordinate) {
                    Image(systemName: "dumbbell.fill").font(.caption.bold()).padding(8).background(Theme.accent, in: .circle).foregroundStyle(.black)
                }
            }
            ForEach(routes.prefix(10)) { r in
                MapPolyline(coordinates: r.coordinates).stroke(color(r.kind).opacity(0.85), lineWidth: 4)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: Theme.radius))
        .overlay(alignment: .topTrailing) {
            if gym != nil { GMIconButton(icon: "scope", size: 36) { focusGym() }.padding(10) }
        }
    }

    private func focusGym() {
        guard let g = gym else { return }
        withAnimation { camera = .region(MKCoordinateRegion(center: g.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)) }
    }

    private func color(_ k: ActivityKind) -> Color {
        switch k {
        case .bike: .orange
        case .caminhada: .cyan
        default: Theme.accent
        }
    }

    // MARK: Status

    private var statusCard: some View {
        let g = gym
        let inside = GymLocation.shared.inside
        let distance = g.flatMap { g in here.map { $0.distance(from: CLLocation(latitude: g.latitude, longitude: g.longitude)) } }
        let always = GymLocation.shared.authorization == .authorizedAlways
        return GMCard {
            HStack(spacing: 12) {
                Image(systemName: inside ? "figure.strengthtraining.traditional" : "location.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(inside ? Theme.accent : Theme.raised, in: .circle)
                    .foregroundStyle(inside ? .black : .white)
                VStack(alignment: .leading, spacing: 3) {
                    if g == nil {
                        Text("Marque sua academia").font(.headline)
                        Text("Para o app sugerir o treino ao chegar e encerrar ao sair").font(.caption).foregroundStyle(Theme.dim)
                    } else if inside {
                        Text("Você está na \(g!.name)").font(.headline)
                        Text(LiveWorkout.hasRunning ? "Treino em andamento" : "Bora treinar 💪").font(.caption).foregroundStyle(Theme.accent)
                    } else {
                        Text(distance.map { $0 < 1000 ? "A \(Int($0)) m da academia" : "A \(kmText($0)) da academia" } ?? "Fora da academia")
                            .font(.headline)
                        Text(g!.name).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
            }
            if g != nil && !always {
                GMDivider()
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Para funcionar com o app fechado, permita a localização \"Sempre\".").font(.caption)
                    Spacer()
                    GMButton("Ajustes", kind: .secondary, full: false, small: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
        }
    }

    // MARK: Academia

    private var gymSection: some View {
        let month = Calendar.current.dateInterval(of: .month, for: .now)!
        let thisMonth = visits.filter { month.contains($0.start) }
        let durations = thisMonth.compactMap(\.minutes).filter { $0 >= 5 }
        let avg = durations.isEmpty ? nil : durations.reduce(0, +) / durations.count
        return GMSection("Minha academia") {
            GMRow(icon: "mappin.and.ellipse", iconTint: Theme.accent, title: gym?.name ?? "Marcar no mapa",
                  subtitle: gym.map { "Raio de \(Int($0.radius)) m" } ?? "Toque para escolher o local", chevron: true) { editingGym = true }
            if gym != nil {
                GMDivider()
                GMToggle(title: "Avisar ao chegar", subtitle: "Sugere começar o treino do dia", isOn: $arrival)
                    .onChange(of: arrival) { _, v in GymLocation.shared.notifyArrival = v }
                GMDivider()
                GMToggle(title: "Encerrar treino ao sair", subtitle: "Salva o treino em andamento (mais de 10 min) ao sair do raio", isOn: $autoFinish)
                    .onChange(of: autoFinish) { _, v in GymLocation.shared.autoFinish = v }
                GMDivider()
                HStack {
                    stat("\(thisMonth.count)", "visitas no mês")
                    stat(avg.map { durationText($0) } ?? "–", "tempo médio")
                    stat(visits.first.map { $0.start.formatted(.dateTime.day().month(.abbreviated)) } ?? "–", "última visita")
                }
            }
        }
    }

    // MARK: Ao ar livre

    private var outdoorSection: some View {
        let month = Calendar.current.dateInterval(of: .month, for: .now)!
        let monthRoutes = routes.filter { month.contains($0.start) }
        return GMSection("Ao ar livre (GPS)") {
            HStack(spacing: 10) {
                ForEach([ActivityKind.corrida, .caminhada, .bike]) { k in
                    Button { outdoor = k } label: {
                        VStack(spacing: 6) {
                            Image(systemName: k.symbol).font(.title2).frame(height: 30)
                            Text(k.name).font(.caption.weight(.semibold))
                            Text(kmText(monthRoutes.filter { $0.kind == k }.reduce(0) { $0 + $1.meters }))
                                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .background(Theme.raised, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(GMPress())
                }
            }
            Text("Toque para começar. Abaixo de cada um, o total do mês.").font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private var routesSection: some View {
        GMSection("Percursos") {
            ForEach(routes.prefix(20)) { r in
                Button { route = r } label: {
                    HStack(spacing: 12) {
                        RouteMap(coords: r.coordinates).frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.kind.name) · \(kmText(r.meters))").font(.subheadline.weight(.semibold))
                            Text("\(r.start.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · \(clock(r.seconds)) · \(paceText(kind: r.kind, meters: r.meters, seconds: r.seconds))")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(GMPress())
                if r.id != routes.prefix(20).last?.id { GMDivider() }
            }
        }
    }

    private func routeDetail(_ r: RouteRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(r.kind.name) · \(kmText(r.meters))").font(.headline)
            RouteMap(coords: r.coordinates).frame(height: 300).clipShape(.rect(cornerRadius: 16))
            HStack {
                stat(clock(r.seconds), "tempo")
                stat(kmText(r.meters), "distância")
                stat(paceText(kind: r.kind, meters: r.meters, seconds: r.seconds), r.kind == .bike ? "velocidade" : "ritmo")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}
