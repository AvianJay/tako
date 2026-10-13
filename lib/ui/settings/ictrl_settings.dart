import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/screen/remote_screen.dart';

/// iOS setup uses local discovery, not Android accessibility or Termux screens.
class IctrlSettings extends StatefulWidget {
  const IctrlSettings({required this.screen, super.key});
  final RemoteScreen screen;
  @override
  State<IctrlSettings> createState() => _IctrlSettingsState();
}

class _IctrlSettingsState extends State<IctrlSettings> {
  late final _endpoint = TextEditingController(text: widget.screen.endpoint);
  bool _editing = false;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    widget.screen.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!_editing) _endpoint.text = widget.screen.endpoint;
    setState(() {});
  }

  @override
  void dispose() {
    widget.screen.removeListener(_changed);
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await widget.screen.connect(endpoint: _endpoint.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String en, String tw) => zh ? tw : en;
    final screen = widget.screen;
    final status = switch (screen.status) {
      RemoteScreenStatus.offline => tr('Runner not detected', '尚未找到執行中的 iCTRL'),
      RemoteScreenStatus.connecting => tr('Connecting…', '連線中…'),
      RemoteScreenStatus.pairing => tr(
        'Approve Tako in the iCTRL pairing notification',
        '請在 iCTRL 配對通知允許 Tako',
      ),
      RemoteScreenStatus.ready => tr('Paired and ready', '已配對，可以操作'),
      RemoteScreenStatus.denied => tr(
        'Pairing was declined. Tap Connect to try again.',
        '配對未獲允許。點選連線可重新配對。',
      ),
      RemoteScreenStatus.failed => tr(
        'Connection failed. Check the runner and address.',
        '連線失敗，請確認 iCTRL 與位址。',
      ),
      RemoteScreenStatus.paused => tr('Remote control disconnected', '遠端操作已中斷'),
    };
    final waiting =
        _busy ||
        screen.status == RemoteScreenStatus.pairing ||
        screen.status == RemoteScreenStatus.connecting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('iCTRL screen control', 'iCTRL 螢幕操作'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Start the iCTRLUITests runner on this phone. Tako detects 127.0.0.1:8200 automatically and asks to pair once. Approve the pairing notification in iCTRL.',
            '先在此手機啟動 iCTRLUITests 執行器。Tako 會自動偵測 127.0.0.1:8200 並發出一次配對請求，請在 iCTRL 通知中允許。',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('ictrl-endpoint'),
          controller: _endpoint,
          enabled: !waiting,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => _editing = true,
          decoration: InputDecoration(
            labelText: tr('iCTRL address', 'iCTRL 位址'),
            hintText: 'http://127.0.0.1:8200',
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(status, key: const ValueKey('ictrl-status')),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('ictrl-connect'),
              onPressed: waiting ? null : _connect,
              child: Text(tr('Connect and pair', '連線並配對')),
            ),
            OutlinedButton(
              key: const ValueKey('ictrl-disconnect'),
              onPressed: screen.status == RemoteScreenStatus.paused
                  ? null
                  : () => unawaited(screen.disconnect()),
              child: Text(tr('Disconnect', '中斷連線')),
            ),
          ],
        ),
        const Divider(height: 32),
        if (screen.sessionDiagnostics.isNotEmpty) ...[
          Text(
            '${tr('Background execution', '背景執行')} · '
            '${screen.sessionDiagnostics['processing_state']} · '
            'build ${screen.sessionDiagnostics['build']}',
            key: const ValueKey('ictrl-background-state'),
          ),
          Text(
            'registered=${screen.sessionDiagnostics['registered']}, '
            'submitted=${screen.sessionDiagnostics['submitted']}, '
            'handler=${screen.sessionDiagnostics['handler_started']}'
            '${screen.sessionDiagnostics['custom_activity_visible'] == null ? '' : ', custom_status=${screen.sessionDiagnostics['custom_activity_visible']}'}'
            '${screen.sessionDiagnostics['error_code'] == null ? '' : ', ${screen.sessionDiagnostics['error_domain']}:${screen.sessionDiagnostics['error_code']}'}',
          ),
          const SizedBox(height: 12),
        ],
        Text(
          tr(
            'For another device, enable Remote Access in iCTRL and enter its LAN or Tailscale address. Pairing is encrypted and the key stays in secure storage.',
            '要操作另一台裝置，請在 iCTRL 開啟 Remote Access，再輸入區網或 Tailscale 位址。配對會加密，金鑰保存在安全儲存區。',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr(
            'On iOS 26 or later, tasks request continued background processing with system status. Extra app status hides automatically; task completion removes it immediately. Swipe an expanded system banner upward if it covers controls. If continued processing is unavailable, iOS grants only a short background window. System cancellation or expiration stops actions.',
            'iOS 26 以上會為任務申請持續背景處理，並由系統顯示狀態。額外的 App 狀態會自動隱藏，任務結束會立即移除；系統橫幅若遮住操作，可向上滑收起。若持續背景處理不可用，則只有短暫的背景執行時間。系統取消或時間用完後會停止操作。',
          ),
        ),
      ],
    );
  }
}
