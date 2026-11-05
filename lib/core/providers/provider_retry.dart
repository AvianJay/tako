import 'dart:async';

import 'package:http/http.dart' as http;

import 'cancel_token.dart';
import 'provider_adapter.dart';
import 'provider_event.dart';

/// Retries model generation from the same request, never the tool executor.
extension ProviderRetry on ProviderAdapter {
  Stream<ProviderEvent> sendWithRetry(
    ChatRequest request, {
    required CancelToken cancel,
    required void Function() onRetry,
    List<Duration> retryDelays = const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
    ],
  }) async* {
    for (var attempt = 0; !cancel.isCancelled; attempt++) {
      ProviderError? failure;
      var deliveredImage = false;
      try {
        await for (final event in send(request, cancel: cancel)) {
          if (cancel.isCancelled) return;
          if (event is ProviderError) {
            failure = event;
            break;
          }
          if (event is GeneratedImage) deliveredImage = true;
          yield event;
          if (event is Done) return;
        }
      } on RequestCancelled {
        return;
      } on ProviderError catch (error) {
        failure = error;
      } on TimeoutException {
        failure = const ProviderError(
          'Provider connection timed out',
          code: 'timeout',
        );
      } on http.ClientException {
        // Transport exceptions can contain private URLs or headers.
        failure = const ProviderError(
          'Could not reach the provider',
          code: 'network',
        );
      }
      if (cancel.isCancelled) return;
      final error =
          failure ??
          const ProviderError(
            'Provider stream ended before completion',
            code: 'incomplete_stream',
          );
      if (deliveredImage ||
          attempt >= retryDelays.length ||
          !_isTransient(error)) {
        yield error;
        return;
      }
      // Keep partial output if Stop is pressed during the backoff. Only reset
      // it when a new attempt actually starts, before any new fragments arrive.
      await _wait(retryDelays[attempt], cancel);
      if (cancel.isCancelled) return;
      onRetry();
    }
  }
}

bool _isTransient(ProviderError error) {
  if ({
    'insufficient_quota',
    'billing_hard_limit_reached',
    'invalid_api_key',
    'authentication_error',
    'permission_error',
    // Tako Den: the daily shared-model limit, or the provider refused the
    // server's key.
    'quota_exceeded',
    'upstream_auth',
  }.contains(error.code)) {
    return false;
  }
  if (error.statusCode case final status?) {
    return {408, 409, 425, 429}.contains(status) ||
        status >= 500 && status <= 599;
  }
  return {
    'network',
    'timeout',
    'incomplete_stream',
    'rate_limit_exceeded',
    'rate_limit_error',
    'overloaded_error',
    'server_error',
    'internal_server_error',
    'service_unavailable',
    'aicore_busy',
    'apple_busy',
  }.contains(error.code);
}

Future<void> _wait(Duration delay, CancelToken cancel) async {
  if (cancel.isCancelled) return;
  final ready = Completer<void>();
  final timer = Timer(delay, ready.complete);
  void stopped() {
    timer.cancel();
    if (!ready.isCompleted) ready.complete();
  }

  cancel.addListener(stopped);
  try {
    await ready.future;
  } finally {
    timer.cancel();
    cancel.removeListener(stopped);
  }
}
