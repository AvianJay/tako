import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../core/on_device/on_device_capability.dart';
import '../../core/on_device/recommended_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Models that run on this device: system models, files and downloads.
class OnDeviceModelsScreen extends ConsumerStatefulWidget {
  const OnDeviceModelsScreen({super.key});
  @override
  ConsumerState<OnDeviceModelsScreen> createState() =>
      _OnDeviceModelsScreenState();
}

class _OnDeviceModelsScreenState extends ConsumerState<OnDeviceModelsScreen> {
  late final _app = ref.read(appControllerProvider);
  OnDeviceCapability get _models => _app.services.onDevice;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_models.refresh());
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    try {
      await action();
    } on OnDeviceException catch (error) {
      if (mounted) _say(onDeviceErrorText(error.code, l));
    } catch (_) {
      if (mounted) _say(l.operationFailed);
    }
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      await _run(() async {
        final model = await _models.importModel();
        if (model != null && mounted) {
          _say(AppLocalizations.of(context).modelAdded(model.id));
        }
      });
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _downloadFromUrl() async {
    final l = AppLocalizations.of(context);
    final url = await showDialog<Uri>(
      context: context,
      builder: (context) => const _UrlDialog(),
    );
    if (url == null) return;
    final name = url.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    await _run(() async {
      await _models.download(url, fileName: name ?? 'model.gguf');
      if (mounted) _say(l.modelDownloadStarted);
    });
  }

  Future<void> _downloadRecommended(
    RecommendedModel model, {
    required bool vision,
  }) => _run(() async {
    await _models.download(
      model.model.url,
      fileName: model.model.file,
      sha256: model.model.sha256,
      size: model.model.size,
      catalogId: model.id,
    );
    if (vision && model.projector != null) {
      await _models.download(
        model.projector!.url,
        fileName: model.projectorName,
        sha256: model.projector!.sha256,
        size: model.projector!.size,
        projectorFor: model.model.file,
      );
    }
  });

  Future<void> _use(LocalModel model) async {
    final l = AppLocalizations.of(context);
    await _run(
      () => _app.useOnDeviceModel(model, providerName: l.onDeviceModels),
    );
    if (mounted) {
      _say(l.modelSelected(model.displayName));
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _delete(LocalModel model) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.deleteModelBody(model.id)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('delete-model-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (yes == true) await _run(() => _app.deleteOnDeviceModel(model.id));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.onDeviceModels)),
      body: ListenableBuilder(
        listenable: _models,
        builder: (context, _) {
          final installed = _models.models;
          final downloads = _models.downloads;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  for (final status in _models.systemModelStatuses)
                    if (status.state != SystemModelState.ready)
                      _systemModel(status, l),
                  if (!_models.isAvailable)
                    Text(l.onDeviceUnavailable)
                  else ...[
                    Text(l.onDeviceIntro),
                    const SizedBox(height: 8),
                    Text(
                      l.onDeviceStorage(formatBytes(_models.storageBytes)),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const ValueKey('on-device-prefer-speed'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.preferSpeed),
                      subtitle: Text(l.preferSpeedHelp),
                      value: _models.preferSpeed,
                      onChanged: (value) => _run(() async {
                        await _app.saveOnDevicePreferSpeed(value);
                        if (mounted) setState(() {});
                      }),
                    ),
                    const SizedBox(height: 16),
                    Text(l.installedModels, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (installed.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(l.noLocalModels),
                      ),
                    for (final model in installed) _installed(model, l),
                    if (downloads.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(l.modelDownloads, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      for (final download in downloads) _download(download, l),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      l.recommendedModels,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.recommendedModelsHelp,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    for (final model in RecommendedModel.all)
                      _recommended(model, installed, downloads, l),
                    const SizedBox(height: 24),
                    Text(l.otherModels, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('import-model'),
                          onPressed: _importing ? null : _import,
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(
                            _importing ? l.importingModel : l.importModel,
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('download-model-url'),
                          onPressed: _downloadFromUrl,
                          icon: const Icon(Icons.link),
                          label: Text(l.downloadFromUrl),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(l.otherModelsHelp, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _systemModel(SystemModelStatus status, AppLocalizations l) {
    final preparing = status.state == SystemModelState.preparing;
    final unavailable = status.state == SystemModelState.unavailable;
    return Card(
      key: ValueKey('aicore-model-${status.model.id}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status.model.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.aicoreHelp),
            if (status.model.id == aicorePreviewModel.id) ...[
              const SizedBox(height: 8),
              Text(l.aicorePreviewHelp),
            ],
            const SizedBox(height: 8),
            if (unavailable)
              Text(l.aicoreUnavailable)
            else if (preparing) ...[
              Text(l.aicorePreparing),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ] else ...[
              if (status.error case final error?)
                Text(onDeviceErrorText(error, l)),
              FilledButton.icon(
                key: ValueKey(
                  status.model.id == aicoreModel.id
                      ? 'prepare-aicore'
                      : 'prepare-aicore-preview',
                ),
                onPressed: () => _run(
                  () => _models.prepareSystemModel(modelId: status.model.id),
                ),
                icon: const Icon(Icons.download_outlined),
                label: Text(l.aicorePrepare),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _installed(LocalModel model, AppLocalizations l) {
    final loaded = _models.loadedModel == model.id;
    return Card(
      child: ListTile(
        key: ValueKey('local-model-${model.id}'),
        contentPadding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
        leading: Icon(loaded ? Icons.memory : Icons.smartphone_outlined),
        title: Text(model.displayName),
        subtitle: Text(
          [
            model.id,
            if (model.isSystem)
              l.aicoreManaged
            else
              formatBytes(model.sizeBytes),
            if (model.profile().capabilities.tools) l.toolsCapability,
            if (model.profile().capabilities.reasoning) l.reasoningCapability,
            if (model.projector != null) l.visionCapability,
            if (loaded) l.inMemory,
          ].join(' · '),
        ),
        onTap: () => _use(model),
        trailing: PopupMenuButton<String>(
          key: ValueKey('local-model-menu-${model.id}'),
          onSelected: (action) => switch (action) {
            'use' => _use(model),
            'projector' => _run(() => _models.importProjector(model.id)),
            'no-projector' => _run(() => _models.removeProjector(model.id)),
            'unload' => _run(_models.unload),
            _ => _delete(model),
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'use', child: Text(l.useInChat)),
            if (!model.isSystem && model.projector == null)
              PopupMenuItem(value: 'projector', child: Text(l.addProjector))
            else if (!model.isSystem)
              PopupMenuItem(
                value: 'no-projector',
                child: Text(l.removeProjector),
              ),
            if (loaded)
              PopupMenuItem(value: 'unload', child: Text(l.unloadModel)),
            if (!model.isSystem)
              PopupMenuItem(value: 'delete', child: Text(l.delete)),
          ],
        ),
      ),
    );
  }

  Widget _download(ModelDownload download, AppLocalizations l) {
    final running = download.state == DownloadState.running;
    final status = switch (download.state) {
      DownloadState.running => [
        formatBytes(download.received),
        if (download.total case final total?) formatBytes(total),
      ].join(' / '),
      DownloadState.verifying => l.verifyingDownload,
      DownloadState.paused => l.downloadPaused,
      DownloadState.failed => onDeviceErrorText(download.error ?? '', l),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(download.id),
                      Text(
                        status,
                        style: download.state == DownloadState.failed
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              )
                            : Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (running)
                  IconButton(
                    tooltip: l.pauseDownload,
                    onPressed: () => _models.pauseDownload(download.id),
                    icon: const Icon(Icons.pause),
                  )
                else if (download.state != DownloadState.verifying)
                  IconButton(
                    tooltip: l.resumeDownload,
                    onPressed: () => _run(
                      () => _models.download(
                        download.url,
                        fileName: download.id,
                        size: download.total,
                        catalogId: download.catalogId,
                        projectorFor: download.projectorFor,
                        sha256: _catalogSha(download.id),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow),
                  ),
                IconButton(
                  tooltip: l.delete,
                  onPressed: () =>
                      _run(() => _models.removeDownload(download.id)),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (download.state != DownloadState.failed) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: download.state == DownloadState.verifying
                    ? null
                    : download.fraction,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A resumed recommended download is still checked against its hash.
  static String? _catalogSha(String fileName) {
    for (final model in RecommendedModel.all) {
      if (model.model.file == fileName) return model.model.sha256;
      if (model.projectorName == fileName) return model.projector?.sha256;
    }
    return null;
  }

  Widget _recommended(
    RecommendedModel model,
    List<LocalModel> installed,
    List<ModelDownload> downloads,
    AppLocalizations l,
  ) {
    final have = installed.any((m) => m.id == model.model.file);
    final busy = downloads.any((d) => d.id == model.model.file);
    final note = switch (model.use) {
      RecommendedUse.fast => l.recommendedFast,
      RecommendedUse.balanced => l.recommendedBalanced,
      RecommendedUse.best => l.recommendedBest,
      RecommendedUse.vision => l.recommendedVision,
    };
    return Card(
      child: ListTile(
        key: ValueKey('recommended-${model.id}'),
        contentPadding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
        title: Text(model.name),
        subtitle: Text(
          '$note\n${formatBytes(model.model.size)} · '
          '${l.memoryNeeded(model.memoryGb)}',
        ),
        isThreeLine: true,
        trailing: have
            ? const Icon(Icons.check)
            : PopupMenuButton<bool>(
                key: ValueKey('recommended-download-${model.id}'),
                enabled: !busy,
                tooltip: l.download,
                icon: const Icon(Icons.download),
                onSelected: (vision) =>
                    _downloadRecommended(model, vision: vision),
                itemBuilder: (context) => [
                  PopupMenuItem(value: false, child: Text(l.download)),
                  if (model.projector case final projector?)
                    PopupMenuItem(
                      value: true,
                      child: Text(
                        l.downloadWithVision(
                          formatBytes(model.model.size + projector.size),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _UrlDialog extends StatefulWidget {
  const _UrlDialog();
  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  final _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final l = AppLocalizations.of(context);
    final url = Uri.tryParse(_url.text.trim());
    if (url == null || !{'https', 'http'}.contains(url.scheme)) {
      setState(() => _error = l.invalidUrl);
      return;
    }
    Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.downloadFromUrl),
      content: TextField(
        key: const ValueKey('model-url'),
        controller: _url,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: l.modelUrl,
          helperText: l.modelUrlHelp,
          helperMaxLines: 4,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.download)),
      ],
    );
  }
}

String onDeviceErrorText(String code, AppLocalizations l) => switch (code) {
  'aicore_unavailable' => l.aicoreUnavailable,
  'aicore_update' => l.aicoreUpdate,
  'aicore_request_too_large' => l.aicoreRequestTooLarge,
  'aicore_busy' => l.aicoreBusy,
  'aicore_failed' => l.aicoreFailed,
  'aicore_text_only' => l.aicoreHelp,
  'aicore_tools_unavailable' => l.aicoreToolsUnavailable,
  'aicore_invalid_tools' => l.aicoreInvalidTools,
  'aicore_background' => l.aicoreBackground,
  'not_gguf' => l.modelErrorNotGguf,
  'is_projector' => l.modelErrorIsProjector,
  'not_projector' => l.modelErrorNotProjector,
  'exists' => l.modelErrorExists,
  'unsupported_url' => l.modelErrorUrl,
  'checksum' => l.modelErrorChecksum,
  'size' => l.modelErrorSize,
  'no_space' => l.modelErrorNoSpace,
  'network' => l.modelErrorNetwork,
  final code when code.startsWith('http_') => l.modelErrorHttp(
    code.substring(5),
  ),
  _ => l.operationFailed,
};

String formatBytes(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
    : bytes >= 1 << 20
    ? '${(bytes / (1 << 20)).toStringAsFixed(0)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';
