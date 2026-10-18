import Flutter
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DezuraReviewPrompt") {
      let channel = FlutterMethodChannel(
        name: "jp.dezura.app/review", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "maybeRequestReview" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(AppDelegate.requestReviewOncePerVersion())
      }
    }
  }

  /// Shows the App Store rating prompt at most once per app version.
  private static func requestReviewOncePerVersion() -> Bool {
    let key = "dezura.reviewRequestedVersion"
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let defaults = UserDefaults.standard
    if defaults.string(forKey: key) == version { return false }
    guard let scene = UIApplication.shared.connectedScenes
      .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    else { return false }
    defaults.set(version, forKey: key)
    SKStoreReviewController.requestReview(in: scene)
    return true
  }
}
