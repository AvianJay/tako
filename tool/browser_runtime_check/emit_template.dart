import 'dart:io';

import 'package:tako/core/browser/browser_scripts.dart';

/// Writes the exact injected browser script with placeholders, so the Node
/// check runs the code the app sends to the WebView. Run from the project
/// root: `dart run tool/browser_runtime_check/emit_template.dart`.
void main() {
  File('tool/browser_runtime_check/template.js').writeAsStringSync(
    browserScript(
      key: '__TAKO_KEY__',
      secret: '__TAKO_SECRET__',
      operation: '__TAKO_OP__',
      arguments: {'__TAKO_ARGS__': 1},
    ),
  );
}
