import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var hdrPlayerPlugin: AppleTvHdrPlayerPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleTvHdrPlayerPlugin") {
      hdrPlayerPlugin = AppleTvHdrPlayerPlugin.register(with: registrar)
    }

    let channel = FlutterMethodChannel(
      name: "io.github.sharon_xa.cinemakom/platform",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isTv":
        result(true)
      case "setWakelock":
        let enabled = (call.arguments as? Bool) ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = enabled
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
