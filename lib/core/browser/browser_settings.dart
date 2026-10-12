import '../util/json.dart';

class BrowserSettings {
  const BrowserSettings({this.openLinksInApp = true});
  static const settingsKey = 'browser.settings';

  /// Chat links open in the in-app browser instead of an external app.
  final bool openLinksInApp;

  factory BrowserSettings.fromJson(JsonMap json) =>
      BrowserSettings(openLinksInApp: asBool(json['openLinksInApp']) ?? true);

  JsonMap toJson() => {'openLinksInApp': openLinksInApp};
}
