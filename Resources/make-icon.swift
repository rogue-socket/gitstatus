// Generates Resources/AppIcon.icns from an SF Symbol.
// Run: swift Resources/make-icon.swift
import AppKit

let sizes: [(px: Int, name: String)] = [
    (16,  "icon_16x16.png"),
    (32,  "icon_16x16@2x.png"),
    (32,  "icon_32x32.png"),
    (64,  "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024,"icon_512x512@2x.png"),
]

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let dim = CGFloat(size)
    let img = NSImage(size: NSSize(width: dim, height: dim))
    img.lockFocus()
    defer { img.unlockFocus() }

    // Rounded-square background, macOS Big Sur style proportions.
    let inset = dim * 0.08
    let rect = NSRect(x: inset, y: inset, width: dim - 2*inset, height: dim - 2*inset)
    let radius = (dim - 2*inset) * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Teal gradient.
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.70, alpha: 1.0),
        NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.55, alpha: 1.0),
    ])!
    gradient.draw(in: path, angle: -90)

    // Branch glyph centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: dim * 0.55, weight: .semibold)
    if let glyph = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let gs = glyph.size
        let gx = (dim - gs.width) / 2
        let gy = (dim - gs.height) / 2
        NSColor.white.set()
        glyph.isTemplate = true
        let dest = NSRect(x: gx, y: gy, width: gs.width, height: gs.height)
        // Tint by drawing the symbol via NSImage tinting trick.
        let tinted = NSImage(size: gs)
        tinted.lockFocus()
        glyph.draw(in: NSRect(origin: .zero, size: gs))
        NSColor.white.set()
        NSRect(origin: .zero, size: gs).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: dest)
    }

    let rep = NSBitmapImageRep(focusedViewRect: NSRect(x: 0, y: 0, width: dim, height: dim))!
    return rep.representation(using: .png, properties: [:])!
}

for (px, name) in sizes {
    let data = render(size: px)
    let url = iconset.appendingPathComponent(name)
    try data.write(to: url)
}

// Pack into .icns
let icns = here.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()

// Clean up the iconset dir; keep only AppIcon.icns
try? FileManager.default.removeItem(at: iconset)
print("✓ wrote \(icns.path)")
