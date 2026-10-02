import AppKit
import SwiftUI

struct StudioState: Decodable {
    var sceneKey: String?
    var verticalEnabled: Bool?
    var destinations: [String]?
    var tiktokZoom: TikTokZoom?
    var mode: String?
    var scene: String
    var verticalScene: String
    var recording: Bool
    var recordingVertical: Bool
    var live: Bool
    var xActive: Bool
    var tiktokOutputActive: Bool
    var timecode: String
    var muted: Bool
    var peak: Double
    var fps: Double
    var cpu: Double
    var freeGB: Double
    var simulated: Bool
    var horizontal: String?
    var portrait: String?
    var previewError: String?
    var savedPath: String?
    var metrics: AudienceMetrics?
    var autoRecord: Bool?
    var youtube: YouTubeDestination?
    var x: YouTubeDestination?
}
struct TikTokZoom: Decodable { var factor: Double; var x: Double; var y: Double }
struct YouTubeDestination: Decodable {
    var enabled: Bool
    var configured: Bool
    var active: Bool
    var dashboardURL: String
    var message: String
}
struct RecordingFile: Decodable, Identifiable {
    var name: String
    var path: String
    var size: Int64?
    var modified: String?
    var ready: Bool?
    var id: String { path }
}
enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

/// JSON-line RPC over the user's existing private SSH connection. No local
/// listener, copied OBS password, shell interpolation, or Terminal windows.
@MainActor final class StudioConnection {
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    var localEngine: Bool { ProcessInfo.processInfo.arguments.contains("--local-engine") }

    func disconnect() {
        process?.terminationHandler = nil
        process?.terminate(); process = nil; input = nil
        failAll("Conexión reiniciada.")
    }

    func connect() throws {
        if process?.isRunning == true { return }
        buffer = Data()
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        let config = ConnectionSettings.load()
        try config.validate()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2", config.host, ConnectionSettings.quote(config.node) + " " + ConnectionSettings.quote(config.controller) + " --serve"]
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { Task { @MainActor in self?.receive(data) } }
        }
        // Drain stderr without displaying environment/SSH details or credentials.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        p.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.process === ended else { return }
                self.failAll("Se cortó la conexión con servidor. Revisá que ambas Macs estén encendidas y tocá Preparar estudio.")
            }
        }
        try p.run(); process = p; input = stdin
    }
    func failAll(_ text: String) {
        for task in timeouts.values { task.cancel() }; timeouts.removeAll()
        let callbacks = pending.values; pending.removeAll()
        for callback in callbacks { callback.resume(throwing: StudioError.message(text)) }
    }
    func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? String, let callback = pending.removeValue(forKey: id) else { continue }
            timeouts.removeValue(forKey: id)?.cancel()
            if object["ok"] as? Bool == true, let result = object["data"], let resultData = try? JSONSerialization.data(withJSONObject: result) { callback.resume(returning: resultData) }
            else { callback.resume(throwing: StudioError.message(object["error"] as? String ?? "No se pudo completar la acción.")) }
        }
    }
    func request(_ command: String, _ values: [String: Any] = [:]) async throws -> Data {
        try connect()
        let id = UUID().uuidString
        var message = values; message["cmd"] = command; message["id"] = id
        var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
        return try await withCheckedThrowingContinuation { callback in
            pending[id] = callback
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, let callback = self.pending.removeValue(forKey: id) else { return }
                self.timeouts.removeValue(forKey: id)
                callback.resume(throwing: StudioError.message("servidor no respondió a tiempo. El estado de OBS es desconocido; reconectá antes de repetir una acción."))
            }
            do { try input?.fileHandleForWriting.write(contentsOf: data) }
            catch { pending.removeValue(forKey: id); timeouts.removeValue(forKey: id)?.cancel(); callback.resume(throwing: error) }
        }
    }
}

