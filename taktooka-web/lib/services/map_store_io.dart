import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class MapStore {
  static Future<Directory>? _directory;
  static int _sequence = 0;
  static Future<Directory> _open() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}/map-data-v1');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<Directory> _folder() =>
      _directory ??= _open().catchError((Object e) {
        _directory = null;
        throw e;
      });
  static Future<Uint8List?> read(String key) async {
    try {
      return await File('${(await _folder()).path}/$key').readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Uint8List bytes) async {
    File? temporary;
    try {
      final path = '${(await _folder()).path}/$key';
      temporary = File('$path.${_sequence++}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(path);
    } catch (_) {
      try {
        await temporary?.delete();
      } catch (_) {}
    }
  }
}
