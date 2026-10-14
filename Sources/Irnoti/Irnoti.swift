import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// IRNoti iOS SDK. Wire protocol: docs/device-api.md.
///
///     Irnoti.shared.configure(appKey: "pk_live_xxx")
///     // in MessagingDelegate.messaging(_:didReceiveRegistrationToken:)
///     Irnoti.shared.setPushToken(fcmToken)
public final class Irnoti {
    public static let shared = Irnoti()
    public static let version = "1.0.0"

    private var apiBase = ""
    private var appKey = ""
    private let queue = DispatchQueue(label: "ir.irnoti.sdk")

    /// Use an App Group suite so the notification extension can report delivery too: `Irnoti.shared.appGroup = "group.com.you.app"` before configure.
    public var appGroup: String? { didSet { if let g = appGroup, let d = UserDefaults(suiteName: g) { storage = d } } }
    private var storage: UserDefaults

    private init() {
        storage = .standard
    }

    // MARK: setup

    public static let defaultAPIBase = "https://api.irnoti.ir/v1/sdk"

    public func configure(appKey: String, apiBase: String = Irnoti.defaultAPIBase) {
        self.apiBase = apiBase.hasSuffix("/") ? String(apiBase.dropLast()) : apiBase
        self.appKey = appKey
        queue.async { self.flushReports() }
    }

    /// Call whenever Firebase hands you a (new) FCM token.
    public func setPushToken(_ token: String) {
        queue.async {
            self.pendingToken = token
            self.syncLocked(token)
        }
    }

    private var pendingToken: String? {
        get { storage.string(forKey: "irn_pending_token") }
        set { storage.set(newValue, forKey: "irn_pending_token") }
    }

    // MARK: public API (all async, safe before registration)

    public func identify(_ externalId: String, aliases: [String: String] = [:]) {
        op { id in self.send("POST", "/devices/\(id)/identify", ["external_id": externalId, "aliases": aliases]) }
    }
    public func logout() { op { id in self.send("POST", "/devices/\(id)/logout", [:]) } }
    public func subscribe(_ topic: String) { op { id in self.send("PUT", "/devices/\(id)/topics/\(Self.enc(topic))", [:]) } }
    public func unsubscribe(_ topic: String) { op { id in self.send("DELETE", "/devices/\(id)/topics/\(Self.enc(topic))", nil) } }
    public func setTags(_ tags: [String: String?]) {
        var body: [String: Any] = [:]
        for (k, v) in tags { body[k] = v ?? NSNull() }
        op { id in self.send("PUT", "/devices/\(id)/tags", body) }
    }
    public func track(_ name: String, props: [String: Any] = [:]) {
        let ev: [String: Any] = ["name": name, "ts": Int(Date().timeIntervalSince1970 * 1000), "props": props]
        op { _ in self.send("POST", "/events", ["events": [ev]]) }
    }
    public func setNotificationsEnabled(_ enabled: Bool) {
        op { id in self.send("PATCH", "/devices/\(id)", ["notifications_enabled": enabled]) }
    }
    public func unregister() {
        op { id in
            _ = self.send("DELETE", "/devices/\(id)", nil)
            self.clearDevice()
        }
    }

    // MARK: notification hooks

    /// `true` if a notification payload (userInfo) belongs to IRNoti.
    public static func isIrnotiMessage(_ userInfo: [AnyHashable: Any]) -> Bool { userInfo["irn_id"] != nil }

    /// Call from `userNotificationCenter(_:willPresent:)` (delivered while foregrounded) and from silent-push handling.
    public func didReceive(userInfo: [AnyHashable: Any]) {
        if let id = userInfo["irn_id"] as? String { report(id, "delivered") }
    }

