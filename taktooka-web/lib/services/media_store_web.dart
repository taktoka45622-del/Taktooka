import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class MediaStore {
  static Future<Uint8List?> read(String key) async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(
        'food-media:$key',
      );
      return s == null ? null : base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Uint8List bytes) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        'food-media:$key',
        base64Encode(bytes),
      );
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    try {
      await (await SharedPreferences.getInstance()).remove('food-media:$key');
    } catch (_) {}
  }
}
