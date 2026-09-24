import StoreKit
import UIKit

/// Asks for an App Store review only after a positive moment (a finished print, a share, a save),
/// once the user has some history with the app, and at most once per app version.
enum ReviewPrompter {
    private static let minimumPhotos = 7
    private static let lastVersionKey = "reviewRequestedForVersion"

    static func requestIfAppropriate() {
        let photos = UserDefaults.standard.integer(forKey: "totalPhotosCount")
        guard photos >= minimumPhotos else { return }

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
