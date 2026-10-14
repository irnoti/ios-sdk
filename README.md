# IRNoti iOS SDK

![iOS 15+](https://img.shields.io/badge/iOS-15%2B-6f42c1.svg)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)

<div dir="rtl" align="right">

SDK رسمی ایران‌ناتیفیکیشن (IRNoti) برای اپلیکیشن‌های آیفون و آیپد است. با آن می‌توانید دستگاه و توکن پوش را ثبت کنید، اعلان را دریافت و نمایش دهید، کاربران را با Topic، Tag، External ID و Alias دسته‌بندی کنید، رویدادهای رفتاری بفرستید و گزارش تحویل و کلیک را ثبت کنید.

**نسخه فعلی:** <code dir="ltr">1.0.0</code>

## قابلیت‌ها

- ثبت و به‌روزرسانی خودکار توکن FCM
- دریافت اعلان در پیش‌زمینه و پس‌زمینه
- اعلان تصویری (با Notification Service Extension) و ثبت کلیک دکمه‌های اعلان (با UNNotificationCategory)
- بازکردن لینک وب و Deep Link
- عضویت و لغو عضویت در Topic
- External ID، Alias و Tag
- رویدادهای رفتاری
- گزارش تحویل و کلیک با صف ماندگار و تلاش مجدد
- فایل حریم خصوصی اپل (`PrivacyInfo.xcprivacy`) همراه بسته

## پیش‌نیازها

1. یک **سازمان** و یک **پروژه** در ایران‌ناتیفیکیشن که سرویس «پوش‌نوتیفیکیشن» برایش فعال است، و یک **اپ** در آن سرویس (با فایل JSON حساب سرویس Firebase). **کلید عمومی** اپ (`pk_live_…`) را از پنل بردارید.
2. Xcode 15 یا بالاتر و iOS 15 به بالا.
3. یک پروژه Firebase با اپ iOS (Bundle ID دقیق) و فایل `GoogleService-Info.plist`.
4. کلید احراز هویت APNs را در Firebase (Project Settings › Cloud Messaging) بارگذاری کنید.
5. قابلیت **Push Notifications** و **Background Modes › Remote notifications** را در Xcode فعال کنید.

> [!IMPORTANT]
> پروژه Firebase اپ و پروژه Firebase‌ای که حساب سرویسش را در ایران‌ناتیفیکیشن ثبت کرده‌اید باید یکی باشند.

> [!CAUTION]
> فقط کلید عمومی را داخل اپ بگذارید. فایل حساب سرویس Firebase، کلید APNs و لینک بروکر محرمانه‌اند و نباید داخل اپ یا Git باشند.

## نصب با Swift Package Manager

در Xcode: `File > Add Package Dependencies` و آدرس زیر:

</div>

```text
https://github.com/irnoti/ios-sdk.git
```

<div dir="rtl" align="right">

قانون نسخه: `Up to Next Major Version` از `1.0.0`. محصول `Irnoti` را به هدف اصلی اپ و محصول `IrnotiExtension` را فقط به Notification Service Extension اضافه کنید. برای نسخه نهایی به شاخه `main` وابسته نشوید و از تگ نسخه استفاده کنید.

## راه‌اندازی

</div>

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

    // توکن FCM را به SDK بدهید
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken { Irnoti.shared.setPushToken(token) }
    }

    // اعلان در پیش‌زمینه
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Irnoti.shared.didReceive(userInfo: notification.request.content.userInfo)
        return [.banner, .sound]
    }

    // لمس اعلان یا دکمه
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let url = Irnoti.shared.didTap(response: response) {
            await UIApplication.shared.open(url)
        }
    }
}
```

<div dir="rtl" align="right">

## اعلان تصویری (Notification Service Extension)

یک هدف از نوع **Notification Service Extension** بسازید، محصول `IrnotiExtension` را به آن اضافه کنید و کلاس آن را این‌طور بنویسید:

</div>

```swift
import IrnotiExtension

