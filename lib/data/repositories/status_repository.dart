import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_providers.dart';
import '../models/service_status.dart';
import '../parsers/status_parser.dart';

final statusRepositoryProvider = Provider<StatusRepository>(
  (ref) => StatusRepository(ref.watch(apiClientProvider)),
);

/// Cinemana's health from Shabakaty's public status page. Call it only after
/// API requests fail, to pick the error message.
class StatusRepository {
  StatusRepository(this._api);

  final ApiClient _api;

  /// Never throws: [ServiceHealth.unknown] when the page can't be read
  /// (for example because the user is offline).
  Future<ServiceHealth> cinemanaHealth() async {
    try {
      return parseCinemanaHealth(
        await _api.fetch(ApiEndpoints.serviceStatus()),
      );
    } on ApiException {
      return ServiceHealth.unknown;
    }
  }
}
