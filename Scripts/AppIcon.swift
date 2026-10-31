// Draws the app icon: a whistle that is a running track, lying flat. The chamber is the round
// end of the track with its lanes, the infield is the whistle's hole, and the mouthpiece is the
// home straight. Colors from Okabe and Ito's palette: a vermillion track, a bluish-green
// infield, on navy.
//
//     swiftc Scripts/AppIcon.swift -o /tmp/icon
//     /tmp/icon App/Resources/Assets.xcassets/AppIcon.appiconset docs/icon.png

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
    let lane: CGColor
    let curb: CGColor
    let infield: CGColor
    let infieldCenter: CGColor

    init(_ variant: Variant) {
        let gray = variant == .tinted
        track = gray ? color(0xD9D9D9) : color(0xD55E00)
        lane = gray ? color(0x5A5A5A) : color(0xFFFFFF, 0.95)
        curb = gray ? color(0x8C8C8C) : color(0xFFFFFF, 0.95)
        infield = gray ? color(0x4A4A4A) : color(0x009E73)
        infieldCenter = gray ? color(0x555555) : color(0x00A57A)
    }
}

/// The whistle's geometry, in a 1024-point square: the chamber on the right, the mouthpiece
/// along its top to the left.
enum Shape {
    static let center = CGPoint(x: 612, y: 560)
    static let outer: CGFloat = 250
    static let inner: CGFloat = 112
    /// Where the straight ends, on the left.
    static let mouth: CGFloat = 150
    static let corner: CGFloat = 44
    static let lanes = 3

    static func circle(_ radius: CGFloat, around point: CGPoint = center) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
    }
}

func drawBackground(_ context: CGContext, space: CGColorSpace) {
    guard
        let gradient = CGGradient(
            colorsSpace: space, colors: [color(0x0B2545), color(0x13315C)] as CFArray,
            locations: [0, 1])
    else { return }
    context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
}

func drawBody(_ context: CGContext, _ palette: Palette) {
    let chamber = CGPath(ellipseIn: Shape.circle(Shape.outer), transform: nil)
    let straight = CGPath(
        roundedRect: CGRect(
            x: Shape.mouth, y: Shape.center.y - Shape.outer, width: Shape.center.x - Shape.mouth,
            height: Shape.outer - Shape.inner),
        cornerWidth: Shape.corner, cornerHeight: Shape.corner, transform: nil)
    context.addPath(chamber.union(straight))
    context.setFillColor(palette.track)
    context.fillPath()
}

/// Lane lines: around the chamber, then straight out along the mouthpiece.
func drawLanes(_ context: CGContext, _ palette: Palette) {
    context.setStrokeColor(palette.lane)
    context.setLineWidth(10)
    context.setLineCap(.round)
    for index in 1..<Shape.lanes {
        let radius =
            Shape.inner + (Shape.outer - Shape.inner) * CGFloat(index) / CGFloat(Shape.lanes)
        context.strokeEllipse(in: Shape.circle(radius))
        context.move(to: CGPoint(x: Shape.mouth + Shape.corner * 0.8, y: Shape.center.y - radius))
        context.addLine(to: CGPoint(x: Shape.center.x, y: Shape.center.y - radius))
        context.strokePath()
    }
}

/// The curb and the infield: the whistle's hole.
func drawInfield(_ context: CGContext, _ palette: Palette, space: CGColorSpace) {
    context.setFillColor(palette.curb)
    context.fillEllipse(in: Shape.circle(Shape.inner))
    let field = Shape.inner - 14
    context.saveGState()
    context.addEllipse(in: Shape.circle(field))
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: space, colors: [palette.infieldCenter, palette.infield] as CFArray,
        locations: [0, 1])
    {
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: Shape.center.x - field * 0.3, y: Shape.center.y - field * 0.35),
            startRadius: 0, endCenter: Shape.center, endRadius: field,
            options: [.drawsAfterEndLocation])
    }
    context.restoreGState()
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
    let palette = Palette(variant)
    drawBody(context, palette)
    drawLanes(context, palette)
    drawInfield(context, palette, space: space)
    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) -> Bool {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

let arguments = CommandLine.arguments.dropFirst()
let folder = URL(fileURLWithPath: arguments.first ?? ".")
for variant in Variant.allCases {
    guard let image = render(variant),
        write(image, to: folder.appendingPathComponent("AppIcon-\(variant.rawValue).png"))
    else {
        FileHandle.standardError.write(Data("Could not render \(variant.rawValue)\n".utf8))
        exit(1)
    }
}
// The README's copy, small.
if let preview = arguments.dropFirst().first, let image = render(.light, size: 160),
    !write(image, to: URL(fileURLWithPath: preview))
{
    FileHandle.standardError.write(Data("Could not write \(preview)\n".utf8))
    exit(1)
}
