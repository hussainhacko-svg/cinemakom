import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// The app-wide [ApiClient]. Logs requests in debug builds.
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(log: kDebugMode ? debugPrint : null),
);
