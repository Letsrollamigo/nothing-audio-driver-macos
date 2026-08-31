import AppKit

// Генератор иконки приложения. Рисуем своё, а не берём чужое: у проекта-донора
// иконка своя и в этот репозиторий не входит.
// Запуск: swift Tools/make-icon.swift Sources/icon-1024.png
let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let s = CGFloat(size)

// фон — скруглённый квадрат
let inset: CGFloat = s * 0.06
let bg = CGPath(roundedRect: CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2),
                cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
ctx.addPath(bg)
ctx.setFillColor(CGColor(red: 0.13, green: 0.13, blue: 0.12, alpha: 1))
ctx.fillPath()

let center = CGPoint(x: s / 2, y: s * 0.46)
ctx.setStrokeColor(CGColor(red: 0.93, green: 0.93, blue: 0.92, alpha: 1))
ctx.setLineCap(.round)

// дуга оголовья
ctx.setLineWidth(s * 0.055)
ctx.addArc(center: center, radius: s * 0.26, startAngle: 0, endAngle: .pi, clockwise: false)
ctx.strokePath()

// чашки (цвет заливки надо задать явно — иначе зальются фоновым и исчезнут)
ctx.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.92, alpha: 1))
for dx in [-1.0, 1.0] as [CGFloat] {
    let w = s * 0.135, h = s * 0.26
    let r = CGRect(x: center.x + dx * s * 0.26 - w / 2, y: center.y - h * 0.85, width: w, height: h)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
}
ctx.fillPath()

// точка снизу — признак «служебное, а не штатное приложение»
ctx.setFillColor(CGColor(red: 0.85, green: 0.31, blue: 0.16, alpha: 1))
ctx.addEllipse(in: CGRect(x: center.x - s * 0.035, y: s * 0.17, width: s * 0.07, height: s * 0.07))
ctx.fillPath()

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("иконка записана: \(out) (\(png.count) б)")
