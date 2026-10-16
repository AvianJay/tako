import '../util/json.dart';

/// A durable pause boundary, never an implicit approval.
class AgentSuspended implements Exception {
  const AgentSuspended(this.reason, [this.pending = const {}]);
  final String reason;
  final JsonMap pending;
}
