import 'dart:async';

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

Future<T> retryNetworkRead<T>(Future<T> Function() request) async {
  try {
    return await request();
  } catch (error) {
    if (error is TimeoutException || !isTransientNetworkFailure(error)) rethrow;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return request();
  }
}
