/// Simple logging service that wraps [print] to satisfy the `avoid_print`
/// lint rule while providing stdout output for CLI scripts.
class LogService {
  /// Logs [message] to stdout.
  static void log(Object? message) {
    // ignore: avoid_print
    print(message);
  }
}
