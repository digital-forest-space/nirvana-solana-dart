/// Retry utility with exponential backoff
class Retry {
  /// Execute an async operation with exponential backoff retry
  ///
  /// [operation] - The async function to execute
  /// [maxAttempts] - Maximum number of attempts (default: 5)
  /// [initialDelay] - Initial delay in milliseconds (default: 1000)
  /// [maxDelay] - Maximum delay cap in milliseconds (default: 30000)
  /// [backoffMultiplier] - Multiplier for each retry (default: 2.0)
  /// [retryIf] - Optional predicate to determine if error is retryable
  static Future<T> withBackoff<T>({
    required Future<T> Function() operation,
    int maxAttempts = 5,
    int initialDelay = 1000,
    int maxDelay = 30000,
    double backoffMultiplier = 2.0,
    bool Function(Exception)? retryIf,
  }) async {
    int attempt = 0;
    int delay = initialDelay;

    while (true) {
      attempt++;
      try {
        return await operation();
      } catch (e) {
        final isRetryable = e is Exception &&
            (retryIf == null || retryIf(e));

        if (!isRetryable || attempt >= maxAttempts) {
          rethrow;
        }

        // Wait before retry
        await Future.delayed(Duration(milliseconds: delay));

        // Increase delay for next attempt (with cap)
        delay = (delay * backoffMultiplier).toInt();
        if (delay > maxDelay) delay = maxDelay;
      }
    }
  }

  /// Check if an error is a rate limit (429) error
  static bool isRateLimitError(Exception e) {
    final msg = e.toString();
    return msg.contains('429') ||
           msg.contains('rate limit') ||
           msg.contains('Too many requests');
  }

  /// Check if an error is a "not found" error that might resolve with retry
  static bool isNotFoundError(Exception e) {
    final msg = e.toString();
    return msg.contains('not found') ||
           msg.contains('Not found') ||
           msg.contains('null');
  }

  /// Check if error is retryable (rate limit or transient not found)
  static bool isRetryableError(Exception e) {
    return isRateLimitError(e) || isNotFoundError(e);
  }
}
