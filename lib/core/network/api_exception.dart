/// What went wrong with an API call, in a form the UI can map to a message.
enum ApiErrorKind {
  /// No connection, DNS failure, TLS error, connection reset.
  network,

  /// Connect, send or receive took longer than [ApiClient.timeout].
  timeout,

  /// The server answered with a non-2xx status.
  http,

  /// The body could not be decoded as JSON.
  invalidResponse,

  /// The request was cancelled by the caller.
  cancelled,
}

class ApiException implements Exception {
  const ApiException(this.kind, {this.statusCode, this.message, this.path});

  final ApiErrorKind kind;
  final int? statusCode;

  /// The server's `{msg}` text when it sent one, otherwise a short description.
  final String? message;

  /// The endpoint path, for logs.
  final String? path;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' $statusCode';
    return 'ApiException(${kind.name}$status, $path): ${message ?? ''}';
  }
}
