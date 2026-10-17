// recortar-final <entrada> <saida> <lado> [<saida_live> <lado_live>]  (FLOOD=1: remove só o fundo liso, mantém aura)
// Recorte com Vision (como tools/recortar-sprite.swift), limpa a franja do fundo, centraliza e reduz sem interpolação.
import AppKit
import Vision

let args = CommandLine.arguments
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[1])))!
let cg = rep.cgImage!
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w*h*4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

// cor do fundo: média dos 4 cantos
var bg = [0.0, 0.0, 0.0]
for (x, y) in [(2, 2), (w-3, 2), (2, h-3), (w-3, h-3)] { for c in 0..<3 { bg[c] += Double(px[(y*w+x)*4+c]) / 4 } }
func nearBg(_ i: Int, _ tol: Double) -> Bool {
  let d = (0..<3).map { abs(Double(px[i+$0]) - bg[$0]) }.max()!
  return d < tol
}

if ProcessInfo.processInfo.environment["FLOOD"] != nil {
  // Ultimate com aura: o Vision corta a aura, então remove só o fundo liso ligado às bordas
  var seenF = [Bool](repeating: false, count: w*h)
  var stackF: [Int] = []
  for x in 0..<w { stackF += [x, (h-1)*w + x] }
  for y in 0..<h { stackF += [y*w, y*w + w-1] }
  while let p = stackF.popLast() {
    if seenF[p] || !nearBg(p*4, 22) { continue }
    seenF[p] = true
    px[p*4] = 0; px[p*4+1] = 0; px[p*4+2] = 0; px[p*4+3] = 0
    let x = p % w, y = p / w
    if x > 0 { stackF.append(p-1) }; if x < w-1 { stackF.append(p+1) }
    if y > 0 { stackF.append(p-w) }; if y < h-1 { stackF.append(p+w) }
  }
} else {
let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: cg)
try! handler.perform([req])
guard let obs = req.results?.first else { print("sem objeto:", args[1]); exit(1) }
let maskBuf = try! obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
CVPixelBufferLockBaseAddress(maskBuf, .readOnly)
let mw = CVPixelBufferGetWidth(maskBuf), mh = CVPixelBufferGetHeight(maskBuf)
let row = CVPixelBufferGetBytesPerRow(maskBuf)
let base = CVPixelBufferGetBaseAddress(maskBuf)!.assumingMemoryBound(to: UInt8.self)
let isFloat = CVPixelBufferGetPixelFormatType(maskBuf) == kCVPixelFormatType_OneComponent32Float
for y in 0..<h {
  for x in 0..<w {
    let mx = x * mw / w, my = y * mh / h
    let v: Float = isFloat ? base.advanced(by: my*row).withMemoryRebound(to: Float.self, capacity: mw) { $0[mx] } : Float(base[my*row + mx]) / 255
    let i = (y*w + x) * 4
    // fora da máscara, ou cor de fundo encostada na máscara: transparente
    if v < 0.5 { px[i] = 0; px[i+1] = 0; px[i+2] = 0; px[i+3] = 0 }
  }
}
CVPixelBufferUnlockBaseAddress(maskBuf, .readOnly)
}

// franja: pixels com cor de fundo vizinhos de transparente, em várias passadas
for _ in 0..<12 {
  var kill: [Int] = []
  for y in 1..<(h-1) {
    for x in 1..<(w-1) {
      let i = (y*w + x) * 4
      if px[i+3] == 0 || !nearBg(i, 28) { continue }
      if px[i+3-4] == 0 || px[i+3+4] == 0 || px[i+3-w*4] == 0 || px[i+3+w*4] == 0 { kill.append(i) }
    }
  }
  if kill.isEmpty { break }
  for i in kill { px[i] = 0; px[i+1] = 0; px[i+2] = 0; px[i+3] = 0 }
}
// fundo preso dentro do desenho (ex.: entre braço e corpo) com área grande: flood fill a partir do fundo já removido não alcança,
// então removemos ilhas de cor de fundo maiores que 0,3% da imagem
var seen = [Bool](repeating: false, count: w*h)
for start in 0..<(w*h) {
  if seen[start] || px[start*4+3] == 0 || !nearBg(start*4, 6) { continue }
  var stack = [start], comp: [Int] = []
  seen[start] = true
  while let p = stack.popLast() {
    comp.append(p)
    let x = p % w, y = p / w
    for q in [x > 0 ? p-1 : -1, x < w-1 ? p+1 : -1, y > 0 ? p-w : -1, y < h-1 ? p+w : -1] where q >= 0 {
      if !seen[q] && px[q*4+3] != 0 && nearBg(q*4, 6) { seen[q] = true; stack.append(q) }
    }
  }
  if comp.count > w*h*3/1000 { for p in comp { px[p*4] = 0; px[p*4+1] = 0; px[p*4+2] = 0; px[p*4+3] = 0 } }
}

var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where px[(y*w+x)*4+3] != 0 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let full = ctx.makeImage()!
let crop = full.cropping(to: CGRect(x: minX, y: minY, width: maxX-minX+1, height: maxY-minY+1))!

func write(_ side: Int, _ path: String) {
  let pad = side / 40
  let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  out.interpolationQuality = side < 200 ? .high : .none
  let s = Double(side - 2*pad) / Double(max(crop.width, crop.height))
  let cw = Double(crop.width) * s, ch = Double(crop.height) * s
  out.draw(crop, in: CGRect(x: (Double(side)-cw)/2, y: (Double(side)-ch)/2, width: cw, height: ch))
  try! NSBitmapImageRep(cgImage: out.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
write(Int(args[3])!, args[2])
if args.count > 5 { write(Int(args[5])!, args[4]) }
