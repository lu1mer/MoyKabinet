import AppKit
import CoreGraphics

let target = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 1024
let height = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let canvas = CGRect(x: 0, y: 0, width: width, height: height)
let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
defer { bytes.deallocate() }
guard let context = CGContext(
    data: bytes, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("Unable to make icon context") }
let colors = [
    CGColor(red: 1.0, green: 0.32, blue: 0.62, alpha: 1),
    CGColor(red: 0.80, green: 0.08, blue: 0.43, alpha: 1)
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
context.fillEllipse(in: CGRect(x: -220, y: 530, width: 720, height: 720))
context.fillEllipse(in: CGRect(x: 660, y: -180, width: 600, height: 600))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let font = NSFont.systemFont(ofSize: 670, weight: .black)
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let mark = "м" as NSString
let bounds = mark.size(withAttributes: attributes)
mark.draw(at: CGPoint(x: (CGFloat(width) - bounds.width) / 2 - 24, y: (CGFloat(height) - bounds.height) / 2 - 45), withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: 800, y: 275, width: 73, height: 73))
guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("Unable to encode icon") }
try png.write(to: target)
