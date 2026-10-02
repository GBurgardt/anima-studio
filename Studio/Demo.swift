import AppKit
import SwiftUI

// Offline visual fixture. Explicitly labelled, never connects to OBS or NDI.
enum Demo {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--demo") }
    static var stage: Int { let a = ProcessInfo.processInfo.arguments; guard let i = a.firstIndex(of: "--stage"), i + 1 < a.count else { return 0 }; return Int(a[i + 1]) ?? 0 }
    static func screen(vertical: Bool, zoomed: Bool) -> NSImage {
        let size = vertical ? NSSize(width: 540, height: 960) : NSSize(width: 1280, height: 720)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.045, green: 0.06, blue: 0.085, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        func text(_ s: String, x: CGFloat, y: CGFloat, font: CGFloat, color: NSColor = .white) {
            (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: font, weight: .medium), .foregroundColor: color])
        }
        let mint = NSColor(calibratedRed: 0.45, green: 0.94, blue: 0.72, alpha: 1)
        text("BUILDING LIVE", x: 30, y: size.height - 55, font: vertical ? 24 : 32, color: mint)
        text("EXAMPLE SOURCE / NOT LIVE", x: 30, y: size.height - 86, font: vertical ? 13 : 17, color: .lightGray)
        let code = ["const studio = {", "  engine: 'server Mac',", "  client: 'main Mac',", "  transport: 'SSH + NDI'", "};", "", "await shareMonitor(2);", "await vertical.zoom(2.5);", "", "// horizontal stays intact"]
        let f: CGFloat = vertical ? (zoomed ? 29 : 14) : 30
        for (i, line) in code.enumerated() { text(line, x: 30, y: size.height - 155 - CGFloat(i) * (f + 14), font: f, color: i == 7 ? mint : .white) }
        if vertical {
            NSColor(calibratedRed: 0.1, green: 0.16, blue: 0.22, alpha: 1).setFill()
            NSRect(x: 20, y: 40, width: 500, height: 205).fill()
            text("CAMERA AREA", x: 130, y: 145, font: 25, color: mint)
            text("Your camera stays separate", x: 70, y: 108, font: 17, color: .lightGray)
        }
        image.unlockFocus()
        return image
    }
    @MainActor static func install(_ model: StudioModel) {
        let object: [String: Any] = ["scene":"Screen", "sceneKey":"pantalla", "verticalEnabled":true, "destinations":["YouTube","TikTok","X"], "verticalScene":"Vertical Screen", "recording":false, "recordingVertical":false, "live":false, "xActive":false,"tiktokOutputActive":false,"timecode":"00:00:00","muted":false,"peak": -18.0,"fps":30.0,"cpu":2.0,"freeGB":100.0,"simulated":true,"tiktokZoom":["factor":stage > 0 ? 2.5 : 1.0,"x":0.5,"y":0.5]]
        if let data = try? JSONSerialization.data(withJSONObject: object) { try? model.update(data) }
        model.horizontal = screen(vertical:false, zoomed:false)
        model.portrait = screen(vertical:true, zoomed:stage > 0)
        model.message = "OFFLINE DEMO — no device or network connection"
    }
    @MainActor static func captureIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let i = args.firstIndex(of:"--snapshot"), i + 1 < args.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now()+2) {
            guard let view = NSApp.windows.first(where: {$0.title == "Anima Studio"})?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in:view.bounds, to:rep)
            if let data = rep.representation(using:.png, properties:[:]) { try? data.write(to:URL(fileURLWithPath:args[i+1])) }
            NSApp.terminate(nil)
        }
    }
}
