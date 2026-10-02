import AppKit
import SwiftUI

struct ConnectionSettings: Codable {
    var host = ""
    var node = "/opt/homebrew/bin/node"
    var controller = ""
    var recordings = ""
    var lightHost = ""
    static var file: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AnimaStudioPublic/client.json") }
    static func load() -> Self { (try? JSONDecoder().decode(Self.self, from: Data(contentsOf: file))) ?? Self() }
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    func validate() throws {
        guard host.range(of: "^[A-Za-z0-9][A-Za-z0-9._@-]*$", options: .regularExpression) != nil else { throw StudioError.message("Usá un alias SSH válido, por ejemplo studio-server.") }
        for path in [node, controller, recordings] {
            guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\r"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { throw StudioError.message("Las rutas del servidor deben ser absolutas, sin .. ni saltos de línea.") }
        }
        guard lightHost.isEmpty || lightHost.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil else { throw StudioError.message("Nombre de luz inválido.") }
    }
    func save() throws {
        try validate()
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
    }
}
struct ConnectionSettingsView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) var dismiss
    @State private var settings = ConnectionSettings.load()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tu servidor OBS").font(.title2.bold())
            Text("Primero configurá SSH y OBS siguiendo docs/SETUP.md. Las claves de transmisión se quedan en el servidor.").font(.callout)
            TextField("Alias SSH (studio-server)", text: $settings.host)
            TextField("Ruta de Node en el servidor", text: $settings.node)
            TextField("Ruta absoluta de bridge/controller.mjs", text: $settings.controller)
            TextField("Carpeta absoluta de grabaciones del servidor", text: $settings.recordings)
            TextField("Elgato: hostname local (opcional)", text: $settings.lightHost)
            Text("Cerrar el cliente no apaga OBS, pero sí corta el monitor que este cliente envía por NDI. La vista previa no tiene audio.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button("Cancelar") { dismiss() }; Spacer(); Button("Guardar y conectar") { do { try settings.save(); model.connection.disconnect(); dismiss(); Task { await model.action("prepare") } } catch { self.error = error.localizedDescription } } }
        }.padding(24).frame(width: 600)
    }
}
