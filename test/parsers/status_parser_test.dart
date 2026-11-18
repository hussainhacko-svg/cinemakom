import 'package:cinemakom/data/models/service_status.dart';
import 'package:cinemakom/data/parsers/status_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixture.dart';

Map<String, Object?> page(List<Map<String, Object?>> components) => {
  'page': {'name': 'Shabakaty'},
  'components': components,
};

Map<String, Object?> c(
  String id,
  String name,
  String status, {
  String? groupId,
}) => {'id': id, 'name': name, 'status': status, 'group_id': groupId};

void main() {
  test('fixture lists the Cinemana group', () {
    expect(
      parseCinemanaHealth(fixture('service_status')),
      isNot(ServiceHealth.unknown),
    );
  });

  test('the worst status of the group and its components wins', () {
    final json = page([
      c('g', 'Cinemana', 'operational'),
      c('a', 'API', 'partial_outage', groupId: 'g'),
      c('s', 'Search Engine', 'degraded_performance', groupId: 'g'),
      c('x', 'API', 'major_outage', groupId: 'other'),
      c('other', 'TV', 'major_outage'),
    ]);
    final health = parseCinemanaHealth(json);
    expect(health, ServiceHealth.partialOutage);
    expect(health.isDown, isTrue);
  });

  test('operational and degraded are not "down"', () {
    expect(ServiceHealth.operational.isDown, isFalse);
    expect(ServiceHealth.degradedPerformance.isDown, isFalse);
    expect(ServiceHealth.underMaintenance.isDown, isTrue);
    expect(
      parseCinemanaHealth(page([c('g', 'cinemana', 'operational')])),
      ServiceHealth.operational,
    );
  });

  test('missing group, unknown statuses and junk give unknown', () {
    expect(
      parseCinemanaHealth(page([c('t', 'TV', 'operational')])),
      ServiceHealth.unknown,
    );
    expect(
      parseCinemanaHealth(page([c('g', 'Cinemana', 'weird')])),
      ServiceHealth.unknown,
    );
    expect(parseCinemanaHealth(null), ServiceHealth.unknown);
    expect(parseCinemanaHealth([1, 2]), ServiceHealth.unknown);
  });
}
