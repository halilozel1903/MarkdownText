// Checks that a capture shows a rendered app rather than a blank, black or launching screen.
// Usage: check-screenshot <png>
// Prints the measurements and exits with 1 when the capture looks broken.
//
// It looks at the image size and at how varied the colours are: a blank or launching screen is one flat colour,
// while a rendered page has many shades from illustrations, text and anti-aliasing. Used for the Mac and iPhone captures.
import CoreGraphics
import Foundation
import ImageIO

let minimumWidth = 300
let minimumHeight = 350
let minimumColours = 40
let maximumDominantShare = 0.96
let minimumLitShare = 0.03

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: check-screenshot <png>\n".utf8))
    exit(2)
}

guard
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    print("unreadable image")
    exit(1)
}

let width = image.width
let height = image.height
guard width >= minimumWidth, height >= minimumHeight else {
    print("too small: \(width)x\(height)")
    exit(1)
}

let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let decoded = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return false
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard decoded else {
    print("could not decode pixels")
    exit(1)
}

// Count colours quantized to 5 bits per channel, the share of the most common one, and the share of pixels
// that are not near-black.
var histogram: [Int: Int] = [:]
var lit = 0
var total = 0
for y in stride(from: 0, to: height, by: 2) {
    for x in stride(from: 0, to: width, by: 2) {
        let offset = y * bytesPerRow + x * 4
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        histogram[(red >> 3) << 10 | (green >> 3) << 5 | (blue >> 3), default: 0] += 1
        if max(red, green, blue) > 48 {
            lit += 1
        }
        total += 1
    }
}

let colours = histogram.count
let dominantShare = Double(histogram.values.max() ?? 0) / Double(max(total, 1))
let litShare = Double(lit) / Double(max(total, 1))
print("\(width)x\(height), \(colours) colours, most common colour \(Int(dominantShare * 100))%, lit \(Int(litShare * 100))%")

if colours < minimumColours || dominantShare > maximumDominantShare || litShare < minimumLitShare {
    exit(1)
}
