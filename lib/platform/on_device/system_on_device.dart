import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/on_device/on_device_capability.dart';
import '../../core/providers/images/generated_image.dart';
import '../../core/providers/providers.dart';
import '../../core/util/json.dart';
import 'system_model_mapping.dart';

/// Models that the system stores and runs: AICore on Android and Apple
/// Intelligence on iOS. Both native hosts speak the same channel protocol;
/// Tako's Dart agent loop executes approved tools.
abstract class SystemOnDevice extends UnavailableOnDevice {
  SystemOnDevice({
    required MethodChannel methods,
    required EventChannel events,
    required List<LocalModel> models,
  }) : _methods = methods,
       _events = events,
       _statuses = {
         for (final model in models)
           model.id: SystemModelStatus(
             SystemModelState.unavailable,
             model: model,
           ),
       };

  final MethodChannel _methods;
  final EventChannel _events;
  final Map<String, SystemModelStatus> _statuses;
  String? _loaded;
  String? _loading;
  int _nextRequest = 0;
  bool _disposed = false;

  /// The prefix of the service's error codes, such as `aicore`.
  String get service;

  /// Error codes after which the model has to be set up again.
  Set<String> get setupFailures;

  /// The model as the native host describes it.
  LocalModel describe(String id, Map<Object?, Object?> details);

  /// The prompt, tool and output fields of a request to [config]'s model.
  /// Throws a [ProviderError] for a request the model cannot take.
  Map<String, Object?> requestFields(
    ProviderConfig config,
    ChatRequest request,
  );

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  bool get isAvailable => _statuses.values.any(
    (status) => status.state != SystemModelState.unavailable,
  );
  @override
  SystemModelStatus get systemModelStatus => _statuses.values.first;
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
    if (id is! String || !_statuses.containsKey(id)) return;
    final state = switch (details['state']) {
      'ready' => SystemModelState.ready,
      'available' => SystemModelState.available,
      _ => SystemModelState.unavailable,
    };
    // A reason explains why a model is not ready, in the service's codes.
    _statuses[id] = SystemModelStatus(
      state,
      model: describe(id, details),
      error: state == SystemModelState.ready
          ? null
          : asString(details['reason']),
    );
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
    if (status == null) throw OnDeviceException('${service}_unavailable');
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
        throw PlatformException(code: '${service}_unavailable');
      }
      _update(details);
      _loaded = modelId;
    } on PlatformException catch (error) {
      _failed(modelId, error.code);
      throw OnDeviceException(error.code);
    } on MissingPluginException {
      _failed(modelId, '${service}_unavailable');
      throw OnDeviceException('${service}_unavailable');
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
    if (!_statuses.containsKey(config.model) || request.builtInWebSearch) {
      yield ProviderError(
        'Invalid system model or hosted search request',
        code: '${service}_unavailable',
      );
      return;
    }
    final Map<String, Object?> fields;
    try {
      fields = requestFields(config, request);
    } on ProviderError catch (error) {
      yield error;
      return;
    }
    final invalidTools = ProviderError(
      'Invalid system model tool reply',
      code: '${service}_invalid_tools',
    );
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
            ...fields,
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
            'Invalid system model event',
            code: 'invalid_stream',
          );
        }
        switch (value['type']) {
          case 'ready':
            if (value['modelId'] != config.model) {
              throw const ProviderError(
                'Invalid system model',
                code: 'invalid_stream',
              );
            }
            _update(value);
            _loaded = config.model;
            _loading = null;
            _changed();
          case 'text':
            if (request.tools.isNotEmpty || value['text'] is! String) {
              throw invalidTools;
            }
            yield TextDelta(value['text']! as String);
          case 'image':
            final data = value['data'];
            if (request.tools.isNotEmpty) throw invalidTools;
            if (data is! Uint8List) {
              throw const ProviderError(
                'Invalid generated image',
                code: 'invalid_image',
              );
            }
            yield generatedImageFromBytes(data);
          case 'agent':
            if (request.tools.isEmpty || pendingAgent != null) {
              throw invalidTools;
            }
            pendingAgent = systemModelAgentEvents(
              value,
              request.tools,
              invalidCode: '${service}_invalid_tools',
            );
          case 'usage':
            yield Usage(inputTokens: asInt(value['inputTokens']));
          case 'done':
            if (request.tools.isNotEmpty &&
                (pendingAgent == null || value['reason'] != 'stop')) {
              throw invalidTools;
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
              'Unknown system model event',
              code: 'invalid_stream',
            );
        }
      }
      if (!cancel.isCancelled) {
        yield const ProviderError(
          'System model stream ended before completion',
          code: 'incomplete_stream',
        );
      }
    } on ProviderError catch (error) {
      if (!cancel.isCancelled) yield error;
    } on PlatformException catch (error) {
      if (!cancel.isCancelled) {
        if (setupFailures.contains(error.code)) {
          _failed(config.model, error.code);
        }
        yield ProviderError(
          'The system model could not generate a reply',
          code: error.code,
        );
      }
    } catch (_) {
      if (!cancel.isCancelled) {
        _failed(config.model, '${service}_failed');
        yield ProviderError(
          'System model request failed',
          code: '${service}_failed',
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
