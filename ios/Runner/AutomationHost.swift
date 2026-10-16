import BackgroundTasks
import Flutter
import Foundation
import UIKit
import UserNotifications

/// Atomic native ingress is available before Flutter starts, including from
/// App Intents. An event is removed only after Drift commits its import.
final class AutomationIngress {
  static let shared = AutomationIngress()
  private let lock = NSRecursiveLock()
  private var root: URL {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("automation-ingress", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  func rules() -> [[String: Any]] {
    lock.lock(); defer { lock.unlock() }
    guard let bytes = try? Data(contentsOf: root.appendingPathComponent("rules.json")), let rows = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else { return [] }
    return rows
  }
  func sync(_ json: String) throws {
    lock.lock(); defer { lock.unlock() }
    guard let bytes = json.data(using: .utf8), (try JSONSerialization.jsonObject(with: bytes)) is [[String: Any]] else { throw AutomationApiError(code: "invalid_arguments", message: nil, details: nil) }
    try bytes.write(to: root.appendingPathComponent("rules.json"), options: .atomic)
  }
  func put(_ event: [String: Any]) throws {
    lock.lock(); defer { lock.unlock() }
    guard let id = event["id"] as? String, UUID(uuidString: id) != nil else { throw AutomationApiError(code: "invalid_arguments", message: nil, details: nil) }
    try JSONSerialization.data(withJSONObject: event).write(to: root.appendingPathComponent("event-\(id).json"), options: .atomic)
  }
  func inbox() -> [[String: Any]] {
    lock.lock(); defer { lock.unlock() }
    let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    return urls.filter { $0.lastPathComponent.hasPrefix("event-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(200).compactMap { url in
      guard let data = try? Data(contentsOf: url) else { return nil }
      return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
  }
  func acknowledge(_ ids: [String]) {
    lock.lock(); defer { lock.unlock() }
    for id in ids where UUID(uuidString: id) != nil { try? FileManager.default.removeItem(at: root.appendingPathComponent("event-\(id).json")) }
  }
}

final class AutomationBroker {
  static let shared = AutomationBroker()
  private var clients: [UUID: AutomationEvents] = [:]
  private var foregroundClients = Set<UUID>()
  private var owner: String?
  private var interrupted: [String: String] = [:]
  var openRun: String?
  func attach(_ events: AutomationEvents, foreground: Bool) -> UUID { let id = UUID(); clients[id] = events; if foreground { foregroundClients.insert(id) }; return id }
  func detach(_ id: UUID) { clients.removeValue(forKey: id); foregroundClients.remove(id) }
  func acquire(_ value: String) -> Bool {
    if let current = owner, current != value {
      if value == "chat" { interrupted[current] = "chat"; for events in clients.values { events.stop(reason: "chat") { _ in } }; changed() }
      return false
    }
    owner = value; interrupted.removeValue(forKey: value); return true
  }
  func release(_ value: String) { if owner == value { owner = nil }; interrupted.removeValue(forKey: value) }
  func wasInterrupted(_ value: String) -> String? { interrupted[value] }
  func changed() { for events in clients.values { events.changed { _ in } } }
  func opened(_ id: String) {
    openRun = id
    for key in foregroundClients {
      clients[key]?.openRun(runId: id) { result in
        if case .success = result, self.openRun == id { self.openRun = nil }
      }
    }
  }
}

final class AutomationNotifications: NSObject, UNUserNotificationCenterDelegate {
  static let shared = AutomationNotifications()
  var canPost = false
  private var clockObservers: [NSObjectProtocol] = []
  func configure() {
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async { self.canPost = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional }
    }
    if clockObservers.isEmpty {
      for name in [NSNotification.Name.NSSystemTimeZoneDidChange, UIApplication.significantTimeChangeNotification] {
        clockObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
          try? AutomationIngress.shared.put(["id": UUID().uuidString, "kind": "clock"])
          AutomationBackground.schedule(earliest: Date()); AutomationBroker.shared.changed()
        })
      }
    }
  }
  func post(id: String, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = String(title.prefix(120)); content.body = String(body.prefix(4000)); content.sound = .default
    content.userInfo = ["automationRunId": id]
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "automation.\(id)", content: content, trigger: nil))
  }
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    if let id = response.notification.request.content.userInfo["automationRunId"] as? String { DispatchQueue.main.async { AutomationBroker.shared.opened(id) } }
    completionHandler()
  }
}

