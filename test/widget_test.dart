import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/app/app.dart';
import 'package:tako/app/app_controller.dart';
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/core/chat/conversation.dart';
import 'package:tako/core/chat/message.dart';
import 'package:tako/core/files/workspace.dart';
import 'package:tako/core/permissions/permission_gate.dart';
import 'package:tako/core/providers/providers.dart';
import 'package:tako/core/tools/tool.dart';
import 'package:tako/data/database.dart';
import 'package:tako/platform/media_attachment_capability.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/chat/tool_run_widgets.dart';
import 'package:tako/ui/chat/tool_widgets.dart';
import 'package:tako/ui/render/visuals/cards.dart';
import 'package:tako/ui/render/visuals/visual_block.dart';
import 'package:tako/ui/settings/provider_editor.dart';
import 'package:tako/ui/settings/tool_settings_screen.dart';

const captureUi = bool.fromEnvironment('UPDATE_UI_SCREENSHOTS');
const captureKey = Key('app-screenshot');

class ModelListAdapter implements ProviderAdapter {
  ModelListAdapter({this.catalog});
  final List<ModelInfo>? catalog;
  @override
  Future<List<ModelInfo>> listModels({CancelToken? cancel}) async =>
      catalog ??
      [
        const ModelInfo(id: 'deepseek-flash'),
        const ModelInfo(id: 'deepseek-v4-pro'),
        for (var i = 0; i < 60; i++) ModelInfo(id: 'custom-$i'),
      ];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) => const Stream.empty();
}

class FakePlatformServices extends PlatformServices {
  final secrets = <String, String>{};

  @override
  Future<DeviceContext> deviceContext() async => const DeviceContext(
    platform: 'Android',
    osVersion: 'test',
    model: 'test device',
    batteryPercent: 75,
    network: 'wifi',
  );

  @override
  Future<String?> readSecret(String reference) async => secrets[reference];

  @override
  Future<void> writeSecret(String reference, String? value) async {
    if (value == null) {
      secrets.remove(reference);
    } else {
      secrets[reference] = value;
    }
  }
}

class PickerWorkspace implements WorkspaceCapability {
  String? importedImageName;
  Uint8List? importedImageBytes;
  @override
  bool get isAvailable => true;
  @override
  Future<ImageBlock> importImageBytes(
    String name,
    Uint8List bytes, {
    CancelToken? cancel,
  }) async {
    importedImageName = name;
    importedImageBytes = bytes;
    return const ImageBlock(
      path: 'attachments/keyboard-image.png',
      mimeType: 'image/png',
    );
  }

  @override
  Future<List<ContentBlock>> importFiles({CancelToken? cancel}) async => const [
    FileBlock(
      path: 'attachments/note.txt',
      name: 'note.txt',
      mimeType: 'text/plain',
      extractedText: 'Frozen attachment contents',
    ),
  ];
  @override
  Future<List<ContentBlock>> hydrateBlocks(
    List<ContentBlock> blocks, {
    required bool vision,
    CancelToken? cancel,
  }) async => blocks;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AttachmentServices extends FakePlatformServices {
  final _workspace = PickerWorkspace();
  @override
  PickerWorkspace get workspace => _workspace;

  @override
  Future<Uint8List> readWorkspaceImage(String relative) async =>
      relative.contains('camera') ? _warmThumbnail : _coolThumbnail;
}

Uint8List _thumbnail({required bool warm}) {
  final image = img.Image(width: 192, height: 160);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(
        x,
        y,
        warm ? 205 + x ~/ 8 : 45 + y ~/ 3,
        warm ? 120 + y ~/ 3 : 120 + x ~/ 4,
        warm ? 90 + x ~/ 5 : 195 + y ~/ 4,
      );
    }
  }
  img.fillCircle(
    image,
    x: warm ? 128 : 60,
    y: 65,
    radius: 30,
    color: img.ColorRgb8(245, 235, 210),
  );
  return Uint8List.fromList(img.encodePng(image));
}

final _warmThumbnail = _thumbnail(warm: true);
final _coolThumbnail = _thumbnail(warm: false);

class PickerMediaAttachments implements MediaAttachmentCapability {
  int photoCalls = 0;
  int cameraCalls = 0;
  @override
  bool get isAvailable => true;
  @override
  Future<List<ContentBlock>> pickPhotos({
    int limit = 8,
    CancelToken? cancel,
  }) async {
    photoCalls++;
    return const [
      ImageBlock(path: 'attachments/photo.png', mimeType: 'image/png'),
    ];
  }

  @override
  Future<List<ContentBlock>> capturePhoto({CancelToken? cancel}) async {
    cameraCalls++;
    return const [
      ImageBlock(path: 'attachments/camera.jpg', mimeType: 'image/jpeg'),
    ];
  }

  @override
  Future<List<ContentBlock>> recoverLostPhotos({
    int limit = 8,
    CancelToken? cancel,
  }) async => [];
}

class MediaAttachmentServices extends AttachmentServices {
  final _mediaAttachments = PickerMediaAttachments();
  @override
  PickerMediaAttachments get mediaAttachments => _mediaAttachments;
}

class AnswerAdapter extends ModelListAdapter {
  final requests = <ChatRequest>[];
  @override
  Stream<ProviderEvent> send(
    ChatRequest request, {
    required CancelToken cancel,
  }) async* {
    requests.add(request);
    yield const TextDelta('I read the attachment.');
    yield const Done('stop');
  }
}

