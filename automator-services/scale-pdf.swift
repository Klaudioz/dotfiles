import Foundation
import CoreGraphics

let args = CommandLine.arguments
guard args.count > 1 else {
    fputs("Usage: scale-pdf <input.pdf> [scale]\n", stderr)
    exit(1)
}

let inputPath = args[1]
let scale: CGFloat = args.count > 2 ? CGFloat(Double(args[2]) ?? 0.85) : 0.85

let inputURL = URL(fileURLWithPath: inputPath)
guard let pdf = CGPDFDocument(inputURL as CFURL) else {
    fputs("Error: cannot open PDF\n", stderr)
    exit(1)
}

let pageCount = pdf.numberOfPages
guard pageCount > 0 else {
    fputs("Error: PDF has no pages\n", stderr)
    exit(1)
}

let tempPath = NSTemporaryDirectory() + "print85_\(ProcessInfo.processInfo.globallyUniqueString).pdf"
let tempURL = URL(fileURLWithPath: tempPath)

var firstBox = pdf.page(at: 1)!.getBoxRect(.mediaBox)
guard let context = CGContext(tempURL as CFURL, mediaBox: &firstBox, nil) else {
    fputs("Error: cannot create output PDF\n", stderr)
    exit(1)
}

for i in 1...pageCount {
    guard let page = pdf.page(at: i) else { continue }
    let box = page.getBoxRect(.mediaBox)

    context.beginPDFPage(nil)

    let offsetX = box.width * (1 - scale) / 2
    let offsetY = box.height * (1 - scale) / 2
    context.translateBy(x: offsetX, y: offsetY)
    context.scaleBy(x: scale, y: scale)
    context.drawPDFPage(page)

    context.endPDFPage()
}

context.closePDF()
print(tempPath)
