import AppKit

// Reproducible silent explainer; screenshots come from the real native --demo mode.
// No simulated footage is presented as a public broadcast.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("swift promo/render.swift OUTPUT_DIR ASSET_DIR") }
let output = URL(fileURLWithPath: args[1]), assets = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let W: CGFloat = 1920, H: CGFloat = 1080
let bg = NSColor(calibratedRed:0.035,green:0.045,blue:0.06,alpha:1)
let panel = NSColor(calibratedRed:0.075,green:0.095,blue:0.125,alpha:1)
let mint = NSColor(calibratedRed:0.48,green:0.96,blue:0.73,alpha:1)
let muted = NSColor(calibratedRed:0.60,green:0.67,blue:0.75,alpha:1)
func box(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ color:NSColor) { color.setFill(); NSRect(x:x,y:H-y-h,width:w,height:h).fill() }
func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:NSColor = .white,_ width:CGFloat = 1720) {
    let p=NSMutableParagraphStyle();p.lineBreakMode = .byWordWrapping;p.lineSpacing = 8
    (s as NSString).draw(in:NSRect(x:x,y:H-y-260,width:width,height:260),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:.semibold),.foregroundColor:color,.paragraphStyle:p])
}
func screenshot(_ name:String,_ rect:NSRect) {
    let image=NSImage(contentsOf:assets.appendingPathComponent(name))!
    let scale=min(rect.width/image.size.width,rect.height/image.size.height)
    let size=NSSize(width:image.size.width*scale,height:image.size.height*scale)
    image.draw(in:NSRect(x:rect.minX+(rect.width-size.width)/2,y:H-rect.minY-size.height,width:size.width,height:size.height))
}
func card(_ x:CGFloat,_ title:String,_ body:String) { box(x,385,740,340,panel);box(x,385,740,5,mint);text(title,x+42,430,42);text(body,x+42,500,29,muted,650) }
for i in 0..<8 {
    let image=NSImage(size:NSSize(width:W,height:H)); image.lockFocus();box(0,0,W,H,bg)
    text("ANIMA STUDIO",90,45,25,mint)
    text(String(format:"%02d / 08",i+1),1645,45,22,muted,210)
    switch i {
    case 0:
        text("I just wanted to stream.",90,190,92)
        text("So I put OBS on another Mac.",90,335,68,mint)
        box(90,560,1740,255,panel)
        text("One machine runs the broadcast.",140,615,48)
        text("The other is where I actually work.",140,685,43,muted)
        text("A remote control panel I built for my own streams.",90,915,29,muted)
    case 1:
        text("Your spare Mac becomes the engine.",90,175,69)
        card(90,"MAIN MAC","Anima Studio\nScenes · monitor selection · previews")
        card(1090,"SERVER MAC","OBS\nComposition · encoding · recordings")
        text("SSH →",860,440,32,mint,210)
        text("NDI →",860,540,32,mint,210)
        text("Control over SSH. Screen video over your local network.",90,845,35,muted)
        text("Camera and microphone reach OBS separately.",90,925,25,muted)
    case 2:
        text("Your main Mac is the control panel.",90,125,61)
        screenshot("panel-wide.png",NSRect(x:210,y:245,width:1500,height:735))
    case 3:
        text("A whole desktop is tiny on a phone.",90,125,62)
        screenshot("panel-wide.png",NSRect(x:90,y:265,width:1200,height:685))
        box(1370,340,430,390,panel)
        text("Horizontal",1400,375,37)
        text("looks fine.",1400,435,34,muted,390)
        text("Vertical?",1400,535,37,mint)
        text("Needs its own framing.",1400,605,34,muted,360)
    case 4:
        text("Zoom the vertical. Keep the horizontal.",90,125,61)
        screenshot("panel-zoom.png",NSRect(x:210,y:245,width:1500,height:735))
    case 5:
        text("Less operating. More streaming.",90,170,76)
        card(90,"ONE MONITOR","Pick the screen you want to show.\nKeep the others out of the broadcast.")
        card(1090,"ONE PANEL","Talk · Screen · Pause\nRecord · mute · retrieve recordings")
        text("Optional: Elgato light control + clean editing-master setup.",90,860,33,mint)
    case 6:
        text("The engine stays on the server.",90,170,76)
        box(90,365,1740,425,panel)
        text("Close the panel → OBS keeps running.",145,425,56,mint)
        text("The client's monitor feed stops when you close it.",145,535,37)
        text("Keep the client open while sharing its screen.",145,615,34,muted)
        text("Recordings stay on the server. Bring a copy when you need it.",90,890,33,muted)
    default:
        text("Built for my setup.",90,180,88)
        text("Now yours to adapt.",90,300,88,mint)
        box(90,510,1740,200,panel)
        text("github.com/GBurgardt/anima-studio",135,563,58)
        text("Open source · macOS developer beta · OBS + SSH",90,790,37)
        text("Setup guide, optional integrations, tests. No cloud account.",90,865,29,muted)
    }
    text("Native panel demo · example sources · not a live broadcast",90,1025,20,muted)
    image.unlockFocus()
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(String(format:"%02d.png",i)))
}
