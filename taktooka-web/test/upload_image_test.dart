import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:taktooka/services/upload_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = img.Image(width: 1800, height: 900)
    ..clear(img.ColorRgb8(220, 40, 40));
  for (final sample in <String, List<int>>{
    'JPEG': img.encodeJpg(source),
    'PNG': img.encodePng(source),
    'GIF': img.encodeGif(source),
    'BMP': img.encodeBmp(source),
    'TIFF': img.encodeTiff(source),
    'TGA': img.encodeTga(source),
    'ICO': img.encodeIco(img.copyResize(source, width: 128)),
  }.entries) {
    test(
      '${sample.key} converts to bounded JPEG preserving proportions',
      () async {
        final result = await prepareUploadImage(
          Uint8List.fromList(sample.value),
          dimension: 800,
        );
        final image = img.decodeJpg(result)!;
        expect(image.width, lessThanOrEqualTo(800));
        expect(image.height, image.width ~/ 2);
        expect(result.length, lessThan(10 * 1024 * 1024));
      },
    );
  }
}
