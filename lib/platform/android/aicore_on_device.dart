import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/on_device/on_device_capability.dart';
import '../../core/providers/providers.dart';
import '../../core/util/json.dart';
import 'aicore_mapping.dart';

export 'aicore_mapping.dart';

/// ML Kit Prompt API over Android AICore. Model files stay in the service.
class AicoreOnDevice extends UnavailableOnDevice {
  AicoreOnDevice({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('tw.avianjay.tako/aicore'),
      _events = events ?? const EventChannel('tw.avianjay.tako/aicore/events');

  final MethodChannel _methods;
  final EventChannel _events;
  final _statuses = <String, SystemModelStatus>{
    aicoreModel.id: const SystemModelStatus(SystemModelState.unavailable),
    aicorePreviewModel.id: const SystemModelStatus(
      SystemModelState.unavailable,
      model: aicorePreviewModel,
    ),
  };
  String? _loaded;
  String? _loading;
  int _nextRequest = 0;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  bool get isAvailable => _statuses.values.any(
    (status) => status.state != SystemModelState.unavailable,
  );
  @override
  SystemModelStatus get systemModelStatus => _statuses[aicoreModel.id]!;
  @override
  List<SystemModelStatus> get systemModelStatuses => _statuses.values.toList();
  @override
  List<LocalModel> get models => [
    for (final status in _statuses.values)
      if (status.state == SystemModelState.ready) status.model,
  ];
  @override
  String? get loadedModel => _loaded;
  @override
  String? get loadingModel => _loading;

  void _update(Map<Object?, Object?> details) {
    final id = details['modelId'];
    if (id is! String || !isAicoreModel(id)) return;
    final preview = id == aicorePreviewModel.id;
    final context = (asInt(details['contextWindow']) ?? 4096).clamp(1, 1 << 20);
    final baseName = asString(details['baseModelName']) ?? 'Gemini Nano';
    final model = LocalModel.system(
      id: id,
      name: '$baseName (AICore${preview ? ' Preview' : ''})',
      profile: ModelProfile(
        id: id,
        autoDetect: true,
        capabilities: ProviderCapabilities(
          tools: details['tools'] == true,
          contextWindow: context,
        ),
        maxOutputTokens: 1024,
      ),
    );
    final state = switch (details['state']) {
      'ready' => SystemModelState.ready,
      'available' => SystemModelState.available,
      _ => SystemModelState.unavailable,
    };
    _statuses[id] = SystemModelStatus(state, model: model);
    if (state == SystemModelState.unavailable && _loaded == id) _loaded = null;
  }

  @override
  Future<void> refresh() async {
    try {
      final statuses = await _methods.invokeListMethod<Object?>('status') ?? [];
      for (final value in statuses) {
        if (value is Map<Object?, Object?>) _update(value);
      }
    } on PlatformException {
      _unavailable();
    } on MissingPluginException {
      _unavailable();
    }
    _changed();
  }

  void _unavailable() {
    for (final entry in _statuses.entries.toList()) {
      _statuses[entry.key] = SystemModelStatus(
        SystemModelState.unavailable,
        model: entry.value.model,
      );
    }
    _loaded = null;
  }

  @override
  Future<void> prepareSystemModel({
    String modelId = 'aicore:gemini-nano',
  }) async {
    final status = _statuses[modelId];
    if (status == null) throw const OnDeviceException('aicore_unavailable');
    _loading = modelId;
    _loaded = null;
    _statuses[modelId] = SystemModelStatus(
      SystemModelState.preparing,
      model: status.model,
    );
    _changed();
    try {
      final details = await _methods.invokeMapMethod<Object?, Object?>(
        'prepare',
        {'modelId': modelId},
      );
      if (details == null ||
          details['modelId'] != modelId ||
          details['state'] != 'ready') {
        throw PlatformException(code: 'aicore_unavailable');
      }
      _update(details);
      _loaded = modelId;
    } on PlatformException catch (error) {
      _failed(modelId, error.code);
      throw OnDeviceException(error.code);
    } on MissingPluginException {
      _failed(modelId, 'aicore_unavailable');
      throw const OnDeviceException('aicore_unavailable');
    } finally {
      _loading = null;
      _changed();
    }
  }

  void _failed(String id, String code) {
    if (_loaded == id) _loaded = null;
    final old = _statuses[id];
    if (old != null) {
      _statuses[id] = SystemModelStatus(
        SystemModelState.failed,
        model: old.model,
        error: code,
      );
    }
  }

  @override
  Future<void> unload() async {
    await _methods.invokeMethod<void>('unload');
    _loaded = null;
    _changed();
  }

  @override
  Stream<ProviderEvent> generate(
    ProviderConfig config,
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    if (cancel.isCancelled) return;
    if (!isAicoreModel(config.model) || request.builtInWebSearch) {
      yield const ProviderError(
        'Invalid AICore model or hosted search request',
        code: 'aicore_unavailable',
      );
      return;
    }
    final id = ++_nextRequest;
    final incoming = StreamController<Object?>();
    StreamSubscription<Object?>? subscription;
    void stop() {
      unawaited(
        _methods
            .invokeMethod<void>('cancel', {'requestId': id})
            .catchError((_) {}),
      );
      unawaited(incoming.close());
    }

    _loading = config.model;
    _loaded = null;
    _changed();
    try {
      subscription = _events
          .receiveBroadcastStream({
            'requestId': id,
            'modelId': config.model,
            'prompt': aicorePrompt(request),
            'useTools': request.tools.isNotEmpty,
            'maxOutputTokens': request.maxTokens ?? config.maxOutputTokens,
          })
          .listen(
            (event) {
              if (!incoming.isClosed) incoming.add(event);
            },
            onError: (Object error, StackTrace stack) {
              if (!incoming.isClosed) incoming.addError(error, stack);
            },
            onDone: incoming.close,
          );
      cancel.addListener(stop);
      List<ProviderEvent>? pendingAgent;
      await for (final value in incoming.stream) {
        if (cancel.isCancelled) return;
        if (value is! Map<Object?, Object?>) {
          throw const ProviderError(
            'Invalid AICore event',
            code: 'invalid_stream',
          );
        }
        switch (value['type']) {
          case 'ready':
            if (value['modelId'] != config.model) {
              throw const ProviderError(
                'Invalid AICore model',
                code: 'invalid_stream',
              );
            }
            _update(value);
            _loaded = config.model;
            _loading = null;
            _changed();
          case 'text':
            if (request.tools.isNotEmpty || value['text'] is! String) {
              throw const ProviderError(
                'Invalid AICore tool stream',
                code: 'aicore_invalid_tools',
              );
            }
            yield TextDelta(value['text']! as String);
          case 'agent':
            if (request.tools.isEmpty || pendingAgent != null) {
              throw const ProviderError(
                'Unexpected AICore tool reply',
                code: 'aicore_invalid_tools',
              );
            }
            pendingAgent = aicoreAgentEvents(value, request.tools);
          case 'usage':
            yield Usage(inputTokens: asInt(value['inputTokens']));
          case 'done':
            if (request.tools.isNotEmpty &&
                (pendingAgent == null || value['reason'] != 'stop')) {
              throw const ProviderError(
                'Missing AICore tool reply',
                code: 'aicore_invalid_tools',
              );
            }
            for (final event in pendingAgent ?? const <ProviderEvent>[]) {
              if (cancel.isCancelled) return;
              yield event;
            }
            if (cancel.isCancelled) return;
            yield Done(
              pendingAgent?.any((event) => event is ToolCallStart) == true
                  ? 'tool_calls'
                  : asString(value['reason']),
            );
            return;
          default:
            throw const ProviderError(
              'Unknown AICore event',
              code: 'invalid_stream',
            );
        }
      }
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'AICore stream ended before completion',
          code: 'incomplete_stream',
        );
      }
    } on ProviderError catch (error) {
      if (!cancel.isCancelled) yield error;
    } on PlatformException catch (error) {
      if (!cancel.isCancelled) {
        if ({
          'aicore_unavailable',
          'aicore_update',
          'aicore_failed',
        }.contains(error.code)) {
          _failed(config.model, error.code);
        }
        yield ProviderError(
          'AICore could not generate a reply',
          code: error.code,
        );
      }
    } catch (_) {
      if (!cancel.isCancelled) {
        _failed(config.model, 'aicore_failed');
        yield const ProviderError(
          'AICore request failed',
          code: 'aicore_failed',
        );
      }
    } finally {
      cancel.removeListener(stop);
      await subscription?.cancel();
      unawaited(incoming.close());
      _loading = null;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
