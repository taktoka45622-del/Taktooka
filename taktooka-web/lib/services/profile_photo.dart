import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Uint8List prepareProfilePhoto(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('الصورة غير صالحة');
  }
  if (decoded == null) throw const FormatException('الصورة غير صالحة');
  final oriented = img.bakeOrientation(decoded);
  final resized = oriented.width > 512 || oriented.height > 512
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 512 : null,
          height: oriented.height > oriented.width ? 512 : null,
        )
      : oriented;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

Future<Uint8List> compressProfilePhoto(Uint8List bytes) =>
    compute(prepareProfilePhoto, bytes);
