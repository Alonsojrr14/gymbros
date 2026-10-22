// folha <saida.png> <imagens...>: folha de contato 5 por linha com o nome de cada arte, para revisar o lote
import AppKit
let files = CommandLine.arguments.dropFirst(2).map { $0 }
let cell = 220, cols = 5, rows = (files.count + cols - 1) / cols
let img = NSImage(size: NSSize(width: cols*cell, height: rows*(cell+18)))
img.lockFocus()
NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: cols*cell, height: rows*(cell+18)).fill()
for (i, f) in files.enumerated() {
  let x = (i % cols) * cell, y = (rows - 1 - i / cols) * (cell+18)
  NSImage(contentsOfFile: f)?.draw(in: NSRect(x: x+10, y: y+18, width: cell-20, height: cell-20))
  (URL(fileURLWithPath: f).deletingPathExtension().lastPathComponent as NSString).draw(at: NSPoint(x: x+4, y: y+2), withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
