import 'dart:typed_data';

import '../core/browser/browser_capability.dart';
import '../core/files/workspace.dart';
import '../core/notifications/notification_capability.dart';
import '../core/screen/screen_capability.dart';
import '../core/shell/shell_capability.dart';
import 'capabilities.dart';
import 'device_tools_capability.dart';
import 'media_attachment_capability.dart';

class DeviceContext {
  const DeviceContext({
    this.platform = 'Android',
    this.osVersion = '',
    this.model = '',
    this.batteryPercent,
    this.network,
  });
  final String platform;
  final String osVersion;
  final String model;
  final int? batteryPercent;
  final String? network;
}

/// OS services. Shared code depends on this capability contract; native
/// plugins, filesystem access and platform detection stay in implementations.
abstract interface class AppServices implements Capability {
  WorkspaceCapability get workspace;
  DeviceToolsCapability get deviceTools;
  MediaAttachmentCapability get mediaAttachments;
  BrowserCapability get browser;
  ScreenCapability get screen;
  ShellCapability get shell;
  NotificationCapability get notifications;

  /// Re-reads device-control availability, which the user changes in system
  /// settings. Never reads private data.
  Future<void> refreshDeviceControl();

  Future<DeviceContext> deviceContext();
  Future<String?> readSecret(String reference);
  Future<void> writeSecret(String reference, String? value);
  Future<Map<String, String>> readHeaders(String? reference);
  Future<void> copyText(String text);
  Future<void> shareText(String text);
  Future<void> openLink(Uri uri);
  Future<Uint8List> readWorkspaceImage(String relative);
  Future<void> shareWorkspaceFile(String relative);

  /// A user-chosen UTF-8 file, or null when the picker is dismissed.
  Future<String?> pickTextFile({required int maxBytes});

  /// Shares [text] as a temporary file outside the workspace.
  Future<void> shareTextFile(String name, String text);
}
