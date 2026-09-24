import OSLog

enum AnalyticsEvent: String {
    case onboardingCompleted
    case paywallShown
    case paywallDismissed
    case purchaseStarted
    case purchaseCompleted
    case purchaseCancelled
    case purchaseFailed
    case restoreCompleted
    case photoCaptured
    case videoCaptured
    case timelapseCaptured
    case lockedFilterPreviewed
    case lockedFilterCaptureBlocked
    case shareCompleted
    case storyShared
    case printSheetCreated
    case reviewRequested
    case locationPromptAnswered
}

protocol AnalyticsSink {
    func send(_ event: AnalyticsEvent, parameters: [String: String])
}

/// Single entry point for product analytics. Events currently go to the unified log only;
/// plug a real backend in by appending a sink in `sinks` (see pricing-and-monetization.md).
enum Analytics {
    static var sinks: [AnalyticsSink] = [LogSink()]

    static func track(_ event: AnalyticsEvent, _ parameters: [String: String] = [:]) {
        for sink in sinks {
            sink.send(event, parameters: parameters)
        }
    }
}

private struct LogSink: AnalyticsSink {
    private let logger = Logger(subsystem: "com.pola", category: "analytics")

    func send(_ event: AnalyticsEvent, parameters: [String: String]) {
        let params = parameters.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        logger.info("\(event.rawValue, privacy: .public) \(params, privacy: .public)")
    }
}
