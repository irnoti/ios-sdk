import UserNotifications
import Irnoti

/// Subclass this in your Notification Service Extension target (set `Irnoti.shared.appGroup` first if you want the
/// extension to share the install with the app). It downloads `image` as a rich attachment and records delivery.
open class IrnotiNotificationService: UNNotificationServiceExtension {
    private var handler: ((UNNotificationContent) -> Void)?
    private var best: UNMutableNotificationContent?

    override open func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        handler = contentHandler
        best = request.content.mutableCopy() as? UNMutableNotificationContent
        let info = request.content.userInfo
        guard Irnoti.isIrnotiMessage(info) else { return contentHandler(request.content) }
        Irnoti.shared.didReceive(userInfo: info)

        guard let s = info["image"] as? String, s.hasPrefix("https://"), let url = URL(string: s) else {
            return contentHandler(best ?? request.content)
        }
        URLSession.shared.downloadTask(with: url) { [weak self] tmp, resp, _ in
            defer { self?.finish() }
            guard let tmp = tmp else { return }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + "." + ext)
            guard (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil,
                  let att = try? UNNotificationAttachment(identifier: "image", url: dest) else { return }
            self?.best?.attachments = [att]
        }.resume()
    }

    override open func serviceExtensionTimeWillExpire() { finish() }

    private func finish() {
        if let h = handler, let c = best { handler = nil; h(c) }
    }
}