    /// Call from `userNotificationCenter(_:didReceive:)`. Returns the URL to open (deeplink wins over url), if any.
    @discardableResult
    public func didTap(response: UNNotificationResponse) -> URL? {
        let info = response.notification.request.content.userInfo
        guard let id = info["irn_id"] as? String else { return nil }
        let isDefault = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let isDismiss = response.actionIdentifier == UNNotificationDismissActionIdentifier
        report(id, isDismiss ? "dismissed" : (isDefault ? "clicked" : "action"), actionId: isDefault || isDismiss ? nil : response.actionIdentifier)
        if isDismiss { return nil }
        var target = (info["deeplink"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (info["url"] as? String) ?? ""
        if !isDefault, let raw = info["actions"] as? String, let data = raw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let u = arr.first(where: { ($0["id"] as? String) == response.actionIdentifier })?["url"] as? String, !u.isEmpty {
            target = u
        }
        return URL(string: target)
    }

    // MARK: reports

    public func report(_ messageId: String, _ type: String, actionId: String? = nil) {
        var r: [String: Any] = ["message_id": messageId, "type": type, "ts": Int(Date().timeIntervalSince1970 * 1000)]
        if let a = actionId { r["action_id"] = a }
        queue.async {
            var q = self.storage.array(forKey: "irn_reports") as? [[String: Any]] ?? []
            q.append(r)
            self.storage.set(Array(q.suffix(200)), forKey: "irn_reports")
            self.flushReports()
        }
    }

    // MARK: internals (run on `queue`)

    private var installId: String {
        if let v = storage.string(forKey: "irn_install_id") { return v }
        let v = UUID().uuidString
        storage.set(v, forKey: "irn_install_id")
        return v
    }
    private var deviceId: String? { storage.string(forKey: "irn_device_id") }
    private var deviceToken: String? { storage.string(forKey: "irn_device_token") }

    private func clearDevice() {
        ["irn_device_id", "irn_device_token", "irn_last_sync", "irn_sent_token"].forEach { storage.removeObject(forKey: $0) }
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))) ?? s
    }

    private func op(_ block: @escaping (String) -> Void) {
        queue.async {
            guard let token = self.pendingToken else { return }
            if self.deviceId == nil || self.deviceToken == nil { self.syncLocked(token) }
            guard let id = self.deviceId else { return }
            block(id)
        }
    }

    private func syncLocked(_ token: String) {
        guard !apiBase.isEmpty else { return }
        let stale = Date().timeIntervalSince1970 - storage.double(forKey: "irn_last_sync") > 24 * 3600
        if let id = deviceId, deviceToken != nil {
            if storage.string(forKey: "irn_sent_token") == token && !stale { return }
            let (st, code, _) = request("PATCH", "/devices/\(id)", ["push_token": token, "locale": Locale.current.identifier,
                                                                    "app_version": Self.appVersion()])
            if st == 401 || st == 404, code == "invalid_device_token" || code == "device_not_found" {
                clearDevice()
                return syncLocked(token)
            }
            if (200..<300).contains(st) {
                storage.set(token, forKey: "irn_sent_token")
                storage.set(Date().timeIntervalSince1970, forKey: "irn_last_sync")
            }
            return
        }
        let body: [String: Any] = [
            "install_id": installId, "platform": "ios", "push_provider": "fcm", "push_token": token,
            "app_version": Self.appVersion(), "os_version": Self.osVersion(), "device_model": Self.model(),
            "sdk_version": "ios/\(Self.version)", "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier, "notifications_enabled": true,
        ]
        let (st, _, result) = request("POST", "/devices", body, auth: false)
        if (200..<300).contains(st), let id = result["device_id"] as? String {
            storage.set(id, forKey: "irn_device_id")
            if let t = result["device_token"] as? String { storage.set(t, forKey: "irn_device_token") }
            storage.set(token, forKey: "irn_sent_token")
            storage.set(Date().timeIntervalSince1970, forKey: "irn_last_sync")
            flushReports()
        }
    }

    @discardableResult
    private func send(_ method: String, _ path: String, _ body: [String: Any]?) -> Int {
        let (st, code, _) = request(method, path, body)
        if st == 401 || st == 404, code == "invalid_device_token" || code == "device_not_found" { clearDevice() }
        return st
    }

    private func flushReports() {
        guard deviceToken != nil else { return }
        while true {
            let q = storage.array(forKey: "irn_reports") as? [[String: Any]] ?? []
            if q.isEmpty { return }
            let batch = Array(q.prefix(20))
            let (st, code, _) = request("POST", "/reports", ["reports": batch])
            if st == 0 || st >= 500 || st == 429 { return } // keep, retry later
            if st == 401 || st == 404, code == "invalid_device_token" || code == "device_not_found" { clearDevice(); return }
            storage.set(Array(q.dropFirst(batch.count)), forKey: "irn_reports") // sent, or a permanent 4xx: drop
        }
    }

    /// Blocking request; always call on `queue`. Returns (status, error code, result object).
    private func request(_ method: String, _ path: String, _ body: [String: Any]?, auth: Bool = true) -> (Int, String?, [String: Any]) {
        guard let url = URL(string: apiBase + path) else { return (0, nil, [:]) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue(appKey, forHTTPHeaderField: "X-Irnoti-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth { req.setValue("Bearer " + (deviceToken ?? ""), forHTTPHeaderField: "Authorization") }
        if let b = body { req.httpBody = try? JSONSerialization.data(withJSONObject: b) }
        let sem = DispatchSemaphore(value: 0)
        var out: (Int, String?, [String: Any]) = (0, nil, [:])
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let json = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            let code = (json["error"] as? [String: Any])?["code"] as? String
            out = (st, code, (json["result"] as? [String: Any]) ?? [:])
        }.resume()
        sem.wait()
        return out
    }

    private static func appVersion() -> String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    private static func osVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
    private static func model() -> String {
        var sys = utsname(); uname(&sys)
        return withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
    }
}
