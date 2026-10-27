import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:taktooka/services/profile_photo.dart';

void main() {
  test('Avatar compression produces a bounded JPEG without stretching', () {
    final original = img.Image(width: 1200, height: 800);
    final jpeg = prepareProfilePhoto(
      Uint8List.fromList(img.encodePng(original)),
    );
    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, 512);
    expect(decoded.height, 341);
    expect(jpeg.length, lessThan(2097152));
  });
  test('Invalid avatar bytes are rejected', () {
    expect(
      () => prepareProfilePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
