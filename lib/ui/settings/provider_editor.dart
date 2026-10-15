import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../core/providers/hosted_search_probe.dart';
import '../../core/providers/model_catalog.dart';
import '../../core/providers/model_names.dart';
import '../../core/providers/providers.dart';
import '../../core/util/ids.dart';
import '../../l10n/gen/app_localizations.dart';
import '../chat/tool_widgets.dart';
import 'on_device_models_screen.dart';

IconData providerIcon(ProviderConfig provider) =>
    provider.apiType == ApiType.onDevice
    ? Icons.smartphone_outlined
    : provider.isLocal
    ? Icons.dns_outlined
    : Icons.cloud_outlined;

class ProviderEditor extends ConsumerStatefulWidget {
  const ProviderEditor({super.key, this.provider});
  final ProviderConfig? provider;
  @override
  ConsumerState<ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends ConsumerState<ProviderEditor> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  late final TextEditingController _name,
      _url,
      _model,
      _key,
      _headers,
      _context,
      _output,
      _budget;
  late ApiType _type;
  late bool _autoFetchModels, _autoRouteModels;
  ApiType? _modelApiOverride;
  late ReasoningMode _reasoning;
  String _effort = 'medium';
  late bool _local, _tools, _vision, _canReason;
  ImageGenerationMode _imageGeneration = ImageGenerationMode.none;
  bool _imageReferenceInput = false;
  bool _builtInSearch = false;
  bool _allowCustomSearchEndpoint = false;
  bool _testingSearch = false;
  HostedSearchProbeResult? _searchProbeResult;
  bool _localOverride = false,
      _removeKey = false,
      _removeHeaders = false,
      _working = false;
  String? _feedback;
  bool _failed = false;
  CancelToken? _cancel;
  late final List<ModelProfile> _models;
  int _editingModel = 0;
  bool _autoDetect = true;
  bool _loadingModel = false;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _models = p == null
        ? [const ModelProfile(id: '', autoDetect: true)]
        : List.of(p.models);
    _autoDetect = _models.first.autoDetect;
    _id = p?.id ?? newId();
    _name = TextEditingController(text: p?.displayName ?? '');
    _url = TextEditingController(text: p?.baseUrl ?? 'http://127.0.0.1:8080');
    _model = TextEditingController(text: p?.model ?? '');
    _key = TextEditingController();
    _headers = TextEditingController();
    _context = TextEditingController(
      text: '${p?.capabilities.contextWindow ?? 32768}',
    );
    _output = TextEditingController(text: '${p?.maxOutputTokens ?? 4096}');
    _budget = TextEditingController(text: '${p?.thinkingBudgetTokens ?? 1024}');
    _type = p?.apiType ?? ApiType.chatCompletions;
    _autoFetchModels = p?.autoFetchModels ?? true;
    _autoRouteModels = p?.autoRouteModels ?? false;
    _reasoning = p?.reasoningMode ?? ReasoningMode.off;
    _effort = p?.reasoningEffort ?? 'medium';
    _local = p?.isLocal ?? true;
    _localOverride = p != null;
    _tools = p?.capabilities.tools ?? false;
    _vision = p?.capabilities.vision ?? false;
    _canReason = p?.capabilities.reasoning ?? false;
    _builtInSearch = p?.capabilities.builtInWebSearch ?? false;
    _allowCustomSearchEndpoint =
        p?.capabilities.allowCustomSearchEndpoint ?? false;
    _url.addListener(() {
      if (!_localOverride) {
        setState(
          () => _local = isLocalHost(Uri.tryParse(_url.text)?.host ?? ''),
        );
      }
    });
    _model.addListener(_detectModel);
    for (final field in [_url, _key, _headers]) {
      field.addListener(_invalidateSearchProbe);
    }
    _loadModel(0);
  }

  bool get _onDevice => _type == ApiType.onDevice;
  ApiType get _effectiveApi => _autoRouteModels && !_onDevice
      ? _modelApiOverride ?? modelApiType(_model.text, fallback: _type)
      : _type;

  bool get _imagesOnly =>
      _imageGeneration == ImageGenerationMode.imagesApi ||
      _imageGeneration == ImageGenerationMode.onDevice;

  /// On-device image generation belongs to a system model; it is detected,
  /// never chosen.
  bool _supportsImageMode(ImageGenerationMode mode) => switch (mode) {
    ImageGenerationMode.none => true,
    ImageGenerationMode.imagesApi =>
      _effectiveApi == ApiType.chatCompletions ||
          _effectiveApi == ApiType.responses,
    ImageGenerationMode.chatOutput => _effectiveApi == ApiType.chatCompletions,
    ImageGenerationMode.responsesTool => _effectiveApi == ApiType.responses,
    ImageGenerationMode.onDevice => _onDevice,
  };

  /// Specs of a model: for on-device models, read from the GGUF file or
  /// reported by the system.
  ModelSpec? _spec(String id) {
    if (!_onDevice) return ModelCatalog.detect(id);
    final model = ref
        .read(appControllerProvider)
        .services
        .onDevice
        .models
        .where((m) => m.id == id.trim())
        .firstOrNull;
    if (model == null) return null;
    final profile = model.profile();
    return ModelSpec(
      profile.capabilities.contextWindow!,
      profile.maxOutputTokens,
      tools: profile.capabilities.tools,
      vision: profile.capabilities.vision,
      reasoning: profile.capabilities.reasoning,
      imageGeneration: profile.capabilities.imageGeneration,
      imageReferenceInput: profile.capabilities.imageReferenceInput,
    );
  }

  void _detectModel() {
    if (_loadingModel) return;
    _searchProbeResult = null;
    if (!_autoDetect) {
      setState(() {});
      return;
    }
    final spec = _spec(_model.text);
    setState(() {
      _context.text = '${spec?.contextWindow ?? 32768}';
      _output.text = '${spec?.maxOutputTokens ?? 4096}';
      _tools = spec?.tools ?? false;
      _vision = spec?.vision ?? false;
      _canReason = spec?.reasoning ?? false;
      final imageMode = spec?.imageGeneration ?? ImageGenerationMode.none;
      _imageGeneration = _supportsImageMode(imageMode)
          ? imageMode
          : ImageGenerationMode.none;
      _imageReferenceInput = spec?.imageReferenceInput ?? false;
    });
  }

  ModelProfile _currentProfile() => ModelProfile(
    id: _model.text.trim(),
    label: _models[_editingModel].id == _model.text.trim()
        ? _models[_editingModel].label
        : null,
    apiType: _modelApiOverride,
    capabilities: ProviderCapabilities(
      tools: _tools,
      vision: _vision,
      reasoning: _canReason,
      imageGeneration: _imageGeneration,
      imageReferenceInput:
          _imageGeneration != ImageGenerationMode.none && _imageReferenceInput,
      builtInWebSearch: _builtInSearch,
      allowCustomSearchEndpoint: _allowCustomSearchEndpoint,
      contextWindow: int.tryParse(_context.text) ?? 32768,
    ),
    maxOutputTokens: int.tryParse(_output.text) ?? 4096,
    reasoningMode: _reasoning,
    thinkingBudgetTokens: int.tryParse(_budget.text) ?? 1024,
    autoDetect: _autoDetect,
    reasoningEffort: _effort,
  );

  bool _storeModel() {
    final l = AppLocalizations.of(context);
    if (!_form.currentState!.validate()) return false;
    final model = _currentProfile();
    if (_models.indexed.any(
      (entry) => entry.$1 != _editingModel && entry.$2.id == model.id,
    )) {
      setState(() {
        _feedback = l.duplicateModel;
        _failed = true;
      });
      return false;
    }
    if (!_imagesOnly &&
        (model.maxOutputTokens >= model.capabilities.contextWindow! ||
            model.reasoningMode == ReasoningMode.enabled &&
                (model.thinkingBudgetTokens < 1024 ||
                    model.thinkingBudgetTokens >= model.maxOutputTokens))) {
      setState(() {
        _feedback = l.invalidBudget;
        _failed = true;
      });
      return false;
    }
    _models[_editingModel] = model;
    return true;
  }

  void _loadModel(int index) {
    _loadingModel = true;
    final model = _models[index];
    _editingModel = index;
    _modelApiOverride = model.apiType;
    _model.text = model.id;
    _context.text = '${model.capabilities.contextWindow ?? 32768}';
    _output.text = '${model.maxOutputTokens}';
    _budget.text = '${model.thinkingBudgetTokens}';
    _reasoning = model.reasoningMode;
    _effort = model.reasoningEffort;
    _tools = model.capabilities.tools;
    _vision = model.capabilities.vision;
    _canReason = model.capabilities.reasoning;
    _imageGeneration = _supportsImageMode(model.capabilities.imageGeneration)
        ? model.capabilities.imageGeneration
        : ImageGenerationMode.none;
    _imageReferenceInput = model.capabilities.imageReferenceInput;
    _builtInSearch = model.capabilities.builtInWebSearch;
    _allowCustomSearchEndpoint = model.capabilities.allowCustomSearchEndpoint;
    _searchProbeResult = null;
    _autoDetect = model.autoDetect;
    _loadingModel = false;
  }

  void _selectModel(int index) {
    if (!_storeModel()) return;
    setState(() => _loadModel(index));
  }

  void _addModel() {
    if (!_storeModel()) return;
    setState(() {
      _models.add(const ModelProfile(id: '', autoDetect: true));
      _loadModel(_models.length - 1);
    });
  }

  @override
  void dispose() {
    _cancel?.cancel();
    for (final controller in [
      _name,
      _url,
      _model,
      _key,
      _headers,
      _context,
      _output,
      _budget,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String>? _headerValues() {
    if (_headers.text.trim().isEmpty) return null;
    final value = jsonDecode(_headers.text);
    if (value is! Map<String, dynamic> ||
        value.values.any((v) => v is! String)) {
      throw const FormatException();
    }
    final headers = value.cast<String, String>();
    if (headers.entries.any(
      (e) =>
          !RegExp(r'^[!#$%&\x27*+.^_`|~0-9A-Za-z-]+$').hasMatch(e.key) ||
          e.value.contains('\r') ||
          e.value.contains('\n'),
    )) {
      throw const FormatException();
    }
    return headers;
  }

  ModelProfile _profileForApi(ModelProfile model) {
    final api = _autoRouteModels && !_onDevice
        ? model.apiType ?? modelApiType(model.id, fallback: _type)
        : _type;
    final compatible = switch (model.capabilities.imageGeneration) {
      ImageGenerationMode.none => true,
      ImageGenerationMode.imagesApi =>
        api == ApiType.responses || api == ApiType.chatCompletions,
      ImageGenerationMode.chatOutput => api == ApiType.chatCompletions,
      ImageGenerationMode.responsesTool => api == ApiType.responses,
      ImageGenerationMode.onDevice => api == ApiType.onDevice,
    };
    if (compatible) return model;
    return ModelProfile(
      id: model.id,
      label: model.label,
      apiType: model.apiType,
      capabilities: model.capabilities.copyWith(
        imageGeneration: ImageGenerationMode.none,
        imageReferenceInput: false,
      ),
      maxOutputTokens: model.maxOutputTokens,
      reasoningMode: model.reasoningMode,
      thinkingBudgetTokens: model.thinkingBudgetTokens,
      reasoningEffort: model.reasoningEffort,
      autoDetect: model.autoDetect,
    );
  }

  ProviderConfig _config() => ProviderConfig(
    id: _id,
    displayName: _name.text.trim(),
    apiType: _type,
    autoFetchModels: _autoFetchModels,
    autoRouteModels: _autoRouteModels,
    baseUrl: _onDevice ? '' : _url.text.trim(),
    model: _model.text.trim(),
    models: _models.map(_profileForApi).toList(),
    apiKeyRef: widget.provider?.apiKeyRef,
    extraHeadersRef: widget.provider?.extraHeadersRef,
    isLocal: _local,
    capabilities: ProviderCapabilities(
      tools: _tools,
      vision: _vision,
      reasoning: _canReason,
      imageGeneration: _imageGeneration,
      imageReferenceInput:
          _imageGeneration != ImageGenerationMode.none && _imageReferenceInput,
      builtInWebSearch: _builtInSearch,
      allowCustomSearchEndpoint: _allowCustomSearchEndpoint,
      contextWindow: int.tryParse(_context.text) ?? 32768,
    ),
    maxOutputTokens: int.tryParse(_output.text) ?? 4096,
    reasoningMode: _reasoning,
    thinkingBudgetTokens: int.tryParse(_budget.text) ?? 1024,
    reasoningEffort: _effort,
  );

  Future<void> _save() async {
    if (!_storeModel()) return;
    final l = AppLocalizations.of(context);
    final config = _config();
    setState(() => _working = true);
    try {
      await ref
          .read(appControllerProvider)
          .saveProvider(
            config,
            key: _key.text.trim(),
            headers: _headers.text.trim(),
            removeKey: _removeKey,
            removeHeaders: _removeHeaders,
          );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback = l.operationFailed;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _connect({required bool pickModel}) async {
    final l = AppLocalizations.of(context);
    try {
      if (!_onDevice) {
        providerEndpoint(_url.text, 'models');
        _headerValues();
      }
    } catch (_) {
      setState(() {
        _feedback = l.invalidUrl;
        _failed = true;
      });
      return;
    }
    setState(() {
      _working = true;
      _feedback = null;
    });
    _cancel = CancelToken();
    try {
      final adapter = await ref
          .read(appControllerProvider)
          .adapterFor(
            _config(),
            temporaryKey: _key.text.trim(),
            temporaryHeaders: _onDevice ? null : _headerValues(),
            removeKey: _removeKey,
            removeHeaders: _removeHeaders,
          );
      final models = await adapter.listModels(cancel: _cancel);
      if (!mounted) return;
      setState(() {
        _working = false;
        _feedback = models.isEmpty ? l.noModels : l.connectionOk;
        _failed = false;
      });
      if (pickModel && models.isNotEmpty) {
        final selectedIds = <String>{
          for (final model in _models)
            if (model.id.isNotEmpty) model.id,
        };
        final selected = await showModalBottomSheet<Set<String>>(
          context: context,
          showDragHandle: true,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.models,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: const ValueKey('provider-model-list'),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final model = models[index];
                          return CheckboxListTile(
                            title: Text(model.displayName),
                            subtitle: model.displayName == model.id
                                ? null
                                : Text(model.id),
                            value: selectedIds.contains(model.id),
                            onChanged: (checked) => update(() {
                              if (checked == true) {
                                selectedIds.add(model.id);
                              } else {
                                selectedIds.remove(model.id);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(context, selectedIds),
                          child: Text(l.addModels),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (selected != null && mounted) {
          setState(() {
            if (_model.text.trim().isNotEmpty) {
              _models[_editingModel] = _currentProfile();
            }
            _models.removeWhere((model) => model.id.isEmpty);
            for (final id in selected) {
              if (_models.any((model) => model.id == id)) continue;
              final spec = _spec(id);
              _models.add(
                ModelProfile(
                  id: id,
                  label: models
                      .where((m) => m.id == id)
                      .firstOrNull
                      ?.displayName,
                  autoDetect: true,
                  capabilities:
                      spec?.capabilities ??
                      const ProviderCapabilities(contextWindow: 32768),
                  maxOutputTokens: spec?.maxOutputTokens ?? 4096,
                ),
              );
            }
            _loadModel(_models.length - 1);
          });
        }
      }
    } on RequestCancelled {
      /* User left the screen. */
    } on ProviderError catch (error) {
      if (mounted) {
        setState(() {
          _feedback = '${l.connectionFailed}: $error';
          _failed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _feedback = l.connectionFailed;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool get _nativeSearchProtocol =>
      _effectiveApi == ApiType.responses || _effectiveApi == ApiType.messages;

  void _invalidateSearchProbe() {
    if (_searchProbeResult != null) {
      setState(() => _searchProbeResult = null);
    }
  }

  Future<void> _probeSearch() async {
    if (!_nativeSearchProtocol || !_storeModel()) return;
    final l = AppLocalizations.of(context);
    Map<String, String>? headers;
    try {
      headers = _headerValues();
    } catch (_) {
      setState(() {
        _feedback = l.operationFailed;
        _failed = true;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    final token = _cancel = CancelToken();
    setState(() {
      _working = true;
      _testingSearch = true;
      _searchProbeResult = null;
    });
    try {
      final result = await ref
          .read(appControllerProvider)
          .probeHostedSearch(
            _config(),
            temporaryKey: _key.text.trim(),
            temporaryHeaders: headers,
            removeKey: _removeKey,
            removeHeaders: _removeHeaders,
            cancel: token,
          );
      if (mounted) setState(() => _searchProbeResult = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _searchProbeResult = const HostedSearchProbeResult(
            HostedSearchProbeStatus.failed,
          ),
        );
      }
    } finally {
      _cancel = null;
      if (mounted) {
        setState(() {
          _working = false;
          _testingSearch = false;
        });
      }
    }
  }

  String _probeResultText(HostedSearchProbeResult result, AppLocalizations l) {
    final label = switch (result.status) {
      HostedSearchProbeStatus.supported => l.nativeSearchSupported,
      HostedSearchProbeStatus.notObserved => l.nativeSearchNotObserved,
      HostedSearchProbeStatus.unsupportedProtocol => l.nativeSearchProtocolHelp,
      HostedSearchProbeStatus.disabled => l.nativeSearchDisabled,
      HostedSearchProbeStatus.denied => l.nativeSearchDenied,
      HostedSearchProbeStatus.failed => l.nativeSearchFailed,
      HostedSearchProbeStatus.cancelled => l.nativeSearchCancelled,
      HostedSearchProbeStatus.timedOut => l.nativeSearchTimeout,
      HostedSearchProbeStatus.busy => l.nativeSearchBusy,
    };
    return result.statusCode == null
        ? label
        : '$label (HTTP ${result.statusCode})';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pending = ref.watch(
      appControllerProvider.select((app) => app.pendingApproval),
    );
    final appBusy = ref.watch(appControllerProvider.select((app) => app.busy));
    String? requiredValue(String? value) =>
        value?.trim().isEmpty != false ? l.requiredField : null;
    String? positive(String? value) =>
        (int.tryParse(value ?? '') ?? 0) <= 0 ? l.invalidNumber : null;
    Widget field(
      TextEditingController controller,
      String label, {
      String? hint,
      bool secret = false,
      String? Function(String?)? validate,
      TextInputType? keyboardType,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: !_working,
        obscureText: secret,
        autocorrect: !secret,
        enableSuggestions: !secret,
        keyboardType: keyboardType,
        validator: validate,
        onChanged: controller == _context || controller == _output
            ? (_) => setState(() => _autoDetect = false)
            : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 3,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.provider == null ? l.addProvider : l.editProvider),
        actions: [
          if (_testingSearch)
            TextButton(
              key: const ValueKey('provider-probe-cancel'),
              onPressed: () => _cancel?.cancel(),
              child: Text(l.cancel),
            ),
        ],
      ),
      bottomSheet: _testingSearch && pending != null
          ? SafeArea(
              top: false,
              child: ToolApprovalSheet(app: ref.read(appControllerProvider)),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                field(_name, l.providerName, validate: requiredValue),
                DropdownButtonFormField<ApiType>(
                  isExpanded: true,
                  initialValue: _type,
                  decoration: InputDecoration(labelText: l.apiType),
                  items: [
                    const DropdownMenuItem(
                      value: ApiType.chatCompletions,
                      child: Text('OpenAI Chat Completions'),
                    ),
                    const DropdownMenuItem(
                      value: ApiType.responses,
                      child: Text('OpenAI Responses'),
                    ),
                    const DropdownMenuItem(
                      value: ApiType.messages,
                      child: Text('Anthropic Messages'),
                    ),
                    if (_onDevice ||
                        ref
                            .read(appControllerProvider)
                            .services
                            .onDevice
                            .isAvailable)
                      DropdownMenuItem(
                        value: ApiType.onDevice,
                        child: Text(l.onDeviceApi),
                      ),
                  ],
                  onChanged: _working
                      ? null
                      : (value) => setState(() {
                          _type = value!;
                          _searchProbeResult = null;
                          if (!_supportsImageMode(_imageGeneration)) {
                            _imageGeneration = ImageGenerationMode.none;
                            _imageReferenceInput = false;
                          }
                          if (_onDevice) {
                            _builtInSearch = false;
                            _allowCustomSearchEndpoint = false;
                          }
                        }),
                ),
                const SizedBox(height: 16),
                if (_autoRouteModels && !_onDevice) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('provider-model-api-$_editingModel'),
                    initialValue: _modelApiOverride?.name ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText:
                          Localizations.localeOf(context).languageCode == 'zh'
                          ? '此模型的 API'
                          : 'API for this model',
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Automatic')),
                      DropdownMenuItem(
                        value: 'messages',
                        child: Text('Anthropic Messages'),
                      ),
                      DropdownMenuItem(
                        value: 'responses',
                        child: Text('OpenAI Responses'),
                      ),
                      DropdownMenuItem(
                        value: 'chatCompletions',
                        child: Text('OpenAI Chat Completions'),
                      ),
                    ],
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _modelApiOverride = ApiType.values
                                .where((a) => a.name == v)
                                .firstOrNull;
                            _searchProbeResult = null;
                          }),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_onDevice)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(l.onDeviceProviderHelp),
                  ),
                if (!_onDevice) ...[
                  SwitchListTile(
                    key: const ValueKey('provider-auto-fetch-models'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '自動取得模型清單'
                          : 'Fetch models automatically',
                    ),
                    subtitle: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '啟動、儲存與開啟選單時更新；保留模型設定。'
                          : 'Refresh on startup, save and model selection; keep model settings.',
                    ),
                    value: _autoFetchModels,
                    onChanged: _working
                        ? null
                        : (v) => setState(() => _autoFetchModels = v),
                  ),
                  SwitchListTile(
                    key: const ValueKey('provider-auto-route-models'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? 'CPA / 多 API 代理'
                          : 'CPA / multi-API proxy',
                    ),
                    subtitle: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? 'Claude 使用 Messages，GPT 使用 Responses，其他模型使用相容 API。'
                          : 'Route Claude through Messages, GPT through Responses, and other models through compatible APIs.',
                    ),
                    value: _autoRouteModels,
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _autoRouteModels = v;
                            _searchProbeResult = null;
                          }),
                  ),
                  field(
                    _url,
                    l.baseUrl,
                    keyboardType: TextInputType.url,
                    validate: (value) {
                      try {
                        providerEndpoint(value ?? '', 'models');
                        return null;
                      } catch (_) {
                        return l.invalidUrl;
                      }
                    },
                  ),
                  field(
                    _key,
                    l.apiKey,
                    secret: true,
                    hint: widget.provider?.apiKeyRef == null
                        ? l.keyHint
                        : l.keyStored,
                  ),
                ],
                if (!_onDevice && widget.provider?.apiKeyRef != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.removeKey),
                    value: _removeKey,
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _removeKey = v!;
                            _searchProbeResult = null;
                          }),
                  ),
                const Divider(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.models,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _working ? null : _addModel,
                      icon: const Icon(Icons.add),
                      label: Text(l.addModel),
                    ),
                  ],
                ),
                if (_models.length > 6)
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      'provider-edit-model-$_editingModel-${_models.length}',
                    ),
                    initialValue: _editingModel,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.model),
                    items: [
                      for (final entry in _models.indexed)
                        DropdownMenuItem(
                          value: entry.$1,
                          child: Text(
                            entry.$2.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _working
                        ? null
                        : (value) => _selectModel(value!),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final entry in _models.indexed)
                        InputChip(
                          label: Text(
                            entry.$1 == _editingModel
                                ? (_model.text.isEmpty
                                      ? l.newModel
                                      : modelDisplayName(_model.text))
                                : entry.$2.displayName,
                          ),
                          selected: entry.$1 == _editingModel,
                          onPressed: _working || entry.$1 == _editingModel
                              ? null
                              : () => _selectModel(entry.$1),
                          onDeleted: _working || _models.length == 1
                              ? null
                              : () {
                                  if (entry.$1 != _editingModel &&
                                      !_storeModel()) {
                                    return;
                                  }
                                  setState(() {
                                    final previous = _editingModel;
                                    _models.removeAt(entry.$1);
                                    _loadModel(
                                      entry.$1 == previous
                                          ? 0
                                          : previous -
                                                (entry.$1 < previous ? 1 : 0),
                                    );
                                  });
                                },
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                field(
                  _model,
                  l.model,
                  hint: l.modelHint,
                  validate: requiredValue,
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _working
                          ? null
                          : () => _connect(pickModel: true),
                      icon: const Icon(Icons.list_alt),
                      label: Text(l.loadModels),
                    ),
                    if (_onDevice)
                      TextButton.icon(
                        key: const ValueKey('manage-on-device-models'),
                        onPressed: _working
                            ? null
                            : () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const OnDeviceModelsScreen(),
                                ),
                              ),
                        icon: const Icon(Icons.memory),
                        label: Text(l.manageOnDeviceModels),
                      )
                    else
                      TextButton.icon(
                        onPressed: _working
                            ? null
                            : () => _connect(pickModel: false),
                        icon: const Icon(Icons.network_check),
                        label: Text(l.testConnection),
                      ),
                  ],
                ),
                if (_onDevice)
                  const SizedBox(height: 12)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      l.connectionHelp,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_working) const LinearProgressIndicator(),
                if (_feedback != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _feedback!,
                      style: TextStyle(
                        color: _failed
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                if (!_onDevice) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.localProvider),
                    subtitle: Text(l.localDescription),
                    value: _local,
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _local = v;
                            _localOverride = true;
                          }),
                  ),
                  const SizedBox(height: 16),
                  field(
                    _headers,
                    l.extraHeaders,
                    secret: true,
                    hint: widget.provider?.extraHeadersRef == null
                        ? l.headersHint
                        : l.headersStored,
                    validate: (_) {
                      try {
                        _headerValues();
                        return null;
                      } catch (_) {
                        return l.invalidJson;
                      }
                    },
                  ),
                ],
                if (!_onDevice && widget.provider?.extraHeadersRef != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.removeHeaders),
                    value: _removeHeaders,
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _removeHeaders = v!;
                            _searchProbeResult = null;
                          }),
                  ),
                const Divider(height: 32),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.autoModelSpecs),
                  subtitle: Text(
                    _spec(_model.text) == null
                        ? l.unknownModelSpecs
                        : l.knownModelSpecs,
                  ),
                  value: _autoDetect,
                  onChanged: _working
                      ? null
                      : (value) {
                          setState(() => _autoDetect = value);
                          if (value) _detectModel();
                        },
                ),
                if (_spec(_model.text)?.officialId case final officialId?)
                  if (officialId != _model.text.trim())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${l.officialModelId}: $officialId',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                if (!_onDevice && !_imagesOnly)
                  SwitchListTile(
                    key: const ValueKey('provider-native-search'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.builtInSearch),
                    subtitle: Text(
                      _nativeSearchProtocol
                          ? l.builtInSearchHelp
                          : l.nativeSearchProtocolHelp,
                    ),
                    value: _nativeSearchProtocol && _builtInSearch,
                    onChanged: _working || !_nativeSearchProtocol
                        ? null
                        : (v) => setState(() {
                            _builtInSearch = v;
                            if (v) _tools = true;
                          }),
                  ),
                if (_nativeSearchProtocol && !_imagesOnly) ...[
                  SwitchListTile(
                    key: const ValueKey('provider-custom-search-endpoint'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.allowCustomSearchEndpoint),
                    subtitle: Text(l.allowCustomSearchEndpointHelp),
                    value: _allowCustomSearchEndpoint,
                    onChanged: _working || !_builtInSearch
                        ? null
                        : (value) => setState(
                            () => _allowCustomSearchEndpoint = value,
                          ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const ValueKey('provider-probe-search'),
                      onPressed: _working || appBusy ? null : _probeSearch,
                      icon: const Icon(Icons.travel_explore),
                      label: Text(
                        _testingSearch
                            ? l.nativeSearchTesting
                            : l.testNativeSearch,
                      ),
                    ),
                  ),
                  Text(
                    l.nativeSearchTestHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_searchProbeResult case final result?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _probeResultText(result, l),
                        key: const ValueKey('provider-probe-result'),
                        style: TextStyle(
                          color:
                              result.status == HostedSearchProbeStatus.supported
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                Text(
                  l.capabilities,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!_onDevice) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ImageGenerationMode>(
                    key: ValueKey(
                      'provider-image-mode-$_editingModel-${_type.name}-${_imageGeneration.name}',
                    ),
                    isExpanded: true,
                    initialValue: _imageGeneration,
                    decoration: InputDecoration(labelText: l.imageGeneration),
                    items: [
                      for (final mode in ImageGenerationMode.values)
                        if (_supportsImageMode(mode))
                          DropdownMenuItem(
                            value: mode,
                            child: Text(switch (mode) {
                              ImageGenerationMode.none => l.imageGenerationNone,
                              ImageGenerationMode.imagesApi =>
                                l.imageGenerationImagesApi,
                              ImageGenerationMode.chatOutput =>
                                l.imageGenerationChatOutput,
                              ImageGenerationMode.responsesTool =>
                                l.imageGenerationResponsesTool,
                              ImageGenerationMode.onDevice =>
                                l.imageGenerationOnDevice,
                            }),
                          ),
                    ],
                    onChanged: _working || _type == ApiType.messages
                        ? null
                        : (value) => setState(() {
                            _imageGeneration = value!;
                            _autoDetect = false;
                          }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _type == ApiType.messages
                        ? l.imageGenerationProtocolHelp
                        : l.imageGenerationHelp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_imageGeneration != ImageGenerationMode.none)
                    SwitchListTile(
                      key: const ValueKey('provider-image-reference'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.imageReferenceInput),
                      subtitle: Text(l.imageReferenceInputHelp),
                      value: _imageReferenceInput,
                      onChanged: _working
                          ? null
                          : (value) => setState(() {
                              _imageReferenceInput = value;
                              _autoDetect = false;
                            }),
                    ),
                  const SizedBox(height: 16),
                ],
                if (!_imagesOnly) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.toolsCapability),
                    value: _tools,
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _tools = v;
                            _autoDetect = false;
                          }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.visionCapability),
                    subtitle: Text(l.visionCapabilityHelp),
                    value: _vision,
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _vision = v;
                            _autoDetect = false;
                          }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.reasoningCapability),
                    value: _canReason,
                    onChanged: _working
                        ? null
                        : (v) => setState(() {
                            _canReason = v;
                            _autoDetect = false;
                          }),
                  ),
                  const SizedBox(height: 16),
                  field(
                    _context,
                    l.contextWindow,
                    validate: positive,
                    keyboardType: TextInputType.number,
                  ),
                  field(
                    _output,
                    l.maxOutput,
                    validate: positive,
                    keyboardType: TextInputType.number,
                  ),
                  DropdownButtonFormField<ReasoningMode>(
                    key: ValueKey(
                      'reasoning-$_editingModel-${_models[_editingModel].id}',
                    ),
                    isExpanded: true,
                    initialValue: _reasoning,
                    decoration: InputDecoration(labelText: l.reasoningMode),
                    items: [
                      DropdownMenuItem(
                        value: ReasoningMode.off,
                        child: Text(l.reasoningOff),
                      ),
                      DropdownMenuItem(
                        value: ReasoningMode.enabled,
                        child: Text(l.reasoningEnabled),
                      ),
                      DropdownMenuItem(
                        value: ReasoningMode.adaptive,
                        child: Text(l.reasoningAdaptive),
                      ),
                    ],
                    onChanged: _working
                        ? null
                        : (v) => setState(() => _reasoning = v!),
                  ),
                  const SizedBox(height: 16),
                  if (_reasoning == ReasoningMode.enabled)
                    field(
                      _budget,
                      l.thinkingBudget,
                      validate: positive,
                      keyboardType: TextInputType.number,
                    ),
                  if (_reasoning != ReasoningMode.off) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('effort-$_editingModel'),
                      isExpanded: true,
                      initialValue: _effort,
                      decoration: InputDecoration(labelText: l.reasoningEffort),
                      items: [
                        for (final effort in {
                          'low',
                          'medium',
                          'high',
                          'xhigh',
                          'max',
                          _effort,
                        })
                          DropdownMenuItem(
                            value: effort,
                            child: Text(
                              effort == 'xhigh' ? 'Extra (xhigh)' : effort,
                            ),
                          ),
                      ],
                      onChanged: _working
                          ? null
                          : (value) => setState(() => _effort = value!),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                FilledButton(
                  onPressed: _working ? null : _save,
                  child: Text(l.save),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
