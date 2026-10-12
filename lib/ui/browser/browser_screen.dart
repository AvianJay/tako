import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_info.dart';
import '../../core/browser/browser_capability.dart';
import '../../l10n/gen/app_localizations.dart';
import '../chat/tool_widgets.dart';

/// Opens the shared browser, loading [url] in a new tab. While a browser
/// screen is mounted no second one is pushed.
Future<void> openBrowserScreen(
  BuildContext context,
  AppController app, {
  String? url,
}) async {
  final browser = app.services.browser;
  if (url != null) await browser.newTab(url: url);
  if (!context.mounted || browser.viewMounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const BrowserScreen()));
}

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({this.openedForModel = false, super.key});

  /// Shown so the user can watch the model. It closes by itself when the
  /// response ends, unless the user took over or used the browser.
  final bool openedForModel;
  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  late final _app = ref.read(appControllerProvider);
  BrowserCapability get _browser => _app.services.browser;
  bool _userActed = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _browser.onConfirmDownload = _confirmDownload;
    _browser.onDownloadFinished = _downloadFinished;
    if (widget.openedForModel) {
      _app.addListener(_followModel);
      // The response may already be over by the time the screen is built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _followModel());
    }
  }

  @override
  void dispose() {
    _app.removeListener(_followModel);
    if (_browser.onConfirmDownload == _confirmDownload) {
      _browser.onConfirmDownload = null;
    }
    if (_browser.onDownloadFinished == _downloadFinished) {
      _browser.onDownloadFinished = null;
    }
    super.dispose();
  }

  void _userActs() => _userActed = true;

  void _followModel() {
    if (!mounted || _closing || _userActed || _app.isGenerating) return;
    // The response is over: go back to the chat and its answer.
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userActed) return;
      // Leave it open under a dialog the user is answering.
      if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.pop(context);
    });
  }

  void _message(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) _message(AppLocalizations.of(context).operationFailed);
    }
  }

  /// Every download asks, including ones started by the model's clicks.
  Future<bool> _confirmDownload(BrowserDownload download) async {
    if (!mounted) return false;
    final l = AppLocalizations.of(context);
    final name = download.fileName?.trim().isNotEmpty == true
        ? download.fileName!.trim()
        : download.url.pathSegments.where((s) => s.isNotEmpty).lastOrNull ??
              download.url.host;
    final size = download.contentLength;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.download_outlined),
            title: Text(l.downloadTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.downloadBody(name, download.url.host)),
                  if (size != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_size(size)),
                    ),
                  const SizedBox(height: 8),
                  SelectableText(
                    download.url.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.download),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _downloadFinished(String? path, String? error) {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    if (path != null) {
      _message(
        l.downloadSaved,
        action: SnackBarAction(
          label: l.share,
          onPressed: () => _run(() => _app.services.shareWorkspaceFile(path)),
        ),
      );
    } else {
      _message(
        error == 'download_too_large' ? l.downloadTooLarge : l.downloadFailed,
      );
    }
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : bytes >= 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '$bytes B';

  Future<void> _showTabs() async {
    _userActs();
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: _browser,
        builder: (context, _) {
          final theme = Theme.of(context);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.tabs,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          key: const ValueKey('browser-new-tab'),
                          onPressed: () {
                            Navigator.pop(context);
                            unawaited(_run(_browser.newTab));
                          },
                          icon: const Icon(Icons.add),
                          label: Text(l.newTab),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tab in _browser.tabs)
                          _tabTile(context, l, tab),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tabTile(
    BuildContext context,
    AppLocalizations l,
    BrowserTabInfo tab,
  ) {
    final uri = Uri.tryParse(tab.url);
    final host = uri == null || uri.host.isEmpty ? '' : uri.host;
    return ListTile(
      key: ValueKey('browser-tab-${tab.id}'),
      selected: tab.id == _browser.activeTabId,
      leading: Icon(
        tab.openedByModel ? Icons.smart_toy_outlined : Icons.public,
      ),
      title: Text(
        tab.title.isNotEmpty
            ? tab.title
            : host.isNotEmpty
            ? host
            : l.blankTab,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: host.isEmpty && !tab.openedByModel
          ? null
          : Text(
              [
                if (host.isNotEmpty) host,
                if (tab.openedByModel) l.openedByAssistant(kAppName),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: () {
        _browser.selectTab(tab.id);
        Navigator.pop(context);
      },
      trailing: IconButton(
        key: ValueKey('browser-close-tab-${tab.id}'),
        tooltip: l.closeTab,
        icon: const Icon(Icons.close),
        onPressed: () => _run(() => _browser.closeTab(tab.id)),
      ),
    );
  }

  Future<void> _address() async {
    _userActs();
    final l = AppLocalizations.of(context);
    final current = _browser.url;
    final controller = TextEditingController(
      text: current.startsWith('http') ? current : '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.browserAddressHint),
        content: SizedBox(
          width: 560,
          child: TextField(
            key: const ValueKey('browser-address'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'example.com'),
            onSubmitted: (text) => Navigator.pop(context, text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l.continueAction),
          ),
        ],
      ),
    );
    // The dialog's closing animation can still reference its controller.
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 250),
        controller.dispose,
      ),
    );
    if (value == null || !mounted) return;
    final url = browserUrlFromInput(value);
    if (url == null) {
      _message(l.browserInvalidAddress);
      return;
    }
    await _run(() => _browser.navigate(url));
  }

  Future<void> _menu(String action) async {
    _userActs();
    final l = AppLocalizations.of(context);
    switch (action) {
      case 'newTab':
        await _run(_browser.newTab);
      case 'forward':
        await _run(_browser.goForward);
      case 'external':
        final uri = Uri.tryParse(_browser.url);
        if (uri != null) await _run(() => _app.services.openLink(uri));
      case 'clear':
        final yes =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(l.clearBrowsingData),
                content: Text(l.clearBrowsingDataBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l.delete),
                  ),
                ],
              ),
            ) ??
            false;
        if (yes) {
          await _run(() async {
            await _browser.clearBrowsingData();
            _message(l.browsingDataCleared);
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = ref.watch(appControllerProvider);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _browser,
      builder: (context, _) {
        final browser = _browser;
        final uri = Uri.tryParse(browser.url);
        final hasPage = uri != null && {'http', 'https'}.contains(uri.scheme);
        final modelActive = app.isGenerating && browser.modelActive;
        return PopScope(
          // System back navigates the page first; the close button leaves.
          canPop: !browser.canGoBack,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _userActs();
            unawaited(browser.goBack());
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: l.close,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              titleSpacing: 0,
              title: InkWell(
                key: const ValueKey('browser-title'),
                borderRadius: BorderRadius.circular(12),
                onTap: browser.isAvailable ? _address : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        browser.title.isNotEmpty
                            ? browser.title
                            : hasPage
                            ? uri.host
                            : l.browser,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Row(
                        children: [
                          if (hasPage && uri.scheme == 'https')
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.lock_outline, size: 12),
                            ),
                          Flexible(
                            child: Text(
                              hasPage ? uri.host : l.browserAddressHint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: l.browserBack,
                  onPressed: browser.canGoBack
                      ? () {
                          _userActs();
                          unawaited(_run(browser.goBack));
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: l.browserReload,
                  onPressed: hasPage
                      ? () {
                          _userActs();
                          unawaited(_run(browser.reload));
                        }
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  key: const ValueKey('browser-tabs'),
                  tooltip: l.tabs,
                  onPressed: browser.isAvailable ? _showTabs : null,
                  icon: _TabCount(count: browser.tabs.length),
                ),
                PopupMenuButton<String>(
                  onSelected: _menu,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'newTab',
                      enabled: browser.isAvailable,
                      child: Text(l.newTab),
                    ),
                    PopupMenuItem(
                      value: 'forward',
                      enabled: browser.canGoForward,
                      child: Text(l.browserForward),
                    ),
                    PopupMenuItem(
                      value: 'external',
                      enabled: hasPage,
                      child: Text(l.openExternally),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      enabled: browser.isAvailable,
                      child: Text(l.clearBrowsingData),
                    ),
                  ],
                ),
              ],
              bottom: browser.loading
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(2),
                      child: LinearProgressIndicator(
                        value: browser.progress > 0 ? browser.progress : null,
                        minHeight: 2,
                      ),
                    )
                  : null,
            ),
            body: Column(
              children: [
                if (modelActive)
                  _ModelBanner(
                    onTakeOver: () {
                      _userActs();
                      browser.takeOver();
                    },
                  ),
                Expanded(
                  child: !browser.isAvailable
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(l.browserUnavailable),
                          ),
                        )
                      : Stack(
                          children: [
                            Positioned.fill(
                              child: browser.buildSurface(context),
                            ),
                            if (!hasPage && !browser.loading)
                              Positioned.fill(
                                child: ColoredBox(
                                  color: theme.colorScheme.surface,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.public,
                                            size: 40,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            l.browserEmpty(kAppName),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 16),
                                          FilledButton.tonalIcon(
                                            onPressed: _address,
                                            icon: const Icon(Icons.search),
                                            label: Text(l.browserAddressHint),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                if (app.pendingApproval != null) ToolApprovalSheet(app: app),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The number of open tabs in a rounded square, as in mobile browsers.
class _TabCount extends StatelessWidget {
  const _TabCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color ?? Colors.black, width: 2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _ModelBanner extends StatelessWidget {
  const _ModelBanner({required this.onTakeOver});
  final VoidCallback onTakeOver;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('browser-model-banner'),
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            if (MediaQuery.disableAnimationsOf(context))
              Icon(Icons.smart_toy_outlined, color: colors.onTertiaryContainer)
            else
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onTertiaryContainer,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.browserModelActive(kAppName),
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
            FilledButton.tonal(
              key: const ValueKey('browser-take-over'),
              onPressed: onTakeOver,
              child: Text(l.takeOver),
            ),
          ],
        ),
      ),
    );
  }
}
