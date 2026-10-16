import AppIntents
import Foundation

struct TakoAutomationEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tako Automation")
  static var defaultQuery = TakoAutomationQuery()
  let id: String
  let name: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct TakoAutomationQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [TakoAutomationEntity] {
    let all = try await suggestedEntities()
    return all.filter { identifiers.contains($0.id) }
  }
  func suggestedEntities() async throws -> [TakoAutomationEntity] {
    AutomationIngress.shared.rules().compactMap { rule in
      guard rule["enabled"] as? Bool == true, rule["trigger"] as? String == "shortcut", let id = rule["id"] as? String, let name = rule["name"] as? String else { return nil }
      return TakoAutomationEntity(id: id, name: name)
    }
  }
}

struct QueueTakoAutomationIntent: AppIntent {
  static var title: LocalizedStringResource = "Queue Tako Automation"
  static var description = IntentDescription("Add a saved automation to Tako's background queue. Execution may be delayed by iOS. Open Tako when a task needs your approval.")
  static var openAppWhenRun: Bool = false
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { [.background] }
  @Parameter(title: "Automation") var automation: TakoAutomationEntity
  @Parameter(title: "Input text") var input: String?
  static var parameterSummary: some ParameterSummary { Summary("Queue \(\.$automation) with \(\.$input)") }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let rule = AutomationIngress.shared.rules().first(where: { $0["id"] as? String == automation.id }), rule["enabled"] as? Bool == true, rule["trigger"] as? String == "shortcut" else {
      return .result(dialog: "This automation is unavailable. Open Tako to review it.")
    }
    try AutomationIngress.shared.put(["id": UUID().uuidString, "kind": "shortcut", "ruleId": automation.id, "revision": rule["revision"] ?? 1, "data": ["text": String((input ?? "").prefix(60000)), "source": "shortcut"]])
    await MainActor.run { AutomationBackground.schedule(earliest: Date()); AutomationBroker.shared.changed() }
    return .result(dialog: "Queued in Tako. iOS may delay background execution.")
  }
}

struct TakoAutomationShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: QueueTakoAutomationIntent(), phrases: ["Queue automation in \(.applicationName)"], shortTitle: "Queue Automation", systemImageName: "clock.arrow.circlepath")
  }
}
