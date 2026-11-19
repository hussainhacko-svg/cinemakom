import 'package:cinemakom/core/network/api_client.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';
import 'package:dio/dio.dart';

import '../fixture.dart';

/// Answers requests from [routes]: the first route whose matcher accepts the
/// request wins. A route value can be JSON, an [ApiException] to throw, or a
/// function of the request. Unmatched requests throw.
class FakeApiClient implements ApiClient {
  FakeApiClient(this.routes);

  final List<(bool Function(ApiRequest), Object? Function(ApiRequest))> routes;

  @override
  Duration get retryDelay => Duration.zero;
  final requests = <ApiRequest>[];

  /// A route matching requests whose path starts with [prefix].
  static (bool Function(ApiRequest), Object? Function(ApiRequest)) path(
    String prefix,
    Object? response,
  ) => (
    (r) => r.path.startsWith(prefix),
    (r) => response is Object? Function(ApiRequest) ? response(r) : response,
  );

  /// Like [path], answering with a captured fixture.
  static (bool Function(ApiRequest), Object? Function(ApiRequest)) fixtureAt(
    String prefix,
    String name,
  ) => path(prefix, fixture(name));

  @override
  Future<Object?> fetch(ApiRequest request, {CancelToken? cancelToken}) async {
    requests.add(request);
    for (final (matches, respond) in routes) {
      if (!matches(request)) continue;
      final value = respond(request);
      if (value is ApiException) throw value;
      return value;
    }
    throw StateError('No fake route for $request');
  }

  @override
  Future<String> fetchText(String url) async =>
      '${await fetch(ApiRequest(url))}';
}

const offline = ApiException(ApiErrorKind.network, message: 'offline');
