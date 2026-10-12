import 'dart:math';

final _random = Random.secure();
const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

/// Returns a new unique id: a base-36 millisecond timestamp followed by
/// random characters, so ids sort roughly by creation time.
String newId({DateTime? now}) {
  final millis = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  final buffer = StringBuffer(millis.toRadixString(36).padLeft(9, '0'));
  for (var i = 0; i < 12; i++) {
    buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
  }
  return buffer.toString();
}
