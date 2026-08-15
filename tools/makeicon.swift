import AppKit

// Same sprite as the menu bar icon in App.swift. Kept in step by hand — it is ten lines and
// changes roughly never; sharing it would mean bundling a resource for no real gain.
let pixels = [
    "0011111111111100",
    "0011111111111100",
    "0011011111101100",
    "0011011111101100",
    "1111111111111111",
    "1111111111111111",
    "0011111111111100",
    "0011111111111100",
    "0001010000101000",
    "0001010000101000",
]

let ink = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.086, alpha: 1)   // near-black ground
let clay = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // the sprite

/// Draws one square icon. Each size is rendered fresh rather than downscaled from 1024,
/// so the sprite's edges stay hard at 16pt instead of turning to mush.
func icon(_ side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    // macOS icons are a rounded square inset inside the canvas, not edge to edge.
    let inset = side * 0.09
    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    ink.setFill()
    NSBezierPath(roundedRect: plate, xRadius: side * 0.2, yRadius: side * 0.2).fill()

    let cols = CGFloat(pixels[0].count), rows = CGFloat(pixels.count)
    let cell = (plate.width * 0.62 / cols).rounded(.down).clamped(min: 1)
    let spriteWidth = cell * cols, spriteHeight = cell * rows
    let originX = (side - spriteWidth) / 2
    let originY = (side - spriteHeight) / 2

    clay.setFill()
    for (r, row) in pixels.enumerated() {
        for (c, pixel) in row.enumerated() where pixel == "1" {
            NSRect(x: originX + CGFloat(c) * cell,
                   y: originY + (rows - 1 - CGFloat(r)) * cell,
                   width: cell, height: cell).fill()
        }
    }

    image.unlockFocus()
    return image
}

extension CGFloat {
    func clamped(min lower: CGFloat) -> CGFloat { Swift.max(self, lower) }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// The set iconutil expects.
for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                      (256, 1), (256, 2), (512, 1), (512, 2)] {
    let side = base * scale
    guard let tiff = icon(CGFloat(side)).tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { continue }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try png.write(to: out.appendingPathComponent(name))
}
print("wrote iconset to \(out.path)")
