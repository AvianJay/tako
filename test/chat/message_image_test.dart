import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tako/core/chat/content_block.dart';
import 'package:tako/l10n/gen/app_localizations.dart';
import 'package:tako/platform/services.dart';
import 'package:tako/ui/chat/message_image.dart';

class _Services extends PlatformServices {
  int reads = 0;
  @override
  Future<Uint8List> readWorkspaceImage(String relative) async {
    reads++;
    return Uint8List.fromList(img.encodePng(img.Image(width: 32, height: 24)));
  }
}

void main() {
  testWidgets(
    'generated image preview opens and keeps its read through rebuilds',
    (tester) async {
      final services = _Services();
      var opened = 0;
      Widget build() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MessageImage(
            image: const ImageBlock(
              path: 'attachments/generated.png',
              mimeType: 'image/png',
            ),
            services: services,
            onOpen: () => opened++,
          ),
        ),
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(services.reads, 1);
      await tester.tap(find.byType(InkWell));
      expect(opened, 1);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(services.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
