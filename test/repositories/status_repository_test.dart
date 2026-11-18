import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/models/service_status.dart';
import 'package:cinemakom/data/repositories/status_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_client.dart';

typedef F = FakeApiClient;

void main() {
  test('reads the status page', () async {
    final api = F([F.fixtureAt(ApiEndpoints.statusUrl, 'service_status')]);
    expect(
      await StatusRepository(api).cinemanaHealth(),
      isNot(ServiceHealth.unknown),
    );
  });

  test('never throws: offline gives unknown', () async {
    final api = F([F.path(ApiEndpoints.statusUrl, offline)]);
    expect(await StatusRepository(api).cinemanaHealth(), ServiceHealth.unknown);
  });
}