class NotificationService: IrnotiNotificationService {}
```

<div dir="rtl" align="right">

اگر می‌خواهید اکستنشن هم گزارش تحویل بفرستد و شناسه نصب با اپ مشترک باشد، یک **App Group** بسازید و قبل از `configure` در هر دو هدف بنویسید: `Irnoti.shared.appGroup = "group.com.yourcompany.app"`.

## متدهای عمومی

| متد | توضیح |
|---|---|
| `configure(appKey:apiBase:)` | راه‌اندازی (آدرس پیش‌فرض: `https://api.irnoti.ir/v1/sdk`) |
| `setPushToken(_:)` | ثبت و به‌روزرسانی توکن FCM |
| `setNotificationsEnabled(_:)` | اطلاع از وضعیت مجوز اعلان |
| `identify(_:aliases:)` / `logout()` | اتصال دستگاه به کاربر شما |
| `subscribe(_:)` / `unsubscribe(_:)` | Topic |
| `setTags(_:)` | Tag (مقدار `nil` = حذف) |
| `track(_:props:)` | رویداد |
| `didReceive(userInfo:)` / `didTap(response:)` | گزارش تحویل و کلیک |
| `unregister()` | لغو کامل ثبت دستگاه |

همه متدها غیرهمزمان‌اند و قبل از ثبت دستگاه هم امن هستند.

</div>

```swift
Irnoti.shared.identify("user-123", aliases: ["phone": "09120000000"])
Irnoti.shared.subscribe("news")
Irnoti.shared.setTags(["plan": "pro", "old": nil])
Irnoti.shared.track("purchase", props: ["amount": 120000])
```

<div dir="rtl" align="right">

## فیلدهای پیام

| فیلد | توضیح |
|---|---|
| `title`, `body` | عنوان و متن |
| `image` | آدرس `https` تصویر (نیازمند Notification Service Extension) |
| `url` | لینک وب |
| `deeplink` | آدرس مطلق با Scheme اپ؛ بر `url` اولویت دارد |
| `actions` | حداکثر دو دکمه: `[{"id":"open","title":"مشاهده","url":"myapp://orders/5"}]` |
| `extra` | داده سفارشی |

برای دکمه‌ها، دسته‌های `UNNotificationCategory` را در اپ ثبت کنید یا از دسته پیش‌فرض خودتان استفاده کنید؛ SDK شناسه دکمه را در گزارش کلیک می‌فرستد.

## ارسال اولین اعلان

</div>

```bash
curl -X POST "https://api.irnoti.ir/v1/sdk-apps/APP_ID/send" \
  -H "Authorization: Bearer irn_live_xxx" \
  -H "Content-Type: application/json" \
  -d '{"message":{"title":"سلام","body":"اولین اعلان"},"target":{"all":true}}'
```

<div dir="rtl" align="right">

## رفع اشکال

| مشکل | علت و راه‌حل |
|---|---|
| دستگاه در پنل دیده نمی‌شود | کلید عمومی و اینترنت را بررسی کنید. `setPushToken` باید با توکن FCM صدا زده شود، نه توکن APNs. |
| ثبت با خطای ۴۰۳ رد می‌شود | سرویس پوش پروژه غیرفعال/منقضی است یا سقف دستگاه بسته پر شده؛ وضعیت را در پنل ببینید. |
| اعلان نمی‌رسد | کلید APNs در Firebase، Capabilityهای Xcode و یکی‌بودن پروژه Firebase را بررسی کنید. شبیه‌ساز اعلان راه دور نمی‌گیرد؛ دستگاه واقعی لازم است. |
| تصویر نمایش داده نمی‌شود | Notification Service Extension را اضافه کنید و `mutable-content` فعال باشد (سرور خودکار می‌گذارد). آدرس تصویر باید `https` باشد. |

## مجوز استفاده

مجوز استفاده را مالک مخزن تعیین می‌کند (فایل `LICENSE`).

</div>
