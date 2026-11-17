import StoreKit
import UIKit

/// Asks for an App Store review only after a save or a share, once the user has come back to
/// shoot on a few different days, and at most once per app version. iOS shows the prompt at most
/// three times a year, so asking someone who has only just started would waste one.
enum ReviewPrompter {
    private static let minimumPhotos = 10
    private static let minimumCaptureDays = 3
    private static let lastVersionKey = "reviewRequestedForVersion"
    private static let captureDaysKey = "reviewCaptureDays"
    private static let lastCaptureDayKey = "reviewLastCaptureDay"
    /// Someone who just closed a paywall is the least likely to leave a good rating.
    private static let paywallCooldown: TimeInterval = 5 * 60
    private static var lastPaywallShown: Date?

    /// The App Store's "Write a Review" page. Use it for buttons: the system prompt may not show
    /// at all when the user explicitly asks for it.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6781238494?action=write-review")

    static func paywallShown() {
        lastPaywallShown = .now
    }

    /// Counts each calendar day with at least one capture.
    static func recordCaptureDay() {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: .now)
        if let lastDay = defaults.object(forKey: lastCaptureDayKey) as? Date, lastDay >= today { return }
        defaults.set(today, forKey: lastCaptureDayKey)
        defaults.set(defaults.integer(forKey: captureDaysKey) + 1, forKey: captureDaysKey)
    }

    static func requestIfAppropriate() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: "totalPhotosCount") >= minimumPhotos,
              defaults.integer(forKey: captureDaysKey) >= minimumCaptureDays else { return }

        if let lastPaywallShown, Date.now.timeIntervalSince(lastPaywallShown) < paywallCooldown { return }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard UserDefaults.standard.string(forKey: lastVersionKey) != version else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        UserDefaults.standard.set(version, forKey: lastVersionKey)
        Analytics.track(.reviewRequested)
        // Small delay so the prompt doesn't collide with the animation or sheet that just finished.
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            AppStore.requestReview(in: scene)
        }
    }
}
