import AppKit
let a = CommandLine.arguments
let img = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!.cgImage!
let r = CGRect(x: Int(a[3])!, y: Int(a[4])!, width: Int(a[5])!, height: Int(a[6])!)
try! NSBitmapImageRep(cgImage: img.cropping(to: r)!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
