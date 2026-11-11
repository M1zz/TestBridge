// Regenerate: swift Scripts/make-icon.swift icon-1024.png, then sips -z into Assets.xcassets/AppIcon.appiconset.
import AppKit
// TestBridge icon: a suspension bridge whose main cable is a check mark.
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }

let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.3))
ctx.addPath(platePath); ctx.setFillColor(rgb(20, 40, 90)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(platePath); ctx.clip()
let gradient = CGGradient(colorsSpace: nil, colors: [rgb(64, 120, 255), rgb(22, 44, 120)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

ctx.setLineCap(.round); ctx.setLineJoin(.round)
func stroke(_ points: [CGPoint], _ width: CGFloat, _ color: CGColor) {
    ctx.setStrokeColor(color); ctx.setLineWidth(width)
    ctx.addLines(between: points); ctx.strokePath()
}
let white = rgb(255, 255, 255), faint = rgb(255, 255, 255, 0.55), mint = rgb(110, 245, 170)
let deckY: CGFloat = 400
let left = CGPoint(x: 330, y: 590), dip = CGPoint(x: 455, y: 465), right = CGPoint(x: 700, y: 720)

// Side cables and hangers
stroke([CGPoint(x: 215, y: deckY), left], 14, faint)
stroke([right, CGPoint(x: 809, y: deckY)], 14, faint)
for x in stride(from: CGFloat(380), through: 650, by: 45) {
    let y = x <= dip.x ? left.y - (x - left.x) : dip.y + (x - dip.x) * (right.y - dip.y) / (right.x - dip.x)
    stroke([CGPoint(x: x, y: deckY), CGPoint(x: x, y: y)], 10, faint)
}
// Towers and deck
stroke([CGPoint(x: left.x, y: 310), left], 40, white)
stroke([CGPoint(x: right.x, y: 310), right], 40, white)
stroke([CGPoint(x: 215, y: deckY), CGPoint(x: 809, y: deckY)], 44, white)
// The check
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0, 20, 70, 0.45))
stroke([left, dip, right], 58, mint)

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
