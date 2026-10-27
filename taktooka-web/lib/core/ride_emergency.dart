const emergencyDelay = Duration(minutes: 1);

bool rideEmergencyReady(Map<String, dynamic> ride, DateTime now) {
  if (ride['status'] != 'in_progress') return false;
  final startedAt = DateTime.tryParse('${ride['started_at'] ?? ride['updated_at']}');
  return startedAt != null &&
      now.toUtc().difference(startedAt.toUtc()) >= emergencyDelay;
}
