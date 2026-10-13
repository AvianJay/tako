import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/browser/browser_settings.dart';
import '../core/chat/content_block.dart';
import '../core/chat/conversation.dart';
import '../core/chat/conversation_tree.dart';
import '../core/chat/generated_image_store.dart';
import '../core/chat/message.dart';
import '../core/chat/response_accumulator.dart';
import '../core/chat/title_generator.dart';
import '../core/memory/memory.dart';
import '../core/memory/settings.dart';
import '../core/on_device/on_device_capability.dart';
import '../core/permissions/permission_gate.dart';
import '../core/prompt/context_budget.dart';
import '../core/prompt/context_envelope.dart';
import '../core/prompt/prompt_builder.dart';
import '../core/providers/hosted_search_probe.dart';
import '../core/providers/providers.dart';
import '../core/screen/device_control_settings.dart';
import '../core/screen/remote_control_agent.dart';
import '../core/screen/screen_capability.dart';
import '../core/screen/screen_history.dart';
import '../core/search/search_service.dart';
import '../core/tools/browser_tools.dart';
import '../core/tools/device_tools.dart';
import '../core/tools/file_tools.dart';
import '../core/tools/image_generation_tool.dart';
import '../core/tools/memory_tools.dart';
import '../core/tools/notification_tools.dart';
import '../core/tools/screen_tools.dart';
import '../core/tools/search_tools.dart';
import '../core/tools/shell_tools.dart';
import '../core/tools/shortcut_tools.dart';
import '../core/tools/tool.dart';
import '../core/tools/tool_executor.dart';
import '../core/tools/tool_loop_detector.dart';
import '../core/tools/tool_registry.dart';
import '../core/tools/tool_settings.dart';
import '../core/util/ids.dart';
import '../core/util/json.dart';
import '../data/audit_repository.dart';
import '../data/chat_repository.dart';
import '../data/database.dart';
import '../data/memory_repository.dart';
import '../data/provider_repository.dart';
import '../data/settings_repository.dart';
import '../platform/app_services.dart';
import '../platform/capabilities.dart';
import 'app_info.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw StateError('App not initialized'),
);
typedef AdapterFactory =
    ProviderAdapter Function(
      ProviderConfig config,
      String? key,
      Map<String, String> headers,
    );

class AppController extends ChangeNotifier {
  AppController({
    required this.database,
    required this.services,
    required this.promptTemplate,
    AdapterFactory? adapterFactory,
    TitleGenerator? titleGenerator,
    List<Tool>? extraTools,
  }) : _adapterFactory =
           adapterFactory ??
           ((config, key, headers) => ProviderAdapter.create(
             config,
             apiKey: key,
             secretHeaders: headers,
             onDevice: services.onDevice,
           )),
       _titleGenerator = titleGenerator ?? generateChatTitle,
       _extraTools = extraTools ?? const [],
       chats = ChatRepository(database),
       providerRepository = ProviderRepository(database),
       settings = SettingsRepository(database) {
    // Taking over the shared browser stops the response that is using it.
    services.browser.onTakeOver = stop;
    // So does Stop in the "controlling the screen" notification.
    services.screen.onTakeOver = stop;
    for (final control in _controls) {
      control.addListener(_emit);
    }
  }

  /// Availability changes when the user grants access in system settings.
  late final List<ChangeNotifier> _controls = [
    services.screen,
    services.shell,
    services.notifications,
  ];

  final AppDatabase database;
  final AppServices services;
  final String promptTemplate;
  final AdapterFactory _adapterFactory;
  final TitleGenerator _titleGenerator;
  final _titleJobs = <String, CancelToken>{};
  bool get isGeneratingTitle => _titleJobs.containsKey(conversation?.id);
  final List<Tool> _extraTools;
  late final AuditRepository audit = AuditRepository(database);
  late final MemoryRepository memory = MemoryRepository(database);
  MemorySettings memorySettings = const MemorySettings();
  PersonalizationSettings personalization = const PersonalizationSettings();
  BrowserSettings browserSettings = const BrowserSettings();
  DeviceControlSettings controlSettings = const DeviceControlSettings();

  /// Whether the app is in front, reported by the UI's lifecycle observer.
  /// Approvals needed while it is hidden are shown over other apps.
  bool appInForeground = true;
  final _screenReadings = ScreenReadings();

  /// The next new chat is incognito. An open chat carries its own flag.
  bool incognitoDraft = false;
  bool get incognito => conversation?.incognito ?? incognitoDraft;
  bool get opensLinksInApp =>
      browserSettings.openLinksInApp && services.browser.isAvailable;
  late final PermissionGate permissionGate = PermissionGate(
    onPolicyChanged: (policy) async {
      await settings.setString(PermissionPolicy.settingsKey, policy.encode());
      _emit();
    },
    onPendingChanged: (_) => _emit(),
  );
  PermissionRequest? get pendingApproval => permissionGate.pendingApproval;
  ToolSettings toolSettings = const ToolSettings();
  SearchConfig searchConfig = const SearchConfig();
  late ToolRegistry toolRegistry = _makeRegistry();
  String? activeToolCallId;
  String? _lastStopReason;
  List<ContentBlock> draftAttachments = [];
  CancelToken? _attachmentCancel;
  static const maxAttachments = 8;
  bool get canAttachPhotos => services.mediaAttachments.isAvailable;
  bool get canCapturePhoto => services.mediaAttachments.isAvailable;
  bool get canInsertKeyboardImage => services.workspace.isAvailable;

  Future<void> _importAttachments(
    Future<List<ContentBlock>> Function(CancelToken token, int remaining) pick,
  ) => _mutate(() async {
    final remaining = maxAttachments - draftAttachments.length;
    if (remaining <= 0) {
      errorCode = 'attachmentLimit';
      return;
    }
    errorCode = null;
    final token = _attachmentCancel = CancelToken();
    try {
      final imported = await pick(token, remaining);
      token.throwIfCancelled();
      draftAttachments = [...draftAttachments, ...imported.take(remaining)];
      if (imported.length > remaining) errorCode = 'attachmentLimit';
    } on RequestCancelled {
      /* Picker dismissed or Stop pressed. */
    } finally {
      _attachmentCancel = null;
    }
  });
  Future<void> importAttachments() => _importAttachments(
    (token, _) => services.workspace.importFiles(cancel: token),
  );
  Future<void> importPhotos() => _importAttachments(
    (token, remaining) =>
        services.mediaAttachments.pickPhotos(limit: remaining, cancel: token),
  );
  Future<void> capturePhoto() => _importAttachments(
    (token, _) => services.mediaAttachments.capturePhoto(cancel: token),
  );
  Future<void> attachWorkspaceImage(String path) => _importAttachments((
    token,
    _,
  ) async {
    final image = (await services.workspace.read(path, cancel: token)).image;
    if (image == null) throw const FormatException('Not an image');
    return [
      ImageBlock(path: image.path, mimeType: image.mimeType, alt: image.alt),
    ];
  });
  Future<void> recoverLostAttachments() async {
    if (!services.mediaAttachments.isAvailable) return;
    try {
      await _importAttachments(
        (token, remaining) => services.mediaAttachments.recoverLostPhotos(
          limit: remaining,
          cancel: token,
        ),
      );
    } catch (_) {
      // A stale picker result must never prevent the application from starting.
      errorCode = 'imageUnavailable';
      _emit();
    }
  }

  Future<void> insertKeyboardImage({
    required String mimeType,
    required String uri,
    Uint8List? bytes,
  }) => _importAttachments((token, _) async {
    final extension = switch (mimeType.toLowerCase()) {
      'image/png' => 'png',
      'image/jpeg' => 'jpg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => null,
    };
    if (extension == null) {
      errorCode = 'unsupportedImage';
      return [];
    }
    // Flutter obtains bytes using the IME's temporary content grant. Never
    // fetch an arbitrary keyboard URI, or retain that URI in the conversation.
    if (bytes == null || bytes.isEmpty) {
      errorCode = 'imageUnavailable';
      return [];
    }
    return [
      await services.workspace.importImageBytes(
        'keyboard-image.$extension',
        bytes,
        cancel: token,
      ),
    ];
  });
  void removeAttachment(ContentBlock block) {
    if (!busy) {
      draftAttachments = draftAttachments.where((b) => b != block).toList();
      _emit();
    }
  }

  Future<void> saveToolSettings(ToolSettings value) => _mutate(() async {
    await settings.setString('tools.settings', jsonEncode(value.toJson()));
    toolSettings = value;
    toolRegistry = _makeRegistry();
  });
  Future<void> savePermissionPolicy(PermissionPolicy value) =>
      _mutate(() async {
        await settings.setString(PermissionPolicy.settingsKey, value.encode());
        permissionGate.policy = value;
      });
  String _searchKeyReference(SearchKind kind) =>
      kind == searchConfig.kind && searchConfig.apiKeyRef != null
      ? searchConfig.apiKeyRef!
      : 'search.${kind.name}.key';

  Future<bool> hasSearchKey(SearchKind kind) async =>
      kind.supportsApiKey &&
      (await services.readSecret(_searchKeyReference(kind)))?.isNotEmpty ==
          true;

