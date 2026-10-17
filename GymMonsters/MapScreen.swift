import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Aba Mapa: academia, frequência, atividades ao ar livre e percursos
struct MapScreen: View {
    @Query(sort: \RouteRecord.start, order: .reverse) private var routes: [RouteRecord]
    @Query(sort: \GymVisit.start, order: .reverse) private var visits: [GymVisit]
    @Query(sort: \Gym.createdAt) private var gyms: [Gym]
    @Query private var activities: [Activity]
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var editing: GymEdit?
    @State private var outdoor: ActivityKind?
    @State private var route: RouteRecord?
    @State private var here: CLLocation?
    @State private var arrival = GymLocation.shared.notifyArrival
    @State private var autoFinish = GymLocation.shared.autoFinish

    var body: some View {
        NavigationStack {
            GMScreen("Mapa", avatar: true) {
                bigMap
                statusCard
                gymSection
                outdoorSection
                if !routes.isEmpty { routesSection }
            }
            .gmModal(item: $editing) { GymEditorView(gym: $0.gym) }
            .gmModal(item: $outdoor) { RouteRunView(kind: $0) }
            .gmSheet(isPresented: Binding(get: { route != nil }, set: { if !$0 { route = nil } })) { _ in
                if let r = route { routeDetail(r) }
            }
            .task {
                here = await GymLocation.shared.currentLocation()
                focusPlaces()
            }
        }
    }

    // MARK: Mapa

    private var bigMap: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(gyms) { g in
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
            if !gyms.isEmpty { GMIconButton(icon: "scope", size: 36) { focusPlaces() }.padding(10) }
        }
    }

    /// Centraliza no lugar mais próximo de você (ou no primeiro salvo)
    private func focusPlaces() {
        let target = here.flatMap { h in gyms.min { $0.location.distance(from: h) < $1.location.distance(from: h) } } ?? gyms.first
        guard let g = target else { return }
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
        let inside = GymLocation.shared.insideGym
        let nearest = here.flatMap { h in gyms.map { ($0, $0.location.distance(from: h)) }.min { $0.1 < $1.1 } }
        let always = GymLocation.shared.authorization == .authorizedAlways
        return GMCard {
            HStack(spacing: 12) {
                Image(systemName: inside != nil ? "figure.strengthtraining.traditional" : "location.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(inside != nil ? Theme.accent : Theme.raised, in: .circle)
                    .foregroundStyle(inside != nil ? .black : .white)
                VStack(alignment: .leading, spacing: 3) {
                    if let inside {
                        Text("Você está na \(inside.name)").font(.headline)
                        Text(LiveWorkout.hasRunning ? "Treino em andamento" : "Bora treinar 💪").font(.caption).foregroundStyle(Theme.accent)
                    } else if let (g, m) = nearest {
                        Text(m < 1000 ? "A \(Int(m)) m da \(g.name)" : "A \(kmText(m)) da \(g.name)").font(.headline).lineLimit(2)
                        Text("Lugar salvo mais próximo").font(.caption).foregroundStyle(Theme.dim)
                    } else {
                        Text("Nenhum lugar salvo ainda").font(.headline)
                        Text("Ao começar um treino, o app pergunta onde você está e guarda o lugar").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
            }
            if !gyms.isEmpty && !always {
                GMDivider()
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("Para avisar ao chegar e encerrar ao sair com o app fechado, permita a localização \"Sempre\".").font(.caption)
                    Spacer()
                    GMButton("Ajustes", kind: .secondary, full: false, small: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
        }
    }

    // MARK: Lugares de treino

    private var gymSection: some View {
        let month = Calendar.current.dateInterval(of: .month, for: .now)!
        let monthVisits = visits.filter { month.contains($0.start) }
        // Mais visitados primeiro; conta visitas detectadas e treinos registrados no lugar
        let sorted = gyms.sorted { count($0) > count($1) }
        return GMSection("Lugares de treino · \(gyms.count)",
                         footer: "Ao começar musculação ou CrossFit, o app identifica o lugar ou pergunta onde você está.") {
            ForEach(sorted) { g in
                let last = lastDate(g)
                GMRow(icon: "dumbbell.fill", iconTint: GymLocation.shared.insideID == g.uuid ? Theme.accent : .white, title: g.name,
                      subtitle: "\(count(g)) treino\(count(g) == 1 ? "" : "s")" + (last.map { " · último \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? ""),
                      chevron: true, action: { editing = GymEdit(gym: g) }) {
                    if let h = here { Text(distance(g.location.distance(from: h))).font(.caption.monospacedDigit()).foregroundStyle(Theme.dim) }
                }
                GMDivider()
            }
            GMRow(icon: "plus", iconTint: Theme.accent, title: "Adicionar lugar", chevron: true) { editing = GymEdit(gym: nil) }
            if !gyms.isEmpty {
                GMDivider()
                GMToggle(title: "Avisar ao chegar", subtitle: "Sugere começar o treino do dia", isOn: $arrival)
                    .onChange(of: arrival) { _, v in GymLocation.shared.notifyArrival = v }
                GMDivider()
                GMToggle(title: "Encerrar treino ao sair", subtitle: "Salva o treino em andamento (mais de 10 min) ao sair do lugar", isOn: $autoFinish)
                    .onChange(of: autoFinish) { _, v in GymLocation.shared.autoFinish = v }
                GMDivider()
                HStack {
                    stat("\(monthVisits.count)", "idas no mês")
                    stat(avgMinutes(monthVisits).map { durationText($0) } ?? "–", "tempo médio")
                    stat("\(Set(monthVisits.compactMap(\.gymUUID)).count)", "lugares no mês")
                }
            }
        }
    }

    private func count(_ g: Gym) -> Int {
        max(visits.filter { $0.gymUUID == g.uuid }.count, activities.filter { $0.gymUUID == g.uuid }.count)
    }

    private func lastDate(_ g: Gym) -> Date? {
        (visits.filter { $0.gymUUID == g.uuid }.map(\.start) + activities.filter { $0.gymUUID == g.uuid }.map(\.date)).max()
    }

    private func avgMinutes(_ list: [GymVisit]) -> Int? {
        let d = list.compactMap(\.minutes).filter { $0 >= 5 }
        return d.isEmpty ? nil : d.reduce(0, +) / d.count
    }

    private func distance(_ m: Double) -> String { m < 1000 ? "\(Int(m)) m" : kmText(m) }

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

struct GymEdit: Identifiable {
    let gym: Gym?
    var id: String { gym?.uuid.uuidString ?? "novo" }
}
