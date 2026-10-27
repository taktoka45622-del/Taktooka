import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class DocumentCrop {
  final Uint8List jpeg;
  final bool detected;
  const DocumentCrop(this.jpeg, this.detected);
}

DocumentCrop cropDocument(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('INVALID_DOCUMENT');
  final oriented = img.bakeOrientation(decoded);
  final cw = math.min(oriented.width, (oriented.height * 16 / 9).round());
  final ch = math.min(oriented.height, (oriented.width * 9 / 16).round());
  final full = img.copyCrop(
    oriented,
    x: (oriented.width - cw) ~/ 2,
    y: (oriented.height - ch) ~/ 2,
    width: cw,
    height: ch,
  );
  final small = img.copyResize(full, width: 480);
  final w = small.width, h = small.height;
  final gx = List<double>.filled(w, 0), gy = List<double>.filled(h, 0);
  double lum(int x, int y) {
    final p = small.getPixel(x, y);
    return .299 * p.r + .587 * p.g + .114 * p.b;
  }

  for (int y = (h * .1).round(); y < (h * .9).round(); y++) {
    for (int x = (w * .06).round(); x < (w * .94).round(); x++) {
      gx[x] += (lum(x + 1, y) - lum(x - 1, y)).abs();
      gy[y] += (lum(x, y + 1) - lum(x, y - 1)).abs();
    }
  }
  int peak(List<double> v, int a, int b) {
    int best = a;
    for (int i = a + 1; i <= b; i++) {
      if (v[i] > v[best]) best = i;
    }
    return best;
  }

  final l = peak(gx, (w * .06).round(), (w * .25).round());
  final r = peak(gx, (w * .75).round(), (w * .94).round());
  final t = peak(gy, (h * .1).round(), (h * .3).round());
  final b = peak(gy, (h * .7).round(), (h * .9).round());
  final ratio = (r - l) / (b - t),
      meanX = gx.reduce((a, b) => a + b) / w,
      meanY = gy.reduce((a, b) => a + b) / h;
  int support(bool vertical, int p, int a, int b) {
    int n = 0;
    for (int i = a; i < b; i++) {
      final d = vertical
          ? (lum(p + 1, i) - lum(p - 1, i)).abs()
          : (lum(i, p + 1) - lum(i, p - 1)).abs();
      if (d > 22) n++;
    }
    return n;
  }

  final confident =
      ratio > 1.25 &&
      ratio < 2.05 &&
      gx[l] > meanX * 1.5 &&
      gx[r] > meanX * 1.5 &&
      gy[t] > meanY * 1.5 &&
      gy[b] > meanY * 1.5 &&
      support(true, l, t, b) > (b - t) * .5 &&
      support(true, r, t, b) > (b - t) * .5 &&
      support(false, t, l, r) > (r - l) * .5 &&
      support(false, b, l, r) > (r - l) * .5;
  if (!confident)
    return DocumentCrop(
      Uint8List.fromList(img.encodeJpg(full, quality: 90)),
      false,
    );
  final scale = full.width / w;
  final cropped = img.copyCrop(
    full,
    x: (l * scale).round(),
    y: (t * scale).round(),
    width: ((r - l) * scale).round(),
    height: ((b - t) * scale).round(),
  );
  return DocumentCrop(
    Uint8List.fromList(img.encodeJpg(cropped, quality: 90)),
    true,
  );
}

Uint8List manualDocumentCrop(Map<String, dynamic> data) {
  final source = img.decodeImage(data['bytes'] as Uint8List)!;
  final left = (data['left'] as double), top = (data['top'] as double);
  final right = (data['right'] as double), bottom = (data['bottom'] as double);
  return Uint8List.fromList(
    img.encodeJpg(
      img.copyCrop(
        source,
        x: (source.width * left).round(),
        y: (source.height * top).round(),
        width: (source.width * (right - left)).round(),
        height: (source.height * (bottom - top)).round(),
      ),
      quality: 90,
    ),
  );
}
