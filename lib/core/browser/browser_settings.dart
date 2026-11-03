import '../util/json.dart';

class BrowserSettings {
  const BrowserSettings({
    this.openLinksInApp = true,
    this.loadWebContent = false,
  });
  static const settingsKey = 'browser.settings';

  /// Chat links open in the in-app browser instead of an external app.
  final bool openLinksInApp;

  /// Images, link previews, video thumbnails and maps in replies load
  /// without a tap. Off by default: each one tells a website the device's
  /// address.
  final bool loadWebContent;

  factory BrowserSettings.fromJson(JsonMap json) => BrowserSettings(
    openLinksInApp: asBool(json['openLinksInApp']) ?? true,
    loadWebContent: asBool(json['loadWebContent']) ?? false,
  );

  BrowserSettings copyWith({bool? openLinksInApp, bool? loadWebContent}) =>
      BrowserSettings(
        openLinksInApp: openLinksInApp ?? this.openLinksInApp,
        loadWebContent: loadWebContent ?? this.loadWebContent,
      );

  JsonMap toJson() => {
    'openLinksInApp': openLinksInApp,
    'loadWebContent': loadWebContent,
  };
}
