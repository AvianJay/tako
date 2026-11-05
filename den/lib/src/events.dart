import 'dart:async';
import 'dart:convert';

/// Per-user broadcast of small notices ("pull from seq N"). Clients keep one
/// `GET /v1/events` stream open and pull when told to.
final class EventHub {
  final _streams = <String, StreamController<String>>{};

  Stream<List<int>> subscribe(String userId) {
    final controller = _streams.putIfAbsent(
      userId,
      StreamController<String>.broadcast,
    );
    late final StreamController<List<int>> out;
    StreamSubscription<String>? events;
    Timer? keepAlive;
    out = StreamController<List<int>>(
      onListen: () {
        out.add(utf8.encode(': connected\n\n'));
        events = controller.stream.listen(
          (e) => out.add(utf8.encode(e)),
          onDone: () {
            keepAlive?.cancel();
            out.close();
          },
        );
        // Proxies drop idle connections; a comment line keeps them open.
        keepAlive = Timer.periodic(
          const Duration(seconds: 25),
          (_) => out.add(utf8.encode(': ping\n\n')),
        );
      },
      onCancel: () async {
        keepAlive?.cancel();
        await events?.cancel();
        if (!controller.hasListener) {
          _streams.remove(userId);
          await controller.close();
        }
      },
    );
    return out.stream;
  }

  void publish(String userId, String event, Object data) {
    _streams[userId]?.add('event: $event\ndata: ${jsonEncode(data)}\n\n');
  }

  Future<void> close() async {
    for (final controller in _streams.values.toList()) {
      await controller.close();
    }
    _streams.clear();
  }
}
