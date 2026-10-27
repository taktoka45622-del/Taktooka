String mergePlaceLabel(String? selected, String resolved) {
  if (selected == null || selected.trim().isEmpty) return resolved;
  final parts = <String>[];
  for (final part in [...selected.split('،'), ...resolved.split('،')]) {
    final value = part.trim();
    if (value.isEmpty || parts.contains(value)) continue;
    if (value.startsWith('قرب ') && parts.contains(value.substring(4))) continue;
    parts.add(value);
  }
  final result = parts.join('، ');
  return result.length > 256 ? result.substring(0, 256) : result;
}
