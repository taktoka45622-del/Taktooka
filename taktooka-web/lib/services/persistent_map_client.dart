import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:taktooka/services/map_store.dart';

class PersistentMapClient extends http.BaseClient {
  final http.Client _network;
  final Map<String, Future<http.Response>> _pending = {};
  final Set<String> _refreshing = {};
  PersistentMapClient({http.Client? network})
    : _network = network ?? http.Client();
  static final shared = PersistentMapClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final cacheable =
        request.method == 'GET' &&
        request.url.host == 'api.mapbox.com' &&
        (request.url.path.startsWith('/styles/') ||
            request.url.path.startsWith('/v4/') ||
            request.url.path.startsWith('/fonts/')) &&
        !request.url.path.contains('tilequery');
    if (!cacheable) return _network.send(request);
    final key = sha256.convert(utf8.encode(request.url.toString())).toString();
    final response = await (_pending[key] ??= _load(key, request).whenComplete(
      () {
        _pending.remove(key);
      },
    ));
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  Future<http.Response> _load(String key, http.BaseRequest request) async {
    http.Response? saved;
    DateTime? expires;
    try {
      final bytes = await MapStore.read(key);
      if (bytes != null) {
        final value = jsonDecode(utf8.decode(bytes)) as Map;
        saved = http.Response.bytes(
          base64Decode(value['body'] as String),
          200,
          headers: Map<String, String>.from(value['headers'] as Map),
        );
        expires = DateTime.parse(value['expires'] as String);
      }
    } catch (_) {}
    if (saved != null) {
      if (expires == null || !expires.isAfter(DateTime.now().toUtc())) {
        if (_refreshing.add(key)) {
          unawaited(
            _download(key, request)
                .then<void>((_) {}, onError: (Object _) {})
                .whenComplete(() => _refreshing.remove(key)),
          );
        }
      }
      return saved;
    }
    return _download(key, request);
  }

  Future<http.Response> _download(String key, http.BaseRequest original) async {
    final request = http.Request('GET', original.url)
      ..headers.addAll(original.headers);
    var response = await http.Response.fromStream(
      await _network.send(request).timeout(const Duration(seconds: 10)),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode >= 500 || response.statusCode == 429) {
      final retry = http.Request('GET', original.url)
        ..headers.addAll(original.headers);
      response = await http.Response.fromStream(
        await _network.send(retry).timeout(const Duration(seconds: 10)),
      ).timeout(const Duration(seconds: 10));
    }
    final control = response.headers['cache-control'] ?? '';
    if (response.statusCode == 200 &&
        response.bodyBytes.isNotEmpty &&
        !control.contains('no-store')) {
      final age =
          int.tryParse(
            RegExp(r'(?:^|[, ])max-age=(\d+)').firstMatch(control)?.group(1) ??
                '',
          ) ??
          43200;
      final seconds = control.contains('no-cache') ? 0 : age;
      final value = {
        'headers': response.headers,
        'body': base64Encode(response.bodyBytes),
        'expires': DateTime.now()
            .toUtc()
            .add(Duration(seconds: seconds))
            .toIso8601String(),
      };
      await MapStore.write(key, utf8.encode(jsonEncode(value)));
    }
    return response;
  }

  @override
  void close() => _network.close();
}
