import Flutter
import UIKit

// iOS has no API to block screenshots or screen recording outright (unlike
// Android's FLAG_SECURE) — an app can only react after the fact. This is the
// standard mitigation: blur the window for as long as UIScreen.isCaptured is
// true (active recording/AirPlay mirroring), and warn the user after a
// screenshot is taken. Applies regardless of account role.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyOverlay: UIVisualEffectView?

  private var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  @objc private func screenCaptureChanged() {
    guard let window = keyWindow else { return }
    if UIScreen.main.isCaptured {
      guard privacyOverlay == nil else { return }
      let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
      blur.frame = window.bounds
      blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(blur)
      privacyOverlay = blur
    } else {
      privacyOverlay?.removeFromSuperview()
      privacyOverlay = nil
    }
  }

  @objc private func screenshotTaken() {
    guard let root = keyWindow?.rootViewController else { return }
    let alert = UIAlertController(
      title: "Screenshot Detected",
      message: "Screenshots of this app are against policy. Please delete it.",
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    root.present(alert, animated: true)
  }
}
