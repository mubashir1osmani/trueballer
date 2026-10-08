import AppKit
import CoreGraphics

// StudyPlanner icon: a sticky note with a folded corner, a check mark where
// the plan lands, and a spark for the AI read. Renders 1024px light, dark
// and tinted variants for an iOS 18 single-size app icon.

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

enum Variant { case light, dark, tinted }

func draw(_ variant: Variant, to path: String) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip so y grows downward like a design tool.
    ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)

    // Background.
    switch variant {
    case .light:
        let bg = CGGradient(colorsSpace: space, colors: [rgb(10, 92, 84), rgb(4, 52, 50)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
        // Soft glow behind the note.
        let glow = CGGradient(colorsSpace: space, colors: [rgb(92, 220, 194, 0.45), rgb(92, 220, 194, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 470, y: 430), startRadius: 0, endCenter: CGPoint(x: 470, y: 430), endRadius: 560, options: [])
    case .dark, .tinted:
        break // transparent: iOS supplies the dark / tinted backdrop
    }

    // Sticky note, slightly rotated.
    let note = CGRect(x: 232, y: 232, width: 540, height: 560)
    let fold: CGFloat = 150
    ctx.saveGState()
    ctx.translateBy(x: note.midX, y: note.midY); ctx.rotate(by: -0.07); ctx.translateBy(x: -note.midX, y: -note.midY)

    let body = CGMutablePath()
    let r: CGFloat = 44
    body.move(to: CGPoint(x: note.minX + r, y: note.minY))
    body.addLine(to: CGPoint(x: note.maxX - r, y: note.minY))
    body.addArc(tangent1End: CGPoint(x: note.maxX, y: note.minY), tangent2End: CGPoint(x: note.maxX, y: note.minY + r), radius: r)
    body.addLine(to: CGPoint(x: note.maxX, y: note.maxY - fold))
    body.addLine(to: CGPoint(x: note.maxX - fold, y: note.maxY))
    body.addLine(to: CGPoint(x: note.minX + r, y: note.maxY))
    body.addArc(tangent1End: CGPoint(x: note.minX, y: note.maxY), tangent2End: CGPoint(x: note.minX, y: note.maxY - r), radius: r)
    body.addLine(to: CGPoint(x: note.minX, y: note.minY + r))
    body.addArc(tangent1End: CGPoint(x: note.minX, y: note.minY), tangent2End: CGPoint(x: note.minX + r, y: note.minY), radius: r)
    body.closeSubpath()

    let paper: CGColor, paperShade: CGColor, ink: CGColor, line: CGColor
    switch variant {
    case .light:  paper = rgb(255, 214, 102); paperShade = rgb(232, 170, 52); ink = rgb(6, 70, 64); line = rgb(6, 70, 64, 0.28)
    case .dark:   paper = rgb(255, 206, 92);  paperShade = rgb(214, 150, 40); ink = rgb(8, 48, 46); line = rgb(8, 48, 46, 0.30)
    case .tinted: paper = rgb(255, 255, 255); paperShade = rgb(170, 170, 170); ink = rgb(40, 40, 40); line = rgb(40, 40, 40, 0.35)
    }

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 60, color: rgb(0, 0, 0, variant == .tinted ? 0.0 : 0.35))
    ctx.addPath(body); ctx.setFillColor(paper); ctx.fillPath()
    ctx.restoreGState()

    // Subtle paper gradient.
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    let sheen = CGGradient(colorsSpace: space, colors: [rgb(255, 255, 255, 0.35), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: note.minX, y: note.minY), end: CGPoint(x: note.midX, y: note.maxY), options: [])
    ctx.restoreGState()

    // Folded corner.
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: note.maxX, y: note.maxY - fold))
    flap.addLine(to: CGPoint(x: note.maxX - fold, y: note.maxY))
    flap.addQuadCurve(to: CGPoint(x: note.maxX - fold + 18, y: note.maxY - fold + 18), control: CGPoint(x: note.maxX - fold - 6, y: note.maxY - fold * 0.45))
    flap.addQuadCurve(to: CGPoint(x: note.maxX, y: note.maxY - fold), control: CGPoint(x: note.maxX - fold * 0.45, y: note.maxY - fold - 6))
    flap.closeSubpath()
    ctx.addPath(flap); ctx.setFillColor(paperShade); ctx.fillPath()

    // Scribbled lines: the raw note.
    ctx.setLineCap(.round); ctx.setStrokeColor(line); ctx.setLineWidth(30)
    for (y, len) in [(note.minY + 150, 300.0), (note.minY + 240, 360.0)] {
        ctx.move(to: CGPoint(x: note.minX + 92, y: y)); ctx.addLine(to: CGPoint(x: note.minX + 92 + len, y: y)); ctx.strokePath()
    }

    // Check mark: the plan.
    ctx.setStrokeColor(ink); ctx.setLineWidth(58); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: note.minX + 108, y: note.minY + 390))
    ctx.addLine(to: CGPoint(x: note.minX + 196, y: note.minY + 470))
    ctx.addLine(to: CGPoint(x: note.minX + 350, y: note.minY + 318))
    ctx.strokePath()
    ctx.restoreGState()

    // Spark: four-point star breaking out of the top-right corner.
    func spark(center c: CGPoint, radius R: CGFloat, color: CGColor) {
        let p = CGMutablePath()
        let w = R * 0.26
        p.move(to: CGPoint(x: c.x, y: c.y - R))
        p.addQuadCurve(to: CGPoint(x: c.x + R, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + R), control: CGPoint(x: c.x + w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x - R, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R), control: CGPoint(x: c.x - w, y: c.y - w))
        p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
    }
    let sparkColor: CGColor = variant == .tinted ? rgb(255, 255, 255) : rgb(236, 255, 250)
    ctx.saveGState()
    if variant == .tinted {
        // A clear gap keeps the spark from merging into the white note.
        ctx.setBlendMode(.clear)
        spark(center: CGPoint(x: 770, y: 250), radius: 152, color: rgb(0, 0, 0))
        ctx.setBlendMode(.normal)
    } else {
        ctx.setShadow(offset: .zero, blur: 40, color: rgb(120, 255, 220, 0.8))
    }
    spark(center: CGPoint(x: 770, y: 250), radius: 120, color: sparkColor)
    spark(center: CGPoint(x: 872, y: 400), radius: 50, color: sparkColor)
    ctx.restoreGState()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
draw(.light, to: "\(out)/AppIcon.png")
draw(.dark, to: "\(out)/AppIcon-dark.png")
draw(.tinted, to: "\(out)/AppIcon-tinted.png")
print("ok")
