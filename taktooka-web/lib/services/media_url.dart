String mediaUrl(String baseUrl, String bucket, dynamic value) {
  final path = (value ?? '').toString().trim();
  if (path.isEmpty) return '';
  final uri = Uri.tryParse(path);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http'))
    return path;
  final clean = path.replaceFirst(RegExp(r'^/+'), '');
  if (clean.startsWith('storage/v1/object/')) return '$baseUrl/$clean';
  final relative = clean.startsWith('$bucket/')
      ? clean.substring(bucket.length + 1)
      : clean;
  return '$baseUrl/storage/v1/object/public/$bucket/${relative.split('/').map(Uri.encodeComponent).join('/')}';
}
