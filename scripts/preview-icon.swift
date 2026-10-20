import AppKit
let icon = NSImage(contentsOfFile: CommandLine.arguments[1])!
let image = NSImage(size: NSSize(width: 640, height: 320))
image.lockFocus()
NSColor(white: 0.97, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 320, height: 320).fill()
NSColor(white: 0.09, alpha: 1).setFill()
NSRect(x: 320, y: 0, width: 320, height: 320).fill()
for x in [32, 352] {
    icon.draw(in: NSRect(x: x, y: 32, width: 256, height: 256))
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
