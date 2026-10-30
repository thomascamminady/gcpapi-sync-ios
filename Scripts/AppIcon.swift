// Draws the app icon: a whistle that is a running track. The chamber is the oval track with
// its lanes and the green infield (the whistle's hole), the mouthpiece is the home straight,
// and the air slot is the finish line; the lanyard ring hangs on the side.
//
//     swiftc Scripts/AppIcon.swift -o /tmp/icon
//     /tmp/icon App/Resources/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The icon's appearances: on its own background, on the dark home screen, and tinted.
enum Variant: String, CaseIterable {
    case light
    case dark
    case tinted
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The colors of one variant; the tinted one is grayscale for the system to tint.
struct Palette {
    let track: CGColor
    let trackEdge: CGColor
    let lane: CGColor
    let curb: CGColor
    let infield: CGColor
    let infieldRim: CGColor
    let ring: CGColor
    let finishDark: CGColor
    let finishLight: CGColor

    init(_ variant: Variant) {
        let gray = variant == .tinted
        track = gray ? color(0xD9D9D9) : color(0xE85A4F)
        trackEdge = gray ? color(0xA6A6A6) : color(0xC8443B)
        lane = gray ? color(0x6E6E6E) : color(0xFFFFFF, 0.92)
        curb = gray ? color(0x8C8C8C) : color(0xCFD6DE)
        infield = gray ? color(0x4A4A4A) : color(0x6DBE45)
        infieldRim = gray ? color(0x5E5E5E) : color(0x4E9E2E)
        ring = gray ? color(0xBFBFBF) : color(0xF4F6F9)
        finishDark = gray ? color(0x3A3A3A) : color(0x1E1E24)
        finishLight = gray ? color(0xF0F0F0) : color(0xFFFFFF)
    }
}

/// The whistle's geometry, in a 1024-point square.
enum Shape {
    static let center = CGPoint(x: 575, y: 585)
    static let outer: CGFloat = 255
    static let inner: CGFloat = 105
    /// Where the straight ends, on the left.
    static let mouth: CGFloat = 95
    static let corner: CGFloat = 46
    static let lanes = 4

    static func circle(_ radius: CGFloat, around point: CGPoint = center) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
    }
}

func drawBackground(_ context: CGContext, space: CGColorSpace) {
    guard
        let gradient = CGGradient(
            colorsSpace: space, colors: [color(0x16295C), color(0x2B4C9B)] as CFArray,
            locations: [0, 1])
    else { return }
    context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
}

func drawRing(_ context: CGContext, _ palette: Palette) {
    let distance = Shape.outer + 22
    let point = CGPoint(
        x: Shape.center.x + distance * cos(0.75), y: Shape.center.y + distance * sin(0.75))
    context.setStrokeColor(palette.ring)
    context.setLineWidth(26)
    context.strokeEllipse(in: Shape.circle(46, around: point))
}

func drawBody(_ context: CGContext, _ palette: Palette) {
    let chamber = CGPath(ellipseIn: Shape.circle(Shape.outer), transform: nil)
    let straight = CGPath(
        roundedRect: CGRect(
            x: Shape.mouth, y: Shape.center.y - Shape.outer, width: Shape.center.x - Shape.mouth,
            height: Shape.outer - Shape.inner),
        cornerWidth: Shape.corner, cornerHeight: Shape.corner, transform: nil)
    let body = chamber.union(straight)
    context.addPath(body)
    context.setFillColor(palette.track)
    context.fillPath()
    context.addPath(body)
    context.setStrokeColor(palette.trackEdge)
    context.setLineWidth(10)
    context.strokePath()
}

/// Lane lines: around the oval, then straight out along the mouthpiece.
func drawLanes(_ context: CGContext, _ palette: Palette) {
    context.setStrokeColor(palette.lane)
    context.setLineWidth(9)
    context.setLineCap(.round)
    for index in 1..<Shape.lanes {
        let radius =
            Shape.inner + (Shape.outer - Shape.inner) * CGFloat(index) / CGFloat(Shape.lanes)
        context.strokeEllipse(in: Shape.circle(radius))
        context.move(to: CGPoint(x: Shape.mouth + Shape.corner, y: Shape.center.y - radius))
        context.addLine(to: CGPoint(x: Shape.center.x, y: Shape.center.y - radius))
        context.strokePath()
    }
}

/// The curb and the infield: the whistle's hole.
func drawInfield(_ context: CGContext, _ palette: Palette) {
    context.setFillColor(palette.curb)
    context.fillEllipse(in: Shape.circle(Shape.inner))
    let field = Shape.inner - 18
    context.setFillColor(palette.infield)
    context.fillEllipse(in: Shape.circle(field))
    context.setStrokeColor(palette.infieldRim)
    context.setLineWidth(8)
    context.strokeEllipse(in: Shape.circle(field - 4))
}

/// The finish line across the straight: the whistle's air slot.
func drawFinish(_ context: CGContext, _ palette: Palette) {
    let left = Shape.center.x - 120
    let rows = 6
    let cell = (Shape.outer - Shape.inner) / CGFloat(rows)
    for row in 0..<rows {
        for column in 0..<2 {
            let isDark = (row + column).isMultiple(of: 2)
            context.setFillColor(isDark ? palette.finishDark : palette.finishLight)
            context.fill(
                CGRect(
                    x: left + CGFloat(column) * cell,
                    y: Shape.center.y - Shape.outer + CGFloat(row) * cell, width: cell,
                    height: cell))
        }
    }
}

func render(_ variant: Variant, size: Int = 1024) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    // y grows downward, as in the design.
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    // The dark and tinted variants are transparent: the system draws their background.
    if variant == .light {
        drawBackground(context, space: space)
    }
    // The whistle leans: mouthpiece up and to the left.
    context.translateBy(x: 512, y: 512)
    context.rotate(by: -0.36)
    context.translateBy(x: -512, y: -512)
    let palette = Palette(variant)
    drawRing(context, palette)
    drawBody(context, palette)
    drawLanes(context, palette)
    drawInfield(context, palette)
    drawFinish(context, palette)
    return context.makeImage()
}

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
for variant in Variant.allCases {
    let url = folder.appendingPathComponent("AppIcon-\(variant.rawValue).png")
    guard let image = render(variant),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        FileHandle.standardError.write(Data("Could not render \(variant.rawValue)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}
