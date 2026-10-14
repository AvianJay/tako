import '../providers/cancel_token.dart';

typedef ReplInvoke =
    Future<Map<String, Object?>> Function(
      String method,
      List<Object?> arguments,
    );

class ReplEvaluation {
  const ReplEvaluation({
    this.value,
    this.output = '',
    this.error,
    this.reset = false,
  });
  final Object? value;
  final String output;
  final String? error;
  final bool reset;
}

abstract interface class ReplRuntime {
  Future<ReplEvaluation> evaluate(
    String code, {
    required ReplInvoke invoke,
    required CancelToken cancel,
  });
  void close();
}
