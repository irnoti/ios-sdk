# IRNoti iOS SDK

![iOS 15+](https://img.shields.io/badge/iOS-15%2B-6f42c1.svg)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)

The official IRNoti (Iran Notification) SDK for iPhone and iPad apps. Use it to register the device and its push token, receive and display notifications, segment users with Topics, Tags, External ID and Aliases, send behavioral events, and report delivery and click statistics.

**Current version:** `1.0.0`

## Features

- Automatic FCM token registration and updates
- Receive notifications in the foreground and background
- Rich image notifications (via a Notification Service Extension) and action-button click reporting (via `UNNotificationCategory`)
- Open web links and deep links
- Topic subscribe and unsubscribe
- External ID, Aliases and Tags
- Behavioral events
- Delivery and click reporting with a persistent queue and retry
- Apple privacy manifest (`PrivacyInfo.xcprivacy`) bundled with the package

## Requirements

1. An **organization** and a **project** in IRNoti with the "Push Notification" service enabled, and an **app** in that service (created with your Firebase service-account JSON file). Copy the app's **public key** (`pk_live_…`) from the dashboard.
2. Xcode 15 or later and iOS 15 or later.
3. A Firebase project with an iOS app (exact Bundle ID) and its `GoogleService-Info.plist` file.
4. Upload your APNs authentication key to Firebase (Project Settings › Cloud Messaging).
5. Enable the **Push Notifications** capability and **Background Modes › Remote notifications** in Xcode.

> [!IMPORTANT]
> The Firebase project of your app and the Firebase project whose service account you registered in IRNoti must be the same project.

> [!CAUTION]
> Only put the public key inside the app. The Firebase service-account file, the APNs key and the broker link are secret and must never be included in the app or in Git.

## Installation with Swift Package Manager

In Xcode choose `File > Add Package Dependencies` and enter this URL:

```text
https://github.com/irnoti/ios-sdk.git
```

Version rule: `Up to Next Major Version` starting from `1.0.0`. Add the `Irnoti` product to your main app target, and add the `IrnotiExtension` product only to the Notification Service Extension. For production builds, don't depend on the `main` branch; use a version tag.

## Setup

```swift
import Irnoti
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        Irnoti.shared.configure(appKey: "pk_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Irnoti.shared.setNotificationsEnabled(granted)
            if granted { DispatchQueue.main.async { application.registerForRemoteNotifications() } }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // Pass the FCM token to the SDK
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken { Irnoti.shared.setPushToken(token) }
    }

    // Notification received while the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Irnoti.shared.didReceive(userInfo: notification.request.content.userInfo)
        return [.banner, .sound]
    }

    // User tapped the notification or one of its buttons
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let url = Irnoti.shared.didTap(response: response) {
            await UIApplication.shared.open(url)
        }
    }
}
```

## Image notifications (Notification Service Extension)

Create a target of type **Notification Service Extension**, add the `IrnotiExtension` product to it, and write its class like this:

```swift
import IrnotiExtension

class NotificationService: IrnotiNotificationService {}
```

If you want the extension to report delivery too, and share the installation ID with the app, create an **App Group** and set the following in both targets before calling `configure`: `Irnoti.shared.appGroup = "group.com.yourcompany.app"`.

## Public methods

| Method | Description |
|---|---|
| `configure(appKey:apiBase:)` | Initialize the SDK (default base URL: `https://api.irnoti.ir/v1/sdk`) |
| `setPushToken(_:)` | Register and update the FCM token |
| `setNotificationsEnabled(_:)` | Tell the SDK whether the notification permission is granted |
| `identify(_:aliases:)` / `logout()` | Link the device to your user |
| `subscribe(_:)` / `unsubscribe(_:)` | Topics |
| `setTags(_:)` | Tags (`nil` value = remove) |
| `track(_:props:)` | Events |
| `didReceive(userInfo:)` / `didTap(response:)` | Delivery and click reporting |
| `unregister()` | Fully unregister the device |

All methods are asynchronous and safe to call before the device is registered.

```swift
Irnoti.shared.identify("user-123", aliases: ["phone": "09120000000"])
Irnoti.shared.subscribe("news")
Irnoti.shared.setTags(["plan": "pro", "old": nil])
Irnoti.shared.track("purchase", props: ["amount": 120000])
```

## Message fields

| Field | Description |
|---|---|
| `title`, `body` | Title and body text |
| `image` | `https` URL of the image (requires the Notification Service Extension) |
| `url` | Web link |
| `deeplink` | Absolute URI with your app's scheme; takes priority over `url` |
| `actions` | Up to two buttons: `[{"id":"open","title":"View","url":"myapp://orders/5"}]` |
| `extra` | Custom data |

For action buttons, register your `UNNotificationCategory` categories in the app, or use your own default category; the SDK sends the button ID in the click report.

## Sending your first notification

```bash
curl -X POST "https://api.irnoti.ir/v1/sdk-apps/APP_ID/send" \
  -H "Authorization: Bearer irn_live_xxx" \
  -H "Content-Type: application/json" \
  -d '{"message":{"title":"Hello","body":"Your first notification"},"target":{"all":true}}'
```

## Troubleshooting

| Problem | Cause and solution |
|---|---|
| The device does not appear in the dashboard | Check the public key and internet access. `setPushToken` must be called with the FCM token, not the APNs token. |
| Registration fails with a 403 error | The project's push service is disabled or expired, or the device limit of the plan has been reached. Check the status in the dashboard. |
| Notifications are not delivered | Check the APNs key in Firebase, the Xcode capabilities, and that the Firebase project is the same one. The simulator can't receive remote notifications; use a real device. |
| The image is not shown | Add the Notification Service Extension and make sure `mutable-content` is enabled (the server sets it automatically). The image URL must be `https`. |

## License

The license is determined by the repository owner (see the `LICENSE` file).
