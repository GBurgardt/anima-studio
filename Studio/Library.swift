import AppKit
import SwiftUI
struct AudienceMetrics: Codable {}
struct StreamReport: Decodable, Identifiable { var id: String }
struct SyncStatus: Decodable { var phase: String; var message: String? }
struct StudioLibrary: Decodable { var files: [RecordingFile]; var streams: [StreamReport]; var sync: SyncStatus }
struct StudioLibraryView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Grabaciones del servidor").font(.title2.bold()); Spacer(); Button("Carpeta local") { model.openFolder() }; Button("Listo") { dismiss() } }
            Text("Traer copia el archivo a esta Mac. El original nunca se borra. No se copian archivos mientras OBS graba.").font(.caption)
            ScrollView { LazyVStack(spacing: 12) { ForEach(model.files) { file in
                HStack {
                    VStack(alignment: .leading) { Text(file.name); Text(file.ready == false ? "Grabando / cerrando archivo" : "Disponible").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if model.isLocal(file) { Button("Ver") { model.play(file) }; Button("Copiar URI") { model.copyURI(file) } }
                    else { Button("Traer") { Task { await model.download(file) } }.disabled(model.transferring || model.state?.recording == true || file.ready == false) }
                }.padding(12).background(StudioPalette.raised)
            } } }
            if model.transferring { ProgressView("Copiando…") }
            if let error = model.error { Text(error).foregroundStyle(.orange).font(.caption) }
            Button("Actualizar") { Task { await model.refreshFiles() } }
        }.padding(24).frame(width: 720, height: 520).task { await model.refreshFiles() }
    }
}
