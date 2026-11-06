import Foundation
import OSLog
import StoreKit
import UserNotifications

/// The paywall promises a reminder before a free trial turns into a paid plan. This keeps that
/// promise with a local notification `leadDays` before the trial ends.
enum TrialReminder {
    /// The paywall and notification strings say "2 days"; change them together.
    static let leadDays = 2
    private static let identifier = "trial-ending-reminder"
    private static let logger = Logger(subsystem: "com.giusscos.pola", category: "Premium")

    /// Only trials longer than the lead time can get a reminder, so only those show the promise.
    static func canRemind(trialDays: Int) -> Bool {
        trialDays > leadDays
    }

    static func isFreeTrial(_ tx: Transaction) -> Bool {
        tx.offer?.type == .introductory && tx.offer?.paymentMode == .freeTrial
    }

    /// Asked only right after a trial starts, where the paywall has just explained why.
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Schedules the reminder for a free trial that will renew, and removes it once that's no longer
    /// true (converted, cancelled, refunded, switched to Lifetime). Never asks for permission.
    static func sync(transaction tx: Transaction?, willAutoRenew: Bool, renewalPrice: String?) async {
        let center = UNUserNotificationCenter.current()
        guard let tx, willAutoRenew, isFreeTrial(tx), let trialEnd = tx.expirationDate,
              let fireDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: trialEnd),
              fireDate > .now else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        // Products not loaded (e.g. offline): keep whatever is already scheduled.
        guard let renewalPrice else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            logger.info("Trial reminder not scheduled: notifications not allowed")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Your free trial ends in 2 days", comment: "Trial reminder notification title")
        content.body = String(
            format: NSLocalizedString("After that, Poly Premium renews at %@. Cancel anytime in Settings > Apple Account > Subscriptions.", comment: "Trial reminder notification body; %@ is the price per period"),
            renewalPrice
        )
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // Reusing the identifier replaces the pending request, so repeated syncs never stack reminders.
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            logger.info("Trial reminder scheduled for \(fireDate)")
        } catch {
            logger.error("Trial reminder failed: \(error)")
        }
    }
}
