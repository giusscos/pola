#if DEBUG
import OSLog
import UIKit

/// Debug builds only. Launch with `-FilmStockSnapshots YES` to render `filter_reference` through
/// every film stock into Documents/FilmStockSnapshots (to judge looks by eye) and to time a 12 MP
/// render of each stock (median of three after a warm-up), written to timings.txt and the log.
nonisolated enum FilmStockSnapshots {
    private static let logger = Logger(subsystem: "com.giusscos.pola", category: "FilmStockSnapshots")

    @MainActor
    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "FilmStockSnapshots"),
              let reference = UIImage(named: "filter_reference") else { return }
        let stocks = allFilters.compactMap { filter in filter.effect.map { (name: filter.name, effect: $0) } }
        Task.detached(priority: .userInitiated) {
            await run(stocks: stocks, reference: reference)
        }
    }

    @concurrent
    private static func run(stocks: [(name: String, effect: FilmFilterEffect)], reference: UIImage) async {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("FilmStockSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for stock in stocks {
            let look = FilmPipeline.apply(to: reference, film: stock.effect, lens: nil)
            try? look.jpegData(compressionQuality: 0.9)?.write(to: folder.appendingPathComponent("\(stock.name).jpg"))
        }

        // The camera's 12 MP, 4:3 portrait.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let fullSize = UIGraphicsImageRenderer(size: CGSize(width: 3024, height: 4032), format: format).image { _ in
            reference.draw(in: CGRect(x: 0, y: 0, width: 3024, height: 4032))
        }
        var report = "Film stock render time, 3024 x 4032, median of 3 after one warm-up\n"
        for stock in stocks {
            _ = FilmPipeline.apply(to: fullSize, film: stock.effect, lens: nil)
            var times: [Double] = []
            for _ in 0..<3 {
                let start = ContinuousClock.now
                _ = FilmPipeline.apply(to: fullSize, film: stock.effect, lens: nil)
                let elapsed = ContinuousClock.now - start
                times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
            }
            let median = times.sorted()[1]
            let line = "\(stock.name): \(String(format: "%.0f", median)) ms"
            logger.info("\(line, privacy: .public)")
            report += line + "\n"
        }
        try? report.write(to: folder.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
        logger.info("Film stock snapshots written to \(folder.path, privacy: .public)")
    }
}
#endif
