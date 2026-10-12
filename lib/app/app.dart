import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../ui/chat/chat_screen.dart';
import '../ui/screen/device_control_bridge.dart';
import 'app_controller.dart';
import 'app_info.dart';

class TakoApp extends ConsumerWidget {
  const TakoApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(
      appControllerProvider.select(
        (app) => (app.themeMode, app.locale, app.textScale, app.initialized),
      ),
    );
    ThemeData theme(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xff466953),
        brightness: brightness,
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: brightness == Brightness.light
            ? const Color(0xfffafbf7)
            : const Color(0xff121713),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );
    }

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: appearance.$1,
      locale: appearance.$2,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            MediaQuery.textScalerOf(context).scale(1) * appearance.$3,
          ),
        ),
        child: child!,
      ),
      home: appearance.$4
          ? const DeviceControlBridge(child: ChatScreen())
          : const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
    );
  }
}
