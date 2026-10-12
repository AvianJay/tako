import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../core/search/search_service.dart';
import '../../l10n/gen/app_localizations.dart';

class SearchSettingsScreen extends ConsumerStatefulWidget {
  const SearchSettingsScreen({super.key});
  @override
  ConsumerState<SearchSettingsScreen> createState() =>
      _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends ConsumerState<SearchSettingsScreen> {
  late final _app = ref.read(appControllerProvider);
  late SearchKind _kind = _app.searchConfig.kind;
  late final _url = TextEditingController(text: _app.searchConfig.baseUrl);
  final _key = TextEditingController();
  late final _count = TextEditingController(
    text: '${_app.searchConfig.resultCount}',
  );
  bool _remove = false, _saving = false;
  late Future<bool> _hasKey = _app.hasSearchKey(_kind);
  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.search)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownButtonFormField<SearchKind>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: l.searchProvider),
            items: const [
              DropdownMenuItem(
                value: SearchKind.searxng,
                child: Text('SearXNG'),
              ),
              DropdownMenuItem(value: SearchKind.tavily, child: Text('Tavily')),
              DropdownMenuItem(value: SearchKind.brave, child: Text('Brave')),
              DropdownMenuItem(value: SearchKind.serper, child: Text('Serper')),
              DropdownMenuItem(value: SearchKind.ddgs, child: Text('DDGS')),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() {
                    _kind = v!;
                    _url.text = _kind == _app.searchConfig.kind
                        ? _app.searchConfig.baseUrl
                        : _kind.defaultBaseUrl;
                    _key.clear();
                    _remove = false;
                    _hasKey = _app.hasSearchKey(_kind);
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            enabled: !_saving,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: l.searchUrl,
              hintText: _kind.defaultBaseUrl,
            ),
          ),
          if (_kind.supportsApiKey) ...[
            const SizedBox(height: 16),
            FutureBuilder<bool>(
              future: _hasKey,
              builder: (context, snapshot) => TextField(
                controller: _key,
                enabled: !_saving,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _kind == SearchKind.ddgs
                      ? l.searchOptionalToken
                      : l.searchKey,
                  helperText: snapshot.data == true
                      ? l.keyStored
                      : l.searchKeyHint,
                ),
              ),
            ),
            CheckboxListTile(
              value: _remove,
              title: Text(l.removeKey),
              onChanged: _saving ? null : (v) => setState(() => _remove = v!),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _count,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.searchResults),
          ),
          const SizedBox(height: 16),
          if (_kind == SearchKind.serper) Text(l.searchSerperHelp),
          if (_kind == SearchKind.ddgs) Text(l.searchDdgsHelp),
          if (_kind == SearchKind.searxng) Text(l.searchSearxngHelp),
          const SizedBox(height: 8),
          Text(l.searchHelp),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      final count = int.tryParse(_count.text);
                      if (count == null || count < 1 || count > 10) {
                        throw const FormatException();
                      }
                      if (_kind.requiresBaseUrl && _url.text.trim().isEmpty) {
                        throw const FormatException();
                      }
                      await _app.saveSearchConfig(
                        SearchConfig(
                          kind: _kind,
                          baseUrl: _url.text.trim(),
                          resultCount: count,
                          apiKeyRef: _kind == _app.searchConfig.kind
                              ? _app.searchConfig.apiKeyRef
                              : null,
                        ),
                        key: _key.text.trim(),
                        removeKey: _remove,
                      );
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.operationFailed)),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Text(l.save),
          ),
        ],
      ),
    );
  }
}
