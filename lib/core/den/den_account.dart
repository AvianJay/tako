import '../util/json.dart';
import 'den_client.dart';

/// The Den this device is signed in to. The token itself lives in secure
/// storage under [tokenKey], never in the database.
final class DenAccount {
  const DenAccount({
    required this.server,
    required this.serverName,
    required this.user,
    required this.deviceId,
  });

  static const settingsKey = 'den.account';
  static const tokenKey = 'den.token';

  /// The id of the provider that points at the Den's model gateway. Web chats
  /// use it too, so a chat continues on whichever device opens it.
  static const providerId = 'tako-den';

  static DenAccount? fromJson(JsonMap? json) {
    final server = Uri.tryParse(asString(json?['server']) ?? '');
    final user = asMap(json?['user']);
    if (json == null || server == null || !server.hasScheme || user == null) {
      return null;
    }
    return DenAccount(
      server: server,
      serverName: asString(json['serverName']) ?? 'Tako Den',
      user: DenUser.fromJson(user),
      deviceId: asString(json['deviceId']) ?? '',
    );
  }

  final Uri server;
  final String serverName;
  final DenUser user;
  final String deviceId;

  DenAccount copyWith({String? serverName, DenUser? user}) => DenAccount(
    server: server,
    serverName: serverName ?? this.serverName,
    user: user ?? this.user,
    deviceId: deviceId,
  );

  JsonMap toJson() => {
    'server': server.toString(),
    'serverName': serverName,
    'user': user.toJson(),
    'deviceId': deviceId,
  };
}
