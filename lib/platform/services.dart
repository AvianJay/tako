import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/browser/browser_capability.dart';
import '../core/files/workspace.dart';
import '../core/notifications/notification_capability.dart';
import '../core/screen/screen_capability.dart';
import '../core/shell/shell_capability.dart';
import 'android/device_api.g.dart';
import 'android/device_control.dart';
import 'android/device_tools.dart';
import 'android/media_attachments.dart';
import 'app_services.dart';
import 'browser/webview_browser.dart';
import 'device_tools_capability.dart';
import 'media_attachment_capability.dart';
import 'workspace/local_workspace.dart';

export 'app_services.dart';

/// OS plugins and filesystem access are confined to this platform boundary.
class PlatformServices implements AppServices {
  PlatformServices() {
    if (Platform.isAndroid) {
      AndroidControlEvents(
        screen: screen,
        onStatusChanged: () => unawaited(refreshDeviceControl()),
      ).attach();
    }
  }

  @override
  late final WorkspaceCapability workspace = LocalWorkspace();
  @override
  late final MediaAttachmentCapability mediaAttachments = Platform.isAndroid
      ? AndroidMediaAttachments(workspace)
      : const UnavailableMediaAttachments();
  @override
  late final DeviceToolsCapability deviceTools = Platform.isAndroid
      ? AndroidDeviceTools()
      : const UnavailableDeviceTools();
  // TODO(ios): the same WebView browser on iOS.
  @override
  late final BrowserCapability browser = Platform.isAndroid
      ? WebViewBrowser(workspace: workspace)
      : UnavailableBrowser();
  // TODO(ios): screen control, a shell and Shortcuts on iOS.
  @override
  late final ScreenCapability screen = Platform.isAndroid
      ? AndroidScreen()
      : UnavailableScreen();
  @override
  late final ShellCapability shell = Platform.isAndroid
      ? AndroidShell()
      : UnavailableShell();
  @override
  late final NotificationCapability notifications = Platform.isAndroid
      ? AndroidNotifications()
      : UnavailableNotifications();
  @override
  bool get isAvailable => Platform.isAndroid;

  @override
  Future<void> refreshDeviceControl() async {
    await Future.wait([
      screen.refresh(),
      shell.refresh(),
      notifications.refresh(),
    ]);
  }

  final FlutterSecureStorage _secrets = const FlutterSecureStorage();

  @override
  Future<DeviceContext> deviceContext() async {
    if (!Platform.isAndroid) {
      return const DeviceContext(platform: 'unavailable');
    }
    try {
      final snapshot = await DeviceApi().snapshot();
      return DeviceContext(
        osVersion: snapshot.osVersion,
        model: snapshot.model,
        batteryPercent: snapshot.batteryPercent,
        network: snapshot.network,
      );
    } on PlatformException {
      return const DeviceContext();
    } on MissingPluginException {
      return const DeviceContext();
    }
  }

  @override
  Future<String?> readSecret(String reference) => _secrets.read(key: reference);
  @override
  Future<void> writeSecret(String reference, String? value) =>
      value == null || value.isEmpty
      ? _secrets.delete(key: reference)
      : _secrets.write(key: reference, value: value);
  @override
  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
  @override
  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Future<void> openLink(Uri uri) async {
    if (!{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Unsupported link');
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const FormatException('Unable to open link');
    }
  }

  @override
  Future<Uint8List> readWorkspaceImage(String relative) async {
    final image = (await workspace.read(relative)).image;
    if (image?.data == null) throw const FormatException('Image unavailable');
    return base64Decode(image!.data!);
  }

  @override
  Future<void> shareWorkspaceFile(String relative) =>
      workspace.shareFile(relative);

  @override
  Future<String?> pickTextFile({required int maxBytes}) async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    final length = await file.length();
    if (length == null || length > maxBytes) {
      throw const FormatException('File is too large');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw const FormatException('File is too large');
    }
    return utf8.decode(bytes);
  }

  @override
  Future<void> shareTextFile(String name, String text) async {
    // A cache file, never the workspace: exports must not become model input.
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'exports'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, p.basename(name)));
    await file.writeAsString(text, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Future<Map<String, String>> readHeaders(String? reference) async {
    if (reference == null) return {};
    final value = await readSecret(reference);
    if (value == null) return {};
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }
}
