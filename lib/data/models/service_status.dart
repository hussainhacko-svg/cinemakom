/// Cinemana's health according to Shabakaty's public status page.
///
/// The values mirror Statuspage's component statuses, from best to worst.
enum ServiceHealth {
  operational,
  degradedPerformance,
  underMaintenance,
  partialOutage,
  majorOutage,

  /// The status page couldn't be read, or doesn't list Cinemana.
  unknown;

  /// Whether the UI should say the problem is on Cinemana's side.
  bool get isDown =>
      this == partialOutage || this == majorOutage || this == underMaintenance;
}
