import Flutter
import UIKit

/// Tako's own platform code on iOS: the device tools, keeping model files out
/// of backups, Apple Intelligence, and Shortcuts, which call back through
/// `tako://shortcut/…`.
final class TakoNative: NSObject, IosApi, FlutterSceneLifeCycleDelegate {
  private static var shared: TakoNative?
  private let deviceApi = IosDeviceApi()
  private let events: IosEvents
  private let remoteSession: RemoteSessionController
  private let appleIntelligence: AppleIntelligenceHost

  private init(messenger: FlutterBinaryMessenger) {
    events = IosEvents(binaryMessenger: messenger)
    remoteSession = RemoteSessionController(messenger: messenger)
    appleIntelligence = AppleIntelligenceHost(messenger: messenger)
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let native = TakoNative(messenger: messenger)
    shared = native
    DeviceApiSetup.setUp(binaryMessenger: messenger, api: native.deviceApi)
    IosApiSetup.setUp(binaryMessenger: messenger, api: native)
    registrar.addSceneDelegate(native)
  }

  func excludeFromBackup(path: String) throws {
    var url = URL(fileURLWithPath: path, isDirectory: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  func openUrl(url: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    guard let target = URL(string: url) else {
      completion(.success(false))
      return
    }
    UIApplication.shared.open(target, options: [:]) { opened in
      completion(.success(opened))
    }
  }

  /// `tako://shortcut/<id>/<status>?result=…&errorMessage=…`, from the
  /// Shortcuts app's x-success, x-error and x-cancel callbacks.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts {
      let url = context.url
      if remoteSession.handle(url) { handled = true; continue }
      guard url.scheme == "tako", url.host == "shortcut" else { continue }
      let parts = url.pathComponents.filter { $0 != "/" }
      guard parts.count == 2 else { continue }
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      func value(_ name: String) -> String? {
        query.first { $0.name == name }?.value
      }
      events.shortcutFinished(
        id: parts[0], status: parts[1], result: value("result"),
        errorMessage: value("errorMessage")
      ) { _ in }
      handled = true
    }
    return handled
  }
}
