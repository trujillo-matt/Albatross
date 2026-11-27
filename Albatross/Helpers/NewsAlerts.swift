import Foundation
import Supabase
import UIKit
import UserNotifications

/// Phone alerts for tournament news, written like a sports alert: a headline and a sentence of detail.
///
/// Two paths share one set of words. While the app is open it checks for news itself and posts a local alert.
/// Push alerts reach a closed app: the phone registers its APNs token with the cloud (migration 022), and the
/// `send-news-push` edge function sends each new item to every player of the tournament.
@MainActor
final class NewsAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NewsAlerts()
    /// Profile has a switch for this. On unless someone turns it off.
    static let enabledKey = "newsAlertsEnabled"

    nonisolated private static let seenKey = "newsAlertsSeenIDs"
    private let maxAlertsPerRefresh = 3
    private var askedForPushThisLaunch = false

    private var isEnabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    /// Lets a banner show while the app is on screen, the way a score alert does.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// A push can arrive before the app's own check finds the same item. Whichever comes second stays quiet.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.trigger is UNPushNotificationTrigger,
           let id = notification.request.content.userInfo["news_id"] as? String {
            let defaults = UserDefaults.standard
            let seen = defaults.stringArray(forKey: Self.seenKey) ?? []
            if seen.contains(id) { return [] }
            defaults.set(Array(([id] + seen).prefix(300)), forKey: Self.seenKey)
        }
        return [.banner, .list, .sound]
    }

    /// Alerts for items not seen before. The first call only records what is already in the feed, so installing the app
    /// does not fire a burst of old news.
    func process(_ items: [TournamentNewsItem], tournaments: [Tournament], liveStatus: [UUID: LiveMatchStatus]) async {
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: Self.seenKey)
        let seen = Set(stored ?? [])
        let fresh = items.filter { !seen.contains($0.id.uuidString) }
        let recorded = Array((fresh.map { $0.id.uuidString } + (stored ?? [])).prefix(300))
        defaults.set(recorded, forKey: Self.seenKey)

        // Asks the first time there is a tournament, so push is ready before the first alert matters.
        let allowed = isEnabled ? await hasPermission() : false
        guard allowed, stored != nil, !fresh.isEmpty else { return }
        // A push is already on its way to a phone that is not in use; the app's own alert would be a second copy.
        if UIApplication.shared.applicationState != .active, PushRegistration.shared.isRegistered { return }
        // Oldest first, so the newest alert ends up on top.
        for item in fresh.prefix(maxAlertsPerRefresh).reversed() {
            let story = NewsStoryWriter.story(for: item, in: tournaments, liveStatus: liveStatus)
            let content = UNMutableNotificationContent()
            content.title = story.title
            content.body = story.body
            content.sound = .default
            content.threadIdentifier = item.tournamentID.uuidString
            let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    #if DEBUG
    func forgetSeen() { UserDefaults.standard.removeObject(forKey: Self.seenKey) }
    #endif

    /// Asks the first time, then goes by the answer. Once allowed, the phone also registers for push.
    private func hasPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        let allowed = status == .authorized || status == .provisional || status == .ephemeral
        if allowed, !askedForPushThisLaunch {
            askedForPushThisLaunch = true
            UIApplication.shared.registerForRemoteNotifications()
        }
        return allowed
    }
}

/// Keeps this phone's APNs token in the cloud, so the server can alert it. The token is saved only while someone is signed in.
@MainActor
final class PushRegistration {
    static let shared = PushRegistration()
    private let tokenKey = "apnsDeviceToken"
    private var lastSynced: String?

    /// True once the phone has a token and the cloud has it.
    private(set) var isRegistered = false

    func receive(token: String) async {
        UserDefaults.standard.set(token, forKey: tokenKey)
        await sync()
    }

    /// Saves the token with the alerts switch as it is now. Cheap to call often: it does nothing when nothing changed.
    func sync() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey), let user = supabase.auth.currentUser else { return }
        let enabled = UserDefaults.standard.object(forKey: NewsAlerts.enabledKey) as? Bool ?? true
        let key = "\(user.id)|\(token)|\(enabled)"
        guard key != lastSynced else { return }
        nonisolated struct Params: Encodable { let p_token: String; let p_enabled: Bool }
        do {
            try await supabase.rpc("register_device_token", params: Params(p_token: token, p_enabled: enabled)).execute()
            lastSynced = key
            isRegistered = enabled
        } catch {
            print("PushRegistration: could not save the device token — \(error)")
        }
    }
}

/// Receives the token iOS hands over after `registerForRemoteNotifications`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await PushRegistration.shared.receive(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed — \(error)")
    }
}
