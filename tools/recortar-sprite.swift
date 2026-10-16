// Recorte de objeto com o Vision (o mesmo das Fotos), borda binária para manter o pixel art nítido.
// Antes, descarta as faixas das imagens vizinhas nas bordas (margem em pixels, opcional).
import AppKit
import Vision
import CoreImage

let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let margin = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 0
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: src)))!
var cg = rep.cgImage!
if margin > 0 {
  cg = cg.cropping(to: CGRect(x: margin, y: margin, width: cg.width - 2*margin, height: cg.height - 2*margin))!
}
let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: cg)
try! handler.perform([req])
guard let obs = req.results?.first else { print("sem objeto:", src); exit(1) }
let maskBuf = try! obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w*h*4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
CVPixelBufferLockBaseAddress(maskBuf, .readOnly)
let mw = CVPixelBufferGetWidth(maskBuf), mh = CVPixelBufferGetHeight(maskBuf)
let row = CVPixelBufferGetBytesPerRow(maskBuf)
let base = CVPixelBufferGetBaseAddress(maskBuf)!.assumingMemoryBound(to: UInt8.self)
let isFloat = CVPixelBufferGetPixelFormatType(maskBuf) == kCVPixelFormatType_OneComponent32Float
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
  for x in 0..<w {
    let mx = x * mw / w, my = y * mh / h
    let v: Float = isFloat ? base.advanced(by: my*row).withMemoryRebound(to: Float.self, capacity: mw) { $0[mx] } : Float(base[my*row + mx]) / 255
    let i = (y*w + x) * 4
    if v < 0.5 { px[i] = 0; px[i+1] = 0; px[i+2] = 0; px[i+3] = 0 }
    else { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
  }
}
CVPixelBufferUnlockBaseAddress(maskBuf, .readOnly)
let full = ctx.makeImage()!
let side = max(maxX-minX, maxY-minY) + 16
let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
out.interpolationQuality = .none
// buffer de cima para baixo; o CGImage cortado usa as mesmas coordenadas
let crop = full.cropping(to: CGRect(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1))!
out.draw(crop, in: CGRect(x: (side-crop.width)/2, y: (side-crop.height)/2, width: crop.width, height: crop.height))
try! NSBitmapImageRep(cgImage: out.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
print(dst.split(separator: "/").last!, side)
