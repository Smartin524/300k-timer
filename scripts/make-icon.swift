import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let canvas = CGFloat(pixels)
        // Transparent background: a single green system hourglass remains legible in both appearances.
        let configuration = NSImage.SymbolConfiguration(pointSize: canvas * 0.78, weight: .medium)
        let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)!
            .withSymbolConfiguration(configuration)!
        let height = canvas * 0.82
        let width = height * symbol.size.width / symbol.size.height
        symbol.draw(in: NSRect(x: (canvas - width) / 2, y: (canvas - height) / 2, width: width, height: height))
        NSColor(srgbRed: 0.12, green: 0.62, blue: 0.30, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .sourceIn)
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try representation.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", destination.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
