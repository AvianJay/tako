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
import '../core/chat/message.dart';
import '../core/chat/response_accumulator.dart';
import '../core/memory/memory.dart';
import '../core/memory/settings.dart';
import '../core/permissions/permission_gate.dart';
import '../core/prompt/context_budget.dart';
import '../core/prompt/context_envelope.dart';
import '../core/prompt/prompt_builder.dart';
import '../core/providers/hosted_search_probe.dart';
import '../core/providers/providers.dart';
import '../core/screen/device_control_settings.dart';
import '../core/screen/screen_capability.dart';
import '../core/search/search_service.dart';
import '../core/tools/browser_tools.dart';
import '../core/tools/device_tools.dart';
import '../core/tools/file_tools.dart';
import '../core/tools/memory_tools.dart';
import '../core/tools/notification_tools.dart';
import '../core/tools/screen_tools.dart';
import '../core/tools/search_tools.dart';
import '../core/tools/shell_tools.dart';
import '../core/tools/tool.dart';
import '../core/tools/tool_executor.dart';
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
    List<Tool>? extraTools,
  }) : _adapterFactory =
           adapterFactory ??
           ((config, key, headers) => ProviderAdapter.create(
             config,
             apiKey: key,
             secretHeaders: headers,
           )),
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
    if (value) unawaited(refreshDeviceControl());
  }

  /// Removes the screenshots that only [deleted] messages used, when the
  /// setting asks for it or the chat was incognito. Best effort: a failure
  /// here never blocks deleting the chat itself.
  Future<void> _discardScreenshots(
    List<ChatMessage> deleted, {
    bool always = false,
  }) async {
    if (!always && !controlSettings.deleteScreenshotsWithChat) return;
    final paths = {
      for (final message in deleted)
        for (final block in message.content)
          if (block case ToolResultBlock(
            toolName: 'read_screen',
            :final attachments,
          ))
            for (final attachment in attachments)
              if (attachment case ImageBlock(:final path)) path,
    };
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

  ToolRegistry _makeRegistry() => ToolRegistry([
    ...createDeviceTools(
      services.deviceTools,
      observer: _screenObserver,
      maxChars: toolSettings.maxOutputChars,
    ),
    ...createFileTools(services.workspace),
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
    ..._extraTools,
  ], disabledTools: toolSettings.disabled);

  /// Incognito chats never see memory tools, whatever the settings say.
  Set<String> _disabledTools({required bool incognito}) => {
    ...toolSettings.disabled,
    if (incognito) ...memoryToolNames,
  };

  /// Tool names a conversation offers to this provider.
  Set<String> _conversationTools(
    ProviderConfig provider, {
    required bool incognito,
  }) {
    if (!toolSettings.enabled || !provider.capabilities.tools) return const {};
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

  /// The last message of a response that stopped at the tool-call limit.
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
    }
  }

  Future<void> initialize() => _mutate(() async {
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
      // Before the current chat's prompt is checked against available tools.
      await refreshDeviceControl();
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
      textScale = (double.tryParse(preferences['textScale'] ?? '') ?? 1).clamp(
        .85,
        1.4,
      );
      final current = preferences['conversation'];
      if (current != null) await _openConversation(current);
    } catch (_) {
      errorCode = 'operationFailed';
    } finally {
      initialized = true;
    }
  });

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
      'screen_elements':
          tools.contains('read_screen') &&
          services.screen.observationModes.contains(
            ScreenObservationMode.elements,
          ),
      'screen_vision': tools.contains('read_screen') && _screenVision(provider),
      'shortcuts': false,
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
  }) => _mutate(() async {
    providerEndpoint(config.baseUrl, 'models');
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
  });

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
    return _adapterFactory(provider, key, headers);
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
      if (!provider.capabilities.vision &&
          attachments.any((b) => b is ImageBlock)) {
        errorCode = 'visionRequired';
        return;
      }
      final hydrated = attachments.isEmpty
          ? <ContentBlock>[]
          : await services.workspace.hydrateBlocks(
              attachments,
              vision: provider.capabilities.vision,
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
    }
  }

  Future<void> regenerate(ChatMessage message) async {
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
    var parentId = message.role == MessageRole.user
        ? message.id
        : message.parentId;
    if (message.role == MessageRole.assistant &&
        message.status == MessageStatus.done) {
      final callIds = message.content
          .whereType<ToolCallBlock>()
          .map((call) => call.id)
          .toSet();
      if (callIds.isNotEmpty) {
        final receipts = tree.childrenOf(message.id).where((child) {
          if (child.role != MessageRole.tool ||
              child.status != MessageStatus.done) {
            return false;
          }
          final resultIds = child.content
              .whereType<ToolResultBlock>()
              .map((result) => result.toolCallId)
              .toSet();
          return resultIds.containsAll(callIds);
        }).toList();
        final visibleIds = visibleMessages.map((item) => item.id).toSet();
        final receipt =
            receipts
                .where((child) => visibleIds.contains(child.id))
                .firstOrNull ??
            receipts.lastOrNull;
        // Regenerate the explanation after completed tools. Their receipts
        // remain in history, so file/device changes cannot silently run again.
        if (receipt != null) parentId = receipt.id;
      }
    }
    if (parentId == null) return;
    await _respondFrom(provider, parentId);
  }

  /// Whether the response that stopped at the tool-call limit can go on: its
  /// last message must still be the end of the shown branch.
  bool get canContinueAfterLimit =>
      !busy &&
      errorCode == 'toolStepLimit' &&
      _limitedAt != null &&
      _limitedAt == conversation?.activeLeafId;

  /// Continues a response that stopped at the tool-call limit: from its last
  /// tool results, with a new budget. The user asks for it explicitly.
  Future<void> continueAfterLimit() async {
    final provider = selectedProvider;
    final leaf = _limitedAt;
    if (_disposed || !canContinueAfterLimit || provider == null) return;
    await _respondFrom(provider, leaf!);
  }

  Future<void> _respondFrom(ProviderConfig provider, String parentId) async {
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
    }
  }

  Future<void> _generate(ProviderConfig provider, String parentId) async {
    final token = _cancel!;
    final allowed = toolSettings.enabled && provider.capabilities.tools;
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
    var rounds = 0;
    // Controlling the screen takes an action and a look per step, so a turn
    // that uses screen tools gets the larger screen limit.
    var screenTurn = false;
    int limit() => screenTurn
        ? max(toolSettings.maxSteps, toolSettings.maxScreenSteps)
        : toolSettings.maxSteps;
    while (!token.isCancelled) {
      if (rounds++ >= limit()) {
        errorCode = 'toolStepLimit';
        _limitedAt = leaf;
        _emit();
        return;
      }
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
          leaf = response.id;
          continue;
        }
        return;
      }
      final results = <ContentBlock>[];
      final seen = <String>{};
      var limited = false;
      for (final (index, call) in calls.indexed) {
        activeToolCallId = call.id;
        _emit();
        if (screenToolNames.contains(call.name) &&
            registry.get(call.name) != null) {
          screenTurn = true;
        }
        if (executed >= limit() || call.id.isEmpty || !seen.add(call.id)) {
          final code = executed >= limit() ? 'step_limit' : 'invalid_tool_call';
          limited = true;
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
            content: jsonEncode({'error': code}),
            isError: true,
          );
          await audit.finish(
            id,
            decision: code,
            resultSummary: result.content,
            isError: true,
          );
          results.add(result);
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
          executed++;
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
      if (limited || executed >= limit()) {
        errorCode = 'toolStepLimit';
        _limitedAt = resultMessage.id;
        _emit();
        return;
      }
      leaf = resultMessage.id;
    }
  }

  Future<ChatMessage?> _streamResponse(
    ProviderConfig provider,
    String parentId,
    List<ToolDefinition> definitions, {
    bool builtInWebSearch = false,
  }) async {
    _lastStopReason = null;
    final current = conversation!;
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
    final budget = ContextBudget.trim(
      systemPrompt: current.systemPrompt,
      messages: path,
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
                  vision: provider.capabilities.vision,
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
    final fingerprint = promptFingerprint(current.systemPrompt);
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
            systemPrompt: current.systemPrompt,
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
          accumulator.add(event);
          if (event is ProviderError) {
            error = event.toString();
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
    await chats.saveConversation(conversation!.copyWith(title: title.trim()));
    await _refresh();
  });

  Future<void> deleteConversation(String id) => _mutate(() async {
    await _discardScreenshots(await chats.deleteConversation(id));
    if (conversation?.id == id) await _newChat();
    conversations = await chats.listConversations();
  });

  @override
  void dispose() {
    _disposed = true;
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
