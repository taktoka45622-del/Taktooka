typedef HistoryJson = Map<String, dynamic>;

List<HistoryJson> filterTripHistory(
  List<HistoryJson> customerRides,
  List<HistoryJson> lineRuns,
  String filter,
) {
  final entries = <HistoryJson>[
    if (filter != 'lines')
      ...customerRides.map(
        (r) => {
          ...r,
          'history_type': 'customer',
          'history_at': r['created_at'],
        },
      ),
    if (filter != 'customers')
      ...lineRuns.map(
        (r) => {...r, 'history_type': 'line', 'history_at': r['departure_at']},
      ),
  ];
  final times = Map<HistoryJson, DateTime>.identity();
  for (final entry in entries) {
    times[entry] =
        DateTime.tryParse('${entry['history_at']}') ?? DateTime(2000);
  }
  entries.sort((a, b) {
    final time = times[b]!.compareTo(times[a]!);
    return time != 0 ? time : '${a['id']}'.compareTo('${b['id']}');
  });
  return entries;
}
