import CoreLocation
import EventKit
import Flutter
import Network
import UIKit

/// The device tools on iOS, called only after Tako's permission gate. iOS has
/// no public API for alarms, timers or opening other apps by name, so those
/// tools are not offered there.
final class IosDeviceApi: NSObject, DeviceApi, CLLocationManagerDelegate {
  private let store = EKEventStore()
  private let ids = NumericIds()
  private let monitor = NWPathMonitor()
  private var network = "offline"
  private var locator: CLLocationManager?
  private var locating: [(id: String, completion: (Result<DeviceLocation, Error>) -> Void)] = []
  private var cancelled = Set<String>()

  override init() {
    super.init()
    monitor.pathUpdateHandler = { [weak self] path in
      let network: String
      if path.status != .satisfied {
        network = "offline"
      } else if path.usesInterfaceType(.wifi) {
        network = "wifi"
      } else if path.usesInterfaceType(.cellular) {
        network = "cellular"
      } else if path.usesInterfaceType(.wiredEthernet) {
        network = "ethernet"
      } else {
        network = "connected"
      }
      DispatchQueue.main.async { self?.network = network }
    }
    monitor.start(queue: DispatchQueue(label: "tw.avianjay.tako.network"))
  }

  private static func failure(_ code: String) -> PigeonError {
    PigeonError(code: code, message: nil, details: nil)
  }

  // MARK: Status

  func snapshot() throws -> DeviceSnapshot {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let level = device.batteryLevel
    return DeviceSnapshot(
      osVersion: device.systemVersion,
      model: Self.model(),
      batteryPercent: level < 0 ? nil : Int64((level * 100).rounded()),
      network: network
    )
  }

