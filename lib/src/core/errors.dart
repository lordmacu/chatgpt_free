/// Base type for every error this package raises.
sealed class ChatGptException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const ChatGptException(this.message);

  /// What went wrong, in plain language.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The anonymous quota is spent and rotating to a fresh device did not help.
final class QuotaExceededException extends ChatGptException {
  /// Creates a quota-exhausted error.
  const QuotaExceededException(super.message);
}

/// The backend returned 429. [retryAfter] is set when it told us when to return.
final class RateLimitedException extends ChatGptException {
  /// Creates a rate-limit error.
  const RateLimitedException(super.message, {this.retryAfter});

  /// How long to wait before retrying, when the backend said so.
  final Duration? retryAfter;
}

/// The backend rejected the request body (HTTP 422), or we rejected it first.
final class InvalidRequestException extends ChatGptException {
  /// Creates an invalid-request error naming the offending [field].
  const InvalidRequestException(super.message, {this.field});

  /// The field the backend (or local validation) objected to.
  final String? field;

  @override
  String toString() =>
      'InvalidRequestException: $message${field == null ? '' : ' (field: $field)'}';
}

/// The request never completed: DNS, TLS, socket, timeout.
final class TransportException extends ChatGptException {
  /// Creates a transport error.
  const TransportException(super.message);
}

/// The stream was well-delivered but not well-formed.
final class ProtocolException extends ChatGptException {
  /// Creates a protocol error.
  const ProtocolException(super.message);
}
