import ActivityKit
import BackgroundTasks
import Flutter
import UIKit

/// A Live Activity reports progress. UIApplication supplies finite background
/// execution; expiration stops the agent instead of silently losing its actions.
final class RemoteSessionController: NSObject {
  private static let continuedIdentifier = "tw.avianjay.tako.remote.*"
  private static weak var current: RemoteSessionController?
  private static var registered = false
  // Store the base class so the controller remains usable before iOS 26.
  private var continuedTask: BGTask?
  private var continuedRequestIdentifier: String?
  private let channel: FlutterMethodChannel
  private var activity: Activity<RemoteActivityAttributes>?
  private var task: UIBackgroundTaskIdentifier = .invalid
  private var active = false
  private var expired = false
  private var actions = 0
  private var lastUpdate = Date.distantPast

  /// Register once before applicationDidFinishLaunching returns. Tasks are
  /// submitted later only for an active, user-started foreground chat turn.
  static func registerContinuedProcessing() {
    guard #available(iOS 26.0, *), !registered else { return }
    registered = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: continuedIdentifier, using: .main
    ) { task in
      guard let controller = current, controller.active,
            task.identifier == controller.continuedRequestIdentifier,
            let continued = task as? BGContinuedProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      controller.continuedTask = continued
      continued.progress.totalUnitCount = 200
      continued.progress.completedUnitCount = Int64(min(controller.actions, 199))
      continued.expirationHandler = { [weak controller] in
        DispatchQueue.main.async { controller?.expire() }
      }
      controller.endBackgroundTask()
    }
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "tw.avianjay.tako/remote_session", binaryMessenger: messenger)
    super.init()
    Self.current = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "start": self.start()
      case "end": self.finish()
      case "progress":
        let values = call.arguments as? [String: Any] ?? [:]
        self.actions = values["count"] as? Int ?? self.actions
        if #available(iOS 26.0, *),
           let continued = self.continuedTask as? BGContinuedProcessingTask {
          // Reflect completed device actions, never a timer-based heartbeat.
          continued.progress.totalUnitCount = Int64(max(200, self.actions + 1))
          continued.progress.completedUnitCount = Int64(self.actions)
          continued.updateTitle(self.localized("Remote phone task", "手機遠端任務"),
            subtitle: self.localized("Actions: \(self.actions)", "已操作 \(self.actions) 次"))
        }
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
    if #available(iOS 26.0, *), Self.registered,
       UIApplication.shared.applicationState == .active {
      let identifier = "tw.avianjay.tako.remote." + UUID().uuidString
      let request = BGContinuedProcessingTaskRequest(
        identifier: identifier,
        title: localized("Remote phone task", "手機遠端任務"),
        subtitle: localized("Starting…", "正在開始…"))
      // Never queue a phone task to restart after its initiating turn ends.
      request.strategy = .fail
      continuedRequestIdentifier = identifier
      do { try BGTaskScheduler.shared.submit(request) }
      catch {
        continuedRequestIdentifier = nil
        /* Retain the bounded UIApplication fallback below. */
      }
    }
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
    guard active && task == .invalid && continuedTask == nil else { return }
    task = UIApplication.shared.beginBackgroundTask(withName: "Tako remote task") { [weak self] in
      guard let self = self else { return }
      self.expire()
    }
  }
  private func expire() {
    guard active else { return }
    expired = true
    active = false
    channel.invokeMethod("backgroundExpired", arguments: nil)
    finish()
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
    if let continued = continuedTask {
      continuedTask = nil
      if #available(iOS 26.0, *),
         let processing = continued as? BGContinuedProcessingTask, !expired {
        processing.progress.completedUnitCount = processing.progress.totalUnitCount
      }
      continued.setTaskCompleted(success: !expired)
    }
    if #available(iOS 26.0, *), let identifier = continuedRequestIdentifier {
      continuedRequestIdentifier = nil
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
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
      expired = true
      channel.invokeMethod("stop", arguments: nil)
      finish()
    }
    return true
  }
  deinit { NotificationCenter.default.removeObserver(self) }
}
