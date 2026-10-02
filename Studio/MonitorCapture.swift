import AppKit
import ScreenCaptureKit
import CoreMedia
import NDIBridge

struct StudioMonitor: Identifiable {
    let id: CGDirectDisplayID
    let number: Int
    let name: String
}
// NDI and pixel-buffer ownership stay on this bounded serial queue.
final class MonitorFrames: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "studio.monitor.frames", qos: .userInitiated)
    private var sender: UnsafeMutableRawPointer?
    private var frames = 0
    func open() throws -> String {
        try queue.sync {
            if sender == nil { sender = studio_ndi_create() }
            guard let sender, let name = studio_ndi_name(sender) else {
                throw StudioError.message("No pude cargar NDI. Conservá NDI Scan Converter instalado en Aplicaciones.")
            }
            return String(cString: name)
        }
    }
    var count: Int { queue.sync { frames } }
    func close() { queue.sync { studio_ndi_destroy(sender); sender = nil; frames = 0 } }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let sender,
              let pixel = sampleBuffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddress(pixel) else { return }
        studio_ndi_send(sender, bytes.assumingMemoryBound(to: UInt8.self), Int32(CVPixelBufferGetWidth(pixel)), Int32(CVPixelBufferGetHeight(pixel)), Int32(CVPixelBufferGetBytesPerRow(pixel)))
        frames += 1
    }
}
@MainActor final class MonitorCapture: ObservableObject {
    @Published var monitors: [StudioMonitor] = []
    @Published var selected: CGDirectDisplayID?
    @Published private(set) var includeStudio = false
    @Published private(set) var updatingInclusion = false
    private var stream: SCStream?
    private let frames = MonitorFrames()
    init() { refresh() }
    func refresh() {
        monitors = NSScreen.screens.sorted {
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            return $0.frame.minY > $1.frame.minY
        }.enumerated().compactMap { index, screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return StudioMonitor(id: id, number: index + 1, name: screen.localizedName)
        }
    }
    static func dimensions(width: Int, height: Int) -> (Int, Int) {
        let ratio = min(1, min(1920.0 / Double(max(1, width)), 1080.0 / Double(max(1, height))))
        return (max(2, Int(Double(width) * ratio) / 2 * 2), max(2, Int(Double(height) * ratio) / 2 * 2))
    }
    func start(_ id: CGDirectDisplayID) async throws -> String {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw StudioError.message("Permití Anima Studio en Ajustes → Privacidad y seguridad → Grabación de pantalla. Después reabrí solo este panel; OBS sigue en vivo.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            refresh(); throw StudioError.message("Ese monitor ya no está conectado. Elegí otro.")
        }
        let sourceName = try frames.open()
        let config = SCStreamConfiguration()
        let (width, height) = Self.dimensions(width: display.width, height: display.height)
        config.width = width; config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3; config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true; config.capturesAudio = false
        // Avoid recursive control-panel previews; never capture another display.
        let ownApps = content.applications.filter { Self.excludeApplication(pid: $0.processID, ownPID: ProcessInfo.processInfo.processIdentifier, includeStudio: includeStudio) }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let before = frames.count
        if let stream {
            try await stream.updateContentFilter(filter)
            try await stream.updateConfiguration(config)
        } else {
            let candidate = SCStream(filter: filter, configuration: config, delegate: frames)
            try candidate.addStreamOutput(frames, type: .screen, sampleHandlerQueue: frames.queue)
            do { try await candidate.startCapture(); stream = candidate }
            catch { frames.close(); throw error }
        }
        for _ in 0..<40 {
            if frames.count > before { return sourceName }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw StudioError.message("El monitor todavía no entregó imagen. La transmisión sigue; volvé a elegirlo.")
    }
    static func excludeApplication(pid: Int32, ownPID: Int32, includeStudio: Bool) -> Bool {
        !includeStudio && pid == ownPID
    }
    func setIncludeStudio(_ enabled: Bool) async throws {
        guard !updatingInclusion else { return }
        updatingInclusion = true
        defer { updatingInclusion = false }
        if let stream, let selected {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == selected }) else {
                throw StudioError.message("Ese monitor ya no está conectado. Elegí otro.")
            }
            let excluded = content.applications.filter { Self.excludeApplication(pid: $0.processID, ownPID: ProcessInfo.processInfo.processIdentifier, includeStudio: enabled) }
            try await stream.updateContentFilter(SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: []))
        }
        includeStudio = enabled
    }
    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil; frames.close(); selected = nil
    }
}