final class AutomationHost: AutomationApi {
  let events: AutomationEvents
  private var client: UUID!
  private var owners = Set<String>()
  private let foreground: Bool
  private let messenger: FlutterBinaryMessenger
  private var disposed = false
  var onReady: (() -> Void)?
  init(messenger: FlutterBinaryMessenger, foreground: Bool = true) {
    self.messenger = messenger
    self.foreground = foreground
    events = AutomationEvents(binaryMessenger: messenger)
    client = AutomationBroker.shared.attach(events, foreground: foreground)
    AutomationApiSetup.setUp(binaryMessenger: messenger, api: self)
  }
  deinit { for owner in owners { AutomationBroker.shared.release(owner) }; AutomationBroker.shared.detach(client) }
  func dispose() {
    guard !disposed else { return }; disposed = true
    for owner in owners { AutomationBroker.shared.release(owner) }; owners.removeAll()
    AutomationBroker.shared.detach(client)
    AutomationApiSetup.setUp(binaryMessenger: messenger, api: nil)
  }
  func ready() throws { onReady?() }
  func status() throws -> String {
    let open = foreground ? (AutomationBroker.shared.openRun ?? "") : ""
    if foreground { AutomationBroker.shared.openRun = nil }
    return encode(["exact": false, "canPost": AutomationNotifications.shared.canPost, "notificationTriggers": false, "openRun": open])
  }
  func requestExactPermission() throws {}
  func requestNotifications(completion: @escaping (Result<Bool, Error>) -> Void) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async { AutomationNotifications.shared.canPost = granted; completion(.success(granted)) }
    }
  }
  func syncRules(rulesJson: String) throws { try AutomationIngress.shared.sync(rulesJson); AutomationBackground.schedule() }
  func inbox() throws -> String { encode(AutomationIngress.shared.inbox()) }
  func acknowledge(ids: [String]) throws { AutomationIngress.shared.acknowledge(ids) }
  func wake(at: Int64?) throws { if let at { AutomationBackground.schedule(earliest: Date(timeIntervalSince1970: Double(at) / 1000)) } }
  func notify(runId: String, title: String, body: String, waiting: Bool) throws { AutomationNotifications.shared.post(id: runId, title: title, body: body) }
  func clearNotification(runId: String) throws { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["automation.\(runId)"]) }
  func acquire(owner: String) throws -> Bool { let granted = AutomationBroker.shared.acquire(owner); if granted { owners.insert(owner) }; return granted }
  func release(owner: String) throws { owners.remove(owner); AutomationBroker.shared.release(owner) }
  func interrupted(owner: String) throws -> String? { AutomationBroker.shared.wasInterrupted(owner) }
  func signalChanged() throws { AutomationBroker.shared.changed() }
  private func encode(_ value: Any) -> String { guard let bytes = try? JSONSerialization.data(withJSONObject: value), let text = String(data: bytes, encoding: .utf8) else { return "[]" }; return text }
}

enum AutomationBackground {
  static let identifier = "tw.avianjay.tako.automation.processing"
  private static var worker: AutomationBackgroundWorker?
  static func register() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
      guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
      worker = AutomationBackgroundWorker(task: task)
      worker?.start()
    }
    AutomationNotifications.shared.configure()
  }
  static func schedule(earliest: Date? = nil) {
    let due = AutomationIngress.shared.rules().filter { ($0["enabled"] as? Bool) == true }.compactMap { ($0["nextAt"] as? NSNumber)?.doubleValue }.min().map { Date(timeIntervalSince1970: $0 / 1000) }
    let incoming = AutomationIngress.shared.inbox().isEmpty ? nil : Date()
    guard let next = [earliest, due, incoming].compactMap({ $0 }).min() else { return }
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.earliestBeginDate = next
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
    // Only this identifier is replaced; iCTRL continued-processing is separate.
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    try? BGTaskScheduler.shared.submit(request)
  }
}

final class AutomationBackgroundWorker {
  private let task: BGProcessingTask
  private var engine: FlutterEngine?
  private var native: TakoNative?
  private var finished = false
  init(task: BGProcessingTask) { self.task = task }
  func start() {
    let engine = FlutterEngine(name: "tako.automation.\(UUID().uuidString)", project: nil, allowHeadlessExecution: true)
    self.engine = engine
    engine.run(withEntrypoint: "automationMain")
    GeneratedPluginRegistrant.register(with: engine)
    native = TakoNative.registerBackground(messenger: engine.binaryMessenger)
    native?.automation.onReady = { [weak self] in
      self?.native?.automation.events.execute { [weak self] result in
        self?.finish(success: (try? result.get()) == true)
      }
    }
    task.expirationHandler = { [weak self] in
      DispatchQueue.main.async {
        self?.native?.automation.events.stop(reason: "system") { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.finish(success: false) }
      }
    }
  }
  private func finish(success: Bool) {
    guard !finished else { return }; finished = true
    task.setTaskCompleted(success: success)
    native?.automation.dispose(); native = nil; engine?.destroyContext(); engine = nil
    AutomationBackground.schedule()
  }
}
