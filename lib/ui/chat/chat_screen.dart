import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as md;

import '../../app/app_controller.dart';
import '../../app/app_info.dart';
import '../../core/browser/browser_capability.dart';
import '../../core/chat/content_block.dart';
import '../../core/chat/message.dart';
import '../../core/on_device/on_device_capability.dart';
import '../../l10n/gen/app_localizations.dart';
import '../brand/tako_mark.dart';
import '../browser/browser_screen.dart';
import '../render/message_markdown.dart';
import '../settings/on_device_models_screen.dart';
import '../settings/provider_editor.dart';
import '../settings/settings_screen.dart';
import 'chat_timeline.dart';
import 'draft_attachment_strip.dart';
import 'memory_chip.dart';
import 'message_image.dart';
import 'thinking_section.dart';
import 'tool_run_widgets.dart';
import 'tool_widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  String _renderStamp = '';
  late final BrowserCapability _browser = ref
      .read(appControllerProvider)
      .services
      .browser;

  @override
  void initState() {
    super.initState();
    // The model acts only on a visible browser, so the user can watch it.
    _browser.onRequestOpen = _showBrowserForModel;
  }

  @override
  void dispose() {
    if (_browser.onRequestOpen == _showBrowserForModel) {
      _browser.onRequestOpen = null;
    }
    _composer.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _showBrowserForModel() {
    if (!mounted || _browser.viewMounted) return;
    _focus.unfocus();
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const BrowserScreen(openedForModel: true),
        ),
      ),
    );
  }

  Future<void> _openLink(AppController app, Uri uri) => _run(() async {
    if (app.opensLinksInApp && isBrowserUrl(uri.toString())) {
      await openBrowserScreen(context, app, url: uri.toString());
    } else {
      await app.services.openLink(uri);
    }
  });

  Future<void> _run(Future<void> Function() action, {String? failure}) async {
    final l = AppLocalizations.of(context);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure ?? l.operationFailed)));
      }
    }
  }

  void _insertKeyboardImage(KeyboardInsertedContent content) {
    final app = ref.read(appControllerProvider);
    final l = AppLocalizations.of(context);
    if (app.busy) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.attachmentBusy)));
      return;
    }
    _run(
      () => app.insertKeyboardImage(
        mimeType: content.mimeType,
        uri: content.uri,
        bytes: content.data,
      ),
      failure: l.imageUnavailable,
    );
  }

  Widget _attachmentMenu(AppController app, AppLocalizations l) {
    final entries = <(IconData, String, Future<void> Function())>[
      if (app.canCapturePhoto)
        (Icons.camera_alt_outlined, l.camera, app.capturePhoto),
      if (app.canAttachPhotos)
        (Icons.photo_library_outlined, l.photos, app.importPhotos),
      (Icons.attach_file_rounded, l.files, app.importAttachments),
    ];
    final rowHeight = math.max(
      64.0,
      MediaQuery.textScalerOf(context).scale(18) + 28,
    );
    return TextFieldTapRegion(
      child: MenuAnchor(
        // Keep every option above the composer, including while the IME is open.
        alignmentOffset: Offset(0, -(entries.length * rowHeight + 24)),
        style: MenuStyle(
          alignment: AlignmentDirectional.topStart,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 8),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
        menuChildren: [
          for (final (icon, label, action) in entries)
            MenuItemButton(
              style: ButtonStyle(
                fixedSize: WidgetStatePropertyAll(Size(230, rowHeight)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
              leadingIcon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24),
              ),
              onPressed: app.busy
                  ? null
                  : () => _run(action, failure: l.importFailed),
              child: Text(label),
            ),
        ],
        builder: (context, controller, child) => IconButton(
          tooltip: l.attach,
          icon: const Icon(Icons.add_rounded, size: 28),
          style: const ButtonStyle(
            fixedSize: WidgetStatePropertyAll(Size(48, 48)),
          ),
          onPressed: app.busy
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }

  Widget _composerPanel(AppController app, AppLocalizations l) {
    final media = MediaQuery.of(context);
    final color = Theme.of(context).colorScheme;
    final usableHeight =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.vertical -
        kToolbarHeight;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: media.viewInsets.bottom > 0 ? 6 : 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextFieldTapRegion(
              child: AnimatedSize(
                duration: media.disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: Container(
                  key: const ValueKey('chat-composer'),
                  constraints: BoxConstraints(
                    maxHeight: (usableHeight - 24).clamp(100.0, 360.0),
                  ),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.surfaceContainer,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: color.outlineVariant.withValues(alpha: .6),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (app.draftAttachments.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: DraftAttachmentStrip(
                                    key: const ValueKey('draft-attachments'),
                                    attachments: app.draftAttachments,
                                    services: app.services,
                                    enabled: !app.busy,
                                    onRemove: app.removeAttachment,
                                    onPreview: (image) => _image(image.path),
                                  ),
                                ),
                              TextField(
                                key: const ValueKey('composer-text'),
                                controller: _composer,
                                focusNode: _focus,
                                minLines: 1,
                                maxLines: 6,
                                enabled: app.providers.isNotEmpty,
                                keyboardType: TextInputType.multiline,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.copyWith(height: 1.4),
                                contentInsertionConfiguration:
                                    app.canInsertKeyboardImage
                                    ? ContentInsertionConfiguration(
                                        allowedMimeTypes: const [
                                          'image/png',
                                          'image/jpeg',
                                          'image/gif',
                                          'image/webp',
                                        ],
                                        onContentInserted: _insertKeyboardImage,
                                      )
                                    : null,
                                decoration: InputDecoration(
                                  hintText: l.messageHint,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        key: const ValueKey('composer-actions'),
                        children: [
                          _attachmentMenu(app, l),
                          const Spacer(),
                          if (app.busy)
                            IconButton.filled(
                              tooltip: l.stop,
                              onPressed: app.stop,
                              icon: const Icon(Icons.stop_rounded),
                            )
                          else
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _composer,
                              builder: (context, value, child) =>
                                  IconButton.filled(
                                    tooltip: l.send,
                                    onPressed:
                                        app.selectedProvider == null ||
                                            (value.text.trim().isEmpty &&
                                                app.draftAttachments.isEmpty)
                                        ? null
                                        : _send,
                                    icon: const Icon(
                                      Icons.arrow_upward_rounded,
                                    ),
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _send() {
    final app = ref.read(appControllerProvider);
    final value = _composer.text;
    if (value.trim().isEmpty &&
        ref.read(appControllerProvider).draftAttachments.isEmpty) {
      return;
    }
    _composer.clear();
    _focus.requestFocus();
    final userIds = {
      for (final message in app.messages)
        if (message.role == MessageRole.user) message.id,
    };
    _run(() async {
      await app.send(value);
      if (mounted &&
          app.errorCode != null &&
          _composer.text.isEmpty &&
          !app.messages.any(
            (m) => m.role == MessageRole.user && !userIds.contains(m.id),
          )) {
        _composer.text = value;
      }
    });
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final l = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _editText(
    String title,
    String initial, {
    bool multiline = true,
  }) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 10 : 1,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l.save),
          ),
        ],
      ),
    );
    // The dialog's closing animation can still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    return value;
  }

  Future<void> _chooseProvider() async {
    final app = ref.read(appControllerProvider);
    final l = AppLocalizations.of(context);
    if (app.providers.isEmpty) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const ProviderEditor()),
      );
      return;
    }
    final id = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                l.chooseModel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final p in app.providers)
              for (final model in p.models)
                ListTile(
                  leading: Icon(
                    p.forModel(model.id).generatesImages
                        ? Icons.image_outlined
                        : providerIcon(p),
                  ),
                  title: Text(model.id),
                  subtitle: app.providers.length > 1
                      ? Text(p.displayName)
                      : null,
                  trailing:
                      p.id == app.selectedProvider?.id &&
                          model.id == app.selectedProvider?.model
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, (p.id, model.id)),
                ),
          ],
        ),
      ),
    );
    if (id == null ||
        !mounted ||
        id.$1 == app.selectedProvider?.id &&
            id.$2 == app.selectedProvider?.model) {
      return;
    }
    if (app.conversation != null &&
        id.$1 != app.selectedProvider?.id &&
        !await _confirm(
          l.changeProvider,
          l.changeProviderBody,
          l.continueAction,
        )) {
      return;
    }
    await _run(() => app.selectProvider(id.$1, model: id.$2));
  }

  Future<void> _copy(String value) async {
    await ref.read(appControllerProvider).services.copyText(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).copied),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  String _plainText(String value) => md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(value.split('\n')).map((node) => node.textContent).join('\n');

  Future<void> _messageActions(ChatMessage message) async {
    final app = ref.read(appControllerProvider);
    final l = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in <(String, IconData, String)>[
                ('copy', Icons.copy_outlined, l.copy),
                ('markdown', Icons.code, l.copyMarkdown),
                ('select', Icons.text_fields, l.selectText),
                ('share', Icons.ios_share, l.share),
                if (!app.busy && message.role == MessageRole.user)
                  ('edit', Icons.edit_outlined, l.edit),
                if (!app.busy && message.role == MessageRole.assistant)
                  ('regenerate', Icons.refresh, l.regenerate),
                if (!app.busy) ('rewind', Icons.history, l.rewind),
                if (!app.busy)
                  ('deleteAfter', Icons.delete_sweep_outlined, l.rewindDelete),
                if (message.contextEnvelope != null)
                  ('context', Icons.data_object, l.developerContext),
              ])
                ListTile(
                  leading: Icon(item.$2),
                  title: Text(item.$3),
                  onTap: () => Navigator.pop(context, item.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'copy':
        await _run(() => _copy(_plainText(message.text)));
      case 'markdown':
        await _run(() => _copy(message.text));
      case 'share':
        await _run(() => app.services.shareText(message.text));
      case 'select':
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.selectText),
            content: SingleChildScrollView(child: SelectableText(message.text)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.close),
              ),
            ],
          ),
        );
      case 'context':
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.developerContext),
            content: SelectableText(message.contextEnvelope!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.close),
              ),
            ],
          ),
        );
      case 'edit':
        final text = await _editText(l.edit, message.text);
        if (text != null && text.trim().isNotEmpty) {
          await _run(() => app.send(text, editing: message));
        }
      case 'regenerate':
        await _run(() => app.regenerate(message));
      case 'rewind':
        await _rewind(message);
      case 'deleteAfter':
        if (await _confirm(l.rewindDelete, l.rewindDeleteBody, l.delete)) {
          await _rewind(message, deleteAfter: true);
        }
    }
  }

  Future<void> _rewind(ChatMessage message, {bool deleteAfter = false}) async {
    final app = ref.read(appControllerProvider);
    final l = AppLocalizations.of(context);
    final effects = app.sideEffectsAfter(message);
    if (effects.isNotEmpty) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.sideEffectsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(l.sideEffectsBody),
                  for (final effect in effects)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(effect.summary),
                      subtitle: Text(
                        effect.memoryUndo != null
                            ? l.memorySaved
                            : effect.backupPath ?? l.noBackup,
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l.cancel),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, 'rewind'),
                        child: Text(l.rewindOnly),
                      ),
                      if (effects.any(
                        (e) => e.backupPath != null || e.memoryUndo != null,
                      ))
                        FilledButton(
                          onPressed: () => Navigator.pop(context, 'restore'),
                          child: Text(l.restoreAndRewind),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (choice == null) return;
      if (choice == 'restore') {
        try {
          await app.restoreSideEffects(effects);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.restoreFailed)));
          }
          return;
        }
      }
    }
    await _run(() => app.rewind(message, deleteAfter: deleteAfter));
  }

  Future<void> _image(String source) async {
    final l = AppLocalizations.of(context);
    final services = ref.read(appControllerProvider).services;
    final uri = Uri.tryParse(source);
    if (uri?.scheme == 'https') {
      await _run(() => services.openLink(uri!));
      return;
    }
    await _run(() async {
      final bytes = await services.readWorkspaceImage(source);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(l.image),
              actions: [
                IconButton(
                  tooltip: l.imageReferenceInput,
                  onPressed: ref.read(appControllerProvider).busy
                      ? null
                      : () => _run(() async {
                          await ref
                              .read(appControllerProvider)
                              .attachWorkspaceImage(source);
                          if (context.mounted) Navigator.pop(context);
                        }),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
                IconButton(
                  tooltip: l.share,
                  onPressed: () =>
                      _run(() => services.shareWorkspaceFile(source)),
                  icon: const Icon(Icons.ios_share),
                ),
              ],
            ),
            body: Center(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, error, stack) => Text(l.fileUnavailable),
                ),
              ),
            ),
          ),
        ),
      );
    }, failure: l.fileUnavailable);
  }

  String _error(String? code, AppLocalizations l) => switch (code) {
    'contextTooLarge' => l.contextTooLarge,
    'visionRequired' => l.visionRequired,
    'attachmentLimit' => l.attachmentLimit,
    'imageUnavailable' => l.imageUnavailable,
    'unsupportedImage' => l.unsupportedImage,
    'toolStepLimit' => l.toolStepLimit,
    'localModelMissing' => l.localModelMissing,
    'localModelLoad' => l.localModelLoad,
    'aicoreUnavailable' => l.aicoreUnavailable,
    'aicoreUpdate' => l.aicoreUpdate,
    'aicoreRequestTooLarge' => l.aicoreRequestTooLarge,
    'aicoreBusy' => l.aicoreBusy,
    'aicoreFailed' => l.aicoreFailed,
    'aicoreHelp' => l.aicoreHelp,
    'aicoreToolsUnavailable' => l.aicoreToolsUnavailable,
    'aicoreInvalidTools' => l.aicoreInvalidTools,
    'aicoreBackground' => l.aicoreBackground,
    'modelErrorNoSpace' => l.modelErrorNoSpace,
    'noProviderSelected' => l.noProviderSelected,
    'providerRemoved' => l.providerRemoved,
    'emptyResponse' => l.emptyResponse,
    'toolsLater' => l.toolsLater,
    'operationFailed' => l.operationFailed,
    _ => code ?? l.operationFailed,
  };

  Widget _history(
    AppController app,
    AppLocalizations l, {
    bool drawer = false,
  }) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 20, 18),
          child: Row(
            children: [
              TakoMark(color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(kAppName, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (drawer)
                IconButton(
                  tooltip: l.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.tonalIcon(
            onPressed: app.busy
                ? null
                : () async {
                    if (drawer) Navigator.pop(context);
                    await _run(app.newChat);
                  },
            icon: const Icon(Icons.add),
            label: Text(l.newChat),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(l.chats, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: app.conversations.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l.noChats,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final chat in app.conversations)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          selected: chat.id == app.conversation?.id,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormat.MMMd(
                              l.localeName,
                            ).format(chat.updatedAt.toLocal()),
                          ),
                          onTap: app.busy
                              ? null
                              : () async {
                                  if (drawer) Navigator.pop(context);
                                  await _run(
                                    () => app.openConversation(chat.id),
                                  );
                                },
                          trailing: IconButton(
                            tooltip: l.delete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: app.busy
                                ? null
                                : () async {
                                    if (await _confirm(
                                      l.delete,
                                      l.deleteChatBody,
                                      l.delete,
                                    )) {
                                      await _run(
                                        () => app.deleteConversation(chat.id),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(l.settings),
          onTap: () async {
            if (drawer) Navigator.pop(context);
            await Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 13),
              const SizedBox(width: 6),
              Text(l.privacy, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    ),
  );

  void _openToolAttachment(ContentBlock block) {
    if (block is ImageBlock) {
      _image(block.path);
    } else if (block is FileBlock) {
      _run(
        () => ref
            .read(appControllerProvider)
            .services
            .shareWorkspaceFile(block.path),
        failure: AppLocalizations.of(context).fileUnavailable,
      );
    }
  }

  Widget _messageContent(
    ChatMessage message,
    List<ContentBlock> blocks,
    AppController app,
    AppLocalizations l, {
    required String identity,
  }) {
    final children = <Widget>[];
    final thinking = blocks
        .whereType<ReasoningBlock>()
        .map((b) => b.text)
        .join('\n');
    if (thinking.isNotEmpty) {
      children.add(
        ThinkingSection(
          key: ValueKey('thinking-$identity'),
          text: thinking,
          label: l.thinking,
          hasAnswer: blocks.whereType<TextBlock>().any(
            (b) => b.text.isNotEmpty,
          ),
        ),
      );
    }
    var text = '';
    var part = 0;
    void flushText() {
      if (text.isEmpty) return;
      children.add(
        MessageMarkdown(
          key: ValueKey('message-text-$identity-${part++}'),
          data: text,
          isStreaming: message.status == MessageStatus.streaming,
          copyLabel: l.copy,
          imageLabel: l.image,
          fileLabel: l.file,
          onCopy: (value) => _run(() => _copy(value)),
          onLink: (uri) => _openLink(app, uri),
          onFile: (path) => _run(
            () => app.services.shareWorkspaceFile(path),
            failure: l.fileUnavailable,
          ),
          onImage: _image,
        ),
      );
      text = '';
    }

    for (final block in blocks) {
      if (block is TextBlock) {
        text += block.text;
      } else if (block is ImageBlock) {
        flushText();
        children.add(
          message.role != MessageRole.user && !block.path.startsWith('https:')
              ? MessageImage(
                  key: ValueKey('message-image-${block.path}'),
                  image: block,
                  services: app.services,
                  onOpen: () => _image(block.path),
                )
              : ActionChip(
                  avatar: const Icon(Icons.image_outlined),
                  label: Text(block.alt ?? l.image),
                  onPressed: () => _image(block.path),
                ),
        );
      } else if (block is FileBlock) {
        flushText();
        children.add(
          ActionChip(
            avatar: const Icon(Icons.description_outlined),
            label: Text(block.name),
            onPressed: () => _run(
              () => app.services.shareWorkspaceFile(block.path),
              failure: l.fileUnavailable,
            ),
          ),
        );
      }
    }
    flushText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  OnDeviceCapability get _onDevice =>
      ref.read(appControllerProvider).services.onDevice;

  Widget _messageState(
    ChatMessage message,
    AppLocalizations l, {
    bool showStreaming = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showStreaming && message.status == MessageStatus.streaming)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: _onDevice,
                builder: (context, _) => Text(
                  _onDevice.loadingModel == null ? l.streaming : l.loadingModel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      if (message.status == MessageStatus.stopped)
        Text(
          l.stopped,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      if (message.status == MessageStatus.error)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _error(message.error, l),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  Widget _messageMetadata(
    ChatMessage message,
    AppController app,
    AppLocalizations l,
  ) {
    final color = Theme.of(context).colorScheme;
    final siblings = app.tree.siblingsOf(message.id);
    final branch = siblings.indexWhere((m) => m.id == message.id);
    return Wrap(
      key: ValueKey('message-metadata-${message.id}'),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          DateFormat.Hm(l.localeName).format(message.wallTime),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: color.outline),
        ),
        const SizedBox(width: 8),
        if (siblings.length > 1) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l.previousBranch,
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: app.busy || branch <= 0
                ? null
                : () => _run(() => app.switchBranch(siblings[branch - 1])),
          ),
          Text(
            '${branch + 1}/${siblings.length}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l.nextBranch,
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: app.busy || branch >= siblings.length - 1
                ? null
                : () => _run(() => app.switchBranch(siblings[branch + 1])),
          ),
        ],
        if (message.status == MessageStatus.error ||
            message.status == MessageStatus.stopped)
          TextButton.icon(
            onPressed: app.busy
                ? null
                : () => _run(() => app.regenerate(message)),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(l.retry),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l.messageActions,
          icon: const Icon(Icons.more_horiz, size: 18),
          onPressed: () => _messageActions(message),
        ),
      ],
    );
  }

  Widget _message(ChatMessage message, AppController app, AppLocalizations l) {
    final color = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: GestureDetector(
              onLongPress: () => _messageActions(message),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    key: ValueKey('message-bubble-${message.id}'),
                    padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                    decoration: BoxDecoration(
                      color: color.secondaryContainer.withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: _messageContent(
                      message,
                      message.content,
                      app,
                      l,
                      identity: message.id,
                    ),
                  ),
                  _messageState(message, l),
                  _messageMetadata(message, app, l),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _assistantTurn(
    ChatTimelineEntry entry,
    AppController app,
    AppLocalizations l,
  ) {
    final last = entry.lastAssistant!;
    final segments = buildAssistantSegments(entry.messages);
    final color = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: ValueKey('assistant-turn-${entry.anchor.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: GestureDetector(
              onLongPress: () => _messageActions(last),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: ValueKey('message-bubble-${entry.anchor.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          key: ValueKey(
                            'assistant-turn-header-${entry.anchor.id}',
                          ),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              TakoMark(size: 19, color: color.primary),
                              const SizedBox(width: 8),
                              Text(
                                kAppName,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                        for (final (index, segment) in segments.indexed)
                          switch (segment) {
                            AssistantContentSegment() => Padding(
                              padding: EdgeInsets.only(
                                top: index == 0 || segment.blocks.isEmpty
                                    ? 0
                                    : 8,
                              ),
                              child: GestureDetector(
                                onLongPress: () =>
                                    _messageActions(segment.message),
                                child: _messageContent(
                                  segment.message,
                                  segment.blocks,
                                  app,
                                  l,
                                  identity: '${segment.message.id}:$index',
                                ),
                              ),
                            ),
                            ToolRunSegment() => Padding(
                              padding: EdgeInsets.only(
                                top: index == 0 ? 0 : 4,
                                bottom: 2,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ToolRunSummary(
                                    app: app,
                                    run: segment,
                                    onAttachment: _openToolAttachment,
                                    onMessageActions: _messageActions,
                                  ),
                                  MemorySavedChips(app: app, run: segment),
                                ],
                              ),
                            ),
                          },
                      ],
                    ),
                  ),
                  _messageState(
                    last,
                    l,
                    showStreaming: !last.content.any(
                      (block) => block is ToolCallBlock,
                    ),
                  ),
                  // Earlier branch points remain reachable without duplicating
                  // every intermediate timestamp, action row and assistant header.
                  for (final message in entry.messages)
                    if (message.role == MessageRole.assistant &&
                        message.id != last.id &&
                        app.tree.siblingsOf(message.id).length > 1)
                      _intermediateBranch(message, app, l),
                  KeyedSubtree(
                    key: ValueKey('assistant-turn-metadata-${entry.anchor.id}'),
                    child: _messageMetadata(last, app, l),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intermediateBranch(
    ChatMessage message,
    AppController app,
    AppLocalizations l,
  ) {
    final siblings = app.tree.siblingsOf(message.id);
    final branch = siblings.indexWhere((m) => m.id == message.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l.previousBranch,
          icon: const Icon(Icons.chevron_left, size: 18),
          onPressed: app.busy || branch <= 0
              ? null
              : () => _run(() => app.switchBranch(siblings[branch - 1])),
        ),
        Text(
          '${branch + 1}/${siblings.length}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l.nextBranch,
          icon: const Icon(Icons.chevron_right, size: 18),
          onPressed: app.busy || branch >= siblings.length - 1
              ? null
              : () => _run(() => app.switchBranch(siblings[branch + 1])),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appControllerProvider.select((value) => value.pendingApproval), (
      _,
      request,
    ) {
      if (request != null) _focus.unfocus();
    });
    final app = ref.watch(appControllerProvider);
    final l = AppLocalizations.of(context);
    final visible = app.visibleMessages;
    final timeline = buildChatTimeline(visible);
    final stamp = '${app.conversation?.id}:${visible.length}:${app.revision}';
    if (stamp != _renderStamp) {
      final changedConversation = !stamp.startsWith(
        '${_renderStamp.split(':').first}:',
      );
      final nearBottom =
          !_scroll.hasClients || _scroll.position.extentAfter < 180;
      _renderStamp = stamp;
      if (changedConversation || nearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final continuations = visible.isEmpty
        ? <ChatMessage>[]
        : app.messages.where((m) => m.parentId == visible.last.id).toList();
    return Scaffold(
      drawer: wide ? null : Drawer(child: _history(app, l, drawer: true)),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 282,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: _history(app, l),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                AppBar(
                  automaticallyImplyLeading: !wide,
                  title: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: app.busy ? null : _chooseProvider,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app.selectedProvider?.model ?? kAppName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (app.providers.length > 1 ||
                                    app.selectedProvider == null)
                                  Text(
                                    app.selectedProvider?.displayName ??
                                        l.chooseModel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.expand_more, size: 20),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    if (app.services.browser.isAvailable)
                      IconButton(
                        key: const ValueKey('open-browser'),
                        tooltip: l.openBrowser,
                        onPressed: () =>
                            _run(() => openBrowserScreen(context, app)),
                        icon: const Icon(Icons.public),
                      ),
                    if (app.conversation == null)
                      IconButton(
                        key: const ValueKey('incognito-toggle'),
                        tooltip: l.incognitoChat,
                        isSelected: app.incognitoDraft,
                        onPressed: app.busy
                            ? null
                            : () => _run(
                                () =>
                                    app.newChat(incognito: !app.incognitoDraft),
                              ),
                        icon: const Icon(Icons.visibility_off_outlined),
                        selectedIcon: const Icon(Icons.visibility_off),
                      ),
                    if (app.conversation != null && !app.incognito)
                      IconButton(
                        tooltip: l.renameChat,
                        onPressed: app.busy
                            ? null
                            : () async {
                                final title = await _editText(
                                  l.renameChat,
                                  app.conversation!.title,
                                  multiline: false,
                                );
                                if (title != null) {
                                  await _run(
                                    () => app.renameConversation(title),
                                  );
                                }
                              },
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                    IconButton(
                      tooltip: l.newChat,
                      onPressed: app.busy ? null : () => _run(app.newChat),
                      icon: const Icon(Icons.add_comment_outlined),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                if (app.incognito && visible.isNotEmpty)
                  Material(
                    key: const ValueKey('incognito-banner'),
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_off_outlined, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${l.incognitoChat} · ${l.incognitoBody}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(32),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconTheme.merge(
                                      data: IconThemeData(
                                        size: 44,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      child: app.incognito
                                          ? const Icon(
                                              Icons.visibility_off_outlined,
                                            )
                                          : const TakoMark(),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Text(
                                    app.providers.isEmpty
                                        ? l.noProviders
                                        : app.incognito
                                        ? l.incognitoChat
                                        : l.welcome,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    app.providers.isEmpty
                                        ? l.setupBody
                                        : app.incognito
                                        ? l.incognitoBody
                                        : l.welcomeBody,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(height: 1.65),
                                  ),
                                  if (app.providers.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 24),
                                      child: FilledButton.icon(
                                        onPressed: () => Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ProviderEditor(),
                                          ),
                                        ),
                                        icon: const Icon(Icons.add),
                                        label: Text(l.addProvider),
                                      ),
                                    ),
                                  if (app.providers.isEmpty &&
                                      app.services.onDevice.isAvailable)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: TextButton.icon(
                                        key: const ValueKey('setup-on-device'),
                                        onPressed: () => Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const OnDeviceModelsScreen(),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.smartphone_outlined,
                                        ),
                                        label: Text(l.useOnDeviceModel),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 840),
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 24,
                              ),
                              itemCount:
                                  timeline.length +
                                  (continuations.isEmpty ? 0 : 1),
                              itemBuilder: (context, index) {
                                if (index == timeline.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Wrap(
                                      spacing: 8,
                                      children: [
                                        for (final child in continuations)
                                          OutlinedButton.icon(
                                            onPressed: app.busy
                                                ? null
                                                : () => _run(
                                                    () =>
                                                        app.switchBranch(child),
                                                  ),
                                            icon: const Icon(
                                              Icons.redo,
                                              size: 16,
                                            ),
                                            label: Text(
                                              '${l.continueAction} · ${child.text.characters.take(28)}',
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }
                                final entry = timeline[index];
                                final message = entry.anchor;
                                final date = DateFormat.yMMMd(
                                  l.localeName,
                                ).format(message.wallTime);
                                final previousDate = index == 0
                                    ? null
                                    : DateFormat.yMMMd(l.localeName).format(
                                        timeline[index - 1].anchor.wallTime,
                                      );
                                return Column(
                                  children: [
                                    if (date != previousDate)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        child: Text(
                                          date,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ),
                                    entry.isAssistantTurn
                                        ? _assistantTurn(entry, app, l)
                                        : _message(message, app, l),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                ),
                if (app.pendingApproval != null) ToolApprovalSheet(app: app),
                if (app.errorCode != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error(app.errorCode, l),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        if (app.canContinueAfterLimit)
                          TextButton(
                            key: const Key('continue-tools'),
                            onPressed: () => _run(app.continueAfterLimit),
                            child: Text(l.continueAction),
                          ),
                      ],
                    ),
                  ),
                if (app.selectedProvider == null && app.conversation != null)
                  TextButton(
                    onPressed: _chooseProvider,
                    child: Text(l.providerRemoved),
                  ),
                if (app.contextTrimmed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l.contextTrimmed,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                _composerPanel(app, l),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
