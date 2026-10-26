import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (size, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
  for scale in scales {
    let px = size * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18).fill()
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .bold)
      .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
      .withSymbolConfiguration(cfg) {
      let sz = sym.size
      sym.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
  }
}
