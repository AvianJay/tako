import ActivityKit
import BackgroundTasks
import Flutter
import UIKit

/// A Live Activity reports progress. UIApplication supplies finite background
/// execution; expiration stops the agent instead of silently losing its actions.
final class RemoteSessionController: NSObject {
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
  private var processingState = "idle"
  private var registered = false
  private var submitted = false
  private var handlerStarted = false
  private var submissionError: NSError?
  private var activityHide: DispatchWorkItem?
  private var statusAutoHidden = false
  private var stopReason: String?
  private var previousIdleTimerDisabled: Bool?

  /// Continued tasks may register at user initiation. Register the same concrete
  /// identifier we submit, not the Info.plist permission wildcard. Each ID is
  /// registered once; the scheduler's retained handler captures only weak self.
  @available(iOS 26.0, *)
  private func registerContinuedProcessing(_ identifier: String) -> Bool {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: identifier, using: .main
    ) { [weak self] task in
      guard let controller = self, controller.active,
            task.identifier == controller.continuedRequestIdentifier,
            let continued = task as? BGContinuedProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      controller.continuedTask = continued
      controller.handlerStarted = true
      controller.processingState = "running"
      continued.progress.totalUnitCount = 200
      continued.progress.completedUnitCount = Int64(min(controller.actions, 199))
      continued.expirationHandler = { [weak controller] in
        DispatchQueue.main.async { controller?.expire() }
      }
      controller.endBackgroundTask()
      controller.publishDiagnostics()
    }
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "tw.avianjay.tako/remote_session", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "diagnostics": result(self.diagnostics()); return
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
          // Keep the system presentation quiet. Rewriting the subtitle for
          // every tap can repeatedly expand the banner over app navigation.
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
  private func diagnostics() -> [String: Any] {
    var values: [String: Any] = [
      "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
      "processing_state": processingState,
      "registered": registered,
      "submitted": submitted,
      "handler_started": handlerStarted,
      "custom_activity_visible": activity != nil,
      "status_auto_hidden": statusAutoHidden
    ]
    if let reason = stopReason { values["stop_reason"] = reason }
    if let error = submissionError {
      values["error_domain"] = error.domain
      values["error_code"] = error.code
    }
    return values
  }
  private func publishDiagnostics() {
    channel.invokeMethod("diagnosticsChanged", arguments: diagnostics())
  }
  private func start() {
    guard !active else { return }
    previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
    UIApplication.shared.isIdleTimerDisabled = true
    active = true; expired = false; actions = 0
    stopReason = nil
    statusAutoHidden = false
    registered = false; submitted = false; handlerStarted = false
    submissionError = nil; processingState = "bounded"
    if #available(iOS 26.0, *),
       UIApplication.shared.applicationState == .active {
      let identifier = "tw.avianjay.tako.remote." + UUID().uuidString
      let request = BGContinuedProcessingTaskRequest(
        identifier: identifier,
        title: localized("Remote phone task", "手機遠端任務"),
        subtitle: localized("Starting…", "正在開始…"))
      // Never queue a phone task to restart after its initiating turn ends.
      request.strategy = .fail
      continuedRequestIdentifier = identifier
      registered = registerContinuedProcessing(identifier)
      if registered {
        do {
          try BGTaskScheduler.shared.submit(request)
          submitted = true
          if !handlerStarted { processingState = "submitted" }
        } catch {
          submissionError = error as NSError
          processingState = "submission_failed"
          continuedRequestIdentifier = nil
        }
      } else {
        processingState = "registration_failed"
        continuedRequestIdentifier = nil
      }
    }
    publishDiagnostics()
    // iOS 26 continued processing already supplies a system Live Activity.
    // Avoid a duplicate custom activity. The fallback status is brief and
    // ending it never ends the actual background execution task.
    if !submitted && ActivityAuthorizationInfo().areActivitiesEnabled {
      let state = RemoteActivityAttributes.ContentState(message: localized("Controlling the screen", "正在操作螢幕"), actions: 0, running: true)
      do {
        activity = try Activity.request(attributes: RemoteActivityAttributes(startedAt: Date()),
          content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(45)), pushType: nil)
        let hide = DispatchWorkItem { [weak self] in self?.hideActivity() }
        activityHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: hide)
      } catch { /* Activity authorization never blocks a remote task. */ }
    }
    // Acquire finite background time before launch can move us out of front.
    // The continued-processing handler releases this bridge when it starts.
    background()
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
    stopReason = "system_expiration"
    processingState = "expired"
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
  private func hideActivity() {
    activityHide?.cancel()
    activityHide = nil
    guard let current = activity else { return }
    activity = nil
    statusAutoHidden = true
    Task { await current.end(nil, dismissalPolicy: .immediate) }
    publishDiagnostics()
  }
  private func finish() {
    active = false
    if let previous = previousIdleTimerDisabled {
      UIApplication.shared.isIdleTimerDisabled = previous
      previousIdleTimerDisabled = nil
    }
    if !expired { processingState = "ended" }
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
    activityHide?.cancel()
    activityHide = nil
    let current = activity
    activity = nil
    publishDiagnostics()
    guard let current = current else { return }
    let message = expired ? localized("Paused — open Tako to continue", "已暫停，請開啟 Tako 繼續") : localized("Remote task ended", "遠端任務已結束")
    let state = RemoteActivityAttributes.ContentState(message: message, actions: actions, running: false)
    Task { await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
  }
  func handle(_ url: URL) -> Bool {
    guard url.scheme == "tako", url.host == "remote" else { return false }
    if url.path == "/stop" {
      expired = true
      stopReason = "user_stop"
      channel.invokeMethod("stop", arguments: nil)
      finish()
    }
    return true
  }
  deinit { NotificationCenter.default.removeObserver(self) }
}
