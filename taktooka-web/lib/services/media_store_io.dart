import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class MediaStore {
  static Future<Directory> folder() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/food-media-v1').create(recursive: true);
  }

  static Future<Uint8List?> read(String key) async {
    try {
      return await File('${(await folder()).path}/$key').readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Uint8List bytes) async {
    try {
      final file = File('${(await folder()).path}/$key.part');
      await file.writeAsBytes(bytes);
      await file.rename('${(await folder()).path}/$key');
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    try {
      await File('${(await folder()).path}/$key').delete();
    } catch (_) {}
  }
}
