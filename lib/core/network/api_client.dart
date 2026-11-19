import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';

import 'api_endpoints.dart';
import 'api_exception.dart';

/// The single HTTP client for the Cinemana API.
///
/// Pure Dart (no Flutter imports) so `tool/capture_fixtures.dart` can use it.
class ApiClient {
  ApiClient({
    Dio? dio,
    void Function(String message)? log,
    int maxConcurrent = 6,
    this.retryDelay = const Duration(milliseconds: 500),
  }) : _dio = dio ?? createDio(log: log),
       _slots = _Slots(maxConcurrent);

  static const String baseUrl = 'https://cinemana.shabakaty.com/api/android/';

  static const Duration timeout = Duration(seconds: 30);

  /// Sent with **every** request to Cinemana: API calls, images, video streams
  /// and downloads. Reuse this map, never copy it. As of 2026-11-19 the
  /// servers don't require them, but the website sends them, so we do too.
  static const Map<String, String> defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://cinemana.shabakaty.com/',
    'Origin': 'https://cinemana.shabakaty.com',
  };

  static Dio createDio({void Function(String message)? log}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: timeout,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        headers: defaultHeaders,
        // Decode JSON ourselves: the server's content types are unreliable.
        responseType: ResponseType.plain,
      ),
    );
    if (log != null) dio.interceptors.add(_LogInterceptor(log));
    return dio;
  }

  final Dio _dio;

  /// The server slows down badly under many parallel requests (20 at once
  /// took ~20 s), so at most this many run at a time; the rest wait.
  final _Slots _slots;

  /// Wait before the single retry of a failed GET.
  final Duration retryDelay;

  /// Sends [request] and returns the decoded JSON (a `List`, `Map`, scalar or
  /// `null` for an empty body). Throws [ApiException] on any failure.
  ///
  /// A GET that fails with a network error, a timeout or a 5xx is retried
  /// once. 4xx answers and POSTs are never retried.
  Future<Object?> fetch(ApiRequest request, {CancelToken? cancelToken}) async {
    await _slots.acquire();
    try {
      try {
        return await _send(request, cancelToken);
      } on ApiException catch (e) {
        if (!_isRetryable(request, e) || cancelToken?.isCancelled == true) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
        return await _send(request, cancelToken);
      }
    } finally {
      _slots.release();
    }
  }

  /// Downloads a text file (a subtitle) from an absolute [url] with the
  /// shared headers, retried once like [fetch]. A UTF-8 BOM is dropped.
  Future<String> fetchText(String url) async {
    Future<String> once() async {
      try {
        final response = await _dio.get<String>(url);
        final body = response.data ?? '';
        return body.startsWith('\uFEFF') ? body.substring(1) : body;
      } on DioException catch (e) {
        throw _mapDioError(e, url);
      }
    }

    await _slots.acquire();
    try {
      try {
        return await once();
      } on ApiException catch (e) {
        if (!_isRetryable(ApiRequest(url), e)) rethrow;
        await Future<void>.delayed(retryDelay);
        return await once();
      }
    } finally {
      _slots.release();
    }
  }

  static bool _isRetryable(ApiRequest request, ApiException e) =>
      request.method == HttpMethod.get &&
      (e.kind == ApiErrorKind.network ||
          e.kind == ApiErrorKind.timeout ||
          (e.kind == ApiErrorKind.http && (e.statusCode ?? 0) >= 500));

  Future<Object?> _send(ApiRequest request, CancelToken? cancelToken) async {
    try {
      final Response<String> response = switch (request.method) {
        HttpMethod.get => await _dio.get<String>(
          request.path,
          queryParameters: request.query,
          cancelToken: cancelToken,
        ),
        HttpMethod.post => await _dio.post<String>(
          request.path,
          queryParameters: request.query,
          data: request.json != null ? jsonEncode(request.json) : request.form,
          options: Options(
            contentType: request.json != null
                ? Headers.jsonContentType
                : Headers.formUrlEncodedContentType,
          ),
          cancelToken: cancelToken,
        ),
      };
      return await decodeBodyAsync(response.data, path: request.path);
    } on DioException catch (e) {
      throw _mapDioError(e, request.path);
    }
  }

  /// Bodies above this size are decoded on a background isolate.
  static const int isolateThreshold = 50 * 1024;

  /// [decodeBody], on a background isolate for large bodies.
  static Future<Object?> decodeBodyAsync(String? body, {String? path}) async {
    if (body == null || body.length < isolateThreshold) {
      return decodeBody(body, path: path);
    }
    return Isolate.run(() => decodeBody(body, path: path));
  }

  /// Decodes a raw body. Empty bodies become `null`.
  static Object? decodeBody(String? body, {String? path}) {
    final text = body?.trim() ?? '';
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw ApiException(
        ApiErrorKind.invalidResponse,
        message: e.message,
        path: path,
      );
    }
  }

  static ApiException _mapDioError(DioException e, String path) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException(ApiErrorKind.timeout, path: path);
      case DioExceptionType.cancel:
        return ApiException(ApiErrorKind.cancelled, path: path);
      case DioExceptionType.badResponse:
        return ApiException(
          ApiErrorKind.http,
          statusCode: e.response?.statusCode,
          message: _serverMessage(e.response?.data),
          path: path,
        );
      case DioExceptionType.badCertificate:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return ApiException(
          ApiErrorKind.network,
          message: e.message ?? e.error?.toString(),
          path: path,
        );
    }
  }

  /// Errors are usually HTTP 400 with `{msg}`.
  static String? _serverMessage(Object? data) {
    if (data is! String || data.isEmpty) return null;
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map && decoded['msg'] != null) {
        return decoded['msg'].toString();
      }
    } on FormatException {
      // Not JSON. Fall through to the raw text.
    }
    return data.length > 200 ? data.substring(0, 200) : data;
  }
}

class _LogInterceptor extends Interceptor {
  _LogInterceptor(this._log);

  final void Function(String) _log;
  final _started = <RequestOptions, Stopwatch>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _started[options] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(
      '[api] ${response.statusCode} ${response.requestOptions.method} '
      '${response.requestOptions.uri} (${_ms(response.requestOptions)} ms)',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(
      '[api] ERROR ${err.type.name} ${err.response?.statusCode ?? ''} '
      '${err.requestOptions.method} ${err.requestOptions.uri} '
      '(${_ms(err.requestOptions)} ms)',
    );
    handler.next(err);
  }

  int _ms(RequestOptions o) => _started.remove(o)?.elapsedMilliseconds ?? -1;
}

/// A counting semaphore.
class _Slots {
  _Slots(this._free) : assert(_free > 0);

  int _free;
  final _waiting = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_free > 0) {
      _free--;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _free++;
    }
  }
}
