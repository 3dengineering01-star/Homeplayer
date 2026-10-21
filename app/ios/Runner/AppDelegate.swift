import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Photo backup in the background. The identifier is Backup's periodic task in Dart and is
    // listed in BGTaskSchedulerPermittedIdentifiers; iOS decides when it actually runs.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "homeplay-backup", earliestBeginInSeconds: NSNumber(value: 15 * 60))
    // With scenes, the handlers must be in place before launching finishes.
    WorkmanagerPlugin.registerLaunchHandlers()
    // Download progress notifications show while the app is open too.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HomeplayLinks") {
      HomeplayLinks.register(with: registrar)
    }
  }
}

/// The "homeplay/links" channel: invite links that open the app (homeplay://join?...) and the
/// share sheet, as MainActivity does on Android.
class HomeplayLinks: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let channel: FlutterMethodChannel

  /// The link the app was started with, until Dart asks for it.
  private var startLink: String?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "homeplay/links", binaryMessenger: registrar.messenger())
    let instance = HomeplayLinks(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
    registrar.addApplicationDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      result(startLink)
      startLink = nil
    case "share":
      let args = call.arguments as? [String: Any]
      share(args?["text"] as? String ?? "")
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func invite(_ url: URL?) -> String? {
    guard let url, url.scheme == "homeplay" else { return nil }
    return url.absoluteString
  }

  // MARK: - Links

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let link = connectionOptions?.urlContexts.compactMap({ Self.invite($0.url) }).first else {
      return false
    }
    startLink = link
    return true
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    guard let link = URLContexts.compactMap({ Self.invite($0.url) }).first else { return false }
    channel.invokeMethod("open", arguments: link)
    return true
  }

  // Without scenes (not used now, kept so links still work if that changes).
  func application(
    _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard let link = Self.invite(url) else { return false }
    channel.invokeMethod("open", arguments: link)
    return true
  }

  // MARK: - Share sheet

  private func share(_ text: String) {
    guard let top = Self.topController() else { return }
    let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    // On iPad the sheet is a popover and needs a place to point at.
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = top.view
      popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    top.present(sheet, animated: true)
  }

  private static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let shown = top?.presentedViewController { top = shown }
    return top
  }
}