@MainActor final class StudioModel: ObservableObject {
    @Published var state: StudioState?
    @Published var horizontal: NSImage?
    @Published var portrait: NSImage?
    @Published var connected = false
    @Published var busy = false
    @Published var message = "Prepará el estudio para ver lo que está saliendo."
    @Published var error: String?
    @Published var files: [RecordingFile] = []
    @Published var transferring = false
    @Published var reports: [StreamReport] = []
    @Published var syncStatus: SyncStatus?
    let connection = StudioConnection()
    let monitorCapture = MonitorCapture()
    func selectMonitor(_ monitor: StudioMonitor) async {
        guard canControl else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let source = try await monitorCapture.start(monitor.id)
            try update(await connection.request("monitor-source", ["source": source]))
            monitorCapture.selected = monitor.id
            try update(await connection.request("scene", ["scene": "pantalla"]))
            message = "Compartiendo Monitor \(monitor.number) · \(monitor.name). Los otros monitores no se capturan."
        } catch { self.error = error.localizedDescription }
    }
    private var libraryCache: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AnimaStudioPublic/LibraryCache.json") }
    init() {
        if let data = try? Data(contentsOf: libraryCache), let cached = try? JSONDecoder().decode(StudioLibrary.self, from: data) {
            files = cached.files; reports = cached.streams; syncStatus = cached.sync
        }
    }
    var canControl: Bool { connected && !busy && !Demo.enabled }
    var canRehearse: Bool { canControl && state?.live == false }

    static func image(_ dataURL: String?) -> NSImage? {
        guard let s = dataURL, let comma = s.firstIndex(of: ","), let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return NSImage(data: data)
    }
    func update(_ data: Data) throws {
        let next = try JSONDecoder().decode(StudioState.self, from: data)
        state = next; connected = true
        horizontal = Self.image(next.horizontal); portrait = Self.image(next.portrait)
        // Local, bounded health receipt for installation diagnostics. No images,
        // tokens, messages or browsing data are logged.
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AnimaStudio")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let info: [String: Any] = ["updatedAt":ISO8601DateFormatter().string(from: Date()),"connected":true,"scene":next.scene,"verticalScene":next.verticalScene,"recording":next.recording,"live":next.live,"horizontalPreview":horizontal != nil,"verticalPreview":portrait != nil,"localRecordings":files.filter(isLocal).count,"reports":reports.count,"recoveredReplayLocal":files.contains { $0.name.contains("recuperado") && isLocal($0) }]
            var receiptInfo = info
            receiptInfo["youtubeEnabled"] = next.youtube?.enabled ?? false
            receiptInfo["youtubeConfigured"] = next.youtube?.configured ?? false
            receiptInfo["youtubeActive"] = next.youtube?.active ?? false
            receiptInfo["xConfigured"] = next.x?.configured ?? false
            receiptInfo["xActive"] = next.xActive
            receiptInfo["mode"] = next.mode ?? "custom"
            if let receipt = try? JSONSerialization.data(withJSONObject: receiptInfo) { try? receipt.write(to: folder.appendingPathComponent("status.json"), options: .atomic) }
        }
        if let path = next.savedPath { message = "Ensayo guardado en el servidor. Abrí Biblioteca para traerlo."; _ = path }
    }
    func action(_ command: String, _ values: [String: Any] = [:]) async {
        guard !busy, !Demo.enabled else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try update(await connection.request(command, values))
            if command == "prepare" {
                message = "Conectado. Elegí una escena y, cuando quieras, grabá un ensayo."
            }
            if command == "record-start" { message = "Grabando en servidor, sin publicar. Cambiá de escena para ensayar." }
            if command == "scene" { message = "Escena actualizada en ambos formatos." }
            if command == "tiktok-zoom" { message = "Zoom solo en la pantalla de TikTok · horizontal y cámara sin cambios." }
            if command == "live-start" { message = "OBS tiene las salidas seleccionadas activas. Confirmá la recepción en los paneles oficiales." }
            if command == "live-stop" { message = "Envío detenido. Confirmá el cierre en los paneles oficiales. Traé las grabaciones desde Biblioteca." }
        } catch { self.error = error.localizedDescription; if command == "prepare" { connected = false } }
    }
    func poll() async {
        guard !busy, connected else { return }
        do { try update(await connection.request("status")) }
        catch { connected = false; horizontal = nil; portrait = nil; self.error = error.localizedDescription }
    }
    func refreshFiles() async {
        guard !Demo.enabled else { return }
        do {
            let data = try await connection.request("library")
            let library = try JSONDecoder().decode(StudioLibrary.self, from: data); files = library.files; reports = library.streams; syncStatus = library.sync
            try? FileManager.default.createDirectory(at: libraryCache.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? data.write(to: libraryCache, options: .atomic)
        }
        catch { self.error = error.localizedDescription }
    }
    var syncDescription: String {
        switch syncStatus?.phase {
        case "copying": return "Copiando videos a esta Mac en segundo plano… Podés seguir usando el panel."
        case "done": return "Biblioteca sincronizada · Películas → Anima Studio"
        default: return syncStatus?.message ?? "Traer copia el archivo desde el servidor y conserva el original."
        }
    }
    func localURL(_ file: RecordingFile) -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Anima Studio").appendingPathComponent(file.name) }
    func isLocal(_ file: RecordingFile) -> Bool {
        guard Self.safeRecording(file.path), let attrs = try? FileManager.default.attributesOfItem(atPath: localURL(file).path), let actual = attrs[.size] as? NSNumber else { return false }
        return file.size == nil ? actual.int64Value > 0 : actual.int64Value == file.size
    }
    func play(_ file: RecordingFile) { if isLocal(file) { NSWorkspace.shared.open(localURL(file)) } }
    func copyURI(_ file: RecordingFile) { guard isLocal(file) else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(localURL(file).absoluteString, forType: .string); message = "URI completa copiada." }
    func openFolder() { let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Anima Studio"); try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); NSWorkspace.shared.open(folder) }
    func dashboard(_ platform: String) {
        let raw = platform == "YouTube" ? youtubeDashboard : (platform == "TikTok" ? "https://livecenter.tiktok.com/realtime" : "https://studio.x.com/live")
        guard let url = URL(string: raw) else { return }; NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/Google Chrome.app"), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }
    var youtubeDashboard: String {
        guard let raw = state?.youtube?.dashboardURL, let url = URL(string: raw), url.scheme == "https", url.host == "studio.youtube.com" else { return "https://studio.youtube.com" }
        return raw
    }
    var liveDestinations: String { state?.destinations?.joined(separator: ", ") ?? "los destinos configurados" }
    var liveConfirmationToken: String { "START_CONFIGURED_OUTPUTS" }
    func download(_ file: RecordingFile) async {
        guard !transferring, Self.safeRecording(file.path), URL(fileURLWithPath: file.path).lastPathComponent == file.name, file.ready != false else { return }
        transferring = true; error = nil
        defer { transferring = false }
        do {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Anima Studio")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(file.name)
            let config = ConnectionSettings.load()
            try config.validate()
            try await Task.detached {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
                let source = config.host + ":" + ConnectionSettings.quote(file.path)
                p.arguments = ["-a", "--", source, destination.path]
                let sink = FileHandle.nullDevice; p.standardOutput = sink; p.standardError = sink
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0 else { throw StudioError.message("No se pudo traer el archivo. La copia original sigue segura en servidor.") }
            }.value
            message = "Grabación copiada a Películas → Anima Studio."
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { self.error = error.localizedDescription }
    }
    static func safeRecording(_ path: String) -> Bool {
        let root = ConnectionSettings.load().recordings
        guard !root.isEmpty else { return false }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return false }
        let name = String(path.dropFirst(prefix.count))
        return name.range(of: "^[A-Za-z0-9][A-Za-z0-9 ._-]*\\.(mp4|mkv|mov)$", options: [.regularExpression, .caseInsensitive]) != nil
    }
    func openNDI() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/NDI Scan Converter.app"), configuration: config) { _, error in
            if error != nil { Task { @MainActor in self.error = "No pude abrir NDI Scan Converter. Buscalo en Aplicaciones." } }
        }
    }
    func chat(_ kind: String) {
        if kind == "YouTube" || kind == "X" { dashboard(kind); return }
        // Reuse the exact chat/monitor links of the existing Anima setup.
        let raw = "https://livecenter.tiktok.com/live_monitor?apply_mode=11"
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/Google Chrome.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { Task { @MainActor in self.error = "No pude abrir Chrome. Abrí el panel de \(kind) en tu navegador." } }
        }
    }
}
