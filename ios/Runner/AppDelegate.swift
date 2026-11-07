import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // google_maps_flutter: the SDK must have an API key before any GoogleMap
    // widget is created, otherwise the app aborts when the roadside location
    // picker / tracking screen opens. Key is read from Info.plist (GMSApiKey).
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }

    // flutter_local_notifications: route UNUserNotificationCenter callbacks
    // through FlutterAppDelegate so driving alerts show while the app is in
    // the foreground.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
