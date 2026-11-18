import '../../core/json/json_utils.dart';
import '../models/service_status.dart';

/// `components.json` of the status page: the worst status among the
/// "Cinemana" group and its components (API, Search Engine). Unknown status
/// strings are ignored. [ServiceHealth.unknown] when Cinemana isn't listed.
ServiceHealth parseCinemanaHealth(Object? json) {
  final components = [
    for (final c in asList(asMap(json)?['components'])) ?asMap(c),
  ];
  final group = components
      .where((c) => readString(c['name'])?.toLowerCase() == 'cinemana')
      .firstOrNull;
  if (group == null) return ServiceHealth.unknown;
  final groupId = readString(group['id']);
  final members = [
    group,
    for (final c in components)
      if (groupId != null && readString(c['group_id']) == groupId) c,
  ];
  ServiceHealth? worst;
  for (final c in members) {
    final health = _health(readString(c['status']));
    if (health != null && (worst == null || health.index > worst.index)) {
      worst = health;
    }
  }
  return worst ?? ServiceHealth.unknown;
}

ServiceHealth? _health(String? status) => switch (status) {
  'operational' => ServiceHealth.operational,
  'degraded_performance' => ServiceHealth.degradedPerformance,
  'under_maintenance' => ServiceHealth.underMaintenance,
  'partial_outage' => ServiceHealth.partialOutage,
  'major_outage' => ServiceHealth.majorOutage,
  _ => null,
};
