import 'dart:async';

/// Recognizes transport failures only. Business and authentication failures
/// must never be retried as if the network disconnected.
bool isTransientNetworkFailure(Object error) {
  if (error is TimeoutException) return true;
  final text = error.toString().toLowerCase();
  return const [
    'socketexception',
    'failed host lookup',
    'connection reset by peer',
    'connection closed before full header',
    'connection timed out',
    'network is unreachable',
    'network request failed',
    'failed to fetch',
    'connection refused',
  ].any(text.contains);
}

String? networkFailureMessage(Object error) {
  if (error is TimeoutException) {
    return 'الخدمة تأخرت بالرد؛ أعد المحاولة بعد قليل';
  }
  if (isTransientNetworkFailure(error)) {
    return 'انقطع الاتصال بالخدمة؛ تحقق من الإنترنت وأعد المحاولة';
  }
  return null;
}

/// For reads only: never replay payments, order acceptance, or account writes.
Future<T> retryNetworkRead<T>(Future<T> Function() request) async {
  try {
    return await request();
  } catch (error) {
    // A timed-out request may still be running; avoid overlapping it.
    if (error is TimeoutException || !isTransientNetworkFailure(error)) rethrow;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return request();
  }
}
