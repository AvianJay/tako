import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/automation/automation.dart';
import '../core/automation/automation_management.dart';
import '../core/chat/agent_suspended.dart';
import '../core/chat/content_block.dart';
import '../core/chat/message.dart';
import '../core/permissions/permission_gate.dart';
import '../core/providers/cancel_token.dart';
import '../core/tools/tool.dart';
import '../core/tools/tool_executor.dart';
import '../core/util/json.dart';
import '../data/automation_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../platform/app_services.dart';
import 'app_controller.dart';
import 'automation_screen_status.dart';

class AutomationController extends ChangeNotifier
    implements AutomationManagement {
  AutomationController(this.app)
    : repository = AutomationRepository(app.database);
  final AppController app;
  final AutomationRepository repository;
  List<AutomationRule> rules = [];
  List<AutomationRun> runs = [];
  Map<String, Object?> platformStatus = {};
  String? pendingOpenRunId;
  bool _background = false, _disposed = false;
  Future<void>? _work;
  AppController? _executor;
  String? _activeRunId;
  String _pauseReason = 'paused';
  Timer? _poll;
  String? _syncedRules;
  final _watchedRuns = <String>{};
  PermissionRequest? get pendingApproval =>
      _executor?.permissionGate.pendingApproval;
  void decideApproval(PermissionChoice choice) =>
      _executor?.permissionGate.decide(choice);
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _showRun(AutomationRun run) {
    runs = [
      for (final previous in runs) previous.id == run.id ? run : previous,
    ];
    _emit();
  }

  Future<void> initialize({bool background = false}) async {
    _background = background;
    final capability = app.services.automation;
    if (!capability.isAvailable) return;
    capability.onStop = (reason) => pause(reason: reason);
    capability.onChanged = () {
      if (_disposed) {
        return;
      }
      unawaited(
        refresh().then((_) {
          if (runs.any((r) => r.id == _activeRunId && r.terminal)) {
            pause(reason: 'cancelled');
          }
          return drain();
        }),
      );
    };
    capability.onOpen = (id) {
      pendingOpenRunId = id;
      _emit();
    };
    await repository.recover();
    await refresh();
    await synchronize();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_disposed) unawaited(drain());
    });
    if (!background) unawaited(drain());
  }

  Future<void> refresh() async {
    rules = await repository.rules();
    runs = await repository.recentRuns();
    for (final id in _watchedRuns.toList()) {
      if (runs.any((r) => r.id == id)) continue;
      final run = await repository.run(id);
      if (run != null && _watchedRuns.contains(id)) runs.add(run);
    }
    if (app.services.automation.isAvailable) {
      platformStatus = await app.services.automation.status();
      if (platformStatus['openRun'] case final String id when id.isNotEmpty) {
        pendingOpenRunId = id;
      }
    }
    _emit();
  }

  Future<void> watchRun(String id) async {
    _watchedRuns.add(id);
    final run = await repository.run(id);
    if (run != null && _watchedRuns.contains(id)) {
      runs = [...runs.where((r) => r.id != id), run];
      _emit();
    }
  }

  void unwatchRun(String id) => _watchedRuns.remove(id);

  Future<void> clearHistory() async {
    final conversations = await repository.clearHistory(
      openConversationId: app.conversation?.id,
    );
    for (final id in conversations) {
      await app.deleteConversation(id, removeAttachments: true);
    }
    await app.services.automation.signalChanged();
    await refresh();
  }

  Future<void> synchronize() async {
    if (!app.services.automation.isAvailable) return;
    final rules = await repository.rules(), next = await repository.nextTimes();
    final fingerprint = jsonEncode([
      platformStatus['exact'],
      for (final rule in rules)
        {...rule.toJson(), 'nextAt': next[rule.id]?.millisecondsSinceEpoch},
    ]);
    if (_syncedRules != fingerprint) {
      await app.services.automation.syncRules(rules, next);
      _syncedRules = fingerprint;
    }
    await app.services.automation.wake(await repository.nextWake());
  }

  @override
  Future<List<AutomationRule>> listRules() => repository.rules();
  @override
  Future<AutomationRule?> getRule(String id) => repository.rule(id);
  @override
  Future<AutomationRule> saveRule(AutomationRule value) async {
    if (value.providerId.isEmpty || value.model.isEmpty) {
      final selected = app.selectedProvider;
      final provider = app.providers
          .where(
            (p) =>
                p.id ==
                (value.providerId.isEmpty ? selected?.id : value.providerId),
          )
          .firstOrNull;
      value = AutomationRule.fromJson({
        ...value.toJson(),
        'providerId': provider?.id ?? '',
        'model': value.model.isNotEmpty
            ? value.model
            : provider?.id == selected?.id
            ? selected?.model
            : provider?.model,
      });
    }
    value.validate();
    final previous = await repository.rule(value.id);
    if (value.enabled &&
        value.usesSchedule &&
        value.schedule.frequency == 'once' &&
        !value.schedule.at!.isAfter(DateTime.now()) &&
        (previous == null || !value.sameTiming(previous))) {
      throw const FormatException('Schedule must be in the future');
    }
    if (!app.services.automation.isAvailable ||
        value.trigger == AutomationTrigger.notification &&
            !app.services.automation.notificationTriggers ||
        value.trigger == AutomationTrigger.shortcut &&
            !app.services.automation.shortcutEntry ||
        value.schedule.exact && !app.services.automation.exactSchedules) {
      throw const FormatException('Unsupported trigger');
    }
    final provider = app.providers
        .where((p) => p.id == value.providerId)
        .firstOrNull;
    if (provider == null ||
        provider.forModel(value.model).capabilities.imagesOnly) {
      throw const FormatException('Text model required');
    }
    final saved = value.copyWith(
      revision: (previous?.revision ?? 0) + 1,
      conversationId: previous?.conversationId,
    );
    await repository.saveRule(saved);
    if (!saved.enabled) {
      for (final run in await repository.runs(ruleId: saved.id)) {
        if (run.status == AutomationStatus.cancelled) {
          await app.services.automation.clearNotification(run.id);
        }
      }
    }
    await synchronize();
    await app.services.automation.signalChanged();
    await refresh();
    return saved;
  }

  @override
  Future<void> deleteRule(String id) async {
    await repository.deleteRule(id);
    for (final run in await repository.runs(ruleId: id)) {
      if (run.status == AutomationStatus.cancelled) {
        await app.services.automation.clearNotification(run.id);
      }
    }
    await synchronize();
    await app.services.automation.signalChanged();
    await refresh();
  }

  @override
  Future<AutomationRun> runRule(String id) async {
    final rule = await repository.rule(id);
    if (rule == null || !rule.enabled) {
      throw const FormatException('Enabled rule required');
    }
    final run = await repository.enqueue(rule);
    await synchronize();
    await refresh();
    if (!_background) unawaited(drain());
    return run;
  }

  Future<void> cancel(String id) async {
    final run = await repository.run(id);
    if (run != null && !run.terminal) {
      await repository.saveRun(
        run.copyWith(status: AutomationStatus.cancelled),
      );
    }
    if (_activeRunId == id) {
      pause(reason: 'cancelled');
    }
    await app.services.automation.clearNotification(id);
    await app.services.automation.signalChanged();
    await refresh();
  }

  Future<void> resume(String id) async {
    await _work;
    final run = await repository.run(id);
    if (run == null || run.terminal) return;
    if (run.expired(DateTime.now())) {
      await repository.saveRun(
        run.copyWith(status: AutomationStatus.timedOut, reason: 'timeout'),
      );
      await app.services.automation.clearNotification(id);
      await refresh();
      return;
    }
    await _execute(run, foreground: true);
    await refresh();
    await synchronize();
  }

  void pause({String reason = 'paused'}) {
    _pauseReason = reason;
    _executor?.stop();
  }

  Future<void> pauseForChat() async {
    pause(reason: 'chat');
    await _work;
    final capability = app.services.automation;
    if (capability.isAvailable && await capability.acquire('chat')) {
      await capability.release('chat');
    }
  }

  Future<bool> acquireChat({CancelToken? cancel}) async {
    if (!app.services.automation.isAvailable) return true;
    final until = DateTime.now().add(const Duration(seconds: 30));
    do {
      cancel?.throwIfCancelled();
      if (await app.services.automation.acquire('chat')) {
        if (await repository.acquire('chat')) return true;
        await app.services.automation.release('chat');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    } while (DateTime.now().isBefore(until));
    return false;
  }

  Future<void> releaseChat() async {
    await repository.release('chat');
    if (app.services.automation.isAvailable) {
      await app.services.automation.release('chat');
    }
  }

  Future<void> drain() {
    if (_disposed || _work != null) return _work ?? Future.value();
    final work = _drain();
    _work = work;
    return work.whenComplete(() => _work = null);
  }

  Future<void> _drain() async {
    final capability = app.services.automation;
    if (!capability.isAvailable) return;
    try {
      await repository.recover();
      final input = await capability.inbox();
      platformStatus = await capability.status();
      if (platformStatus['openRun'] case final String id when id.isNotEmpty) {
        pendingOpenRunId = id;
      }
      await repository.ingest(
        input,
        allowExact:
            !capability.exactSchedules || platformStatus['exact'] == true,
      );
      await capability.acknowledge(
        input.map((e) => e['id']).whereType<String>().toList(),
      );
      final pending = await repository.runs(
        statuses: AutomationRepository.activeStatuses,
      );
      for (final run in pending) {
        if (run.status == AutomationStatus.waiting &&
            run.expired(DateTime.now())) {
          await repository.saveRun(
            run.copyWith(status: AutomationStatus.timedOut, reason: 'timeout'),
          );
          await capability.clearNotification(run.id);
        }
      }
      if (!app.busy && (_background || app.appInForeground)) {
        final due =
            pending
                .where(
                  (r) =>
                      r.status == AutomationStatus.queued &&
                      !r.dueAt.isAfter(DateTime.now()),
                )
                .toList()
              ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
        // Foreground work uses the UI permission sheet; background work pauses.
        if (due.isNotEmpty) {
          await _execute(
            due.first,
            foreground: !_background && app.appInForeground,
          );
        }
      }
      await refresh();
      await synchronize();
    } catch (_) {
      // Keep native events until a successful transaction acknowledges them.
      // Never surface provider data or secret-bearing native exceptions.
    }
  }

  Future<void> _execute(
    AutomationRun original, {
    required bool foreground,
  }) async {
    if (_executor != null) return;
    final capability = app.services.automation;
    final owner = 'automation:${original.id}';
    if (!await capability.acquire(owner)) return;
    if (!await repository.acquire(owner)) {
      await capability.release(owner);
      return;
    }
    var run = await repository.run(original.id) ?? original;
    if (run.terminal) {
      await repository.release(owner);
      await capability.release(owner);
      return;
    }
    final executor = app.forkForAutomation();
    final screenStatus = foreground
        ? null
        : AutomationScreenStatus(
            screen: app.services.screen,
            notifications: app.services.notifications,
            strings: lookupAppLocalizations(app.locale),
          );
    _executor = executor;
    _activeRunId = run.id;
    Future<bool> saveActive(AutomationRun value) =>
        app.database.transaction(() async {
          if ((await repository.run(value.id))?.terminal == true) {
            return false;
          }
          await repository.saveRun(value);
          return true;
        });
    _pauseReason = 'paused';
    executor.addListener(_emit);
    Timer? waitingTimer;
    PermissionRequest? lastRequest;
    void observeApproval() {
      final request = executor.permissionGate.pendingApproval;
      if (request == null) {
        if (lastRequest != null) {
          lastRequest = null;
          waitingTimer?.cancel();
          run = run.copyWith(
            status: AutomationStatus.running,
            clearWaiting: true,
          );
          _showRun(run);
        }
        return;
      }
      if (identical(request, lastRequest)) return;
      lastRequest = request;
      final started = run.waitingAt ?? DateTime.now();
      if (run.rule.waitTimeoutMinutes case final minutes?) {
        final remaining = started
            .add(Duration(minutes: minutes))
            .difference(DateTime.now());
        waitingTimer?.cancel();
        waitingTimer = Timer(
          remaining.isNegative ? Duration.zero : remaining,
          () => pause(reason: 'timeout'),
        );
      }
    }

    executor.addListener(observeApproval);
    final heartbeat = Timer.periodic(const Duration(seconds: 10), (_) async {
      final current = await repository.run(run.id);
      final interruption = await capability.interrupted(owner);
      if (current?.terminal == true || interruption != null) {
        pause(reason: interruption ?? 'cancelled');
        return;
      }
      if (executor.permissionGate.pendingApproval == null) {
        await repository.acquire(owner);
      }
    });
    final deadline = foreground
        ? null
        : Timer(const Duration(minutes: 8), () => pause(reason: 'system'));
    try {
      await executor.initialize(automationWorker: true);
      executor.permissionGate.pauseOnAsk = !foreground;
      executor.permissionGate.onSuspended = (p) => executor.agentSuspension = p;
      Future<void> ensureLease() async {
        if (await capability.interrupted(owner) case final reason?) {
          throw AgentSuspended(reason);
        }
        if (!await capability.acquire(owner)) {
          throw const AgentSuspended('chat');
        }
        if (!await repository.acquire(owner)) {
          await capability.release(owner);
          throw const AgentSuspended('chat');
        }
      }

      executor.permissionGate.onWaiting = (request) async {
        run = run.copyWith(
          status: AutomationStatus.waiting,
          waitingAt: run.waitingAt ?? DateTime.now(),
          pending: {
            ...run.pending,
            'tool': request.toolName,
            'arguments': request.arguments,
            'risk': request.risk.name,
            'details': request.details,
          },
        );
        if ((await repository.run(run.id))?.terminal == true) {
          throw const AgentSuspended('cancelled');
        }
        if (!await saveActive(run)) {
          throw const AgentSuspended('cancelled');
        }
        await repository.release(owner);
        await capability.release(owner);
        await refresh();
      };
      Future<void> checkpoint(
        ToolCallBlock call,
        ToolContext context,
        ToolExecution? execution,
      ) async {
        await app.database.transaction(() async {
          final current = await repository.run(run.id);
          if (execution == null && current?.terminal == true) {
            throw const AgentSuspended('cancelled');
          }
          final pending = {...run.pending};
          final active = {...?asMap(pending['inFlight'])};
          final key = '${context.messageId}:${call.id}';
          final receipts = [...?asList(pending['receipts'])];
          if (execution == null) {
            active[key] = {
              'messageId': context.messageId,
              'call': call.toJson(),
            };
          } else {
            active.remove(key);
            receipts.add({
              'messageId': context.messageId,
              'call': call.toJson(),
              'result': execution.result.toJson(),
            });
          }
          pending['inFlight'] = active;
          pending['receipts'] = receipts.length > 200
              ? receipts.sublist(receipts.length - 200)
              : receipts;
          run = run.copyWith(
            pending: pending,
            status: current?.terminal == true ? current!.status : run.status,
          );
          await repository.saveRun(run);
          _showRun(run);
        });
      }

      executor.onToolStarted = (call, context) async {
        await ensureLease();
        await screenStatus?.flush();
        await checkpoint(call, context, null);
      };
      executor.onToolFinished = checkpoint;
      executor.beforeAgentStep = () async {
        if ((await repository.run(run.id))?.terminal == true) {
          throw const AgentSuspended('cancelled');
        }
        if (await capability.interrupted(owner) case final reason?) {
          throw AgentSuspended(reason);
        }
        if (executor.agentSuspension case final pause?) throw pause;
        await ensureLease();
      };
      run = run.copyWith(status: AutomationStatus.running, clearWaiting: true);
      if (!await saveActive(run)) {
        return;
      }
      await refresh();
      final answer = await executor.runAutomation(
        run,
        onConversation: (id) async {
          run = run.copyWith(conversationId: id);
          if (!await saveActive(run)) {
            throw const AgentSuspended('cancelled');
          }
          _showRun(run);
          if (run.rule.continueConversation) {
            final current = await repository.rule(run.rule.id);
            if (current != null) {
              await app.database.customStatement(
                'UPDATE automation_rules SET data=? WHERE id=?',
                [current.copyWith(conversationId: id).encode(), current.id],
              );
            }
          }
        },
      );
      if (executor.agentSuspension case final pause?) throw pause;
      if (executor.wasAutomationStopped) throw AgentSuspended(_pauseReason);
      await executor.beforeAgentStep?.call();
      if (answer == null || answer.status != MessageStatus.done) {
        final reason = answer?.error ?? executor.errorCode ?? 'emptyResponse';
        if ({'aicoreBackground', 'appleBackground'}.contains(reason)) {
          throw const AgentSuspended('foreground');
        }
        run = run.copyWith(status: AutomationStatus.failed, reason: reason);
      } else {
        final silent = isSilentAutomationResult(answer.text);
        final result = answer.text.trim();
        final hasArtifact = answer.content.any(
          (b) => b is ImageBlock || b is FileBlock,
        );
        run = run.copyWith(
          status: silent ? AutomationStatus.silent : AutomationStatus.completed,
          result: result,
          pending: const {},
        );
        if (!await saveActive(run)) {
          return;
        }
        if (!silent && (result.isNotEmpty || hasArtifact)) {
          await capability.notify(
            run.id,
            run.rule.name,
            result.isEmpty
                ? lookupAppLocalizations(app.locale).automationCompleted
                : result,
          );
        }
      }
      if ((await repository.run(run.id))?.status !=
          AutomationStatus.cancelled) {
        await saveActive(run);
      }
    } on AgentSuspended catch (pause) {
      final current = await repository.run(run.id);
      if (current?.terminal != true) {
        final retry = {'chat', 'system'}.contains(pause.reason);
        run = run.copyWith(
          status: pause.reason == 'timeout'
              ? AutomationStatus.timedOut
              : retry
              ? AutomationStatus.queued
              : AutomationStatus.waiting,
          reason: pause.reason,
          waitingAt: retry ? null : run.waitingAt ?? DateTime.now(),
          clearWaiting: retry,
          pending: {...run.pending, ...pause.pending},
        );
        if (!await saveActive(run)) {
          return;
        }
        if (!retry &&
            pause.reason != 'cancelled' &&
            pause.reason != 'timeout') {
          await capability.notify(
            run.id,
            run.rule.name,
            lookupAppLocalizations(app.locale).automationReasonForeground,
            waiting: true,
          );
        }
      }
    } on FormatException {
      if ((await repository.run(run.id))?.terminal != true) {
        await saveActive(
          run.copyWith(
            status: AutomationStatus.failed,
            reason: 'configuration',
          ),
        );
      }
    } catch (_) {
      if ((await repository.run(run.id))?.terminal != true) {
        final saved = await saveActive(
          run.copyWith(
            status: AutomationStatus.waiting,
            reason: 'foreground',
            waitingAt: run.waitingAt ?? DateTime.now(),
          ),
        );
        if (saved) {
          await capability.notify(
            run.id,
            run.rule.name,
            lookupAppLocalizations(app.locale).automationReasonForeground,
            waiting: true,
          );
        }
      }
    } finally {
      heartbeat.cancel();
      deadline?.cancel();
      waitingTimer?.cancel();
      executor.removeListener(_emit);
      executor.removeListener(observeApproval);
      executor.dispose();
      _executor = null;
      _activeRunId = null;
      await screenStatus?.dispose();
      await repository.release(owner);
      await capability.release(owner);
      final saved = await repository.run(run.id);
      if (saved?.terminal == true &&
          saved!.status != AutomationStatus.completed) {
        await capability.clearNotification(run.id);
      }
      await capability.signalChanged();
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _executor?.stop();
    super.dispose();
  }
}
