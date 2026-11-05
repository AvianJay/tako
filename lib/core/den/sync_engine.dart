import 'dart:async';
import 'dart:math';

import '../util/json.dart';
import 'den_client.dart';

/// A local record that changed since it was last pushed.
final class PendingChange {
  const PendingChange({
    required this.collection,
    required this.id,
    required this.serverVersion,
    required this.rev,
    this.data,
  });

  final String collection;
  final String id;
  final int serverVersion;

  /// The local change counter when this was read. A record edited again
  /// while its push was in flight stays pending.
  final int rev;

  /// Null for a deletion.
  final JsonMap? data;

  DenChange get change => DenChange(
    collection: collection,
    id: id,
    baseVersion: serverVersion,
    data: data,
  );
}

final class ApplyResult {
  const ApplyResult({
    this.conversations = const {},
    this.memories = false,
    this.settings = false,
    this.deferred = const [],
  });

  /// Conversations whose record or messages changed.
  final Set<String> conversations;
  final bool memories;
  final bool settings;

  /// Messages whose conversation is not here yet; retried after more pulls.
  final List<DenRecord> deferred;

  bool get changed => conversations.isNotEmpty || memories || settings;
}

/// The local side of sync, kept in the app database.
abstract interface class SyncLedger {
  /// Starts tracking changes and marks every existing record for upload, so
  /// what this device already has is merged into the account.
  Future<void> enable();

  /// Stops tracking and forgets all sync state. Local data stays.
  Future<void> disable();

  Future<int> cursor();
  Future<void> setCursor(int seq);
  Future<List<PendingChange>> pending({int limit = 200});
  Future<int> pendingCount();
  Future<void> markPushed(PendingChange change, int version);

  /// The server refused the record (too large, invalid); stop retrying it.
  Future<void> markRejected(PendingChange change);

  /// The server lost its copy; the next push sends the record as new.
  Future<void> forgetServerCopy(String collection, String id);

  /// Writes remote records locally without marking them for upload. A record
  /// with unpushed local changes is resolved: deletions win, otherwise the
  /// newer conversation or memory wins and a local message is kept.
  Future<ApplyResult> apply(List<DenRecord> records);
}

final class SyncStatus {
  const SyncStatus({
    this.syncing = false,
    this.lastSyncedAt,
    this.error,
    this.pending = 0,
    this.live = false,
  });

  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? error;
  final int pending;

  /// Connected to the server's event stream.
  final bool live;

  SyncStatus copyWith({
    bool? syncing,
    DateTime? lastSyncedAt,
    String? error,
    bool clearError = false,
    int? pending,
    bool? live,
  }) => SyncStatus(
    syncing: syncing ?? this.syncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: clearError ? null : (error ?? this.error),
    pending: pending ?? this.pending,
    live: live ?? this.live,
  );
}

/// Pushes local changes and pulls remote ones. One sync runs at a time; a
/// request during a sync runs another one right after it.
final class SyncEngine {
  SyncEngine({
    required this.client,
    required this.ledger,
    required this.deviceId,
    this.onApplied,
    this.onStatus,
    this.onModelsChanged,
    this.onAccountChanged,
    this.onSignedOut,
  });

  final DenClient client;
  final SyncLedger ledger;
  final String deviceId;
  final void Function(ApplyResult)? onApplied;
  final void Function(SyncStatus)? onStatus;
  final void Function()? onModelsChanged;
  final void Function()? onAccountChanged;

  /// The token stopped working (revoked from the web, account disabled).
  final void Function()? onSignedOut;

  SyncStatus status = const SyncStatus();
  Future<void>? _running;
  bool _again = false;
  Timer? _scheduled;
  bool _disposed = false;
  Completer<void>? _stopLive;

  static const _maxPushRounds = 20;

  void _set(SyncStatus next) {
    status = next;
    if (!_disposed) onStatus?.call(next);
  }

  /// Syncs after [delay], merging requests that arrive meanwhile.
  void schedule([Duration delay = const Duration(seconds: 2)]) {
    if (_disposed) return;
    _scheduled?.cancel();
    _scheduled = Timer(delay, () => unawaited(sync()));
  }

