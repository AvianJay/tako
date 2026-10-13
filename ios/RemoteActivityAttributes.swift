import ActivityKit
import Foundation

struct RemoteActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var message: String
    var actions: Int
    var running: Bool
  }
  let startedAt: Date
}
