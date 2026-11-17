import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 206, yRadius: 206)
NSColor(calibratedRed: 0.12, green: 0.50, blue: 0.94, alpha: 1).setFill()
background.fill()
let battery = NSBezierPath(roundedRect: NSRect(x: 229, y: 357, width: 532, height: 310), xRadius: 55, yRadius: 55)
NSColor.white.setStroke()
battery.lineWidth = 42
battery.stroke()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 786, y: 455, width: 42, height: 114), xRadius: 14, yRadius: 14).fill()
NSBezierPath(roundedRect: NSRect(x: 274, y: 402, width: 300, height: 220), xRadius: 18, yRadius: 18).fill()
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
