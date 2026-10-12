import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../ui/brand/tako_mark.dart';
import 'app.dart';
import 'app_controller.dart';
import 'app_info.dart';

/// Paint before starting storage and platform initialization.
///
/// The first frame repeats the native launch screen (`launch_background.xml`
/// and Android 12's splash): the mark at 1.5 dp per unit, centred. Once that
/// frame is on screen the head shrinks into the dots, which hop until the app
/// is ready to fade in.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({required this.loadController, super.key});
  final Future<AppController> Function() loadController;
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with TickerProviderStateMixin {
  // The launch screen colours in android/app/src/main/res/values*/colors.xml.
  static const _light = (
    background: Color(0xfffafbf7),
    mark: Color(0xff466953),
  );
  static const _dark = (background: Color(0xff121713), mark: Color(0xff92d5ab));
  // A beat on the launch picture while the window transition ends.
  static const _hold = Interval(1 / 3, 1);
  late final _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 840),
  );
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final _frames = Listenable.merge([_morph, _wave]);
  late final _opacity = ReverseAnimation(_exit);
  Timer? _fallback;
  AppController? _controller;
  bool _failed = false;
  bool _splash = true;

  bool get _reducedMotion => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  void initState() {
    super.initState();
    _morph.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (!_failed) unawaited(_wave.repeat());
      _leaveSplash();
    });
    _exit.addStatusListener((status) {
      if (status == AnimationStatus.completed) _hideSplash();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_load());
      if (_reducedMotion) return;
      // Engine start-up can hold back the first raster for most of a second,
      // and frames until then never reach the screen: start the morph once
      // one has. The timer covers an engine that does not report it.
      _fallback = Timer(const Duration(seconds: 2), _startMorph);
      unawaited(
        WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
          (_) => _startMorph(),
        ),
      );
    });
  }

  void _startMorph() {
    _fallback?.cancel();
    if (mounted && _morph.isDismissed) unawaited(_morph.forward());
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _morph.dispose();
    _wave.dispose();
    _exit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    if (_morph.isCompleted) unawaited(_wave.repeat());
    AppController? controller;
    try {
      controller = await widget.loadController();
      await controller.initialize();
      if (controller.errorCode != null) {
        throw StateError('Initialization failed');
      }
      if (!mounted) {
        controller.dispose();
        await controller.database.close();
        return;
      }
      setState(() => _controller = controller);
      _leaveSplash();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(controller!.recoverLostAttachments());
      });
    } catch (_) {
      controller?.dispose();
      await controller?.database.close();
      if (mounted) {
        _wave.stop();
        setState(() => _failed = true);
      }
    }
  }

  /// Once the app is ready and the dots have formed.
  void _leaveSplash() {
    if (_controller == null || !_splash || _exit.isAnimating) return;
    if (_reducedMotion) {
      _hideSplash();
    } else if (_morph.isCompleted) {
      unawaited(_exit.forward());
    }
  }

  void _hideSplash() {
    _wave.stop();
    setState(() => _splash = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        if (controller != null)
          ProviderScope(
            key: const ValueKey('app'),
            overrides: [
              appControllerProvider.overrideWith((ref) => controller),
            ],
            child: const TakoApp(),
          ),
        if (_splash)
          IgnorePointer(
            key: const ValueKey('splash'),
            ignoring: controller != null,
            child: FadeTransition(opacity: _opacity, child: _splashApp()),
          ),
      ],
    );
  }

  Widget _splashApp() => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: kAppName,
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff466953)),
      scaffoldBackgroundColor: _light.background,
    ),
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff466953),
      scaffoldBackgroundColor: _dark.background,
    ),
    home: Builder(
      builder: (context) {
        final launch = Theme.of(context).brightness == Brightness.dark
            ? _dark
            : _light;
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Semantics(
                  label: kAppName,
                  child: AnimatedBuilder(
                    animation: _frames,
                    builder: (context, _) => CustomPaint(
                      size: const Size.square(
                        TakoMarkPainter.launcherExtent * 1.5,
                      ),
                      painter: TakoMarkPainter(
                        color: launch.mark,
                        extent: TakoMarkPainter.launcherExtent,
                        morph: _hold.transform(_morph.value),
                        wave: _wave.isAnimating ? _wave.value : null,
                      ),
                    ),
                  ),
                ),
              ),
              if (_failed)
                Align(
                  alignment: const Alignment(0, .5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppLocalizations.of(context).operationFailed),
                      TextButton(
                        onPressed: _load,
                        child: Text(AppLocalizations.of(context).retry),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