Future<AppController> boot(
  WidgetTester tester, {
  Locale? locale,
  Size? size,
  bool seeded = false,
  AdapterFactory? adapterFactory,
  PlatformServices? services,
  ThemeMode? theme,
  double? scale,
}) async {
  if (size != null) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final database = AppDatabase(NativeDatabase.memory());
  final controller = AppController(
    titleGenerator: (_, _, _) async => null,
    database: database,
    services: services ?? FakePlatformServices(),
    promptTemplate: 'You are {{app_name}}.',
    adapterFactory: adapterFactory,
  );
  await tester.runAsync(() async {
    await controller.initialize();
    if (locale != null || theme != null || scale != null) {
      await controller.updateAppearance(
        language: locale,
        theme: theme,
        scale: scale,
      );
    }
    if (seeded) {
      await seedConversation(controller);
      controller.conversations = await controller.chats.listConversations();
    }
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const TakoApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    // ProviderScope owns the controller's disposal.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });
  return controller;
}

Future<void> seedConversation(AppController controller) async {
  final now = DateTime.utc(2026, 10, 10, 10, 30);
  await controller.saveProvider(
    ProviderConfig(
      id: 'local',
      displayName: 'Local model',
      apiType: ApiType.chatCompletions,
      baseUrl: 'http://127.0.0.1:8080',
      model: 'llama-server',
    ),
  );
  await controller.chats.createConversation(
    Conversation(
      id: 'visual',
      title: 'A small plan for today',
      createdAt: now,
      updatedAt: now,
      systemPrompt: 'You are Tako.',
      providerId: 'local',
      model: 'llama-server',
    ),
  );
  await controller.chats.saveMessage(
    ChatMessage(
      id: 'user',
      conversationId: 'visual',
      role: MessageRole.user,
      content: const [
        TextBlock('Help me make a small plan, with a table and a formula.'),
      ],
      createdAt: now,
      timezoneOffsetMinutes: 480,
    ),
  );
  await controller.chats.saveMessage(
    ChatMessage(
      id: 'alternative',
      conversationId: 'visual',
      parentId: 'user',
      role: MessageRole.assistant,
      content: const [TextBlock('An earlier version of the plan.')],
      createdAt: now.add(const Duration(seconds: 1)),
      timezoneOffsetMinutes: 480,
    ),
  );
  await controller.chats.saveMessage(
    ChatMessage(
      id: 'answer',
      conversationId: 'visual',
      parentId: 'user',
      role: MessageRole.assistant,
      content: const [
        ReasoningBlock(
          text: 'I will keep the plan practical and leave room for a break.',
        ),
        TextBlock(
          '## A little progress\n\nStart with **one useful thing**.\n\n'
          '| Time | Plan |\n| --- | --- |\n| 20 min | Focus |\n| 5 min | Rest |\n\n'
          'A simple rhythm is \$T = 20 + 5\$.\n\n'
          '```dart\nfinal nextStep = "Start small";\n```\n\n'
          '- Pick one task\n- Leave room to adjust',
        ),
      ],
      createdAt: now.add(const Duration(seconds: 2)),
      timezoneOffsetMinutes: 480,
    ),
  );
  await controller.openConversation('visual');
}

const visualReply = r'''
## 文字以外，我還能怎麼呈現？

```cards
[
  {"icon": "dashboard", "title": "① 卡片式介面", "subtitle": "適合：專案介紹、功能清單、資訊儀表板", "text": "把不同資訊拆成獨立區塊，有標題、圖示、摘要與操作，不必在一大坨文字裡考古。"},
  {"icon": "bar_chart", "title": "② 資料圖表", "subtitle": "適合：統計、效能監控、數據比較", "text": "可以呈現**長條圖**、折線圖、圓餅圖等，並搭配資料解讀。"},
  {"icon": "🧭", "title": "③ 流程圖與架構圖", "subtitle": "適合：步驟說明、系統架構", "text": "用 Mermaid 畫出流程、循序互動或心智圖。"}
]
```

```chart
{"type": "bar", "title": "範例：每月請求數", "labels": ["1 月", "2 月", "3 月", "4 月"], "series": [{"name": "請求數", "data": [120, 210, 170, 320]}], "unit": "次"}
```

```chart
{"type": "line", "title": "每週活躍使用者", "labels": ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"], "series": [{"name": "Android", "data": [820, 932, 901, 934, 1290, 1330, 1320, 1452]}, {"name": "iOS", "data": [620, 732, 701, 734, 1090, 1130, 1120, 1210]}]}
```

```chart
{"type": "donut", "title": "流量來源", "labels": ["自然搜尋", "社群", "直接造訪", "推薦連結", "電子報", "廣告", "其他管道"], "series": [{"data": [42, 23, 15, 8, 5, 4, 3]}], "unit": "%"}
```

```chart
{"type": "bar", "title": "最常用的裝置", "labels": ["智慧型手機", "筆記型電腦", "平板電腦", "智慧手錶", "無線耳機", "電子書閱讀器"], "series": [{"data": [86, 64, 38, 22, 51, 9]}], "unit": "%", "source": "範例資料"}
```

```mermaid
flowchart TD
    A([開始]) --> B{已登入？}
    B -- 是 --> C[讀取個人資料]
    B -- 否 --> D[顯示登入頁]
    D --> E[/輸入帳號密碼/]
    E --> F{驗證成功？}
    F -->|是| C
    F -->|否| D
    C --> G[(資料庫)]
    C --> H([完成])
```

```mermaid
flowchart LR
    subgraph phone [手機]
        App[Tako App] --> Engine[llama.cpp]
    end
    subgraph cloud [雲端]
        API[OpenAI 相容 API]
    end
    App -->|HTTPS| API
    App --> DB[(SQLite)]
```

```mermaid
sequenceDiagram
    autonumber
    actor U as 使用者
    participant T as Tako
    participant M as 模型
    U->>T: 幫我畫一張圖表
    T->>M: 傳送對話與工具
    alt 需要即時資料
        M->>T: 呼叫 web_search
        T-->>M: 搜尋結果
    else 已有資料
        M-->>T: 直接回覆
    end
    Note over T,M: 回覆內含 chart 區塊
    T-->>U: 顯示圖表
```

```mermaid
mindmap
  root((Tako 顯示方式))
    圖表
      長條圖
      折線圖
      圓餅圖
    圖
      流程圖
      循序圖
      心智圖
    卡片
      清單
      數據卡
    提示框
```

```cards
[{"title": "本月請求", "value": "320", "delta": "+88%", "icon": "trending_up"}, {"title": "平均回應時間", "value": "1.8 秒", "delta": "-0.4 秒"}, {"title": "錯誤率", "value": "0.6%", "delta": "-0.2%"}, {"title": "活躍裝置", "value": "1,284"}]
```

> [!TIP]
> 點一下圖表可以看數值，點表格圖示可以切換成表格。

> [!WARNING] 注意資料來源
> 圖表只用模型手上真的有的資料。
''';

/// A reply that uses every visual block, for layout checks and screenshots.
Future<void> seedVisualReply(AppController controller) async {
  final now = DateTime.utc(2026, 10, 15, 9, 30);
  await controller.saveProvider(
    ProviderConfig(
      id: 'local',
      displayName: 'Local model',
      apiType: ApiType.chatCompletions,
      baseUrl: 'http://127.0.0.1:8080',
      model: 'llama-server',
    ),
  );
  await controller.chats.createConversation(
    Conversation(
      id: 'visuals',
      title: '顯示方式',
      createdAt: now,
      updatedAt: now,
      systemPrompt: 'You are Tako.',
      providerId: 'local',
      model: 'llama-server',
    ),
  );
  await controller.chats.saveMessage(
    ChatMessage(
      id: 'ask',
      conversationId: 'visuals',
      role: MessageRole.user,
      content: const [TextBlock('文字以外，你還能怎麼呈現？')],
      createdAt: now,
      timezoneOffsetMinutes: 480,
    ),
  );
  await controller.chats.saveMessage(
    ChatMessage(
      id: 'reply',
      conversationId: 'visuals',
      parentId: 'ask',
      role: MessageRole.assistant,
      content: const [TextBlock(visualReply)],
      createdAt: now.add(const Duration(seconds: 1)),
      timezoneOffsetMinutes: 480,
    ),
  );
  await controller.openConversation('visuals');
}

final _toolTimelineTime = DateTime.utc(2026, 10, 10, 10, 30);

ChatMessage _toolMessage(
  String id,
  String parent,
  MessageRole role,
  List<ContentBlock> content,
  int seconds, {
  MessageStatus status = MessageStatus.done,
}) => ChatMessage(
  id: id,
  conversationId: 'tool-timeline',
  parentId: parent,
  role: role,
  content: content,
  createdAt: _toolTimelineTime.add(Duration(seconds: seconds)),
  timezoneOffsetMinutes: 480,
  status: status,
);

Future<void> seedToolTimeline(
  AppController app, {
  bool splitWithText = false,
  bool pending = false,
  bool withAlternative = false,
}) async {
  await app.saveProvider(
    ProviderConfig(
      id: 'tool-provider',
      displayName: 'Local',
      apiType: ApiType.chatCompletions,
      baseUrl: 'http://127.0.0.1:8080',
      model: 'test-model',
    ),
  );
  await app.chats.createConversation(
    Conversation(
      id: 'tool-timeline',
      title: 'Read my notes',
      createdAt: _toolTimelineTime,
      updatedAt: _toolTimelineTime,
      systemPrompt: 'You are Tako.',
      providerId: 'tool-provider',
      model: 'test-model',
    ),
  );
  await app.chats.saveMessage(
    ChatMessage(
      id: 'timeline-user',
      conversationId: 'tool-timeline',
      role: MessageRole.user,
      content: const [TextBlock('Read my notes and give me a short summary.')],
      createdAt: _toolTimelineTime,
      timezoneOffsetMinutes: 480,
    ),
  );
  if (withAlternative) {
    await app.chats.saveMessage(
      _toolMessage(
        'timeline-alternative',
        'timeline-user',
        MessageRole.assistant,
        const [TextBlock('An alternative answer without tools.')],
        1,
      ),
    );
  }
  await app.chats.saveMessage(
    _toolMessage(
      'timeline-a',
      'timeline-user',
      MessageRole.assistant,
      const [
        ToolCallBlock(
          id: 'call-a',
          name: 'file_list',
          arguments: '{"path":""}',
        ),
      ],
      2,
      status: pending ? MessageStatus.streaming : MessageStatus.done,
    ),
  );
  if (!pending) {
    await _appendToolTimeline(app, splitWithText: splitWithText);
  }
  await app.openConversation('tool-timeline');
}

Future<void> _appendToolTimeline(
  AppController app, {
  bool splitWithText = false,
}) async {
  final first = await app.chats.getMessage('timeline-a');
  await app.chats.saveMessage(first!.copyWith(status: MessageStatus.done));
  for (final message in [
    _toolMessage('timeline-receipt-a', 'timeline-a', MessageRole.tool, const [
      ToolResultBlock(
        toolCallId: 'call-a',
        toolName: 'file_list',
        content: '{"files":["notes.txt"]}',
      ),
    ], 3),
    _toolMessage('timeline-b', 'timeline-receipt-a', MessageRole.assistant, [
      if (splitWithText)
        const TextBlock('I found the note. I will read it next.'),
      const ToolCallBlock(
        id: 'call-b',
        name: 'file_read',
        arguments: '{"path":"notes.txt"}',
      ),
    ], 4),
    _toolMessage('timeline-receipt-b', 'timeline-b', MessageRole.tool, const [
      ToolResultBlock(
        toolCallId: 'call-b',
        toolName: 'file_read',
        content: '{"text":"Finish the sketch and review the draft."}',
      ),
    ], 5),
    _toolMessage(
      'timeline-final',
      'timeline-receipt-b',
      MessageRole.assistant,
      const [
        TextBlock(
          'Your notes list two tasks: finish the sketch and review the draft.',
        ),
      ],
      6,
    ),
  ]) {
    await app.chats.saveMessage(message);
  }
}

Future<void> _waitForToolUi(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> screenshot(WidgetTester tester, String name) async {
  if (!captureUi) return;
  // Image codec completion uses real asynchronous work. Wait for the same
  // providers used by visible previews before capturing their first frame.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  try {
    boundary.markNeedsPaint();
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/qa').create(recursive: true);
      await File(
        'build/qa/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = previousShadows;
  }
}

void main() {
  setUpAll(() async {
    if (!captureUi) return;
    // Capture-only fonts: never packaged with the app or required by CI. The
    // test engine has no glyph fallback and uses the first font registered
    // for a family and weight, so Microsoft JhengHei (which also has Latin
    // glyphs) goes first: Chinese text then renders instead of boxes.
    for (final (family, path) in [
      ('Roboto', 'C:/Windows/Fonts/msjh.ttc'),
      ('Roboto', 'C:/Windows/Fonts/msjhbd.ttc'),
      (
        'Roboto',
        'D:/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ),
      (
        'MaterialIcons',
        'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
      ('monospace', 'C:/Windows/Fonts/consola.ttf'),
    ]) {
      final file = File(path);
      if (await file.exists()) {
        await (FontLoader(
          family,
        )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
    final fontManifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final item in fontManifest.cast<Map<String, dynamic>>()) {
      final family = item['family'] as String;
      if (!family.contains('flutter_math_fork')) continue;
      final loader = FontLoader(family);
      for (final font
          in (item['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  testWidgets('Traditional Chinese onboarding opens the provider editor', (
    tester,
  ) async {
    final controller = await boot(tester, size: const Size(390, 844));
    expect(controller.locale, const Locale('zh', 'TW'));
    expect(controller.errorCode, isNull);
    expect(find.text('連接你的模型'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await screenshot(tester, 'mobile-empty-zh');
    await tester.tap(find.text('新增供應商'));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderEditor), findsOneWidget);
    expect(field('顯示名稱'), findsOneWidget);
    expect(field('基底網址'), findsOneWidget);
    expect(find.text('http://127.0.0.1:8080'), findsOneWidget);
    expect(find.text('OpenAI Chat Completions'), findsOneWidget);
    await screenshot(tester, 'mobile-provider-zh');
    expect(tester.takeException(), isNull);
  });

  testWidgets('English provider form saves a local model and enables chat', (
    tester,
  ) async {
    final controller = await boot(tester, locale: const Locale('en'));
    expect(find.text('Connect your model'), findsOneWidget);
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Display name'), 'Local test server');
    await tester.enterText(field('Base URL'), 'http://127.0.0.1:8080');
    final keyField = tester.widget<EditableText>(
      find.descendant(
        of: field('API key'),
        matching: find.byType(EditableText),
      ),
    );
    expect(keyField.obscureText, isTrue);
    final editorScroll = find
        .descendant(
          of: find.byType(ProviderEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      field('Model'),
      220,
      scrollable: editorScroll,
    );
    await tester.enterText(field('Model'), 'test-model');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.text('Save'),
      300,
      scrollable: editorScroll,
    );
    await tester.tap(find.text('Save'));
    // Allow actual SQLite writes to complete outside the fake clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ProviderEditor), findsNothing);
    expect(controller.providers, hasLength(1));
    expect(controller.selectedProvider?.displayName, 'Local test server');
    expect(controller.selectedProvider?.model, 'test-model');
    expect(controller.selectedProvider?.isLocal, isTrue);
    expect(find.text('A little space to think.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final entry in {
    'mobile': const Size(390, 844),
    'narrow': const Size(320, 800),
    'wide': const Size(1280, 800),
  }.entries) {
    testWidgets('${entry.key} conversation renders without overflow', (
      tester,
    ) async {
      await boot(
        tester,
        locale: const Locale('en'),
        size: entry.value,
        seeded: true,
      );
      expect(find.text('2/2'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      await screenshot(tester, '${entry.key}-conversation-en');
      expect(tester.takeException(), isNull);
    });
  }
  for (final (name, size, theme, scale) in [
    ('visuals-mobile', const Size(390, 6400), ThemeMode.light, 1.0),
    ('visuals-narrow-dark', const Size(320, 7200), ThemeMode.dark, 1.0),
    ('visuals-large-text', const Size(390, 8400), ThemeMode.light, 1.4),
  ]) {
    testWidgets('$name renders every visual block without overflow', (
      tester,
    ) async {
      final controller = await boot(
        tester,
        locale: const Locale('zh', 'TW'),
        size: size,
        theme: theme,
        scale: scale,
      );
      await tester.runAsync(() => seedVisualReply(controller));
      await tester.pumpAndSettle();
      expect(find.byType(VisualBlock), findsNWidgets(8));
      expect(find.byType(CardsView), findsNWidgets(2));
      expect(find.text('注意資料來源'), findsOneWidget);
      await screenshot(tester, name);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('wide empty view renders without overflow', (tester) async {
    await boot(tester, locale: const Locale('en'), size: const Size(1280, 800));
    await screenshot(tester, 'wide-empty-en');
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat header keeps renaming without a generate-title button', (
    tester,
  ) async {
    await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
      seeded: true,
    );
    expect(find.byKey(const ValueKey('generate-chat-title')), findsNothing);
    expect(find.byTooltip('Generate chat title'), findsNothing);
    expect(find.byTooltip('Rename chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'message metadata is outside the bubble and single provider is hidden',
    (tester) async {
      final controller = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(390, 844),
        seeded: true,
      );
      final bubble = find.byKey(const ValueKey('message-bubble-user'));
      final metadata = find.byKey(const ValueKey('message-metadata-user'));
      expect(bubble, findsOneWidget);
      expect(metadata, findsOneWidget);
      expect(find.descendant(of: bubble, matching: metadata), findsNothing);
      expect(
        tester.getTopLeft(metadata).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(bubble).dy),
      );
      expect(find.text('Local model'), findsNothing);
      expect(find.text('llama-server'), findsOneWidget);
      await tester.runAsync(
        () => controller.saveProvider(
          controller.providers.single.copyWith(
            models: const [
              ModelProfile(id: 'llama-server'),
              ModelProfile(id: 'second-model'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('llama-server'));
      await tester.pumpAndSettle();
      expect(find.text('Local model'), findsNothing);
      await tester.tap(find.text('second-model'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(controller.selectedProvider!.model, 'second-model');
      expect(find.text('second-model'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'automatically fetched friendly main models can be searched independently',
    (tester) async {
      final controller = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(390, 844),
        adapterFactory: (_, _, _) => ModelListAdapter(
          catalog: const [
            ModelInfo(id: 'gpt-6.1-sol'),
            ModelInfo(id: 'claude-haiku-5-5'),
          ],
        ),
      );
      await tester.runAsync(() async {
        await controller.saveProvider(
          ProviderConfig(
            id: 'cpa',
            displayName: 'CPA',
            apiType: ApiType.messages,
            baseUrl: 'https://proxy.test/v1',
            model: 'claude-haiku-5-5',
            autoRouteModels: true,
            capabilities: const ProviderCapabilities(
              tools: true,
              reasoning: true,
            ),
          ),
        );
        await controller.refreshProviderModels();
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Haiku 5.5'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('main-model-search')),
        'gpt 6.1',
      );
      await tester.pumpAndSettle();
      expect(find.text('GPT 6.1 Sol'), findsOneWidget);
      await tester.tap(find.text('GPT 6.1 Sol'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(controller.selectedProvider!.model, 'gpt-6.1-sol');
      expect(controller.remoteAgentProvider!.model, 'claude-haiku-5-5');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'provider editor detects specs and saves multiple model profiles',
    (tester) async {
      final controller = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(390, 844),
      );
      await tester.tap(find.text('Add provider'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Display name'), 'DeepSeek');
      await tester.enterText(field('Base URL'), 'https://api.deepseek.com');
      final scroll = find
          .descendant(
            of: find.byType(ProviderEditor),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(field('Model'), 200, scrollable: scroll);
      await tester.enterText(field('Model'), 'deepseek-v4.1-flash');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Add model'),
        -160,
        scrollable: scroll,
      );
      await tester.tap(find.text('Add model'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Model'), 'private-model');
      tester.testTextInput.hide();
      await tester.scrollUntilVisible(
        field('Context window (tokens)'),
        250,
        scrollable: scroll,
      );
      await tester.enterText(field('Context window (tokens)'), '64000');
      await tester.enterText(field('Maximum output tokens'), '8000');
      tester.testTextInput.hide();
      await tester.scrollUntilVisible(
        find.text('Save'),
        250,
        scrollable: scroll,
      );
      await tester.tap(find.text('Save'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(controller.providers, hasLength(1));
      final profiles = controller.providers.single.models;
      expect(profiles, hasLength(2));
      expect(profiles.first.id, 'deepseek-v4.1-flash');
      expect(profiles.first.capabilities.contextWindow, 1048576);
      expect(profiles.first.capabilities.vision, isTrue);
      expect(profiles.first.maxOutputTokens, 393216);
      expect(profiles.last.capabilities.contextWindow, 64000);
      expect(profiles.last.maxOutputTokens, 8000);
      expect(profiles.last.autoDetect, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider model list adds several checked models in one save', (
    tester,
  ) async {
    final controller = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
      adapterFactory: (_, key, headers) => ModelListAdapter(),
    );
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Display name'), 'DeepSeek');
    final scroll = find
        .descendant(
          of: find.byType(ProviderEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Load models'),
      220,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.text('Load models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('deepseek-flash'));
    await tester.pump();
    await tester.tap(find.text('deepseek-v4-pro'));
    await tester.pump();
    final modelList = find.descendant(
      of: find.byKey(const ValueKey('provider-model-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('custom-59'),
      400,
      scrollable: modelList,
    );
    expect(find.text('Add selected').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Add selected'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('provider-auto-fetch-models')),
      -300,
      scrollable: scroll,
    );
    await tester.tap(find.byKey(const ValueKey('provider-auto-fetch-models')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save'), 300, scrollable: scroll);
    await tester.tap(find.text('Save'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(controller.providers.single.models.map((model) => model.id), [
      'deepseek-flash',
      'deepseek-v4-pro',
    ]);
    expect(
      controller.providers.single.models.first.capabilities.vision,
      isTrue,
    );
    expect(
      controller.providers.single.models.last.capabilities.vision,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment picker adds a file-only message with frozen text', (
    tester,
  ) async {
    final adapter = AnswerAdapter();
    final controller = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
      services: AttachmentServices(),
      adapterFactory: (_, key, headers) => adapter,
    );
    await tester.runAsync(
      () => controller.saveProvider(
        ProviderConfig(
          id: 'p',
          displayName: 'Local',
          apiType: ApiType.chatCompletions,
          baseUrl: 'http://localhost:8080',
          model: 'test',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Attach images or files'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Files'));
    await tester.pumpAndSettle();
    expect(find.text('note.txt'), findsOneWidget);
    await screenshot(tester, 'attachment-composer');
    await tester.tap(find.byTooltip('Send'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 140));
    });
    await tester.pumpAndSettle();
    expect(controller.errorCode, isNull);
    expect(
      adapter.requests.single.messages.first.content
          .whereType<FileBlock>()
          .single
          .extractedText,
      'Frozen attachment contents',
    );
    expect(controller.draftAttachments, isEmpty);
    expect(
      find.text('I read the attachment.', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'attachment menu stays above the keyboard and opens each source',
    (tester) async {
      final services = MediaAttachmentServices();
      final controller = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(390, 844),
        seeded: true,
        services: services,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(find.byTooltip('Attach images or files'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Camera'), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'Photos'), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'Files'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.widgetWithText(MenuItemButton, 'Files')).dy,
        lessThan(
          tester.getTopLeft(find.byTooltip('Attach images or files')).dy,
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      await screenshot(tester, 'attachment-source-menu');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Photos'));
      await tester.pumpAndSettle();
      expect(services.mediaAttachments.photoCalls, 1);
      expect(controller.draftAttachments.single, isA<ImageBlock>());
      await tester.tap(find.byTooltip('Attach images or files'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Camera'));
      await tester.pumpAndSettle();
      expect(services.mediaAttachments.cameraCalls, 1);
      expect(controller.draftAttachments, hasLength(2));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this draft',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'tapping blank chat history and dragging dismiss the keyboard without losing a draft',
    (tester) async {
      final app = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(390, 844),
        seeded: true,
      );
      final field = find.byType(TextField);
      final history = find.byKey(const ValueKey('chat-history-surface'));
      await tester.enterText(field, 'Keep this draft');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, true);
      final area = tester.getRect(history);
      await tester.tapAt(Offset(area.right - 8, area.bottom - 8));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, false);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Keep this draft',
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, true);
      await tester.runAsync(() async {
        await app.chats.saveMessage(
          ChatMessage(
            id: 'scroll-history',
            conversationId: 'visual',
            parentId: 'answer',
            role: MessageRole.assistant,
            createdAt: DateTime.now(),
            content: [
              TextBlock(
                List.filled(
                  40,
                  'A long history paragraph for scrolling.',
                ).join('\n\n'),
              ),
            ],
          ),
        );
        await app.openConversation('visual');
      });
      await tester.pumpAndSettle();
      final list = tester.getRect(
        find.byKey(const ValueKey('chat-history-list')),
      );
      await tester.dragFrom(
        Offset(list.right - 8, list.center.dy),
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, false);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Keep this draft',
      );
    },
  );

  testWidgets('IME commitContent adds an image without changing typed text', (
    tester,
  ) async {
    final services = AttachmentServices();
    final controller = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
      seeded: true,
      services: services,
    );
    await tester.enterText(find.byType(TextField), 'What is in this image?');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.contentInsertionConfiguration!.allowedMimeTypes, [
      'image/png',
      'image/jpeg',
      'image/gif',
      'image/webp',
    ]);
    const bytes = [137, 80, 78, 71];
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/textinput',
      const JSONMessageCodec().encodeMessage({
        'method': 'TextInputClient.performAction',
        'args': [
          -1,
          'TextInputAction.commitContent',
          {
            'mimeType': 'image/png',
            'uri': 'content://keyboard/image.png',
            'data': bytes,
          },
        ],
      }),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(services.workspace.importedImageName, 'keyboard-image.png');
    expect(services.workspace.importedImageBytes, bytes);
    expect(controller.draftAttachments.single, isA<ImageBlock>());
    expect(field.controller!.text, 'What is in this image?');
    expect(find.byKey(const ValueKey('draft-attachments')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IME image without bytes shows a localized retry message', (
    tester,
  ) async {
    final controller = await boot(
      tester,
      locale: const Locale('zh', 'TW'),
      size: const Size(390, 844),
      seeded: true,
      services: AttachmentServices(),
    );
    await tester.enterText(find.byType(TextField), '看這張圖');
    final field = tester.widget<TextField>(find.byType(TextField));
    field.contentInsertionConfiguration!.onContentInserted(
      const KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://keyboard/unavailable.png',
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.draftAttachments, isEmpty);
    expect(find.text('無法讀取這張圖片，請改由「相片」或「檔案」選取。'), findsOneWidget);
    expect(field.controller!.text, '看這張圖');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'composer groups thumbnails, text and bottom actions in one compact surface',
    (tester) async {
      final services = MediaAttachmentServices();
      final controller = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(390, 844),
        seeded: true,
        theme: ThemeMode.dark,
        services: services,
      );
      await tester.runAsync(controller.newChat);
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('chat-composer'));
      final fieldFinder = find.byType(TextField);
      final plus = find.byTooltip('Attach images or files');
      final send = find.byTooltip('Send');
      final emptyBounds = tester.getRect(composer);
      expect(emptyBounds.left, inInclusiveRange(0, 12));
      expect(390 - emptyBounds.right, inInclusiveRange(0, 12));
      expect(844 - emptyBounds.bottom, inInclusiveRange(0, 12));
      expect(emptyBounds.height, inInclusiveRange(88, 136));
      expect(
        tester.getRect(fieldFinder).bottom,
        lessThanOrEqualTo(tester.getRect(plus).top + 1),
      );
      expect(tester.getCenter(plus).dy, closeTo(tester.getCenter(send).dy, 1));
      await screenshot(tester, 'composer-dark-empty');

      await controller.importPhotos();
      await controller.capturePhoto();
      await tester.pumpAndSettle();
      final strip = find.byKey(const ValueKey('draft-attachments'));
      final photo = find.byKey(
        const ValueKey('draft-image-attachments/photo.png'),
      );
      final camera = find.byKey(
        const ValueKey('draft-image-attachments/camera.jpg'),
      );
      expect(find.descendant(of: composer, matching: strip), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      final bounds = tester.getRect(composer);
      final stripBounds = tester.getRect(strip);
      expect(bounds.contains(stripBounds.topLeft), isTrue);
      expect(bounds.contains(stripBounds.bottomRight), isTrue);
      expect(tester.getRect(photo).left - bounds.left, inInclusiveRange(6, 12));
      expect(tester.getSize(photo), const Size(136, 112));
      expect(tester.getSize(camera), const Size(136, 112));
      expect(tester.getTopLeft(photo).dy, tester.getTopLeft(camera).dy);
      expect(
        tester.getRect(fieldFinder).top,
        greaterThanOrEqualTo(stripBounds.bottom),
      );
      expect(
        tester.getRect(fieldFinder).bottom,
        lessThanOrEqualTo(tester.getRect(plus).top + 1),
      );
      expect(bounds.height, lessThanOrEqualTo(285));
      await screenshot(tester, 'composer-dark-attachments');

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(fieldFinder, 'Explain these two images');
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(fieldFinder);
      expect(field.focusNode!.hasFocus, isTrue);
      final remove = find.byKey(
        const ValueKey('remove-attachment-attachments/photo.png'),
      );
      expect(find.descendant(of: photo, matching: remove), findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(controller.draftAttachments, hasLength(1));
      expect(photo, findsNothing);
      expect(camera, findsOneWidget);
      expect(field.controller!.text, 'Explain these two images');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(544));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow composer keeps large text and mixed attachments inside its bounds',
    (tester) async {
      final controller = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(320, 700),
        seeded: true,
        theme: ThemeMode.dark,
        scale: 1.4,
        services: MediaAttachmentServices(),
      );
      await tester.runAsync(controller.newChat);
      await controller.importAttachments();
      await controller.importPhotos();
      await controller.capturePhoto();
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), 'A larger draft');
      await tester.pumpAndSettle();
      final composer = find.byKey(const ValueKey('chat-composer'));
      final strip = find.byKey(const ValueKey('draft-attachments'));
      final bounds = tester.getRect(composer);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.bottom, lessThanOrEqualTo(460));
      expect(find.text('note.txt'), findsOneWidget);
      expect(
        find.descendant(
          of: composer,
          matching: find.byKey(
            const ValueKey('draft-file-attachments/note.txt'),
          ),
        ),
        findsOneWidget,
      );
      await tester.drag(strip, const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(const ValueKey('draft-image-attachments/camera.jpg'))
            .hitTestable(),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'A larger draft');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(controller.draftAttachments, hasLength(3));
      await screenshot(tester, 'composer-narrow-large-text');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings separate full permissions from high-risk opt-in', (
    tester,
  ) async {
    final controller = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    final popped = nav.push<void>(
      MaterialPageRoute(builder: (_) => const ToolSettingsScreen()),
    );
    await tester.pumpAndSettle();
    await screenshot(tester, 'permission-settings');
    await tester.tap(find.text('Full permissions').first);
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(controller.permissionGate.policy.fullPermissions, isTrue);
    expect(controller.permissionGate.policy.skipHighRiskConfirmations, isFalse);
    await tester.enterText(
      find.widgetWithText(
        TextFormField,
        'Start loop detection after this many tool calls',
      ),
      '7',
    );
    tester.testTextInput.hide();
    await tester.tap(find.text('Save'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await popped;
    expect(controller.toolSettings.maxSteps, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool summaries open full arguments and results on phones', (
    tester,
  ) async {
    final controller = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
      seeded: true,
    );
    await tester.runAsync(() async {
      final now = DateTime.now();
      await controller.chats.saveMessage(
        ChatMessage(
          id: 'tool-call-message',
          conversationId: 'visual',
          parentId: 'answer',
          role: MessageRole.assistant,
          content: const [
            ToolCallBlock(
              id: 'call',
              name: 'file_write',
              arguments: '{"path":"notes.txt","text":"Plan"}',
            ),
          ],
          createdAt: now,
        ),
      );
      await controller.chats.saveMessage(
        ChatMessage(
          id: 'tool-result-message',
          conversationId: 'visual',
          parentId: 'tool-call-message',
          role: MessageRole.tool,
          content: const [
            ToolResultBlock(
              toolCallId: 'call',
              toolName: 'file_write',
              content: '{"written":"notes.txt"}',
            ),
          ],
          createdAt: now.add(const Duration(seconds: 1)),
        ),
      );
      await controller.openConversation('visual');
    });
    await tester.pumpAndSettle();
    expect(find.byType(ToolCallCard), findsNothing);
    expect(find.byType(ToolRunSummary), findsOneWidget);
    await tester.tap(find.byType(ToolRunSummary));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool-run-drawer')), findsOneWidget);
    expect(find.text('Arguments'), findsOneWidget);
    expect(find.textContaining('"written": "notes.txt"'), findsOneWidget);
    await screenshot(tester, 'tool-drawer');
    expect(tester.takeException(), isNull);
  });
  for (final proof in [
    (verified: true, review: false, label: 'Completed'),
    (verified: false, review: true, label: 'Incomplete'),
    (verified: true, review: true, label: 'Incomplete'),
  ]) {
    testWidgets(
      'remote task badge reflects ${proof.label} with verified=${proof.verified} review=${proof.review}',
      (tester) async {
        final app = await boot(
          tester,
          locale: const Locale('en'),
          size: const Size(390, 844),
          seeded: true,
        );
        await tester.runAsync(() async {
          final now = DateTime.now();
          await app.chats.saveMessage(
            ChatMessage(
              id: 'remote-call',
              conversationId: 'visual',
              parentId: 'answer',
              role: MessageRole.assistant,
              createdAt: now,
              content: const [
                ToolCallBlock(
                  id: 'remote',
                  name: 'remote_control',
                  arguments: '{"title":"Read storage"}',
                ),
              ],
            ),
          );
          await app.chats.saveMessage(
            ChatMessage(
              id: 'remote-result',
              conversationId: 'visual',
              parentId: 'remote-call',
              role: MessageRole.tool,
              createdAt: now.add(const Duration(seconds: 1)),
              content: [
                ToolResultBlock(
                  toolCallId: 'remote',
                  toolName: 'remote_control',
                  content: jsonEncode({
                    'status': 'reported_complete',
                    'verified': proof.verified,
                    'semantic_review_needed': proof.review,
                  }),
                ),
              ],
            ),
          );
          await app.openConversation('visual');
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('· ${proof.label}'), findsOneWidget);
        if (proof.label == 'Incomplete') {
          expect(find.textContaining('· Completed'), findsNothing);
        }
      },
    );
  }

  testWidgets(
    'phone action titles appear in summaries and details with legacy fallback',
    (tester) async {
      final controller = await boot(
        tester,
        locale: const Locale('en'),
        size: const Size(390, 844),
        seeded: true,
      );
      await tester.runAsync(() async {
        final now = DateTime.now();
        await controller.chats.saveMessage(
          ChatMessage(
            id: 'phone-call-message',
            conversationId: 'visual',
            parentId: 'answer',
            role: MessageRole.assistant,
            createdAt: now,
            content: const [
              ToolCallBlock(id: 'legacy', name: 'read_screen', arguments: '{}'),
              ToolCallBlock(
                id: 'tap',
                name: 'tap',
                arguments: '{"id":4,"title":"Open Wi-Fi settings"}',
              ),
            ],
          ),
        );
        await controller.chats.saveMessage(
          ChatMessage(
            id: 'phone-result-message',
            conversationId: 'visual',
            parentId: 'phone-call-message',
            role: MessageRole.tool,
            createdAt: now.add(const Duration(seconds: 1)),
            content: const [
              ToolResultBlock(
                toolCallId: 'legacy',
                toolName: 'read_screen',
                content: 'Settings',
              ),
              ToolResultBlock(
                toolCallId: 'tap',
                toolName: 'tap',
                content: '{"done":true}',
              ),
            ],
          ),
        );
        await controller.openConversation('visual');
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Open Wi-Fi settings'), findsOneWidget);
      await tester.tap(find.byType(ToolRunSummary));
      await tester.pumpAndSettle();
      expect(find.text('Open Wi-Fi settings'), findsOneWidget);
      expect(find.text('Read screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('consecutive tool rounds share one compact assistant turn', (
    tester,
  ) async {
    final app = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
      theme: ThemeMode.dark,
    );
    await tester.runAsync(() => seedToolTimeline(app, withAlternative: true));
    await tester.pumpAndSettle();
    final turn = find.byKey(const ValueKey('assistant-turn-timeline-a'));
    expect(turn, findsOneWidget);
    expect(find.byType(ToolRunSummary), findsOneWidget);
    expect(find.byType(ToolCallCard), findsNothing);
    expect(
      find.descendant(of: turn, matching: find.text('Tako')),
      findsOneWidget,
    );
    final metadata = find.descendant(
      of: turn,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'message-metadata-',
            ),
      ),
    );
    expect(metadata, findsOneWidget);
    expect(tester.getSize(turn).height, lessThan(340));
    expect(
      find.descendant(of: turn, matching: find.byTooltip('Previous branch')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: metadata,
        matching: find.byTooltip('Message actions'),
      ),
      findsOneWidget,
    );
    await screenshot(tester, 'tool-timeline-chat-dark');

    await tester.tap(find.byType(ToolRunSummary));
    await tester.pumpAndSettle();
    final drawer = find.byKey(const ValueKey('tool-run-drawer'));
    expect(drawer, findsOneWidget);
    expect(find.textContaining('"path": ""'), findsOneWidget);
    expect(find.textContaining('"files": ['), findsOneWidget);
    await screenshot(tester, 'tool-timeline-drawer-dark');
    final second = find.byKey(
      const ValueKey('tool-run-step-timeline-b-call-b'),
    );
    await tester.scrollUntilVisible(
      second,
      220,
      scrollable: find
          .descendant(of: drawer, matching: find.byType(Scrollable))
          .first,
    );
    expect(second, findsOneWidget);
    expect(
      find.textContaining('Finish the sketch and review the draft.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: metadata,
        matching: find.byTooltip('Message actions'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Regenerate'), findsOneWidget);
    expect(find.text('Rewind to here'), findsOneWidget);
    Navigator.of(tester.element(find.text('Regenerate'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: turn, matching: find.byTooltip('Previous branch')),
    );
    await _waitForToolUi(
      tester,
      () => app.conversation?.activeLeafId == 'timeline-alternative',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ToolRunSummary), findsNothing);
    expect(
      find.byKey(const ValueKey('assistant-turn-timeline-alternative')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual model text splits consecutive tool summaries in place', (
    tester,
  ) async {
    final app = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(430, 932),
    );
    await tester.runAsync(() => seedToolTimeline(app, splitWithText: true));
    await tester.pumpAndSettle();
    expect(find.byType(ToolRunSummary), findsNWidgets(2));
    final middle = find.text('I found the note. I will read it next.');
    expect(middle, findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(ToolRunSummary).first).dy,
      lessThan(tester.getTopLeft(middle).dy),
    );
    expect(
      tester.getBottomLeft(middle).dy,
      lessThan(tester.getTopLeft(find.byType(ToolRunSummary).last).dy),
    );
    final turn = find.byKey(const ValueKey('assistant-turn-timeline-a'));
    expect(
      find.descendant(of: turn, matching: find.text('Tako')),
      findsOneWidget,
    );
    expect(find.byType(ToolCallCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open tool drawer receives results and appended calls live', (
    tester,
  ) async {
    final app = await boot(
      tester,
      locale: const Locale('en'),
      size: const Size(390, 844),
      theme: ThemeMode.dark,
    );
    await tester.runAsync(() => seedToolTimeline(app, pending: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ToolRunSummary), findsOneWidget);
    await tester.tap(find.byType(ToolRunSummary));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final drawer = find.byKey(const ValueKey('tool-run-drawer'));
    expect(drawer, findsOneWidget);
    expect(
      find.byKey(const ValueKey('tool-run-step-timeline-a-call-a')),
      findsOneWidget,
    );
    expect(find.textContaining('"files": ['), findsNothing);

    app.permissionGate.policy = const PermissionPolicy(
      overrides: {'file_list': ToolPermission.ask},
    );
    final approval = app.permissionGate.authorize(
      toolName: 'file_list',
      args: const {'path': ''},
      risk: RiskLevel.safe,
      context: ToolContext(
        conversationId: 'tool-timeline',
        messageId: 'timeline-a',
        cancel: CancelToken(),
      ),
    );
    await _waitForToolUi(
      tester,
      () => find.byType(ToolApprovalSheet).evaluate().isNotEmpty,
    );
    expect(find.text('Allow once').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Allow once').hitTestable());
    final decision = await tester.runAsync(() => approval);
    expect(decision!.allowed, isTrue);
    await _waitForToolUi(
      tester,
      () => find.byType(ToolApprovalSheet).evaluate().isEmpty,
    );
    expect(drawer, findsOneWidget);

    await tester.runAsync(() async {
      await _appendToolTimeline(app);
      await app.openConversation('tool-timeline');
    });
    await tester.pumpAndSettle();
    expect(drawer, findsOneWidget);
    expect(find.textContaining('"files": ['), findsOneWidget);
    final second = find.byKey(
      const ValueKey('tool-run-step-timeline-b-call-b'),
    );
    await tester.scrollUntilVisible(
      second,
      220,
      scrollable: find
          .descendant(of: drawer, matching: find.byType(Scrollable))
          .first,
    );
    expect(second, findsOneWidget);
    expect(
      find.textContaining('Finish the sketch and review the draft.'),
      findsOneWidget,
    );
    expect(find.text('Waiting'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
