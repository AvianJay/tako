import ActivityKit
import Flutter
import UIKit

/// A Live Activity reports progress. UIApplication supplies finite background
/// execution; expiration stops the agent instead of silently losing its actions.
final class RemoteSessionController: NSObject {
  private let channel: FlutterMethodChannel
  private var activity: Activity<RemoteActivityAttributes>?
  private var task: UIBackgroundTaskIdentifier = .invalid
  private var active = false
  private var expired = false
  private var actions = 0
  private var lastUpdate = Date.distantPast

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "tw.avianjay.tako/remote_session", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "start": self.start()
      case "end": self.finish()
      case "progress":
        let values = call.arguments as? [String: Any] ?? [:]
        self.actions = values["count"] as? Int ?? self.actions
        if Date().timeIntervalSince(self.lastUpdate) > 1 {
          self.lastUpdate = Date()
          self.update(message: self.localized("Controlling the screen", "正在操作螢幕"), running: true)
        }
      default: result(FlutterMethodNotImplemented); return
      }
      result(nil)
    }
    NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
    // Stale activities can survive a terminated app. Reconcile on startup.
    let staleActivities = Activity<RemoteActivityAttributes>.activities
    Task {
      for item in staleActivities {
        await item.end(nil, dismissalPolicy: .immediate)
      }
    }
  }
  private func localized(_ en: String, _ zh: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
  }
  private func start() {
    guard !active else { return }
    active = true; expired = false; actions = 0
    if ActivityAuthorizationInfo().areActivitiesEnabled {
      let state = RemoteActivityAttributes.ContentState(message: localized("Controlling the screen", "正在操作螢幕"), actions: 0, running: true)
      do {
        activity = try Activity.request(attributes: RemoteActivityAttributes(startedAt: Date()),
          content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)), pushType: nil)
      } catch { /* Activity authorization never blocks a remote task. */ }
    }
    if UIApplication.shared.applicationState == .background { background() }
  }
  @objc private func background() {
    guard active && task == .invalid else { return }
    task = UIApplication.shared.beginBackgroundTask(withName: "Tako remote task") { [weak self] in
      guard let self = self else { return }
      self.expired = true
      self.active = false
      self.channel.invokeMethod("backgroundExpired", arguments: nil)
      self.finish()
    }
  }
  @objc private func foreground() { endBackgroundTask() }
  private func endBackgroundTask() {
    if task != .invalid {
      UIApplication.shared.endBackgroundTask(task)
      task = .invalid
    }
  }
  private func update(message: String, running: Bool) {
    guard let current = activity else { return }
    let state = RemoteActivityAttributes.ContentState(message: message, actions: actions, running: running)
    Task { await current.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(45))) }
  }
  private func finish() {
    active = false
    endBackgroundTask()
    guard let current = activity else { return }
    activity = nil
    let message = expired ? localized("Paused — open Tako to continue", "已暫停，請開啟 Tako 繼續") : localized("Remote task ended", "遠端任務已結束")
    let state = RemoteActivityAttributes.ContentState(message: message, actions: actions, running: false)
    Task { await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: expired ? .default : .after(Date().addingTimeInterval(15))) }
  }
  func handle(_ url: URL) -> Bool {
    guard url.scheme == "tako", url.host == "remote" else { return false }
    if url.path == "/stop" {
      channel.invokeMethod("stop", arguments: nil)
      finish()
    }
    return true
  }
  deinit { NotificationCenter.default.removeObserver(self) }
}
