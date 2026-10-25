import 'package:drift/native.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/browser/browser_capability.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/notifications/notification_capability.dart';
import 'package:tako/core/on_device/on_device_capability.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/screen/screen_capability.dart';
import 'package:tako/core/shell/shell_capability.dart';
import 'package:tako/core/shortcuts/shortcuts_capability.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/app_services.dart';
import 'package:tako/platform/device_tools_capability.dart';
import 'package:tako/platform/media_attachment_capability.dart';

/// Captures the real AppController request with an empty, isolated database.
/// Supply the production system prompt asset. No native services, credentials,
/// user files, network requests, or tool execution are involved.
Future<ChatRequest> realisticAicoreChatRequest({
  required String promptTemplate,
  String userText = 'hi',
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  final services = _FixtureServices();
  final capture = _CaptureAdapter();
  final app = AppController(
    database: database,
    services: services,
    promptTemplate: promptTemplate,
    adapterFactory: (_, _, _) => capture,
    titleGenerator: (_, _, _) async => null,
    bindControls: false,
  );
  try {
    await app.initialize();
    await app.useOnDeviceModel(_fixtureModel, providerName: 'On device');
    await app.send(userText);
    if (app.errorCode != null || capture.requests.length != 1) {
      throw StateError(
        'Could not capture realistic AICore request: '
        '${app.errorCode}, requests=${capture.requests.length}',
      );
    }
    if ((await app.audit.list()).isNotEmpty) {
      throw StateError('The request fixture unexpectedly executed a tool.');
    }
    return capture.requests.single;
  } finally {
    app.dispose();
    await database.close();
    services.dispose();
  }
}

const _fixtureModel = LocalModel.system(
  id: 'aicore:gemini-nano-preview',
  name: 'Gemini Nano 4 Full (AICore Preview)',
  profile: ModelProfile(
    id: 'aicore:gemini-nano-preview',
    capabilities: ProviderCapabilities(tools: true, contextWindow: 8192),
    maxOutputTokens: 1024,
  ),
);

class _CaptureAdapter implements ProviderAdapter {
  final requests = <ChatRequest>[];

  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async => const [];

  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    yield const TextDelta('Hello!');
    yield const Done('stop');
  }
}

class _FixtureServices implements AppServices {
  @override
  bool get isAvailable => true;
  @override
  final workspace = _FixtureWorkspace();
  @override
  final deviceTools = _FixtureDeviceTools();
  @override
  final mediaAttachments = const UnavailableMediaAttachments();
  @override
  final browser = _FixtureBrowser();
  @override
  final screen = UnavailableScreen();
  @override
  final shell = UnavailableShell();
  @override
  final notifications = UnavailableNotifications();
  @override
  final onDevice = _FixtureOnDevice();
  @override
  final shortcuts = UnavailableShortcuts();

  @override
  Future<void> refreshDeviceControl() async {}
  @override
  Future<DeviceContext> deviceContext() async => const DeviceContext(
    platform: 'Android',
    osVersion: '16',
    model: 'Pixel fixture',
    batteryPercent: 80,
    network: 'wifi',
  );
  @override
  Future<String?> readSecret(String reference) async => null;
  @override
  Future<void> writeSecret(String reference, String? value) async =>
      throw StateError('Fixture cannot write credentials.');
  @override
  Future<Map<String, String>> readHeaders(String? reference) async => const {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void dispose() {
    browser.dispose();
    screen.dispose();
    shell.dispose();
    notifications.dispose();
    onDevice.dispose();
  }
}

class _FixtureDeviceTools extends UnavailableDeviceTools {
  @override
  bool get isAvailable => true;
  @override
  bool supports(String tool) => deviceToolNames.contains(tool);
}

class _FixtureBrowser extends UnavailableBrowser {
  @override
  bool get isAvailable => true;
}

class _FixtureOnDevice extends UnavailableOnDevice {
  @override
  bool get isAvailable => true;
  @override
  List<LocalModel> get models => const [_fixtureModel];
}

class _FixtureWorkspace implements WorkspaceCapability {
  @override
  bool get isAvailable => true;
  @override
  Future<void> removeAttachments(Iterable<String> paths) async {}
  @override
  Future<List<ContentBlock>> hydrateBlocks(
    List<ContentBlock> blocks, {
    required bool vision,
    CancelToken? cancel,
  }) async => blocks;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
