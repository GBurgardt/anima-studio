import SwiftUI

struct MonitorPicker: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var capture: MonitorCapture
    var body: some View {
        HStack(spacing: 8) {
            ForEach(capture.monitors) { monitor in
                Button { Task { await model.selectMonitor(monitor) } } label: {
                    Label("Monitor \(monitor.number)", systemImage: "display")
                }.buttonStyle(StudioButton(selected: capture.selected == monitor.id))
                    .disabled(!model.canControl || capture.updatingInclusion)
                    .help("Compartir \(monitor.name) · orden de izquierda a derecha")
            }
            Spacer()
            Toggle("Incluir Studio", isOn: Binding(get: { capture.includeStudio }, set: { enabled in
                Task {
                    do { try await capture.setIncludeStudio(enabled) }
                    catch { model.error = error.localizedDescription }
                }
            })).toggleStyle(.checkbox).font(.system(size: 12))
                .disabled(!model.canControl || capture.updatingInclusion)
                .help("Mostrar también este panel. Su vista previa puede generar un efecto de espejo.")
        }.onAppear { capture.refresh() }
    }
}
