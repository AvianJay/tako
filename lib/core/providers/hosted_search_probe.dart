import 'dart:async';

import 'cancel_token.dart';
import 'provider_event.dart';

enum HostedSearchProbeStatus {
  supported,
  notObserved,
  unsupportedProtocol,
  disabled,
  denied,
  failed,
  cancelled,
  timedOut,
  busy,
}

/// Only a bounded status and HTTP code leave the probe. Provider prose, headers
/// and error bodies can contain credentials and are never displayed or stored.
class HostedSearchProbeResult {
  const HostedSearchProbeResult(this.status, {this.statusCode});

  final HostedSearchProbeStatus status;
  final int? statusCode;
}

/// A text claim or a citation is not proof that a proxy forwards hosted search.
/// Require a native receipt and a clean terminal response, even if a successful
/// receipt was followed by an error or an incomplete/truncated completion.
Future<HostedSearchProbeResult> observeHostedSearchProbe(
  Stream<ProviderEvent> events, {
  required CancelToken cancel,
}) async {
  cancel.throwIfCancelled();
  var observed = false;
  var failed = false;
  var completed = false;
  int? statusCode;
  var timedOut = false;
  final result = Completer<HostedSearchProbeResult>();
  late StreamSubscription<ProviderEvent> subscription;
  void cancelled() {
    if (!result.isCompleted) {
      result.complete(
        const HostedSearchProbeResult(HostedSearchProbeStatus.cancelled),
      );
    }
    unawaited(subscription.cancel());
  }

  subscription = events.listen(
    (event) {
      switch (event) {
        case HostedSearchEvent():
          observed |= event.success;
          failed |= !event.success;
        case ProviderError():
          failed = true;
          statusCode = event.statusCode;
          timedOut |= event.code == 'timeout';
        case Done():
          final clean = const {
            'stop',
            'end_turn',
            'stop_sequence',
            'completed',
          }.contains(event.stopReason);
          completed |= clean;
          failed |= !clean;
        default:
          break;
      }
    },
    onError: (Object error, StackTrace stack) {
      failed = true;
      if (error is ProviderError) {
        statusCode = error.statusCode;
        timedOut |= error.code == 'timeout';
      }
    },
    onDone: () {
      if (result.isCompleted) return;
      result.complete(
        HostedSearchProbeResult(
          timedOut
              ? HostedSearchProbeStatus.timedOut
              : failed || !completed
              ? HostedSearchProbeStatus.failed
              : observed
              ? HostedSearchProbeStatus.supported
              : HostedSearchProbeStatus.notObserved,
          statusCode: statusCode,
        ),
      );
    },
  );
  cancel.addListener(cancelled);
  try {
    return await result.future;
  } finally {
    cancel.removeListener(cancelled);
  }
}
