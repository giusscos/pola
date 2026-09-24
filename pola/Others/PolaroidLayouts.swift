import UIKit

// MARK: - Story (9:16)

/// A 1080×1920 image sized for Instagram/TikTok stories: the polaroid sits slightly tilted
/// on a blurred, darkened copy of its own photo.
@MainActor
func renderPolaroidStory(_ entry: PolaroidEntry) -> UIImage {
    let canvas = CGSize(width: 1080, height: 1920)
    let polaroid = renderPolaroidFrame(entry)
    let background = entry.image.flatMap { blurredBackground(from: $0, size: canvas) }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
        let cg = ctx.cgContext
        UIColor(white: 0.08, alpha: 1).setFill()
        cg.fill(CGRect(origin: .zero, size: canvas))
        background?.draw(in: CGRect(origin: .zero, size: canvas))
        UIColor.black.withAlphaComponent(0.35).setFill()
        cg.fill(CGRect(origin: .zero, size: canvas))

        let width: CGFloat = 780
        let height = width / polaroid.size.width * polaroid.size.height
        cg.saveGState()
        cg.translateBy(x: canvas.width / 2, y: canvas.height / 2 - 40)
        cg.rotate(by: -3 * .pi / 180)
        cg.setShadow(offset: CGSize(width: 0, height: 24), blur: 60, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        polaroid.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        cg.restoreGState()
    }
}

private func blurredBackground(from image: UIImage, size: CGSize) -> UIImage? {
    guard let ci = CIImage(image: image) else { return nil }
    let scale = max(size.width / ci.extent.width, size.height / ci.extent.height)
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blurred = scaled.clampedToExtent().applyingGaussianBlur(sigma: 40).cropped(to: scaled.extent)
    let origin = CGPoint(
        x: scaled.extent.midX - size.width / 2,
        y: scaled.extent.midY - size.height / 2
    )
    let crop = CGRect(origin: origin, size: size)
    guard let cg = CIContext().createCGImage(blurred, from: crop) else { return nil }
    return UIImage(cgImage: cg)
}

// MARK: - Print sheet (A4 PDF)

/// Lays polaroids out 3×3 per A4 page with light cut marks, ready to print at home.
/// Returns the URL of a temporary PDF.
@MainActor
func renderPolaroidPrintSheet(_ entries: [PolaroidEntry]) -> URL? {
    guard !entries.isEmpty else { return nil }
    // A4 in PostScript points
    let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    let columns = 3, rows = 3
    let margin: CGFloat = 36
    let gap: CGFloat = 18
    let cellW = (page.width - 2 * margin - CGFloat(columns - 1) * gap) / CGFloat(columns)
    let cellH = cellW / 0.75
    let gridH = CGFloat(rows) * cellH + CGFloat(rows - 1) * gap
    let top = (page.height - gridH) / 2

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("poly-print-sheet-\(Int(Date().timeIntervalSince1970)).pdf")
    let renderer = UIGraphicsPDFRenderer(bounds: page)
    let frames = entries.map { renderPolaroidFrame($0) }

    do {
        try renderer.writePDF(to: url) { ctx in
            for (i, frame) in frames.enumerated() {
                let slot = i % (columns * rows)
                if slot == 0 { ctx.beginPage() }
                let col = slot % columns
                let row = slot / columns
                let rect = CGRect(
                    x: margin + CGFloat(col) * (cellW + gap),
                    y: top + CGFloat(row) * (cellH + gap),
                    width: cellW,
                    height: cellH
                )
                frame.draw(in: rect)
                drawCutMarks(around: rect, in: ctx.cgContext)
            }
        }
    } catch {
        return nil
    }
    return url
}

private func drawCutMarks(around rect: CGRect, in cg: CGContext) {
    let length: CGFloat = 6
    let offset: CGFloat = 3
    cg.saveGState()
    cg.setStrokeColor(UIColor(white: 0.6, alpha: 1).cgColor)
    cg.setLineWidth(0.4)
    for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                   CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
        let dx: CGFloat = corner.x == rect.minX ? -1 : 1
        let dy: CGFloat = corner.y == rect.minY ? -1 : 1
        cg.move(to: CGPoint(x: corner.x + dx * offset, y: corner.y))
        cg.addLine(to: CGPoint(x: corner.x + dx * (offset + length), y: corner.y))
        cg.move(to: CGPoint(x: corner.x, y: corner.y + dy * offset))
        cg.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * (offset + length)))
    }
    cg.strokePath()
    cg.restoreGState()
}

// MARK: - Presenting share sheets

extension UIViewController {
    /// Presents a share sheet and asks for a review when the user actually shared something.
    func presentShareSheet(items: [Any], event: AnalyticsEvent = .shareCompleted, sourceItem: UIBarButtonItem? = nil) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceItem = sourceItem
        vc.completionWithItemsHandler = { activity, completed, _, _ in
            guard completed else { return }
            Analytics.track(event, ["activity": activity?.rawValue ?? "unknown"])
            ReviewPrompter.requestIfAppropriate()
        }
        present(vc, animated: true)
    }
}