  Future<void> sync() {
    if (_disposed) return Future.value();
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      _set(status.copyWith(syncing: true));
      try {
        await _push();
        await _pull();
        _set(
          status.copyWith(
            syncing: false,
            lastSyncedAt: DateTime.now(),
            clearError: true,
            pending: await ledger.pendingCount(),
          ),
        );
      } on DenException catch (e) {
        if (e.status == 401 ||
            e.status == 403 && e.code == 'account_disabled') {
          _set(status.copyWith(syncing: false, error: e.message));
          onSignedOut?.call();
          return;
        }
        _set(status.copyWith(syncing: false, error: e.message));
      } on Object catch (e) {
        _set(status.copyWith(syncing: false, error: '$e'));
      }
    } while (_again && !_disposed);
  }

  Future<void> _push() async {
    for (var round = 0; round < _maxPushRounds && !_disposed; round++) {
      final batch = await ledger.pending();
      if (batch.isEmpty) return;
      final byKey = {for (final c in batch) '${c.collection}/${c.id}': c};
      final results = await client.push([for (final c in batch) c.change]);
      final conflicts = <DenRecord>[];
      for (final result in results) {
        final change = byKey['${result.collection}/${result.id}'];
        if (change == null) continue;
        switch (result) {
          case DenPushed(:final version):
            await ledger.markPushed(change, version);
          case DenPushConflict(:final current?):
            conflicts.add(current);
          case DenPushConflict():
            await ledger.forgetServerCopy(change.collection, change.id);
          case DenPushRejected():
            await ledger.markRejected(change);
        }
      }
      if (conflicts.isNotEmpty) _notify(await ledger.apply(conflicts));
    }
  }

  Future<void> _pull() async {
    var since = await ledger.cursor();
    var deferred = <DenRecord>[];
    final applied = <ApplyResult>[];
    while (!_disposed) {
      final page = await client.pull(since);
      if (page.reset) {
        since = 0;
        await ledger.setCursor(0);
        continue;
      }
      final result = await ledger.apply([...deferred, ...page.records]);
      applied.add(result);
      deferred = result.deferred;
      since = page.seq;
      // Never move past a message still waiting for its conversation, or a
      // restart would skip it.
      final waiting = deferred.map((r) => r.seq - 1);
      await ledger.setCursor(
        waiting.isEmpty ? since : min(since, waiting.reduce(min)),
      );
      if (!page.more) break;
    }
    // Messages of a conversation that never arrived (deleted, or private on
    // the device that wrote them) are dropped.
    if (deferred.isNotEmpty) await ledger.setCursor(since);
    final merged = ApplyResult(
      conversations: {for (final r in applied) ...r.conversations},
      memories: applied.any((r) => r.memories),
      settings: applied.any((r) => r.settings),
    );
    _notify(merged);
  }

  void _notify(ApplyResult result) {
    if (result.changed && !_disposed) onApplied?.call(result);
  }

  /// Keeps an event stream open, syncing when another device changes
  /// something. Reconnects with backoff until [stopLive].
  void startLive() {
    if (_disposed || _stopLive != null) return;
    final stop = _stopLive = Completer<void>();
    unawaited(_listen(stop));
  }

  void stopLive() {
    final stop = _stopLive;
    _stopLive = null;
    if (stop != null && !stop.isCompleted) stop.complete();
    if (!_disposed && status.live) _set(status.copyWith(live: false));
  }

  Future<void> _listen(Completer<void> stop) async {
    var backoff = const Duration(seconds: 2);
    while (!stop.isCompleted && !_disposed) {
      try {
        await for (final event in client.events(cancel: stop.future)) {
          if (!status.live) _set(status.copyWith(live: true));
          backoff = const Duration(seconds: 2);
          switch (event.name) {
            case 'sync' when event.data['deviceId'] != deviceId:
              schedule(const Duration(milliseconds: 300));
            case 'models':
              onModelsChanged?.call();
            case 'account':
              onAccountChanged?.call();
          }
        }
      } on DenException catch (e) {
        if (e.status == 401) {
          onSignedOut?.call();
          return;
        }
      } on Object {
        // Offline or the server restarted; try again below.
      }
      if (stop.isCompleted || _disposed) break;
      if (status.live) _set(status.copyWith(live: false));
      // A timer rather than Future.delayed, so stopping cancels the wait.
      final waited = Completer<void>();
      final timer = Timer(backoff, waited.complete);
      await Future.any([waited.future, stop.future]);
      timer.cancel();
      backoff = Duration(seconds: min(backoff.inSeconds * 2, 60));
      // Changes made while disconnected arrive by pulling.
      if (!stop.isCompleted) schedule(Duration.zero);
    }
  }

  void dispose() {
    stopLive();
    _disposed = true;
    _scheduled?.cancel();
  }
}
