import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:taktooka/pages/verification_flow/document_edges.dart';
import 'package:taktooka/pages/verification_flow/liveness.dart';

void main() {
  test('Only complete ordered blink and turn yields motion evidence', () {
    final c = MotionCheck(rightFirst: true);
    var now = DateTime.utc(2026);
    void frame({double eyes = .95, double yaw = 0, int count = 1, int id = 1}) {
      now = now.add(const Duration(milliseconds: 100));
      c.observe(
        now: now,
        count: count,
        centered: true,
        id: id,
        leftEye: eyes,
        rightEye: eyes,
        yaw: yaw,
      );
    }

    for (var i = 0; i < 3; i++) frame();
    expect(c.stage, 1);
    for (var i = 0; i < 5; i++) frame(yaw: 30);
    expect(c.complete, false);
    frame(eyes: .1);
    frame();
    expect(c.stage, 2);
    frame(yaw: -30);
    frame(yaw: -30);
    expect(c.stage, 2);
    frame(yaw: 30);
    frame(yaw: 30);
    expect(c.stage, 3);
    for (var i = 0; i < 3; i++) frame();
    expect(c.complete, true);
    expect(c.report()['blink'], true);
    frame(id: 2);
    expect(c.complete, false);
  });
  test('Losing the face clears an earlier motion sequence', () {
    final c = MotionCheck(rightFirst: false), now = DateTime.utc(2026);
    for (var i = 0; i < 3; i++)
      c.observe(
        now: now,
        count: 1,
        centered: true,
        id: 1,
        leftEye: .9,
        rightEye: .9,
        yaw: 0,
      );
    expect(c.stage, 1);
    c.observe(
      now: now.add(const Duration(seconds: 1)),
      count: 0,
      centered: false,
    );
    expect(c.stage, 0);
  });
  test('Blank image never masquerades as a detected card', () {
    final im = img.Image(width: 960, height: 540);
    img.fill(im, color: img.ColorRgb8(220, 220, 220));
    final result = cropDocument(Uint8List.fromList(img.encodeJpg(im)));
    expect(result.detected, false);
    final decoded = img.decodeImage(result.jpeg)!;
    expect(decoded.width / decoded.height, closeTo(16 / 9, .01));
  });
  test(
    'Aligned rectangular card is cropped, and manual crop preserves contents',
    () {
      final im = img.Image(width: 960, height: 540);
      img.fill(im, color: img.ColorRgb8(30, 30, 30));
      img.fillRect(
        im,
        x1: 140,
        y1: 75,
        x2: 820,
        y2: 465,
        color: img.ColorRgb8(245, 245, 245),
      );
      final result = cropDocument(Uint8List.fromList(img.encodeJpg(im)));
      expect(result.detected, true);
      final decoded = img.decodeImage(result.jpeg)!;
      expect(decoded.width, lessThan(960));
      final manual = manualDocumentCrop({
        'bytes': result.jpeg,
        'left': .1,
        'right': .9,
        'top': .1,
        'bottom': .9,
      });
      expect(img.decodeImage(manual)!.width, closeTo(decoded.width * .8, 2));
    },
  );
}
