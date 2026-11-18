import 'dart:convert';
import 'dart:typed_data';

import 'package:cinemakom/core/network/api_client.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with [respond] and remembers what was sent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options, String? body) respond;
  final requests = <(RequestOptions, String?)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = requestStream == null
        ? null
        : utf8.decode(await requestStream.expand((b) => b).toList());
    requests.add((options, body));
    return respond(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['text/html; charset=utf-8'],
  },
);

(ApiClient, _FakeAdapter) _client(
  ResponseBody Function(RequestOptions, String?) respond,
) {
  final adapter = _FakeAdapter(respond);
  final dio = ApiClient.createDio()..httpClientAdapter = adapter;
  return (ApiClient(dio: dio), adapter);
}

void main() {
  test('sends the shared headers to the base URL', () async {
    final (client, adapter) = _client((_, _) => _json('[]'));
    await client.fetch(ApiEndpoints.banners());
    final options = adapter.requests.single.$1;
    expect(options.uri.toString(), '${ApiClient.baseUrl}banner/level/0');
    for (final e in ApiClient.defaultHeaders.entries) {
      expect(options.headers[e.key], e.value);
    }
  });

  test('decodes JSON even when the content type is wrong', () async {
    final (client, _) = _client((_, _) => _json('[{"nb":"1"}]'));
    expect(await client.fetch(ApiEndpoints.banners()), [
      {'nb': '1'},
    ]);
  });

  test('large bodies are decoded off the main isolate', () async {
    final big = jsonEncode([
      for (var i = 0; i < 3000; i++) {'nb': '$i', 'en_title': 'Title $i'},
    ]);
    expect(big.length, greaterThan(ApiClient.isolateThreshold));
    final (client, _) = _client((_, _) => _json(big));
    expect(await client.fetch(ApiEndpoints.banners()), hasLength(3000));
  });

  test('empty body is null', () async {
    final (client, _) = _client((_, _) => _json('  '));
    expect(await client.fetch(ApiEndpoints.banners()), isNull);
  });

  test('query parameters are sent', () async {
    final (client, adapter) = _client((_, _) => _json('{}'));
    await client.fetch(
      ApiEndpoints.videosByCategory(categoryId: '84', kind: VideoKind.series),
    );
    final q = adapter.requests.single.$1.uri.queryParameters;
    expect(q, {
      'categoryID': '84',
      'orderby': 'r_desc',
      'videoKind': '2',
      'offset': '0',
      'level': '0',
    });
  });

  test('POST getVideosByIds sends a form body', () async {
    final (client, adapter) = _client((_, _) => _json('[]'));
    await client.fetch(ApiEndpoints.videosByIds(['1', '2']));
    final (options, body) = adapter.requests.single;
    expect(options.method, 'POST');
    expect(options.contentType, startsWith(Headers.formUrlEncodedContentType));
    expect(Uri.splitQueryString(body!), {'ids': '[1, 2]'});
  });

  test('HTTP 400 with {msg} becomes an http ApiException', () async {
    final (client, _) = _client(
      (_, _) => _json('{"msg":"bad id"}', status: 400),
    );
    await expectLater(
      client.fetch(ApiEndpoints.videoInfo('x')),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.http)
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.message, 'message', 'bad id'),
      ),
    );
  });

  test('invalid JSON becomes invalidResponse', () async {
    final (client, _) = _client((_, _) => _json('<html>oops</html>'));
    await expectLater(
      client.fetch(ApiEndpoints.banners()),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('connection failures become network errors', () async {
    final (client, _) = _client(
      (options, _) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      ),
    );
    await expectLater(
      client.fetch(ApiEndpoints.banners()),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network),
      ),
    );
  });
}