  /// The hardware identifier, such as `iPhone17,1`.
  private static func model() -> String {
    var info = utsname()
    uname(&info)
    let identifier = withUnsafeBytes(of: &info.machine) { buffer in
      String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
    return identifier.isEmpty ? UIDevice.current.model : identifier
  }

  // MARK: Location

  func getLocation(
    operationId: String,
    completion: @escaping (Result<DeviceLocation, Error>) -> Void
  ) {
    let manager = locator ?? CLLocationManager()
    if locator == nil {
      manager.delegate = self
      manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
      locator = manager
    }
    switch manager.authorizationStatus {
    case .denied, .restricted:
      completion(.failure(Self.failure("permission_denied")))
      return
    default:
      break
    }
    locating.append((operationId, completion))
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else {
      manager.requestLocation()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
      self?.finishLocation(operationId, .failure(Self.failure("location_timeout")))
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard !locating.isEmpty else { return }
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      manager.requestLocation()
    case .denied, .restricted:
      finishAllLocations(.failure(Self.failure("permission_denied")))
    default:
      break
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    finishAllLocations(
      .success(
        DeviceLocation(
          latitude: location.coordinate.latitude,
          longitude: location.coordinate.longitude,
          accuracyMeters: location.horizontalAccuracy,
          timestampMillis: Int64(location.timestamp.timeIntervalSince1970 * 1000)
        )))
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finishAllLocations(.failure(Self.failure("location_unavailable")))
  }

  private func finishLocation(_ id: String, _ result: Result<DeviceLocation, Error>) {
    guard let index = locating.firstIndex(where: { $0.id == id }) else { return }
    locating.remove(at: index).completion(result)
  }

  private func finishAllLocations(_ result: Result<DeviceLocation, Error>) {
    let waiting = locating
    locating = []
    for request in waiting {
      request.completion(result)
    }
  }

  // MARK: Clipboard

  func clipboardRead() throws -> String? {
    UIPasteboard.general.string
  }

  func clipboardWrite(text: String) throws {
    UIPasteboard.general.string = text
  }

  // MARK: Calendar

  private func withCalendarAccess(_ body: @escaping (Bool) -> Void) {
    let done: (Bool, Error?) -> Void = { granted, _ in
      DispatchQueue.main.async { body(granted) }
    }
    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents(completion: done)
    } else {
      store.requestAccess(to: .event, completion: done)
    }
  }

  private static func date(_ millis: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
  }

  func calendarList(
    operationId: String,
    startMillis: Int64,
    endMillis: Int64,
    limit: Int64,
    completion: @escaping (Result<DeviceCalendarListing, Error>) -> Void
  ) {
    withCalendarAccess { [weak self] granted in
      guard let self else { return }
      if self.cancelled.remove(operationId) != nil {
        completion(.failure(Self.failure("cancelled")))
        return
      }
      guard granted else {
        completion(.failure(Self.failure("permission_denied")))
        return
      }
      let predicate = self.store.predicateForEvents(
        withStart: Self.date(startMillis), end: Self.date(endMillis), calendars: nil)
      let found = self.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
      let shown = found.prefix(Int(max(0, limit)))
      completion(
        .success(
          DeviceCalendarListing(
            calendars: self.store.calendars(for: .event).map {
              DeviceCalendar(
                id: self.ids.id(for: "c:" + $0.calendarIdentifier),
                name: $0.title,
                writable: $0.allowsContentModifications
              )
            },
            events: shown.map {
              DeviceCalendarEvent(
                id: self.ids.id(for: "e:" + ($0.eventIdentifier ?? UUID().uuidString)),
                calendarId: self.ids.id(for: "c:" + $0.calendar.calendarIdentifier),
                title: $0.title ?? "",
                startMillis: Self.millis($0.startDate),
                endMillis: Self.millis($0.endDate),
                allDay: $0.isAllDay,
                location: $0.location
              )
            },
            truncated: found.count > shown.count
          )))
    }
  }

  func calendarAdd(
    operationId: String,
    draft: DeviceEventDraft,
    completion: @escaping (Result<Int64, Error>) -> Void
  ) {
    guard draft.endMillis >= draft.startMillis, !draft.title.isEmpty else {
      completion(.failure(Self.failure("invalid_arguments")))
      return
    }
    withCalendarAccess { [weak self] granted in
      guard let self else { return }
      if self.cancelled.remove(operationId) != nil {
        completion(.failure(Self.failure("cancelled")))
        return
      }
      guard granted else {
        completion(.failure(Self.failure("permission_denied")))
        return
      }
      guard let identifier = self.ids.identifier(for: draft.calendarId),
        identifier.hasPrefix("c:"),
        let calendar = self.store.calendar(withIdentifier: String(identifier.dropFirst(2)))
      else {
        completion(.failure(Self.failure("calendar_unavailable")))
        return
      }
      guard calendar.allowsContentModifications else {
        completion(.failure(Self.failure("calendar_not_writable")))
        return
      }
      let event = EKEvent(eventStore: self.store)
      event.calendar = calendar
      event.title = draft.title
      event.startDate = Self.date(draft.startMillis)
      event.endDate = Self.date(draft.endMillis)
      event.notes = draft.notes
      event.location = draft.location
      do {
        try self.store.save(event, span: .thisEvent, commit: true)
        completion(.success(self.ids.id(for: "e:" + (event.eventIdentifier ?? UUID().uuidString))))
      } catch {
        completion(.failure(Self.failure("device_operation_failed")))
      }
    }
  }

  // MARK: Launching

  func setAlarm(hour: Int64, minute: Int64, label: String?) throws -> DeviceLaunchResult {
    throw Self.failure("unavailable")
  }

  func setTimer(seconds: Int64, label: String?) throws -> DeviceLaunchResult {
    throw Self.failure("unavailable")
  }

  func openUrl(url: String) throws -> DeviceLaunchResult {
    guard let target = URL(string: url),
      ["http", "https"].contains(target.scheme?.lowercased() ?? "")
    else {
      throw Self.failure("invalid_arguments")
    }
    UIApplication.shared.open(target)
    return DeviceLaunchResult(launched: true)
  }

  func openApp(packageName: String) throws -> DeviceLaunchResult {
    throw Self.failure("unavailable")
  }

  func listApps() throws -> [DeviceAppEntry] {
    throw Self.failure("unavailable")
  }

  func cancelOperation(operationId: String) throws {
    cancelled.insert(operationId)
    finishLocation(operationId, .failure(Self.failure("cancelled")))
  }
}

/// EventKit identifiers are strings; the shared API numbers calendars and
/// events. Numbers are kept so they stay valid across launches.
private final class NumericIds {
  private let key = "tako.calendarIds"
  private var ids: [String: Int]

  init() {
    ids = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
  }

  func id(for identifier: String) -> Int64 {
    if let id = ids[identifier] { return Int64(id) }
    let id = (ids.values.max() ?? 0) + 1
    ids[identifier] = id
    UserDefaults.standard.set(ids, forKey: key)
    return Int64(id)
  }

  func identifier(for id: Int64) -> String? {
    ids.first { $0.value == Int(id) }?.key
  }
}
