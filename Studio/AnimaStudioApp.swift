import AppKit
import SwiftUI
import Darwin

// Linear 2026 / Zed: flat workspace, quiet chrome, content-first hierarchy.
enum StudioPalette {
    static func color(_ value: UInt32) -> Color { Color(red: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255) }
    static let canvas = color(0x111214), raised = color(0x1B1D20), primary = color(0xE8E9EB), secondary = color(0x969BA4), accent = color(0xC4D5E6), separator = color(0x2B2E33)
}
struct StudioButton: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(selected ? Color.black : StudioPalette.primary)
            .background(selected ? StudioPalette.accent : StudioPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(selected ? StudioPalette.accent : Color.clear).frame(height: 2) }.opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
    }
}
@MainActor final class StudioDelegate: NSObject, NSApplicationDelegate {
    weak var model: StudioModel?
    func applicationDidFinishLaunching(_ notification: Notification) { Demo.captureIfRequested() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.state?.recording == true || model?.state?.live == true else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "OBS sigue activo en servidor"
        alert.informativeText = "Cerrar el panel no detiene OBS, pero corta el envío de pantalla por NDI. Podés volver o cerrar dejando OBS en marcha."
        alert.addButton(withTitle: "Volver al ensayo"); alert.addButton(withTitle: "Cerrar panel")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct AnimaStudioApp: App {
    init() {
        // NDI peers and SSH may close their sockets/pipes during reconnect.
        // Surface EPIPE to the caller instead of terminating the entire panel.
        signal(SIGPIPE, SIG_IGN)
        if ProcessInfo.processInfo.arguments.contains("--signal-selftest") {
            raise(SIGPIPE)
            print("SIGPIPE survived; app remains available for reconnect")
            exit(0)
        }
    }
    @NSApplicationDelegateAdaptor(StudioDelegate.self) var delegate
    @StateObject private var model = StudioModel()
    var body: some Scene {
        Window("Anima Studio", id: "studio") {
            StudioView(model: model).onAppear { delegate.model = model }
                .frame(minWidth: 1200, minHeight: 700).preferredColorScheme(.dark)
        }.defaultSize(width: 1500, height: 950)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
struct StudioView: View {
    @ObservedObject var model: StudioModel
    @State private var showHelp = false
    @State private var showRecordings = ProcessInfo.processInfo.arguments.contains("--library")
    @State private var showLive = false
    @State private var checkedPicture = false
    @State private var confirmCamera = false
    @State private var showSettings = !Demo.enabled && ConnectionSettings.load().host.isEmpty
    var body: some View {
        GeometryReader { space in
        VStack(spacing: 0) {
        header.padding(.horizontal, 20).padding(.vertical, 14)
        Divider().overlay(StudioPalette.separator)
        HStack(alignment: .top, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                sceneButton("Charla", key: "charla", prefix: "1", icon: "person.fill", subtitle: "Vos al frente")
                sceneButton("Pantalla", key: "pantalla", prefix: "2", icon: "rectangle.on.rectangle", subtitle: "Mostrar y comentar")
                sceneButton("Pausa", key: "pausa", prefix: "3", icon: "pause.fill", subtitle: "Vuelvo enseguida")
                Spacer()
                Text("OBS remoto").foregroundStyle(StudioPalette.secondary).font(.caption)
            }
            MonitorPicker(model: model, capture: model.monitorCapture)
                VStack(alignment: .leading, spacing: 9) {
                    preview(model.horizontal, title: "", ratio: 16/9)
                    HStack {
                        Label(model.state?.muted == true ? "Micrófono silenciado" : "Micrófono", systemImage: model.state?.muted == true ? "mic.slash" : "mic")
                            .font(.system(size: 12)).foregroundStyle(StudioPalette.secondary)
                        Spacer()
                        if model.connected { Text(String(format: "%.0f fps", model.state?.fps ?? 0)).font(.system(size: 12, design: .monospaced)).foregroundStyle(StudioPalette.secondary) }
                    }
                    ProgressView(value: max(0, min(1, ((model.state?.peak ?? -96) + 60)/60))).tint(model.state?.muted == true ? .gray : .green).accessibilityLabel("Nivel del micrófono")
                    if model.state?.simulated == true { Text("Cámara de ensayo").font(.system(size: 12)).foregroundStyle(.orange) }
                    if model.state?.verticalEnabled == true && model.state?.recording != model.state?.recordingVertical { Text("Las grabaciones no coinciden: revisá el formato vertical en OBS.").font(.system(size: 12)).foregroundStyle(.orange) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(StudioPalette.separator)
            HStack(spacing: 10) {
                Button { Task { await model.action(model.state?.recording == true ? "record-stop" : "record-start") } } label: {
                    Label(model.state?.recording == true ? "Detener ensayo" : "Grabar ensayo", systemImage: model.state?.recording == true ? "stop.fill" : "record.circle")
                }.buttonStyle(StudioButton(selected: model.state?.recording == true)).disabled(!model.canRehearse)
                Button { SharedBrowser.shared.show() } label: { Label("Compartir web", systemImage: "globe") }.buttonStyle(StudioButton())
                Button { Task { await model.action("mute", ["muted": !(model.state?.muted ?? false)]) } } label: { Image(systemName: model.state?.muted == true ? "mic.slash.fill" : "mic.fill") }.buttonStyle(StudioButton()).disabled(!model.canControl).help("Silenciar o activar micrófono")
                Spacer()
                Menu { Button("Chat de TikTok (Chrome)") { model.chat("TikTok") }; Button("Chat y panel de YouTube (Chrome)") { model.chat("YouTube") }; Button("Chat y panel de X (Chrome)") { model.chat("X") } } label: { Label("Chats", systemImage: "bubble.left.and.bubble.right") }.menuStyle(.borderlessButton).frame(width: 80)
                Button { showRecordings = true; Task { await model.refreshFiles() } } label: { Label("Biblioteca", systemImage: "film.stack") }.buttonStyle(StudioButton()).help("Grabaciones del servidor")
                Button { showHelp = true } label: { Image(systemName: "questionmark") }.buttonStyle(StudioButton()).help("Cómo ensayar")
            }
        }.frame(width: (space.size.width - 64) * 0.66)
        VStack(spacing: 12) {
            preview(model.portrait, title: "Vertical", ratio: 9/16)
            HStack(spacing: 12) {
                zoomButton("minus", "out", "Alejar pantalla de TikTok")
                Text((model.state?.tiktokZoom?.factor ?? 1.0).formatted(.number.precision(.fractionLength(0...1))) + "×").monospacedDigit()
                zoomButton("plus", "in", "Acercar pantalla de TikTok")
                zoomButton("arrow.counterclockwise", "reset", "Restablecer pantalla de TikTok")
            }
            HStack(spacing: 18) {
                zoomButton("arrow.left", "left", "Ver más a la izquierda")
                zoomButton("arrow.up", "up", "Ver más arriba")
                zoomButton("arrow.down", "down", "Ver más abajo")
                zoomButton("arrow.right", "right", "Ver más a la derecha")
            }
        }.frame(width: (space.size.width - 64) * 0.34, height: max(400, space.size.height - 120), alignment: .top)
        }.padding(20)
        }
        }.background(StudioPalette.canvas).foregroundStyle(StudioPalette.primary)
            .task { if Demo.enabled { Demo.install(model); return }; guard !ProcessInfo.processInfo.arguments.contains("--design-preview"), !ProcessInfo.processInfo.arguments.contains("--light-preview") else { return }; await model.action("prepare"); while !Task.isCancelled { await model.poll(); try? await Task.sleep(nanoseconds: 2_000_000_000) } }
            .sheet(isPresented: $showHelp) { help }
            .sheet(isPresented: $showSettings) { ConnectionSettingsView(model: model) }
            .sheet(isPresented: $showRecordings) { StudioLibraryView(model: model) }
            .sheet(isPresented: $showLive) { liveConfirmation }

    }
    func destination(_ platform: String, active: Bool) -> some View {
        Button { model.dashboard(platform) } label: {
            HStack(spacing: 6) {
                Circle().fill(active ? Color.green : StudioPalette.secondary.opacity(0.4)).frame(width: 5, height: 5)
                Text(platform).font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.up.right").font(.system(size: 9))
            }.padding(.horizontal, 9).padding(.vertical, 7)
        }.buttonStyle(.plain).help("\(platform): abrir chat y panel oficial. \(active ? "OBS enviando señal; verificá publicación." : "Sin envío activo de OBS.")")
    }
    func audience(_ platform: String) -> some View {
        return Button { model.dashboard(platform) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(platform) · espectadores ↗").font(.system(size: 13, weight: .semibold))
                Text("Ver en el panel oficial · apertura manual").font(.system(size: 11)).foregroundStyle(StudioPalette.secondary)
            }.padding(.horizontal, 13).padding(.vertical, 9).frame(minWidth: 215, alignment: .leading).background(StudioPalette.raised).clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).help("Abre el panel oficial sólo cuando tocás este botón. No lee ni controla Chrome y no hay contador integrado de espectadores.")
    }
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Anima Studio").font(.system(size: 16, weight: .semibold))
                if Demo.enabled { Text("OFFLINE DEMO · EXAMPLE SOURCES").font(.system(size: 10)).foregroundStyle(.orange) }
                HStack(spacing: 7) {
                    Circle().fill(model.connected ? (model.state?.live == true ? .red : .green) : .gray).frame(width: 7, height: 7)
                    Text(model.connected ? (model.state?.live == true ? "OBS transmitiendo" : "Listo") : "Desconectado").font(.system(size: 11))
                }.foregroundStyle(StudioPalette.secondary)
            }
            destination("TikTok", active: model.state?.tiktokOutputActive == true)
            destination("YouTube", active: model.state?.youtube?.active == true)
            destination("X", active: model.state?.xActive == true)
            Spacer()
            if !Demo.enabled && !ConnectionSettings.load().lightHost.isEmpty { LightControlView().padding(.trailing, 12) }
            Button { showSettings = true } label: { Image(systemName: "gearshape") }.buttonStyle(StudioButton()).help("Conexión al servidor")
            if model.state?.recording == true {
                Text("● REC  " + (model.state?.timecode.prefix(8) ?? "")).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(StudioPalette.accent)
            }
            if model.busy { ProgressView().controlSize(.small) }
            Button(model.state?.live == true ? "Terminar vivo…" : "Salir en vivo…") { checkedPicture = false; showLive = true }.buttonStyle(StudioButton(selected: true)).disabled(!model.canControl)
            Button { Task { await model.action("prepare") } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(StudioButton()).disabled(model.busy).help(model.connected ? "Reconectar" : "Preparar estudio").accessibilityLabel("Reconectar estudio")
        }
    }
    func zoomButton(_ icon: String, _ action: String, _ label: String) -> some View {
        Button { Task { await model.action("tiktok-zoom", ["action": action]) } } label: {
            Image(systemName: icon).font(.system(size: 16, weight: .medium)).frame(width: 36, height: 32)
                .background(StudioPalette.raised)
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
            .disabled(!model.canControl || model.state?.tiktokZoom == nil || model.state?.sceneKey != "pantalla")
    }
    func sceneButton(_ title: String, key: String, prefix: String, icon: String, subtitle: String) -> some View {
        Button { Task { await model.action("scene", ["scene": key]) } } label: {
            HStack(spacing: 9) { Image(systemName: icon).font(.system(size: 14)); Text(title).font(.system(size: 13, weight: .medium)); Spacer(); if model.connected && model.state?.sceneKey == key { Circle().fill(StudioPalette.accent).frame(width: 5, height: 5) } }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 13)
            .background(model.state?.sceneKey == key ? StudioPalette.raised : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(model.state?.sceneKey == key ? StudioPalette.accent : Color.clear).frame(height: 2) }
            .disabled(!model.canControl).help(subtitle)
    }
    func preview(_ image: NSImage?, title: String, ratio: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(StudioPalette.secondary) }
            ZStack {
                Color.black
                if let image { GeometryReader { geometry in Image(nsImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height) } }
                else { VStack(spacing: 9) { Image(systemName: "video.slash").font(.system(size: 25)); Text(model.connected ? "Sin imagen" : "Sin conexión").font(.system(size: 12)) }.foregroundStyle(StudioPalette.secondary) }
            }.frame(maxWidth: .infinity).aspectRatio(ratio, contentMode: .fit)
        }
    }
    var help: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tu primer ensayo").font(.title2.bold())
            Text("1. Configurá el servidor y la conexión SSH en Ajustes.\n\n2. Elegí Monitor 1, 2 o 3. El cliente envía sólo ese monitor por NDI.\n\n3. Charla / Pantalla / Pausa cambia las escenas configuradas en OBS.\n\n4. Grabar ensayo no publica nada. Revisá el audio en el archivo; las vistas previas son imágenes sin sonido.\n\n5. Biblioteca → Traer copia una grabación del servidor sin borrar el original.").font(.system(size: 14)).lineSpacing(3)
            Text("OBS sigue trabajando si cerrás el panel, pero el envío del monitor se detiene. No hay recopilación automática de audiencia.").font(.caption).foregroundStyle(.orange)
            HStack { Link("NDI®", destination: URL(string: "https://ndi.video")!); Spacer(); Button("Entendido") { showHelp = false } }
        }.padding(28).frame(width: 570).background(StudioPalette.canvas).foregroundStyle(StudioPalette.primary)
    }
    var recordings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grabaciones en servidor").font(.title2.bold())
            Text("Horizontal y vertical se guardan por separado. Traer copia el archivo a Películas → Anima Studio; el original no se borra.").font(.system(size: 12)).foregroundStyle(StudioPalette.secondary)
            if model.transferring { ProgressView("Trayendo grabación…") }
            ScrollView {
                VStack(spacing: 10) { ForEach(model.files) { file in HStack {
                    VStack(alignment: .leading) { Text(file.name.contains("vertical") ? "TikTok · vertical" : "Horizontal").font(.headline); Text(file.name).font(.system(size: 11)).foregroundStyle(StudioPalette.secondary) }
                    Spacer(); Button("Traer") { Task { await model.download(file) } }.disabled(model.transferring || model.state?.recording == true)
                }.padding(12).background(StudioPalette.raised).clipShape(RoundedRectangle(cornerRadius: 8)) } }
            }.frame(height: 270)
            if let error = model.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack { Button("Actualizar") { Task { await model.refreshFiles() } }; Spacer(); Button("Listo") { showRecordings = false }.keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 610).background(StudioPalette.canvas).foregroundStyle(StudioPalette.primary)
    }
    var liveConfirmation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.state?.live == true ? "Terminar la transmisión" : "Salir en \(model.liveDestinations)").font(.title2.bold())
            if model.state?.live == true {
                Text("Se detendrán todas las salidas de OBS y la grabación automática. Podés traer los videos desde Biblioteca. Los originales se conservan en el servidor.")
            } else {
                Text("Esto inicia los destinos configurados en el servidor y graba en OBS. Confirmá la publicación en los paneles oficiales: enviar video no significa estar público.")
                if model.state?.youtube?.enabled == true {
                    Text("Prepará la emisión en cada plataforma antes de iniciar el envío. Al terminar, verificá el cierre también en los paneles oficiales.").font(.system(size: 12)).foregroundStyle(.orange)
                    Button("Abrir YouTube Studio ↗") { model.dashboard("YouTube") }
                    Button("Abrir X Live Studio ↗") { model.dashboard("X") }
                }
                if model.state?.simulated == true { Text("Demo sin conexión: no se puede transmitir desde este modo.").foregroundStyle(.orange) }
                Toggle("Revisé la imagen, escuché mi ensayo y confirmé los destinos", isOn: $checkedPicture)
            }
            HStack {
                Button("Cancelar") { showLive = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.state?.live == true ? "Sí, terminar vivo" : "Sí, iniciar transmisión pública") {
                    let stopping = model.state?.live == true
                    showLive = false
                    Task { await model.action(stopping ? "live-stop" : "live-start", ["confirmation":stopping ? "STOP_PUBLIC_ALL_DESTINATIONS" : model.liveConfirmationToken, "checkedPictureAndVoice":checkedPicture]) }
                }.buttonStyle(StudioButton(selected: true)).disabled(model.state?.live != true && (!checkedPicture || model.state?.simulated != false))
            }
        }.padding(28).frame(width: 570).background(StudioPalette.canvas).foregroundStyle(StudioPalette.primary)
    }
}
