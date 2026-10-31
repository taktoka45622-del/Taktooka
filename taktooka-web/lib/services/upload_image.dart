import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Uint8List encodeUpload(Map<String, Object> input) {
  final image = img.decodeImage(input['bytes'] as Uint8List);
  final limit = input['dimension'] as int;
  if (image == null)
    throw const FormatException('صيغة الصورة غير مدعومة على هذا الجهاز');
  if (image.width * image.height > 80000000)
    throw const FormatException('دقة الصورة كبيرة جدًا');
  final oriented = img.bakeOrientation(image);
  final sized = oriented.width > limit || oriented.height > limit
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? limit : null,
          height: oriented.height > oriented.width ? limit : null,
        )
      : oriented;
  final opaque = img.Image(
    width: sized.width,
    height: sized.height,
    numChannels: 3,
  )..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(opaque, sized);
  return Uint8List.fromList(img.encodeJpg(opaque, quality: 84));
}

Future<Uint8List> prepareUploadImage(
  Uint8List bytes, {
  int dimension = 1600,
}) async {
  if (bytes.isEmpty || bytes.length > 30 * 1024 * 1024)
    throw const FormatException('اختر صورة أقل من 30 ميغابايت');
  try {
    return await compute(encodeUpload, {
      'bytes': bytes,
      'dimension': dimension,
    });
  } on FormatException {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 80000000)
        throw const FormatException('دقة الصورة كبيرة جدًا');
      final wide = descriptor.width >= descriptor.height;
      codec = await descriptor.instantiateCodec(
        targetWidth: wide && descriptor.width > dimension ? dimension : null,
        targetHeight: !wide && descriptor.height > dimension ? dimension : null,
      );
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) throw const FormatException('تعذر قراءة الصورة');
        return await compute(encodeUpload, {
          'bytes': data.buffer.asUint8List(),
          'dimension': dimension,
        });
      } finally {
        frame.image.dispose();
      }
    } catch (_) {
      throw const FormatException(
        'تعذر قراءة هذه الصورة؛ صدّرها كصورة من معرض الجهاز',
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
