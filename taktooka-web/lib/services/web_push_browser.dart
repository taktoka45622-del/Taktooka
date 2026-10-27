import 'dart:convert';
import 'dart:js_interop';

@JS('tktEnablePush')
external JSPromise<JSString> _enable(JSBoolean ask);
@JS('tktWebMessage')
external set _onMessage(JSFunction value);
Future<String?> requestWebPush(bool ask) async =>
    (await _enable(ask.toJS).toDart).toDart;
void listenWebPush(void Function(Map<String, dynamic>, bool) callback) {
  _onMessage = ((JSString json, JSBoolean clicked) {
    try {
      callback(
        Map<String, dynamic>.from(jsonDecode(json.toDart) as Map),
        clicked.toDart,
      );
    } catch (_) {}
  }).toJS;
}
