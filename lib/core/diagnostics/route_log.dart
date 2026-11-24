import 'package:go_router/go_router.dart';

import 'event_log.dart';

/// Every screen [router] shows, in the flight recorder: pushes, Back and
/// tabs. Used by the phone and TV routers.
void logRoutes(GoRouter router) {
  String? last;
  void report() {
    final where = router.routerDelegate.currentConfiguration.uri.path;
    if (where.isEmpty || where == last) return;
    last = where;
    logEvent('route', where);
  }

  router.routerDelegate.addListener(report);
}