  Future<void> saveSearchConfig(
    SearchConfig config, {
    String? key,
    bool removeKey = false,
  }) => _mutate(() async {
    final baseUrl = config.baseUrl.trim();
    if (config.resultCount < 1 ||
        config.resultCount > 10 ||
        config.kind.requiresBaseUrl && baseUrl.isEmpty) {
      throw const SearchFailure('search_not_configured');
    }
    if (baseUrl.isNotEmpty) webUri(baseUrl);
    // Keep keys scoped to their provider. Never reuse a reference supplied by
    // the previously selected provider when switching search services.
    final reference = _searchKeyReference(config.kind);
    final newKey = key?.trim();
    String? storedKey;
    if (config.kind.supportsApiKey) {
      if (removeKey || newKey?.isNotEmpty == true) {
        await services.writeSecret(reference, removeKey ? null : newKey);
      }
      storedKey = await services.readSecret(reference);
    }
    final saved = SearchConfig(
      kind: config.kind,
      baseUrl: baseUrl,
      resultCount: config.resultCount,
      apiKeyRef: storedKey?.isNotEmpty == true ? reference : null,
    );
    await settings.setString('search.config', jsonEncode(saved.toJson()));
    searchConfig = saved;
    toolRegistry = _makeRegistry();
  });
  List<SideEffect> sideEffectsAfter(ChatMessage message) =>
      tree.sideEffectsAfter(conversation?.activeLeafId, message.id);

  /// Restores workspace backups and removes memories saved after the rewind
  /// point. Memory removal is revision-checked: later edits are kept.
  Future<void> restoreSideEffects(List<SideEffect> effects) =>
      _mutate(() async {
        for (final effect in effects.reversed) {
          if (effect.backupPath case final backup?) {
            await services.workspace.restoreBackup(backup);
          }
          if (MemoryUndo.fromJson(effect.memoryUndo) case final undo?) {
            await memory.undoSaved(undo);
          }
        }
      });

  /// The chat chip's Undo. Not tied to [busy]: it is revision-checked.
  Future<bool> undoMemorySave(MemoryUndo undo) async {
    final removed = await memory.undoSaved(undo);
    _emit();
    return removed;
  }

  Future<void> saveMemorySettings(MemorySettings value) => _mutate(() async {
    await settings.setString(
      MemorySettings.settingsKey,
      jsonEncode(value.toJson()),
    );
    memorySettings = value;
  });

  Future<void> savePersonalization(PersonalizationSettings value) =>
      _mutate(() async {
        await settings.setString(
          PersonalizationSettings.settingsKey,
          jsonEncode(value.toJson()),
        );
        personalization = value;
      });

  Future<void> saveBrowserSettings(BrowserSettings value) => _mutate(() async {
    await settings.setString(
      BrowserSettings.settingsKey,
      jsonEncode(value.toJson()),
    );
    browserSettings = value;
  });

  Future<void> saveControlSettings(DeviceControlSettings value) =>
      _mutate(() async {
        await settings.setString(
          DeviceControlSettings.settingsKey,
          jsonEncode(value.toJson()),
        );
        controlSettings = value;
        toolRegistry = _makeRegistry();
      });

  /// Re-reads device-control availability, e.g. after the user returns from
  /// system settings. Bounded, so a stuck platform call never blocks a reply.
  Future<void> refreshDeviceControl() async {
    try {
      await services.refreshDeviceControl().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Keep the last known availability.
    }
  }

  void setAppForeground(bool value) {
    if (appInForeground == value) return;
    appInForeground = value;
    _emit();
    if (value) {
      unawaited(refreshDeviceControl());
      unawaited(refreshProviderModels());
    }
  }

  /// Removes the screenshots that only [deleted] messages used, when the
  /// setting asks for it or the chat was incognito. Best effort: a failure
  /// here never blocks deleting the chat itself.
  Future<void> _discardScreenshots(
    List<ChatMessage> deleted, {
    bool always = false,
  }) async {
    if (!always && !controlSettings.deleteScreenshotsWithChat) return;
    final paths = <String>{};
    for (final message in deleted) {
      for (final block in message.content) {
        if (always && block is ImageBlock) paths.add(block.path);
        if (always && block is FileBlock) paths.add(block.path);
        if (block is ToolResultBlock &&
            (always || block.toolName == 'read_screen')) {
          for (final attachment in block.attachments) {
            if (attachment is ImageBlock) paths.add(attachment.path);
            if (always && attachment is FileBlock) paths.add(attachment.path);
          }
        }
      }
    }
    if (paths.isEmpty) return;
    try {
      final unused = [
        for (final path in paths)
          if (!await chats.mentions(path)) path,
      ];
      if (unused.isNotEmpty) await services.workspace.removeAttachments(unused);
    } catch (_) {
      // The files stay in Files, where the user can delete them.
    }
  }

  /// read_screen attaches screenshots only for vision models, when enabled.
  bool _screenVision(ProviderConfig provider) =>
      controlSettings.screenshots &&
      provider.capabilities.vision &&
      services.screen.screenshotsSupported;

  bool _sendsScreenshots() {
    final provider = selectedProvider;
    return provider != null && _screenVision(provider);
  }

  late final _memoryGate = _Gate(() => memorySettings.enabled);

  /// Actions return the screen after them when reading the screen would run
  /// now without asking; otherwise the model calls read_screen and is asked.
  late final _screenObserver = ScreenObserver(
    screen: services.screen,
    workspace: services.workspace,
    readings: _screenReadings,
    screenshots: _sendsScreenshots,
    allowed: (conversationId) =>
        toolSettings.enabled &&
        !toolSettings.disabled.contains('read_screen') &&
        permissionGate.allowsWithoutAsking(
          toolName: 'read_screen',
          risk: RiskLevel.sensitive,
          conversationId: conversationId,
        ),
  );

  /// A separate saved connection/model; the main chat retains its own model.
  ProviderConfig? get remoteAgentProvider {
    if (!controlSettings.remoteAgent) return null;
    final configured = controlSettings.remoteAgentProviderId;
    final connection = configured?.isNotEmpty == true
        ? providers.where((p) => p.id == configured).firstOrNull
        : providers
              .where(
                (p) =>
                    p.models.any((m) => m.id == 'claude-haiku-5-5') &&
                    p.forModel('claude-haiku-5-5').apiType == ApiType.messages,
              )
              .firstOrNull;
    if (connection == null) return null;
    final requested = controlSettings.remoteAgentModelId;
    if (requested?.isNotEmpty == true &&
        !connection.models.any((m) => m.id == requested)) {
      return null;
    }
    var worker = connection.forModel(
      requested?.isNotEmpty == true
          ? requested
          : configured?.isNotEmpty == true
          ? connection.model
          : 'claude-haiku-5-5',
    );
    if (!worker.capabilities.tools) return null;
    // Keep the requested Haiku Extra default; other models retain their saved
    // capabilities, API, reasoning and limits instead of inheriting Haiku's.
    if (worker.model == 'claude-haiku-5-5' &&
        worker.apiType == ApiType.messages) {
      worker = worker.copyWith(
        reasoningMode: ReasoningMode.adaptive,
        reasoningEffort: 'xhigh',
        maxOutputTokens: max(8192, worker.maxOutputTokens),
      );
    }
    return withWorkerReasoning(worker, controlSettings.remoteAgentEffort);
  }

  late final _remoteAgent = RemoteControlAgent(
    screen: services.screen,
    workspace: services.workspace,
    deviceTools: (observer) =>
        createDeviceTools(services.deviceTools, observer: observer),
    permissions: permissionGate,
    audit: audit,
    available: () => toolSettings.enabled && remoteAgentProvider != null,
    backend: () async {
      final provider = remoteAgentProvider;
      if (provider == null) throw StateError('Remote worker is not configured');
      return (config: provider, adapter: await adapterFor(provider));
    },
    screenshots: () =>
        controlSettings.screenshots && services.screen.screenshotsSupported,
    disabledTools: () => toolSettings.disabled,
    stepLimit: () => toolSettings.maxScreenSteps,
  );
  bool get delegatesScreen =>
      remoteAgentProvider != null &&
      services.screen.isAvailable &&
      !toolSettings.disabled.contains('remote_control');
  Set<String> get _mainScreenToolsHidden =>
      delegatesScreen ? {...screenToolNames, 'open_app', 'open_url'} : const {};

  ToolRegistry _makeRegistry() => ToolRegistry([
    ...createDeviceTools(
      services.deviceTools,
      observer: _screenObserver,
      maxChars: toolSettings.maxOutputChars,
    ),
    ...createFileTools(services.workspace),
    ImageGenerationTool(
      workspace: services.workspace,
      models: () => imageModels,
      adapterFor: adapterFor,
      attachedImages: (context) =>
          ConversationTree(messages)
              .pathTo(context.messageId)
              .reversed
              .where((message) => message.role == MessageRole.user)
              .firstOrNull
              ?.content
              .whereType<ImageBlock>()
              .toList() ??
          const [],
    ),
    ...createSearchTools(
      SearchService(searchConfig, readSecret: services.readSecret),
      PageFetcher(),
    ),
    ...createMemoryTools(memory, gate: _memoryGate),
    ...createBrowserTools(
      services.browser,
      maxChars: toolSettings.maxOutputChars,
    ),
    NotificationsTool(services.notifications),
    ...createScreenTools(
      services.screen,
      workspace: services.workspace,
      maxChars: toolSettings.maxOutputChars,
      screenshots: _sendsScreenshots,
      observer: _screenObserver,
    ),
    ShellTool(
      services.shell,
      maxChars: toolSettings.maxOutputChars,
      timeoutSeconds: () => controlSettings.shellTimeoutSeconds,
    ),
    ...createShortcutTools(services.shortcuts),
    ..._remoteAgent.tools,
    ..._extraTools,
  ], disabledTools: toolSettings.disabled);

