import SwiftUI

struct KeyLightState: Codable, Equatable {
    var on: Int
    var brightness: Int
    var temperature: Int
}
struct KeyLightEnvelope: Codable { var numberOfLights: Int; var lights: [KeyLightState] }

@MainActor final class KeyLightControl: ObservableObject {
    @Published private(set) var state: KeyLightState?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    static func brightness(_ value: Int) -> Int { max(0, min(100, value)) }
    private func request(_ fields: [String: Int]? = nil) async throws -> KeyLightState {
        let config = ConnectionSettings.load()
        try config.validate()
        guard !config.lightHost.isEmpty, let url = URL(string: "http://\(config.lightHost):9123/elgato/lights") else { throw StudioError.message("Configurá una luz en Ajustes.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        if let fields {
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["numberOfLights": 1, "lights": [fields]])
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw StudioError.message("La luz no respondió.") }
        let envelope = try JSONDecoder().decode(KeyLightEnvelope.self, from: data)
        guard envelope.numberOfLights == 1, let light = envelope.lights.first,
              (0...100).contains(light.brightness), (0...1).contains(light.on) else { throw StudioError.message("Respuesta de luz inválida.") }
        return light
    }
    func refresh() async { await perform(nil) }
    func power(_ on: Bool) async { await perform(["on": on ? 1 : 0]) }
    func adjust(_ delta: Int) async {
        guard let state else { return }
        await perform(["brightness": Self.brightness(state.brightness + delta)])
    }
    private func perform(_ fields: [String: Int]?) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await request(fields)
            state = try await request() // Verify device readback, not optimistic state.
            error = nil
        } catch {
            state = nil
            self.error = "Luz sin conexión. Revisá que esté en I y conectada al Wi-Fi."
        }
    }
}

struct LightControlView: View {
    @StateObject private var light = KeyLightControl()
    var body: some View {
        HStack(spacing: 10) {
            Toggle("Luz", isOn: Binding(get: { light.state?.on == 1 }, set: { value in Task { await light.power(value) } }))
                .toggleStyle(.checkbox).disabled(light.busy || light.state == nil)
            Button { Task { await light.adjust(-5) } } label: { Image(systemName: "minus") }
                .disabled(light.busy || light.state == nil || light.state?.brightness == 0).help("Bajar brillo 5 %")
            Text(light.state.map { "\($0.brightness)%" } ?? "—").monospacedDigit().frame(width: 36)
            Button { Task { await light.adjust(5) } } label: { Image(systemName: "plus") }
                .disabled(light.busy || light.state == nil || light.state?.brightness == 100).help("Subir brillo 5 %")
            Button { Task { await light.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(light.busy).help(light.error ?? "Actualizar luz")
            if light.error != nil { Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange).help(light.error!) }
        }.font(.system(size: 12)).buttonStyle(.plain)
            .task {
                guard !ProcessInfo.processInfo.arguments.contains("--design-preview") else { return }
                while !Task.isCancelled {
                    await light.refresh()
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                }
            }
    }
}