  /// Incognito chats never see memory tools, whatever the settings say.
  Set<String> _disabledTools({required bool incognito}) => {
    ...toolSettings.disabled,
    ..._mainScreenToolsHidden,
    if (incognito) ...memoryToolNames,
  };

  List<ProviderConfig> get imageModels => [
    for (final provider in providers)
      for (final model in provider.models)
        if (provider.forModel(model.id).generatesImages)
          provider.forModel(model.id),
  ];

  bool _canRouteReferenceImages(ProviderConfig provider) =>
      toolSettings.enabled &&
      provider.capabilities.tools &&
      provider.capabilities.imageGeneration != ImageGenerationMode.imagesApi &&
      !toolSettings.disabled.contains('generate_image') &&
      services.workspace.isAvailable &&
      imageModels.any((model) => model.capabilities.imageReferenceInput);

  /// Tool names a conversation offers to this provider.
  Set<String> _conversationTools(
    ProviderConfig provider, {
    required bool incognito,
  }) {
    if (!toolSettings.enabled ||
        !provider.capabilities.tools ||
        provider.capabilities.imageGeneration ==
            ImageGenerationMode.imagesApi) {
      return const {};
    }
    final disabled = _disabledTools(incognito: incognito);
    return {
      for (final tool in toolRegistry.availableTools)
        if (!disabled.contains(tool.name)) tool.name,
    };
  }

  final ChatRepository chats;
  final ProviderRepository providerRepository;
  final SettingsRepository settings;
  List<ProviderConfig> providers = [];
  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  Conversation? conversation;
  String? selectedProviderId;
  String? selectedModelId;
  bool _generating = false;
  bool _mutating = false;
  bool _probingHostedSearch = false;
  bool get busy => _generating || _mutating || _probingHostedSearch;
  bool contextTrimmed = false;
  String? errorCode;
  String? providerError;

  /// The last message of a response stopped for a repeated tool loop.
  String? _limitedAt;
  ThemeMode themeMode = ThemeMode.system;
  Locale locale = const Locale('zh', 'TW');
  double textScale = 1;
  CancelToken? _cancel;
  bool _disposed = false;
  bool initialized = false;
  ConversationTree? _tree;
  List<ChatMessage>? _treeMessages;
  int revision = 0;
  bool get isGenerating => _generating;

  ProviderConfig? get selectedProvider {
    final id = conversation?.providerId ?? selectedProviderId;
    for (final provider in providers) {
      if (provider.id == id) {
        return provider.forModel(
          conversation?.model ?? selectedModelId ?? provider.model,
        );
      }
    }
    return conversation == null && providers.isNotEmpty
        ? providers.first.forModel(selectedModelId ?? providers.first.model)
        : null;
  }

  ConversationTree get tree {
    if (!identical(_treeMessages, messages)) {
      _treeMessages = messages;
      _tree = ConversationTree(messages);
    }
    return _tree!;
  }

  List<ChatMessage> get visibleMessages =>
      tree.pathTo(conversation?.activeLeafId);

  void _emit() {
    if (!_disposed) {
      revision++;
      notifyListeners();
    }
  }

  /// Acquire before the first await. Navigation/configuration share this guard
  /// with generation, so they cannot replace a tree while its stream is saving.
  Future<void> _mutate(Future<void> Function() action) async {
    if (busy || _disposed) return;
    _mutating = true;
    _emit();
    try {
      await action();
    } finally {
      _mutating = false;
      _emit();
      if (_pendingModelLists.isNotEmpty && !_disposed) {
        unawaited(_applyModelLists());
      }
    }
  }

  Future<void> initialize() async {
    await _mutate(() async {
      try {
        await chats.recoverInterruptedMessages();
        await _discardScreenshots(
          await chats.deleteIncognitoConversations(),
          always: true,
        );
        await audit.recoverInterrupted();
        final loaded = await (
          providerRepository.list(),
          chats.listConversations(),
          settings.readAll(),
        ).wait;
        providers = loaded.$1;
        conversations = loaded.$2;
        final preferences = loaded.$3;
        permissionGate.policy = PermissionPolicy.decode(
          preferences[PermissionPolicy.settingsKey],
        );
        toolSettings = ToolSettings.fromJson(
          tryDecodeObject(preferences['tools.settings'] ?? '') ?? {},
        );
        searchConfig = SearchConfig.fromJson(
          tryDecodeObject(preferences['search.config'] ?? '') ?? {},
        );
        JsonMap stored(String key) =>
            tryDecodeObject(preferences[key] ?? '') ?? {};
        memorySettings = MemorySettings.fromJson(
          stored(MemorySettings.settingsKey),
        );
        personalization = PersonalizationSettings.fromJson(
          stored(PersonalizationSettings.settingsKey),
        );
        browserSettings = BrowserSettings.fromJson(
          stored(BrowserSettings.settingsKey),
        );
        controlSettings = DeviceControlSettings.fromJson(
          stored(DeviceControlSettings.settingsKey),
        );
        services.onDevice.preferSpeed =
            asBool(stored(_onDeviceKey)['preferSpeed']) ?? false;
        services.shortcuts.names = [
          for (final name in asList(stored(_shortcutsKey)['names']) ?? const [])
            if (name is String) name,
        ];
        // Before the current chat's prompt is checked against available tools.
        await refreshDeviceControl();
        // Model files and interrupted downloads, for settings and the picker.
        unawaited(services.onDevice.refresh().catchError((_) {}));
        toolRegistry = _makeRegistry();
        selectedProviderId = preferences['provider'];
        selectedModelId = preferences['model'];
        final theme = preferences['theme'];
        themeMode = ThemeMode.values.firstWhere(
          (v) => v.name == theme,
          orElse: () => ThemeMode.system,
        );
        locale = preferences['language'] == 'en'
            ? const Locale('en')
            : const Locale('zh', 'TW');
        textScale = (double.tryParse(preferences['textScale'] ?? '') ?? 1)
            .clamp(.85, 1.4);
        final current = preferences['conversation'];
        if (current != null) await _openConversation(current);
      } catch (_) {
        errorCode = 'operationFailed';
      } finally {
        initialized = true;
      }
    });
    if (!_disposed) unawaited(refreshProviderModels());
  }

  static const _modelListLifetime = Duration(minutes: 15);
  final _modelFetches = <String, Future<void>>{};
  final _modelFetchTokens = <String, CancelToken>{};
  final _modelFetchedAt = <String, DateTime>{};
  final _pendingModelLists = <String, (ProviderConfig, List<ModelInfo>)>{};
  final modelFetchErrors = <String, String>{};
  Future<void>? _modelApply;
  bool get fetchingModels => _modelFetches.isNotEmpty;

  /// Coalesced discovery runs independently of chat generation. A late reply
  /// is applied only when idle and when its connection settings still match.
  Future<void> refreshProviderModels({
    String? providerId,
    bool force = false,
  }) async {
    if (_disposed) return;
    final connections = List<ProviderConfig>.of(providers);
    await Future.wait([
      for (final provider in connections)
        if (provider.apiType != ApiType.onDevice &&
            (providerId == null
                ? provider.autoFetchModels
                : provider.id == providerId))
          _fetchModelList(provider, force: force),
    ]);
    await _applyModelLists();
  }

  Future<void> _fetchModelList(ProviderConfig provider, {required bool force}) {
    if (_modelFetches[provider.id] case final inFlight?) return inFlight;
    final previous = _modelFetchedAt[provider.id];
    if (!force &&
        previous != null &&
        DateTime.now().difference(previous) < _modelListLifetime) {
      return Future.value();
    }
    final token = _modelFetchTokens[provider.id] = CancelToken();
    final fetching = Future<void>.microtask(() async {
      try {
        token.throwIfCancelled();
        final adapter = await adapterFor(provider);
        token.throwIfCancelled();
        final found = await token
            .bind(adapter.listModels(cancel: token))
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                token.cancel();
                throw TimeoutException('Model discovery timed out');
              },
            );
        if (_disposed) return;
        if (found.isEmpty) {
          modelFetchErrors[provider.id] = 'no_models';
          return;
        }
        modelFetchErrors.remove(provider.id);
        _modelFetchedAt[provider.id] = DateTime.now();
        _pendingModelLists[provider.id] = (provider, found);
      } catch (_) {
        if (!_disposed) modelFetchErrors[provider.id] = 'connection_failed';
      } finally {
        unawaited(_modelFetches.remove(provider.id));
        _modelFetchTokens.remove(provider.id);
        _emit();
      }
    });
    _modelFetches[provider.id] = fetching;
    _emit();
    return fetching;
  }

  Future<void> _applyModelLists() {
    if (_modelApply case final applying?) return applying;
    if (_disposed || busy || _pendingModelLists.isEmpty) return Future.value();
    final applying = _mutate(() async {
      final pending = Map.of(_pendingModelLists);
      _pendingModelLists.clear();
      for (final entry in pending.entries) {
        final current = providers.where((p) => p.id == entry.key).firstOrNull;
        if (current == null ||
            jsonEncode(current.toJson()) !=
                jsonEncode(entry.value.$1.toJson())) {
          _modelFetchedAt.remove(entry.key);
          continue;
        }
        final merged = mergeDiscoveredModels(current, entry.value.$2);
        if (jsonEncode(current.toJson()) == jsonEncode(merged.toJson())) {
          continue;
        }
        try {
          await providerRepository.save(merged);
          providers = [
            for (final p in providers) p.id == merged.id ? merged : p,
          ];
        } catch (_) {
          modelFetchErrors[entry.key] = 'save_failed';
        }
      }
    });
    _modelApply = applying.whenComplete(() {
      _modelApply = null;
      if (!_disposed && !busy && _pendingModelLists.isNotEmpty) {
        unawaited(_applyModelLists());
      }
    });
    return _modelApply!;
  }

  Future<void> updateAppearance({
    ThemeMode? theme,
    Locale? language,
    double? scale,
  }) => _mutate(() async {
    if (theme != null) {
      await settings.setString('theme', theme.name);
      themeMode = theme;
    }
    if (language != null) {
      await settings.setString('language', language.languageCode);
      locale = language;
    }
    if (scale != null) {
      final value = scale.clamp(.85, 1.4);
      await settings.setString('textScale', '$value');
      textScale = value;
    }
  });

  Future<void> openConversation(String id) =>
      _mutate(() => _openConversation(id));

  Future<void> _openConversation(String id) async {
    if (conversation?.id != id) await _leaveIncognito();
    var current = await chats.getConversation(id);
    final loadedMessages = current == null
        ? <ChatMessage>[]
        : await chats.getMessages(id);
    final provider = providers
        .where((p) => p.id == current?.providerId)
        .firstOrNull;
    if (current != null && provider != null) {
      current = await _withProviderPrompt(
        current,
        provider.forModel(current.model),
      );
    }
    await settings.setString('conversation', current?.id);
    conversation = current;
    messages = loadedMessages;
    errorCode = null;
    providerError = null;
    contextTrimmed = false;
  }

  /// [incognito] makes the next chat incognito: memory is off and the chat
  /// is deleted when the user leaves it.
  Future<void> newChat({bool incognito = false}) =>
      _mutate(() => _newChat(incognito: incognito));

  Future<void> _newChat({bool incognito = false}) async {
    await _leaveIncognito();
    await settings.setString('conversation', null);
    conversation = null;
    incognitoDraft = incognito;
    messages = [];
    draftAttachments = [];
    errorCode = null;
    providerError = null;
    contextTrimmed = false;
  }

  /// Leaving an incognito chat deletes it, including its chat approvals.
  Future<void> _leaveIncognito() async {
    final current = conversation;
    if (current == null || !current.incognito) return;
    await _discardScreenshots(
      await chats.deleteConversation(current.id),
      always: true,
    );
    permissionGate.forgetConversation(current.id);
    conversation = null;
    messages = [];
    conversations = await chats.listConversations();
  }

  String _renderPrompt(
    ProviderConfig provider,
    DeviceContext device, {
    required bool incognito,
    required String memoryProfile,
    required String userNotes,
  }) {
    final tools = _conversationTools(provider, incognito: incognito);
    // The memory section instructs the model to call memory tools. Without
    // them the pinned profile gets a short section of its own; incognito
    // chats and switched-off memory have neither.
    final memory = tools.contains('memory_search');
    final profile = _usesMemory(incognito: incognito) ? memoryProfile : '';
    return PromptBuilder(promptTemplate).render({
      'app_name': kAppName,
      'device_kind': 'phone',
      'provider_name': '${provider.displayName} (${provider.model})',
      'on_device': provider.isLocal,
      'small_model': false,
      'markdown': true,
      'memory': memory,
      'memory_profile': profile,
      'web_search':
          tools.contains('web_search') ||
          toolSettings.enabled &&
              provider.capabilities.tools &&
              !toolSettings.disabled.contains('web_search') &&
              provider.capabilities.builtInWebSearch &&
              supportsBuiltInWebSearch(provider),
      'browser': tools.contains('browser_read'),
      'files': tools.contains('file_list'),
      'screen_control': tools.contains('read_screen'),
      'screen_delegate': tools.contains('remote_control'),
      'screen_elements':
          tools.contains('read_screen') &&
          services.screen.observationModes.contains(
            ScreenObservationMode.elements,
          ),
      'screen_vision': tools.contains('read_screen') && _screenVision(provider),
      'screen_fast':
          tools.contains('read_screen') && services.screen.supportsFastActions,
      'shortcuts': tools.contains('run_shortcut'),
      'shell': tools.contains('run_shell'),
      'shell_env': services.shell.environment,
      'user_notes': userNotes,
      'platform': device.platform,
      'os_version': device.osVersion,
      'device_model': device.model,
    });
  }

  /// Excludes credentials, generation limits and device snapshots. Editing a
  /// key or saving unchanged settings must not change the cached prompt prefix.
  String _promptConfigKey(ProviderConfig provider, {required bool incognito}) {
    final tools = _conversationTools(provider, incognito: incognito);
    return jsonEncode({
      'id': provider.id,
      'name': provider.displayName,
      'api': provider.apiType.name,
      'baseUrl': provider.baseUrl,
      'model': provider.model,
      'isLocal': provider.isLocal,
      'capabilities': provider.capabilities.toJson(),
      'tools': [
        for (final tool in toolRegistry.availableTools)
          if (tools.contains(tool.name)) tool.name,
      ],
      'screenVision': tools.contains('read_screen') && _screenVision(provider),
      'screenFast': services.screen.supportsFastActions,
      // Turning memory off mid-chat removes the profile from the prompt.
      'memory': _usesMemory(incognito: incognito),
      // An app update that changes the template re-renders a chat once.
      'template': _templateHash,
    });
  }

  /// FNV-1a over the template: the same in every run and SDK version.
  late final String _templateHash = () {
    var hash = 0x811c9dc5;
    for (final unit in promptTemplate.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }();

  bool _usesMemory({required bool incognito}) =>
      memorySettings.enabled && !incognito;

  Future<Conversation> _withProviderPrompt(
    Conversation current,
    ProviderConfig provider, {
    DeviceContext? device,
    CancelToken? cancel,
  }) async {
    final key = _promptConfigKey(provider, incognito: current.incognito);
    if (current.promptConfigKey == key &&
        current.providerId == provider.id &&
        current.model == provider.model) {
      return current;
    }
    final DeviceContext snapshot;
    if (device != null) {
      snapshot = device;
    } else if (cancel == null) {
      snapshot = await services.deviceContext();
    } else {
      snapshot = await cancel.bind(services.deviceContext());
    }
    cancel?.throwIfCancelled();
    // Chats created before snapshots existed take one now and keep it.
    final memoryProfile =
        current.memoryProfile ??
        (current.incognito ? '' : await memory.profileSnapshot());
    final userNotes = current.userNotes ?? personalization.promptNotes;
    cancel?.throwIfCancelled();
    final updated = current.copyWith(
      providerId: provider.id,
      model: provider.model,
      systemPrompt: _renderPrompt(
        provider,
        snapshot,
        incognito: current.incognito,
        memoryProfile: memoryProfile,
        userNotes: userNotes,
      ),
      promptConfigKey: key,
      memoryProfile: memoryProfile,
      userNotes: userNotes,
    );
    await chats.saveConversation(updated);
    return updated;
  }

  Future<void> selectProvider(String id, {String? model}) =>
      _mutate(() => _selectProvider(id, model: model));

  Future<void> _selectProvider(String id, {String? model}) async {
    final base = providers.firstWhere((p) => p.id == id);
    final provider = base.forModel(
      model ??
          (conversation?.providerId == id
              ? conversation?.model
              : selectedModelId) ??
          base.model,
    );
    final current = conversation;
    final updated = current == null
        ? null
        : await _withProviderPrompt(current, provider);
    await settings.setString('provider', id);
    selectedProviderId = id;
    selectedModelId = provider.model;
    await settings.setString('model', provider.model);
    conversation = updated;
    errorCode = null;
    providerError = null;
  }

  Future<void> saveProvider(
    ProviderConfig config, {
    String? key,
    String? headers,
    bool removeKey = false,
    bool removeHeaders = false,
  }) async {
    await _mutate(() async {
      if (config.apiType != ApiType.onDevice) {
        providerEndpoint(config.baseUrl, 'models');
      }
      final keyRef = config.apiKeyRef ?? 'provider.${config.id}.key';
      final headersRef =
          config.extraHeadersRef ?? 'provider.${config.id}.headers';
      if (removeKey || key?.isNotEmpty == true) {
        await services.writeSecret(keyRef, removeKey ? null : key);
      }
      if (removeHeaders || headers?.isNotEmpty == true) {
        await services.writeSecret(headersRef, removeHeaders ? null : headers);
      }
      final saved = config.copyWith(
        apiKeyRef: keyRef,
        extraHeadersRef: headersRef,
      );
      await providerRepository.save(saved);
      providers = await providerRepository.list();
      selectedProviderId ??= saved.id;
      await settings.setString('provider', selectedProviderId);
      if (conversation?.providerId == saved.id) await _selectProvider(saved.id);
      _modelFetchedAt.remove(saved.id);
    });
    if (!_disposed && config.autoFetchModels) {
      unawaited(refreshProviderModels(providerId: config.id));
    }
  }

  Future<void> deleteProvider(String id) => _mutate(() async {
    final provider = providers.firstWhere((p) => p.id == id);
    if (provider.apiKeyRef case final ref?) {
      await services.writeSecret(ref, null);
    }
    if (provider.extraHeadersRef case final ref?) {
      await services.writeSecret(ref, null);
    }
    await providerRepository.delete(id);
    providers = await providerRepository.list();
    if (selectedProviderId == id) {
      selectedProviderId = providers.firstOrNull?.id;
    }
    await settings.setString('provider', selectedProviderId);
  });

  static const _shortcutsKey = 'shortcuts.settings';
  static const _onDeviceKey = 'onDevice.settings';

  /// Whether on-device models may use more CPU cores at the cost of a
  /// smooth phone.
  Future<void> saveOnDevicePreferSpeed(bool value) => _mutate(() async {
    await settings.setString(_onDeviceKey, jsonEncode({'preferSpeed': value}));
    services.onDevice.preferSpeed = value;
  });

  /// The Shortcuts the model may list and run, by exact name.
  Future<void> saveShortcutNames(List<String> names) => _mutate(() async {
    final unique = {
      for (final name in names)
        if (name.trim().isNotEmpty) name.trim(),
    }.toList();
    await settings.setString(_shortcutsKey, jsonEncode({'names': unique}));
    services.shortcuts.names = unique;
  });

  /// Chats with [model] from now on, through the on-device provider, which
  /// is created on first use.
  Future<void> useOnDeviceModel(
    LocalModel model, {
    required String providerName,
  }) => _mutate(() async {
    final existing = providers
        .where((p) => p.apiType == ApiType.onDevice)
        .firstOrNull;
    final detected = model.profile();
    final previous = existing?.models
        .where((m) => m.id == model.id)
        .firstOrNull;
    final profile = model.isSystem && previous != null
        ? ModelProfile(
            id: model.id,
            capabilities: previous.autoDetect
                ? detected.capabilities
                : previous.capabilities,
            maxOutputTokens: previous.maxOutputTokens,
            reasoningMode: previous.reasoningMode,
            thinkingBudgetTokens: previous.thinkingBudgetTokens,
            reasoningEffort: previous.reasoningEffort,
            autoDetect: previous.autoDetect,
          )
        : detected;
    final provider = existing == null
        ? ProviderConfig(
            id: newId(),
            displayName: providerName,
            apiType: ApiType.onDevice,
            baseUrl: '',
            model: model.id,
            models: [profile],
          )
        : model.isSystem
        ? existing.copyWith(
            models: [
              for (final saved in existing.models)
                if (saved.id != model.id) saved,
              profile,
            ],
          )
        : existing.models.any((m) => m.id == model.id)
        ? existing
        : existing.copyWith(models: [...existing.models, profile]);
    if (!identical(provider, existing)) {
      await providerRepository.save(provider);
      providers = await providerRepository.list();
    }
    await _selectProvider(provider.id, model: model.id);
  });

  /// Deletes the model file and drops it from on-device providers that have
  /// other models left.
  Future<void> deleteOnDeviceModel(String id) => _mutate(() async {
    await services.onDevice.delete(id);
    for (final provider in providers) {
      if (provider.apiType != ApiType.onDevice || provider.models.length < 2) {
        continue;
      }
      final models = provider.models.where((m) => m.id != id).toList();
      if (models.length == provider.models.length) continue;
      await providerRepository.save(
        provider.copyWith(
          models: models,
          model: provider.model == id ? models.first.id : provider.model,
        ),
      );
    }
    providers = await providerRepository.list();
    if (selectedProvider case final selected?
        when selected.apiType == ApiType.onDevice && selected.model == id) {
      final provider = providers.firstWhere((p) => p.id == selected.id);
      await _selectProvider(provider.id, model: provider.models.first.id);
    }
  });

  Future<ProviderAdapter> adapterFor(
    ProviderConfig provider, {
    String? temporaryKey,
    Map<String, String>? temporaryHeaders,
    bool removeKey = false,
    bool removeHeaders = false,
  }) async {
    final key = removeKey
        ? null
        : temporaryKey?.isNotEmpty == true
        ? temporaryKey
        : provider.apiKeyRef == null
        ? null
        : await services.readSecret(provider.apiKeyRef!);
    final headers = removeHeaders
        ? <String, String>{}
        : temporaryHeaders ??
              await services.readHeaders(provider.extraHeadersRef);
    return _adapterFactory(
      provider.copyWith(apiType: provider.requestApiType),
      key,
      headers,
    );
  }

  /// An explicit, isolated capability check. It never saves this temporary
  /// model configuration or includes the user's messages, prompt or files.
  Future<HostedSearchProbeResult> probeHostedSearch(
    ProviderConfig config, {
    String? temporaryKey,
    Map<String, String>? temporaryHeaders,
    bool removeKey = false,
    bool removeHeaders = false,
    required CancelToken cancel,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final wasBusy = busy;
    final acquired = !wasBusy && !_disposed;
    if (acquired) {
      _probingHostedSearch = true;
      _cancel = cancel;
      _emit();
    }
    final probeId = 'hosted-search-probe-${newId()}';
    const query =
        'Find the official Flutter website using web search. '
        'Return only its title and URL.';
    final args = <String, Object?>{
      'provider': config.displayName,
      'model': config.model,
      'mode': 'hosted_search_probe',
      'query': query,
      'max_calls': 1,
    };
    int? auditId;
    Timer? timer;
    var didTimeOut = false;
    var decision = 'probe';
    var result = const HostedSearchProbeResult(HostedSearchProbeStatus.failed);
    try {
      // Record rejected and cancelled probes too, without persisting credentials
      // or any of the endpoint's response text. Audit failure fails closed.
      auditId = await audit.start(
        conversationId: probeId,
        messageId: probeId,
        toolCallId: newId(),
        toolName: 'web_search',
        arguments: jsonEncode(args),
        risk: RiskLevel.safe,
      );
      if (wasBusy) {
        result = const HostedSearchProbeResult(HostedSearchProbeStatus.busy);
      } else if (_disposed || cancel.isCancelled) {
        result = const HostedSearchProbeResult(
          HostedSearchProbeStatus.cancelled,
        );
      } else if (!toolSettings.enabled ||
          toolSettings.disabled.contains('web_search')) {
        result = const HostedSearchProbeResult(
          HostedSearchProbeStatus.disabled,
        );
      } else if (config.apiType == ApiType.chatCompletions) {
        result = const HostedSearchProbeResult(
          HostedSearchProbeStatus.unsupportedProtocol,
        );
      } else {
        final authorization = await permissionGate.authorize(
          toolName: 'web_search',
          args: args,
          risk: RiskLevel.safe,
          context: ToolContext(
            conversationId: probeId,
            messageId: probeId,
            cancel: cancel,
          ),
        );
        decision = authorization.reason;
        if (!authorization.allowed) {
          result = const HostedSearchProbeResult(
            HostedSearchProbeStatus.denied,
          );
        } else {
          cancel.throwIfCancelled();
          // Approval time does not consume the request timeout.
          timer = Timer(timeout, () {
            didTimeOut = true;
            cancel.cancel();
          });
          final capabilities = config.capabilities;
          final temporary = config.copyWith(
            capabilities: ProviderCapabilities(
              tools: true,
              builtInWebSearch: true,
              allowCustomSearchEndpoint: true,
              vision: capabilities.vision,
              reasoning: capabilities.reasoning,
              contextWindow: capabilities.contextWindow,
            ),
            reasoningMode: ReasoningMode.off,
            maxOutputTokens: 512,
          );
          final adapter = await cancel.bind(
            adapterFor(
              temporary,
              temporaryKey: temporaryKey,
              temporaryHeaders: temporaryHeaders,
              removeKey: removeKey,
              removeHeaders: removeHeaders,
            ),
          );
          cancel.throwIfCancelled();
          result = await observeHostedSearchProbe(
            adapter.send(
              ChatRequest(
                systemPrompt:
                    'This is a web search capability check. '
                    'Use the provided native web search tool exactly once.',
                messages: [
                  ChatMessage(
                    id: probeId,
                    conversationId: probeId,
                    role: MessageRole.user,
                    content: const [TextBlock(query)],
                    createdAt: DateTime.now(),
                  ),
                ],
                maxTokens: 512,
                replayOpaqueReasoning: false,
                builtInWebSearch: true,
                forceBuiltInWebSearch: true,
              ),
              cancel: cancel,
            ),
            cancel: cancel,
          );
        }
      }
    } on RequestCancelled {
      result = const HostedSearchProbeResult(HostedSearchProbeStatus.cancelled);
    } on ProviderError catch (error) {
      result = HostedSearchProbeResult(
        error.code == 'timeout'
            ? HostedSearchProbeStatus.timedOut
            : HostedSearchProbeStatus.failed,
        statusCode: error.statusCode,
      );
    } catch (_) {
      result = const HostedSearchProbeResult(HostedSearchProbeStatus.failed);
    } finally {
      timer?.cancel();
      if (didTimeOut) {
        result = const HostedSearchProbeResult(
          HostedSearchProbeStatus.timedOut,
        );
      } else if (acquired && cancel.isCancelled) {
        result = const HostedSearchProbeResult(
          HostedSearchProbeStatus.cancelled,
        );
      }
      try {
        if (auditId != null) {
          await audit.finish(
            auditId,
            decision: decision == 'probe' ? result.status.name : decision,
            resultSummary: jsonEncode({
              'status': result.status.name,
              if (result.statusCode != null) 'http_status': result.statusCode,
            }),
            isError: result.status != HostedSearchProbeStatus.supported,
          );
        }
      } catch (_) {
        result = const HostedSearchProbeResult(HostedSearchProbeStatus.failed);
      } finally {
        permissionGate.forgetConversation(probeId);
        if (acquired) {
          if (identical(_cancel, cancel)) _cancel = null;
          _probingHostedSearch = false;
          _emit();
        }
      }
    }
    return result;
  }

  Future<void> send(String text, {ChatMessage? editing}) async {
    if (busy ||
        _disposed ||
        (text.trim().isEmpty && draftAttachments.isEmpty && editing == null)) {
      return;
    }
    final provider = selectedProvider;
    if (provider == null) {
      errorCode = 'noProviderSelected';
      _emit();
      return;
    }
    final isNewConversation = conversation == null;
    _titleJobs[conversation?.id]?.cancel();
    _generating = true;
    errorCode = null;
    providerError = null;
    final token = _cancel = CancelToken();
    _emit();
    try {
      if (editing != null &&
          (editing.role != MessageRole.user ||
              editing.conversationId != conversation?.id ||
              !messages.any((m) => m.id == editing.id))) {
        throw ArgumentError(
          'Edited message is not in the current conversation.',
        );
      }
      final attachments = editing == null
          ? List<ContentBlock>.of(draftAttachments)
          : editing.content
                .where((b) => b is ImageBlock || b is FileBlock)
                .toList();
      final acceptsImages =
          provider.capabilities.acceptsImageInput ||
          _canRouteReferenceImages(provider);
      if (!acceptsImages && attachments.any((b) => b is ImageBlock)) {
        errorCode = 'visionRequired';
        return;
      }
      final hydrated = attachments.isEmpty
          ? <ContentBlock>[]
          : await services.workspace.hydrateBlocks(
              attachments,
              vision: acceptsImages,
              cancel: token,
            );
      // The prompt reflects the tools the user has enabled right now.
      await refreshDeviceControl();
      final device = await token.bind(services.deviceContext());
      token.throwIfCancelled();
      final now = DateTime.now();
      if (conversation == null) {
        final isIncognito = incognitoDraft;
        // Frozen for the conversation's lifetime: profile and personalization
        // edits apply to the next chat and never change this cached prefix.
        final memoryProfile = isIncognito
            ? ''
            : await token.bind(memory.profileSnapshot());
        final userNotes = personalization.promptNotes;
        token.throwIfCancelled();
        final created = Conversation(
          id: newId(),
          title: text.trim().isEmpty
              ? (hydrated.first is FileBlock
                    ? (hydrated.first as FileBlock).name
                    : 'Image')
              : text.trim().characters.take(48).toString(),
          createdAt: now,
          updatedAt: now,
          systemPrompt: _renderPrompt(
            provider,
            device,
            incognito: isIncognito,
            memoryProfile: memoryProfile,
            userNotes: userNotes,
          ),
          providerId: provider.id,
          model: provider.model,
          promptConfigKey: _promptConfigKey(provider, incognito: isIncognito),
          incognito: isIncognito,
          memoryProfile: memoryProfile,
          userNotes: userNotes,
        );
        await chats.createConversation(created);
        conversation = created;
        // An incognito chat is never reopened at startup; it is purged.
        if (!isIncognito) await settings.setString('conversation', created.id);
      } else {
        conversation = await _withProviderPrompt(
          conversation!,
          provider,
          device: device,
          cancel: token,
        );
      }
      token.throwIfCancelled();
      final parentId = editing == null
          ? conversation!.activeLeafId
          : editing.parentId;
      final previous = parentId == null
          ? null
          : messages.firstWhere((m) => m.id == parentId);
      final message = ChatMessage(
        id: newId(),
        conversationId: conversation!.id,
        parentId: parentId,
        role: MessageRole.user,
        content: [
          if (text.trim().isNotEmpty) TextBlock(text.trim()),
          ...hydrated,
        ],
        createdAt: now,
        timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
        providerId: provider.id,
        model: provider.model,
        contextEnvelope: ContextEnvelope.build(
          now: now,
          previousMessageAt: previous?.createdAt,
          batteryPercent: device.batteryPercent,
          network: device.network,
        ),
      );
      token.throwIfCancelled();
      await chats.saveMessage(message);
      if (editing == null) draftAttachments = [];
      await _refresh();
      await _generate(provider, message.id);
      final answer = visibleMessages.lastOrNull;
      if (isNewConversation &&
          !token.isCancelled &&
          errorCode == null &&
          answer?.role == MessageRole.assistant &&
          answer?.status == MessageStatus.done &&
          _hasAnswer(answer!.content) &&
          !answer.content.any((b) => b is ToolCallBlock)) {
        unawaited(
          _updateConversationTitle(provider, conversation!, visibleMessages),
        );
      }
    } on RequestCancelled {
      await _refresh();
    } catch (_) {
      errorCode = 'operationFailed';
    } finally {
      _generating = false;
      _cancel = null;
      activeToolCallId = null;
      services.browser.endModelSession();
      services.screen.endModelSession();
      _emit();
      unawaited(_applyModelLists());
    }
  }

  /// Regenerate the entire assistant turn, including its tool rounds.
  Future<void> regenerate(ChatMessage message) =>
      _regenerate(message, wholeTurn: true);

  /// Retry an interrupted stream from its original context and tool receipts.
  Future<void> retryResponse(ChatMessage message) async {
    if (message.role != MessageRole.assistant ||
        (message.status != MessageStatus.error &&
            message.status != MessageStatus.stopped)) {
      return;
    }
    await _regenerate(message, wholeTurn: false);
  }

  Future<void> _regenerate(
    ChatMessage message, {
    required bool wholeTurn,
  }) async {
    if (busy || _disposed) return;
    if (message.conversationId != conversation?.id ||
        !messages.any((m) => m.id == message.id)) {
      return;
    }
    final provider = selectedProvider;
    if (provider == null) {
      errorCode = 'noProviderSelected';
      _emit();
      return;
    }
    final parentId = wholeTurn
        ? tree
              .pathTo(message.id)
              .reversed
              .where((node) => node.role == MessageRole.user)
              .firstOrNull
              ?.id
        : message.parentId;
    if (parentId == null) return;
    await _respondFrom(provider, parentId);
  }

  /// Whether the response stopped for a tool loop can go on: its
  /// last message must still be the end of the shown branch.
  bool get canContinueAfterLimit =>
      !busy &&
      (errorCode == 'toolStepLimit' || errorCode == 'toolLoopDetected') &&
      _limitedAt != null &&
      _limitedAt == conversation?.activeLeafId;

  /// Continues a response stopped for a tool loop from its explanation, with
  /// a fresh loop detector. The user asks for it explicitly.
  Future<void> continueAfterLimit() async {
    final provider = selectedProvider;
    final leaf = _limitedAt;
    if (_disposed || !canContinueAfterLimit || provider == null) return;
    await _respondFrom(provider, leaf!);
  }

  Future<void> _respondFrom(ProviderConfig provider, String parentId) async {
    _titleJobs[conversation?.id]?.cancel();
    _generating = true;
    errorCode = null;
    providerError = null;
    final token = _cancel = CancelToken();
    _emit();
    try {
      await refreshDeviceControl();
      conversation = await _withProviderPrompt(
        conversation!,
        provider,
        cancel: token,
      );
      token.throwIfCancelled();
      await _generate(provider, parentId);
    } on RequestCancelled {
      await _refresh();
    } catch (_) {
      errorCode = 'operationFailed';
    } finally {
      _generating = false;
      _cancel = null;
      activeToolCallId = null;
      services.browser.endModelSession();
      services.screen.endModelSession();
      _emit();
      unawaited(_applyModelLists());
    }
  }

  Future<void> _generate(ProviderConfig provider, String parentId) async {
    final token = _cancel!;
    final allowed =
        toolSettings.enabled &&
        provider.capabilities.tools &&
        provider.capabilities.imageGeneration != ImageGenerationMode.imagesApi;
    final wantsHostedSearch =
        allowed &&
        provider.capabilities.builtInWebSearch &&
        supportsBuiltInWebSearch(provider) &&
        !toolSettings.disabled.contains('web_search');
    final registry = allowed
        ? ToolRegistry(
            toolRegistry.allTools,
            disabledTools: {
              ..._disabledTools(incognito: conversation!.incognito),
              if (wantsHostedSearch) 'web_search',
            },
          )
        : ToolRegistry(const []);
    final executor = ToolExecutor(
      registry: registry,
      permissions: permissionGate,
      audit: audit,
      maxOutputChars: toolSettings.maxOutputChars,
    );
    var leaf = parentId;
    var executed = 0;
    final loops = ToolLoopDetector();
    Future<void> remember(ToolCallBlock call, ToolResultBlock result) async {
      try {
        final attachments = result.attachments.any((b) => b is ImageBlock)
            ? await services.workspace.hydrateBlocks(
                result.attachments,
                vision: true,
                cancel: token,
              )
            : result.attachments;
        loops.record(call, result, attachments: attachments);
      } catch (_) {
        // Loop bookkeeping must never lose a committed tool receipt.
        if (!token.isCancelled) loops.record(call, result);
      }
    }

    // Controlling the screen takes an action and a look per step, so a turn
    // that uses screen tools gets the larger loop-check threshold.
    var screenTurn = false;
    int limit() => screenTurn
        ? max(toolSettings.maxSteps, toolSettings.maxScreenSteps)
        : toolSettings.maxSteps;
    while (!token.isCancelled) {
      var hostedAllowed = false;
      int? hostedAudit;
      if (wantsHostedSearch) {
        final args = <String, Object?>{
          'provider': provider.displayName,
          'model': provider.model,
          'mode': 'provider_managed_search',
          'max_calls': 1,
        };
        hostedAudit = await audit.start(
          conversationId: conversation!.id,
          messageId: leaf,
          toolCallId: newId(),
          toolName: 'web_search',
          arguments: jsonEncode(args),
          risk: RiskLevel.safe,
        );
        try {
          final decision = await permissionGate.authorize(
            toolName: 'web_search',
            args: args,
            risk: RiskLevel.safe,
            context: ToolContext(
              conversationId: conversation!.id,
              messageId: leaf,
              cancel: token,
            ),
          );
          hostedAllowed = decision.allowed;
          if (hostedAllowed) executed++;
          if (!hostedAllowed) {
            await audit.finish(
              hostedAudit,
              decision: decision.reason,
              resultSummary: '{"error":"denied_by_user"}',
              isError: true,
            );
            hostedAudit = null;
          }
        } on RequestCancelled {
          if (hostedAudit case final auditId?) {
            await audit.finish(
              auditId,
              decision: 'cancelled',
              resultSummary: '{"error":"cancelled"}',
              isError: true,
            );
          }
          rethrow;
        }
      }
      ChatMessage? response;
      try {
        response = await _streamResponse(
          provider,
          leaf,
          registry.definitions,
          builtInWebSearch: hostedAllowed,
        );
      } finally {
        if (hostedAudit != null) {
          await audit.finish(
            hostedAudit,
            decision: token.isCancelled ? 'cancelled' : 'provider_managed',
            resultSummary: response?.text ?? '{"error":"request_incomplete"}',
            isError: response?.status != MessageStatus.done,
          );
        }
      }
      if (response == null || response.status != MessageStatus.done) return;
      final calls = response.content.whereType<ToolCallBlock>().toList();
      if (calls.isEmpty) {
        if (hostedAllowed && _lastStopReason == 'pause_turn') {
          const call = ToolCallBlock(
            id: 'hosted',
            name: 'provider_web_search',
            arguments: '{}',
          );
          loops.record(
            call,
            ToolResultBlock(
              toolCallId: call.id,
              toolName: call.name,
              content: jsonEncode([
                for (final state
                    in response.content.whereType<ProviderStateBlock>())
                  for (final item in state.content)
                    {
                      for (final entry in item.entries)
                        if (entry.key != 'id') entry.key: entry.value,
                    },
                response.text,
              ]),
            ),
          );
          final loop = executed >= limit() ? loops.repeatingBefore(call) : null;
          if (loop != null) {
            await _finishToolLoop(provider, response.id, loop);
            return;
          }
          leaf = response.id;
          continue;
        }
        return;
      }
      final results = <ContentBlock>[];
      final seen = <String>{};
      ToolLoop? blockedLoop;
      for (final (index, call) in calls.indexed) {
        activeToolCallId = call.id;
        _emit();
        if (screenToolNames.contains(call.name) &&
            registry.get(call.name) != null) {
          screenTurn = true;
        }
        blockedLoop ??= executed >= limit()
            ? loops.repeatingBefore(call)
            : null;
        if (blockedLoop != null || call.id.isEmpty || !seen.add(call.id)) {
          final code = blockedLoop != null
              ? 'tool_loop_detected'
              : 'invalid_tool_call';
          final id = await audit.start(
            conversationId: response.conversationId,
            messageId: response.id,
            toolCallId: call.id,
            toolName: call.name,
            arguments: call.arguments,
            risk: RiskLevel.high,
          );
          final result = ToolResultBlock(
            toolCallId: call.id,
            toolName: call.name,
            content: jsonEncode({
              'error': code,
              if (blockedLoop != null) 'message': blockedLoop.contextHint,
            }),
            isError: true,
          );
          await audit.finish(
            id,
            decision: code,
            resultSummary: result.content,
            isError: true,
          );
          results.add(result);
          if (blockedLoop == null) {
            await remember(call, result);
            executed++;
          }
        } else {
          final execution = await executor.execute(
            call,
            ToolContext(
              conversationId: response.conversationId,
              messageId: response.id,
              cancel: token,
              lastCall: index == calls.length - 1,
            ),
          );
          results.add(execution.result);
          // Persist committed actions even if Stop prevents image hydration.
          if (!token.isCancelled) await remember(call, execution.result);
          executed++;
          if (!token.isCancelled && services.screen.modelActive) {
            services.screen.updateModelSession(
              phase: ScreenSessionPhase.thinking,
            );
          }
        }
      }
      activeToolCallId = null;
      final now = DateTime.now();
      final resultMessage = ChatMessage(
        id: newId(),
        conversationId: response.conversationId,
        parentId: response.id,
        role: MessageRole.tool,
        content: results,
        createdAt: now,
        timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
        providerId: provider.id,
        model: provider.model,
      );
      // Receipts are persisted even when Stop raced with a committed action.
      await chats.saveMessage(resultMessage);
      await _refresh();
      if (token.isCancelled) return;
      if (blockedLoop != null) {
        await _finishToolLoop(provider, resultMessage.id, blockedLoop);
        return;
      }
      leaf = resultMessage.id;
    }
  }

  Future<void> _finishToolLoop(
    ProviderConfig provider,
    String leaf,
    ToolLoop loop,
  ) async {
    // One tool-free response makes the injected hint visible to the model and
    // lets it explain the blockage without executing the same actions again.
    final response = await _streamResponse(
      provider,
      leaf,
      const [],
      contextHint: loop.contextHint,
    );
    if (_cancel!.isCancelled) return;
    errorCode = 'toolLoopDetected';
    _limitedAt = response?.id ?? leaf;
    _emit();
  }

  Future<ChatMessage?> _streamResponse(
    ProviderConfig provider,
    String parentId,
    List<ToolDefinition> definitions, {
    bool builtInWebSearch = false,
    String? contextHint,
  }) async {
    _lastStopReason = null;
    final current = conversation!;
    final systemPrompt = contextHint == null
        ? current.systemPrompt
        : '${current.systemPrompt}\n\n$contextHint';
    final token = _cancel!;
    token.throwIfCancelled();
    final rawPath = tree.pathTo(parentId);
    // Providers may reuse call IDs across turns. Pair within the actual
    // assistant -> tool edge, never against a global set of IDs in history.
    final pairedIds = <String, Set<String>>{};
    for (var index = 0; index + 1 < rawPath.length; index++) {
      final assistant = rawPath[index];
      final results = rawPath[index + 1];
      if (assistant.role != MessageRole.assistant ||
          assistant.status != MessageStatus.done ||
          results.role != MessageRole.tool ||
          results.status != MessageStatus.done ||
          results.parentId != assistant.id) {
        continue;
      }
      final resultIds = {
        for (final result in results.content.whereType<ToolResultBlock>())
          result.toolCallId,
      };
      final completed = {
        for (final call in assistant.content.whereType<ToolCallBlock>())
          if (call.id.isNotEmpty && resultIds.contains(call.id)) call.id,
      };
      pairedIds[assistant.id] = completed;
      pairedIds[results.id] = completed;
    }
    final path = <ChatMessage>[];
    var historyChanged = false;
    for (final message in rawPath) {
      final content = message.content
          .where(
            (block) => switch (block) {
              ToolCallBlock() =>
                pairedIds[message.id]?.contains(block.id) ?? false,
              ToolResultBlock() =>
                pairedIds[message.id]?.contains(block.toolCallId) ?? false,
              _ => true,
            },
          )
          .toList();
      if (content.isEmpty ||
          message.role == MessageRole.assistant &&
              !_hasAnswer(content) &&
              !content.any(
                (b) =>
                    b is ToolCallBlock ||
                    b is ProviderStateBlock && builtInWebSearch,
              )) {
        historyChanged = true;
        continue;
      }
      if (content.length != message.content.length) historyChanged = true;
      if (content.whereType<ToolCallBlock>().any(
        (call) => tryDecodeObject(call.arguments) == null,
      )) {
        historyChanged = true;
      }
      path.add(
        content.length == message.content.length
            ? message
            : message.copyWith(content: content),
      );
    }
    final screenHistory = services.screen.supportsFastActions
        ? limitRemoteScreenImages(path)
        : (messages: path, changed: false);
    historyChanged |= screenHistory.changed;
    final imagesOnly =
        provider.capabilities.imageGeneration == ImageGenerationMode.imagesApi;
    final budget = imagesOnly
        ? ContextBudgetResult(
            messages: [
              ?path.reversed
                  .where((m) => m.role == MessageRole.user)
                  .firstOrNull,
            ],
            estimatedTokens: 0,
            removedMessages: 0,
            removedToolOutputs: 0,
            exceedsBudget: false,
          )
        : ContextBudget.trim(
            systemPrompt: systemPrompt,
            messages: screenHistory.messages,
            contextWindow: provider.capabilities.contextWindow ?? 32768,
            reserveOutputTokens:
                provider.maxOutputTokens +
                ContextBudget.estimateTokens(
                  jsonEncode(definitions.map((d) => d.schema).toList()),
                ),
          );
    contextTrimmed = budget.wasTrimmed;
    if (budget.exceedsBudget) {
      errorCode = 'contextTooLarge';
      return null;
    }
    final preparedMessages = <ChatMessage>[];
    for (final message in budget.messages) {
      final hasAttachments = message.content.any(
        (b) =>
            b is ImageBlock ||
            b is FileBlock ||
            b is ToolResultBlock && b.attachments.isNotEmpty,
      );
      preparedMessages.add(
        hasAttachments
            ? message.copyWith(
                content: await services.workspace.hydrateBlocks(
                  message.content,
                  vision: provider.capabilities.acceptsImageInput,
                  cancel: token,
                ),
              )
            : message,
      );
    }
    final adapter = await token.bind(adapterFor(provider));
    token.throwIfCancelled();
    final now = DateTime.now();
    var response = ChatMessage(
      id: newId(),
      conversationId: current.id,
      parentId: parentId,
      role: MessageRole.assistant,
      content: [],
      createdAt: now,
      timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
      providerId: provider.id,
      model: provider.model,
      status: MessageStatus.streaming,
    );
    await chats.saveMessage(response);
    await _refresh();
    final fingerprint = promptFingerprint(systemPrompt);
    final accumulator = ResponseAccumulator(
      sourceApi: provider.apiType.name,
      promptHash: fingerprint,
    );
    var status = MessageStatus.done;
    String? error;
    var completed = false;
    var lastSave = DateTime.now();
    Timer? publishTimer;
    void publish() {
      if (_disposed) return;
      response = response.copyWith(
        content: accumulator.content,
        usage: accumulator.usage,
      );
      final index = messages.indexWhere((m) => m.id == response.id);
      if (index >= 0) {
        messages = List.of(messages)..[index] = response;
      }
      _emit();
    }

    try {
      if (!token.isCancelled) {
        await for (final event in adapter.send(
          ChatRequest(
            systemPrompt: systemPrompt,
            messages: preparedMessages,
            tools: definitions,
            builtInWebSearch: builtInWebSearch,
            maxTokens: provider.maxOutputTokens,
            promptHash: fingerprint,
            replayOpaqueReasoning: !budget.wasTrimmed && !historyChanged,
          ),
          cancel: token,
        )) {
          if (token.isCancelled) break;
          if (event is GeneratedImage) {
            accumulator.addImage(
              await storeGeneratedImage(
                services.workspace,
                event,
                cancel: token,
              ),
            );
          } else {
            accumulator.add(event);
          }
          if (event is ProviderError) {
            error = switch (event.code) {
              'model_missing' when provider.apiType == ApiType.onDevice =>
                'localModelMissing',
              'model_load' when provider.apiType == ApiType.onDevice =>
                'localModelLoad',
              'aicore_unavailable' => 'aicoreUnavailable',
              'aicore_update' => 'aicoreUpdate',
              'aicore_request_too_large' => 'aicoreRequestTooLarge',
              'aicore_busy' => 'aicoreBusy',
              'aicore_failed' => 'aicoreFailed',
              'aicore_text_only' => 'aicoreHelp',
              'aicore_tools_unavailable' => 'aicoreToolsUnavailable',
              'aicore_invalid_tools' => 'aicoreInvalidTools',
              'aicore_background' => 'aicoreBackground',
              'no_space' when isAicoreModel(provider.model) =>
                'modelErrorNoSpace',
              _ => event.toString(),
            };
            status = MessageStatus.error;
          }
          if (event is Done) {
            completed = true;
            _lastStopReason = event.stopReason;
          }
          // Batch network fragments; a model may deliver hundreds per second.
          publishTimer ??= Timer(const Duration(milliseconds: 40), () {
            publishTimer = null;
            publish();
          });
          if (DateTime.now().difference(lastSave).inMilliseconds > 800) {
            response = response.copyWith(
              content: accumulator.content,
              usage: accumulator.usage,
            );
            await chats.saveMessage(response);
            lastSave = DateTime.now();
          }
          if (event is ProviderError || event is Done) break;
        }
      }
      if (token.isCancelled) {
        status = MessageStatus.stopped;
      } else if (status != MessageStatus.error &&
          (!completed ||
              (!_hasAnswer(accumulator.content) &&
                  !(builtInWebSearch && _lastStopReason == 'pause_turn') &&
                  !(definitions.isNotEmpty &&
                      accumulator.content.any((b) => b is ToolCallBlock))))) {
        status = MessageStatus.error;
        error = accumulator.content.any((block) => block is ToolCallBlock)
            ? 'toolsLater'
            : 'emptyResponse';
      }
    } catch (_) {
      status = token.isCancelled ? MessageStatus.stopped : MessageStatus.error;
      error = token.isCancelled ? null : 'operationFailed';
    } finally {
      publishTimer?.cancel();
    }
    if (definitions.isEmpty) {
      final unsolicited = accumulator.content.whereType<ToolCallBlock>();
      for (final call in unsolicited) {
        final auditId = await audit.start(
          conversationId: response.conversationId,
          messageId: response.id,
          toolCallId: call.id,
          toolName: call.name,
          arguments: call.arguments,
          risk: RiskLevel.high,
        );
        await audit.finish(
          auditId,
          decision: 'tools_disabled',
          resultSummary: '{"error":"tool_unavailable"}',
          isError: true,
        );
      }
      // Text accompanying unsolicited calls does not authorize execution.
      // Keep stopped/provider-error states, otherwise make rejection explicit.
      if (unsolicited.isNotEmpty && status == MessageStatus.done) {
        status = MessageStatus.error;
        error = 'toolsLater';
      }
    }
    response = response.copyWith(
      content: accumulator.content,
      usage: accumulator.usage,
      status: status,
      error: error,
    );
    await chats.saveMessage(response);
    await _refresh();
    return response;
  }

  void stop() {
    _attachmentCancel?.cancel();
    _cancel?.cancel();
    services.screen.endModelSession();
  }

  bool _hasAnswer(List<ContentBlock> content) => content.any(
    (block) =>
        block is TextBlock && block.text.trim().isNotEmpty ||
        block is ImageBlock ||
        block is FileBlock,
  );

  Future<void> _refresh() async {
    final current = conversation;
    if (current != null) {
      final loaded = await (
        chats.getConversation(current.id),
        chats.getMessages(current.id),
      ).wait;
      conversation = loaded.$1;
      messages = loaded.$2;
    }
    conversations = await chats.listConversations();
    _emit();
  }

  Future<void> rewind(ChatMessage message, {bool deleteAfter = false}) =>
      _mutate(() async {
        if (message.conversationId != conversation?.id) return;
        if (deleteAfter) {
          await _discardScreenshots(
            await chats.deleteDescendants(message.conversationId, message.id),
          );
        } else {
          await chats.setActiveLeaf(message.conversationId, message.id);
        }
        await _refresh();
      });

  Future<void> switchBranch(ChatMessage message) => _mutate(() async {
    if (message.conversationId != conversation?.id) return;
    await chats.switchBranch(message.conversationId, message.id);
    await _refresh();
  });

  Future<void> renameConversation(String title) => _mutate(() async {
    if (conversation == null || title.trim().isEmpty) return;
    _titleJobs[conversation!.id]?.cancel();
    await chats.saveConversation(conversation!.copyWith(title: title.trim()));
    await _refresh();
  });

  Future<bool> generateConversationTitle() async {
    final current = conversation;
    final provider = selectedProvider;
    if (busy ||
        _disposed ||
        isGeneratingTitle ||
        current == null ||
        provider == null) {
      return false;
    }
    return _updateConversationTitle(provider, current, visibleMessages);
  }

  Future<bool> _updateConversationTitle(
    ProviderConfig provider,
    Conversation current,
    List<ChatMessage> path,
  ) async {
    if (_disposed ||
        current.incognito ||
        provider.capabilities.imageGeneration != ImageGenerationMode.none ||
        _titleJobs.containsKey(current.id)) {
      return false;
    }
    final token = CancelToken();
    _titleJobs[current.id] = token;
    _emit();
    final timer = Timer(const Duration(seconds: 30), token.cancel);
    try {
      final adapter = await token.bind(
        adapterFor(provider.copyWith(reasoningMode: ReasoningMode.off)),
      );
      final title = await token.bind(_titleGenerator(adapter, path, token));
      token.throwIfCancelled();
      if (_disposed || title == null || title.trim().isEmpty) return false;
      final updated = await chats.updateTitle(
        current.id,
        title.trim().characters.take(80).toString(),
        expectedTitle: current.title,
      );
      if (updated && !_disposed) {
        if (conversation?.id == current.id) {
          final loaded = await chats.getConversation(current.id);
          if (conversation?.id == current.id) conversation = loaded;
        }
        conversations = await chats.listConversations();
      }
      return updated;
    } catch (_) {
      // Title generation is best effort and never changes response errors.
      return false;
    } finally {
      timer.cancel();
      _titleJobs.remove(current.id);
      _emit();
    }
  }

  Future<void> deleteConversation(String id) => _mutate(() async {
    _titleJobs[id]?.cancel();
    await _discardScreenshots(await chats.deleteConversation(id));
    if (conversation?.id == id) await _newChat();
    conversations = await chats.listConversations();
  });

  @override
  void dispose() {
    _disposed = true;
    for (final token in _titleJobs.values) {
      token.cancel();
    }
    for (final token in _modelFetchTokens.values) {
      token.cancel();
    }
    _pendingModelLists.clear();
    stop();
    if (services.browser.onTakeOver == stop) services.browser.onTakeOver = null;
    if (services.screen.onTakeOver == stop) services.screen.onTakeOver = null;
    for (final control in _controls) {
      control.removeListener(_emit);
    }
    super.dispose();
  }
}

class _Gate implements Capability {
  const _Gate(this._available);
  final bool Function() _available;
  @override
  bool get isAvailable => _available();
}

/// Stable non-secret fingerprint; never use process-randomized String.hashCode.
String promptFingerprint(String prompt) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(prompt)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return '${utf8.encode(prompt).length}:${hash.toRadixString(16)}';
}
